import Foundation
import Observation

/// Reads aloud what Claude last said in the chat the user is looking at, when
/// they ask for it (fork addition): a system-wide shortcut, or the menu. While
/// the chat waits on the user to approve a plan, the plan is read instead. It
/// comes in the summary's window (`SummaryPanel`), and nothing is ever read
/// on its own. Pressing again in the same chat ends the reading; pressing in
/// another chat, or once Claude has said something new, reads that instead.
@MainActor
@Observable
final class ClaudeReplyReader {
    /// How long the window stays once the reading is over, for a listen
    /// again. It would otherwise wait on the screen for its close mark.
    static let lingerAfterEnd: TimeInterval = 8
    /// As Settings and the menu show the shortcut.
    static let shortcutLabel = "\u{2303}\u{2325}D"
    nonisolated static let nothingToRead = "Okunacak bir Claude yanıtı bulunamadı."
    /// Before the chat's title in the window, for a plan.
    static let planTitle = "Plan"

    /// The window's title: the chat's, and for a plan that it is one.
    static func title(of reply: ClaudeReply) -> String {
        reply.isPlan ? "\(planTitle) · \(reply.title)" : reply.title
    }

    typealias Present = @MainActor (_ reply: ClaudeReply, _ onFinish: @escaping @MainActor () -> Void, _ onClose: @escaping @MainActor () -> Void) async -> Void

    @ObservationIgnored private let config: @MainActor () -> Config
    @ObservationIgnored private let find: @Sendable () -> ClaudeReply?
    @ObservationIgnored private let present: Present
    @ObservationIgnored private let dismiss: @MainActor () -> Void
    @ObservationIgnored private let resume: @MainActor () -> Void
    @ObservationIgnored private let windowIsReading: @MainActor () -> Bool
    @ObservationIgnored private let setShortcut: @MainActor (Bool) -> Bool
    @ObservationIgnored private let paths: Paths
    @ObservationIgnored private let clock: @MainActor () -> Date
    @ObservationIgnored private let linger: TimeInterval
    @ObservationIgnored private var lingering: Task<Void, Never>?
    /// The reply in the window. Replacing a window closes it, and `shownID`
    /// keeps that close from counting as the user's.
    @ObservationIgnored private var shown: ClaudeReply?
    @ObservationIgnored private var shownID: UUID?

    /// Another app has the shortcut to itself, for Settings.
    private(set) var shortcutTaken = false

    init(
        config: @escaping @MainActor () -> Config,
        find: @escaping @Sendable () -> ClaudeReply? = { ClaudeChats.lastReply() },
        present: @escaping Present,
        dismiss: @escaping @MainActor () -> Void,
        resume: @escaping @MainActor () -> Void,
        windowIsReading: @escaping @MainActor () -> Bool,
        setShortcut: @escaping @MainActor (Bool) -> Bool,
        paths: Paths = .fromEnvironment(),
        clock: @escaping @MainActor () -> Date = { Date() },
        linger: TimeInterval = ClaudeReplyReader.lingerAfterEnd
    ) {
        self.config = config
        self.find = find
        self.present = present
        self.dismiss = dismiss
        self.resume = resume
        self.windowIsReading = windowIsReading
        self.setShortcut = setShortcut
        self.paths = paths
        self.clock = clock
        self.linger = linger
    }

    /// Takes the shortcut, for the life of the app. Builds that read every
    /// reply on their own left them in this folder for a moment.
    func start() {
        try? FileManager.default.removeItem(at: paths.appSupport.appendingPathComponent("claude-replies", isDirectory: true))
        settingChanged()
    }

    func settingChanged() {
        let on = config().listenShortcut
        shortcutTaken = !setShortcut(on)
    }

    /// The shortcut, or the menu's "Son yanıtı dinle".
    func listen() async {
        let found = await Task.detached(priority: .userInitiated) { [find] in find() }.value
        let reply = found.flatMap { ClaudeReplySpeech.plain($0.text).isEmpty ? nil : $0 }
            ?? ClaudeReply(session: "", title: "Claude", text: Self.nothingToRead, at: clock())
        if reply == shown, shownID != nil {
            if windowIsReading() { dismiss() } else { resume() }
        } else {
            show(reply)
        }
    }

    private func show(_ reply: ClaudeReply) {
        let id = UUID()
        shownID = id
        shown = reply
        lingering?.cancel()
        lingering = nil
        Log.info("claude reply: reading \(reply.isPlan ? "a plan of " : "")\(reply.text.count) characters aloud")
        Task { [weak self, present] in
            await present(reply, { self?.finished(id) }, { self?.closed(id) })
        }
    }

    private func finished(_ id: UUID) {
        guard id == shownID else { return }
        lingering?.cancel()
        lingering = Task { [weak self, linger] in
            try? await Task.sleep(for: .seconds(linger))
            guard !Task.isCancelled, let self, id == self.shownID, !self.windowIsReading() else { return }
            self.dismiss()
        }
    }

    private func closed(_ id: UUID) {
        guard id == shownID else { return }
        shownID = nil
        shown = nil
        lingering?.cancel()
        lingering = nil
    }
}
