import AppKit
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
    /// "While you were away" when the lid opens (fork addition).
    let awaySummary: AwaySummary
    private var statusItem: StatusItemController?
    private var settingsWindow: SettingsWindow?
    private var terminating = false

    override init() {
        let manager = SessionManager.live()
        self.manager = manager
        autoSession = AgentAutoSession(manager: manager)
        awaySummary = AwaySummary(config: { [manager] in manager.config }, notifier: manager.services?.notifier ?? Notifier())
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
        let settings = SettingsWindow { [manager, secrets, locationPermission, loginItem, awaySummary] in
            AnyView(
                SettingsView(
                    manager: manager,
                    secrets: secrets,
                    locationPermission: locationPermission,
                    loginItem: loginItem,
                    awaySummary: awaySummary
                )
            )
        }
        settingsWindow = settings
        statusItem = StatusItemController(manager: manager, status: status) { [weak settings] in
            settings?.show()
        }
        autoSession.onAgentActivityChange = { [weak services = manager.services] active in
            services?.setAgentActive(active)
        }
        autoSession.onAgentWaiting = { [weak services = manager.services, manager] in
            let c = manager.config
            services?.announceAgentWaiting(endsAfter: c.autoSession && c.endWhileWaiting ? c.approvalWaitGrace : nil)
        }
        awaySummary.start()
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
