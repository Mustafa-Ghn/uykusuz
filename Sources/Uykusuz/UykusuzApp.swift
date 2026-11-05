import AppKit
import Carbon.HIToolbox
import SwiftUI

/// Menu bar app. The status item is an `NSStatusItem` hosting SwiftUI, and
/// the settings window is an `NSWindow` this app opens itself (see
/// `SettingsWindow`), so there is no SwiftUI scene with any content in it.
/// `App` still requires one, hence the empty `Settings`. main.swift starts
/// this app unless the command line asks for a one-shot mode first.
struct UykusuzApp: App {
    @NSApplicationDelegateAdaptor private var delegate: AppDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let manager: SessionManager
    let status: any StatusSource
    let secrets: any HotspotSecretStore
    let locationPermission: LocationPermission
    let loginItem = LoginItem()
    /// Starts, extends and ends sessions while an agent is at work (fork
    /// addition).
    let autoSession: AgentAutoSession
    /// "While you were away" when the lid opens (fork addition), and the
    /// window it is told in.
    let awaySummary: AwaySummary
    let summaryPanel = SummaryPanel()
    /// Claude's last reply read aloud on request (fork addition), in the same
    /// window, and the shortcut that asks for it.
    let replyReader: ClaudeReplyReader
    let listenHotKey = GlobalHotKey(keyCode: kVK_ANSI_D, modifiers: controlKey | optionKey)
    /// An area the user draws on the screen read aloud on request, in the same
    /// window, and the shortcut that asks for it.
    let areaReader: AreaReader
    let areaHotKey = GlobalHotKey(keyCode: kVK_ANSI_S, modifiers: controlKey | optionKey)
    /// "Claude is waiting for you" to the iPhone by iMessage (fork addition).
    let waitingAlerts: WaitingAlerts
    /// Claude's own phone pushes only while the user is away (fork addition).
    let pushGate: ClaudePushGate
    /// The notebook: a look at the Mac every two hours, Claude's advice and
    /// the user's replies, and its window.
    let advisor: MacAdvisor
    private var notebookWindow: NotebookWindow?
    private var statusItem: StatusItemController?
    private var settingsWindow: SettingsWindow?
    private var terminating = false

    override init() {
        let manager = SessionManager.live()
        self.manager = manager
        autoSession = AgentAutoSession(manager: manager)
        let panel = summaryPanel
        panel.naturalVoice = { [manager] in manager.config.naturalVoice }
        panel.followOnScreen = { [manager] in manager.config.followOnScreen }
        awaySummary = AwaySummary(
            config: { [manager] in manager.config },
            present: { text, told in await panel.show(text, told: told) },
            dismiss: { panel.close() }
        )
        let keys = awaySummary.keyStore
        let paths = Paths.fromEnvironment()
        let store = manager.store
        advisor = MacAdvisor(
            config: { [manager] in manager.config },
            notebook: store.loadNotebook(),
            save: { notebook in
                do {
                    try store.saveNotebook(notebook)
                } catch {
                    Log.error("notebook: could not save: \(error.localizedDescription)")
                }
            },
            keyStore: keys
        )
        let hotKey = listenHotKey
        replyReader = ClaudeReplyReader(
            config: { [manager] in manager.config },
            present: { reply, onFinish, onClose in
                await panel.show(
                    ClaudeReplySpeech.plain(reply.text),
                    told: reply.at,
                    title: ClaudeReplyReader.title(of: reply),
                    autoplay: true,
                    // "Nothing to read" is not on the screen to be found.
                    onScreen: !reply.session.isEmpty,
                    onFinish: onFinish,
                    onClose: onClose
                )
            },
            dismiss: { panel.close() },
            resume: { panel.resume() },
            windowIsReading: { panel.isReading },
            setShortcut: { hotKey.set($0) },
            paths: paths
        )
        let areaKey = areaHotKey
        let picker = AreaPicker()
        let screenPermission = ScreenPermission()
        areaReader = AreaReader(
            config: { [manager] in manager.config },
            hasPermission: { screenPermission.isGranted },
            askPermission: { screenPermission.ask() },
            read: {
                guard let area = await picker.pick() else { return nil }
                return try await ScreenText.read(area)
            },
            giveUp: { picker.cancel() },
            present: { text, autoplay, onFinish, onClose in
                await panel.show(text, told: Date(), title: AreaReader.title, autoplay: autoplay, onScreen: !AreaReader.isMessage(text), onFinish: onFinish, onClose: onClose)
            },
            dismiss: { panel.close() },
            windowIsReading: { panel.isReading },
            setShortcut: { areaKey.set($0) }
        )
        waitingAlerts = WaitingAlerts(
            config: { [manager] in manager.config },
            sessions: { ClaudeActivity.liveSessions(paths: paths, now: Date()) },
            away: { WaitingAlerts.liveAway() },
            compose: { [manager] session, event in
                await WaitingAlerts.liveCompose(session: session, event: event, keyStore: keys, model: manager.config.summaryModel, paths: paths)
            }
        )
        pushGate = ClaudePushGate(file: ClaudePushGate.file(in: paths)) { [manager] in manager.config.phoneReplies }
        secrets = KeychainHotspotSecretStore(keychain: KeychainStore()) {
            manager.config.hotspotSSID
        }
        if let services = manager.services {
            status = LiveStatusSource(services: services)
            locationPermission = services.locationPermission
        } else {
            Log.error("live SessionManager has no AppServices; using placeholder status")
            status = PlaceholderStatus()
            locationPermission = LocationPermission()
        }
        super.init()
    }

    func applicationWillFinishLaunching(_ notification: Notification) {
        // Before launch finishes, so the first notification already shows
        // while Uykusuz is frontmost.
        ForegroundNotifications.install()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // No Dock icon even when run from `swift run` (the bundle has LSUIElement).
        NSApp.setActivationPolicy(.accessory)
        Log.info("launched, version \(AppBuild.current.label)")
        if LidSimulationBuild.isCompiledIn {
            Log.info(LidSimulationBuild.marker)
        }
        // The login item is tied to the bundle's signature, which install.sh
        // renews on every run: register again if the flag is on, macOS no
        // longer reports the item and the install changed; follow the user
        // if they removed the item for the install macOS had on file.
        var config = manager.config
        if loginItem.healAtLaunch(config: &config) {
            manager.config = config
            do {
                try manager.store.saveConfig(config)
            } catch {
                Log.error("could not save config after the launch at login check: \(error.localizedDescription)")
            }
        }
        // The screen recording grant is tied to the signature too, and a
        // stale one shows switched on but no longer counts: drop it, so ⌃⌥S
        // puts this install on the list afresh.
        let install = LoginItem.liveInstall()
        if Notifier.runningInsideAppBundle(), let bundleID = Bundle.main.bundleIdentifier {
            Task { @MainActor [manager] in
                let recorded = manager.config.screenPermissionInstall
                guard await ScreenPermission.dropStaleGrant(install: install, recorded: recorded, reset: { await ScreenPermission.resetGrant(bundleID: bundleID) }) else { return }
                var config = manager.config
                config.screenPermissionInstall = install
                manager.config = config
                do {
                    try manager.store.saveConfig(config)
                } catch {
                    Log.error("could not save config after dropping the screen recording grant: \(error.localizedDescription)")
                }
            }
        }
        let notebook = NotebookWindow(advisor: advisor, isOn: { [manager] in manager.config.macAdvisor })
        notebookWindow = notebook
        advisor.isReading = { [weak notebook] in notebook?.isVisible ?? false }
        AdviceNotifications.register()
        AdviceNotifications.onResponse = { [advisor, weak notebook] response in
            Task { await advisor.handle(response) { notebook?.show() } }
        }
        let settings = SettingsWindow { [manager, secrets, locationPermission, loginItem, awaySummary, replyReader, areaReader, waitingAlerts, pushGate, advisor, weak notebook] in
            AnyView(
                SettingsView(
                    manager: manager,
                    secrets: secrets,
                    locationPermission: locationPermission,
                    loginItem: loginItem,
                    awaySummary: awaySummary,
                    replyReader: replyReader,
                    areaReader: areaReader,
                    waitingAlerts: waitingAlerts,
                    pushGate: pushGate,
                    advisor: advisor,
                    openNotebook: { notebook?.show() }
                )
            )
        }
        settingsWindow = settings
        statusItem = StatusItemController(
            manager: manager,
            status: status,
            showSettings: { [weak settings] in settings?.show() },
            lastSummary: { [awaySummary] in
                guard awaySummary.last != nil else { return nil }
                return { Task { await awaySummary.showLast() } }
            },
            notebook: { [manager, advisor, weak notebook] in
                // Off, it stays in the menu while there is something to read.
                guard manager.config.macAdvisor || !advisor.notebook.entries.isEmpty else { return nil }
                return (StatusMenu.notebookTitle(unread: advisor.notebook.unread), { notebook?.show() })
            },
            replyReader: replyReader,
            areaReader: areaReader
        )
        autoSession.onAgentActivityChange = { [weak services = manager.services] active in
            services?.setAgentActive(active)
        }
        autoSession.onAgentWaiting = { [weak services = manager.services, manager] in
            let c = manager.config
            services?.announceAgentWaiting(endsAfter: c.autoSession && c.endWhileWaiting ? c.autoWaitGrace : nil)
        }
        awaySummary.start()
        advisor.start()
        listenHotKey.onPress = { [replyReader] in
            Task { await replyReader.listen() }
        }
        replyReader.start()
        areaHotKey.onPress = { [areaReader] in
            Task { await areaReader.listen() }
        }
        areaReader.start()
        waitingAlerts.start()
        pushGate.start()
        // Hooks an earlier build installed lack the events added since.
        do {
            let added = try ClaudeHooks.upgradeIfInstalled()
            if !added.isEmpty { Log.info("claude hooks: added \(added.joined(separator: ", "))") }
        } catch {
            Log.error("claude hooks: could not add the newer events: \(error.localizedDescription)")
        }
        // After the launch reconcile, so a session left on disk is settled
        // before an automatic one can start.
        Task { [manager, autoSession] in
            await manager.reconcile()
            autoSession.start()
        }
    }

    /// Quitting always ends the session (spec 1). Terminate is deferred until
    /// the end has run. A second quit while that is pending is refused rather
    /// than allowed through: `.terminateNow` there would exit mid-cleanup.
    /// If the end could not run (recovery lock busy, journal unreadable),
    /// left the journal dirty with no agent to retry, or could not remove
    /// session.json, the app stays so its own retry can finish the job;
    /// quitting then would abandon a live session. It also stays while a
    /// `sudo pmset` that ignored SIGTERM is alive. The recovery lock would
    /// outlive a quit (the command holds it through its own descriptor),
    /// but the end the command holds up would not: the app is what retries
    /// it, and confirms an undo the command finishes, the moment it exits.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard !terminating else { return .terminateCancel }
        terminating = true
        autoSession.stop()
        Task {
            let outcome = await manager.end(reason: .quit)
            if outcome.letsQuitGo {
                pushGate.stop()
                sender.reply(toApplicationShouldTerminate: true)
            } else {
                Log.error("quit deferred: recovery still pending (\(outcome)); staying to retry")
                terminating = false
                sender.reply(toApplicationShouldTerminate: false)
            }
        }
        return .terminateLater
    }
}
