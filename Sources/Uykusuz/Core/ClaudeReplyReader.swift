import Foundation
import Observation

/// Reads aloud what Claude says when it finishes (fork addition), in the
/// summary's window (`SummaryPanel`): only the reply, which the `Stop` hook
/// leaves in `ClaudeReplyInbox`. The kernel reports the file, so nothing runs
/// between replies.
///
/// Replies from several sessions are read one after another, and a newer
/// reply takes the place of a waiting one from the same session. A new prompt
/// in a session ends the reading of its reply, which is no longer the last
/// word. With the lid closed or the screen locked nothing is read, since a
/// closed Mac speaks to no one; the reply is kept for the menu's "Son yanıtı
/// dinle". Closing the window, which a lid close or a lock also does, ends
/// the reading and drops the replies still waiting.
@MainActor
@Observable
final class ClaudeReplyReader {
    /// How often a reading looks for a new prompt in its session. It only
    /// runs while there is something to read.
    static let watchInterval: TimeInterval = 2
    /// How long the window stays once there is nothing left to read, for a
    /// listen again. It would otherwise wait on the screen for its close mark.
    static let lingerAfterEnd: TimeInterval = 8

    typealias Present = @MainActor (_ reply: ClaudeReply, _ onFinish: @escaping @MainActor () -> Void, _ onClose: @escaping @MainActor () -> Void) async -> Void

    @ObservationIgnored private let config: @MainActor () -> Config
    @ObservationIgnored private let present: Present
    @ObservationIgnored private let dismiss: @MainActor () -> Void
    @ObservationIgnored private let windowIsReading: @MainActor () -> Bool
    @ObservationIgnored private let canSpeak: @MainActor () -> Bool
    @ObservationIgnored private let paths: Paths
    @ObservationIgnored private let clock: @MainActor () -> Date
    @ObservationIgnored private let linger: TimeInterval
    @ObservationIgnored private var source: DispatchSourceFileSystemObject?
    @ObservationIgnored private var watch: Timer?
    @ObservationIgnored private var lingering: Task<Void, Never>?
    @ObservationIgnored private var queue: [ClaudeReply] = []
    /// The reply in the window that is being read or has been paused.
    @ObservationIgnored private var reading: ClaudeReply?
    /// Which window the callbacks are about: replacing one closes it, and
    /// that close must not count as the user's.
    @ObservationIgnored private var presentation: UUID?

    /// The last reply Claude finished with, for the menu.
    private(set) var last: ClaudeReply?

    init(
        config: @escaping @MainActor () -> Config,
        present: @escaping Present,
        dismiss: @escaping @MainActor () -> Void,
        windowIsReading: @escaping @MainActor () -> Bool,
        canSpeak: @escaping @MainActor () -> Bool,
        paths: Paths = .fromEnvironment(),
        clock: @escaping @MainActor () -> Date = { Date() },
        linger: TimeInterval = ClaudeReplyReader.lingerAfterEnd
    ) {
        self.config = config
        self.present = present
        self.dismiss = dismiss
        self.windowIsReading = windowIsReading
        self.canSpeak = canSpeak
        self.paths = paths
        self.clock = clock
        self.linger = linger
    }

    /// Starts watching the inbox, for the life of the app.
    func start() {
        guard source == nil else { return }
        let dir = ClaudeReplyInbox.directory(paths)
        do {
            _ = try OwnerOnly.createDirectory(dir)
        } catch {
            Log.error("claude replies: could not create \(dir.path): \(error.localizedDescription)")
            return
        }
        let fd = open(dir.path, O_EVTONLY | O_CLOEXEC)
        guard fd >= 0 else {
            Log.error("claude replies: could not watch \(dir.path)")
            return
        }
        let watcher = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: .write, queue: .main)
        watcher.setEventHandler { [weak self] in
            MainActor.assumeIsolated { self?.takeReplies() }
        }
        watcher.setCancelHandler { close(fd) }
        watcher.resume()
        source = watcher
        takeReplies()
    }

    /// Internal so tests drive it.
    func takeReplies() {
        for reply in ClaudeReplyInbox.take(paths: paths) { arrived(reply) }
    }

    /// Internal so tests drive it.
    func arrived(_ reply: ClaudeReply) {
        guard config().readClaudeReplies, !ClaudeReplySpeech.plain(reply.text).isEmpty else { return }
        if reply.at >= last?.at ?? reply.at { last = reply }
        guard canSpeak(), clock().timeIntervalSince(reply.at) <= ClaudeReplyInbox.maxAge else { return }
        queue.removeAll { $0.session == reply.session }
        queue.append(reply)
        playNext()
        startWatching()
    }

    /// The menu's "Son yanıtı dinle": asked for, so it plays whatever the
    /// lid and the setting say, and a prompt sent since does not end it.
    func listenAgain() {
        guard let last else { return }
        queue.removeAll()
        show(last)
        reading = nil
    }

    /// The setting changed: off ends a reading and what waits behind it.
    func settingChanged() {
        guard !config().readClaudeReplies, presentation != nil || !queue.isEmpty else { return }
        queue.removeAll()
        reading = nil
        if presentation != nil { dismiss() }
    }

    /// One look at whether anything was overtaken. Internal so tests drive it.
    func look() {
        // Behind a summary, whose window the lid took down without telling us.
        if !canSpeak() { queue.removeAll() }
        queue.removeAll(where: overtaken)
        if let reading, overtaken(reading) {
            self.reading = nil
            presentation = nil
            dismiss()
        }
        playNext()
        if reading == nil, queue.isEmpty { stopWatching() }
    }

    // MARK: Private

    /// The user sent that session a new prompt after this reply. Both are
    /// stamped to the second, and the `Stop` that left the reply removed the
    /// marker, so a prompt in the same second came after it too.
    private func overtaken(_ reply: ClaudeReply) -> Bool {
        let file = ClaudeHookCommand.markerDirectory(paths).appendingPathComponent("\(reply.session).json")
        guard let prompted = ClaudeHookCommand.readMarker(file)?.promptedAt else { return false }
        return prompted >= reply.at
    }

    /// The window also reads a summary the user asked for, or a reply they
    /// asked to hear again; neither is cut off.
    private func playNext() {
        guard reading == nil, !windowIsReading(), !queue.isEmpty else { return }
        show(queue.removeFirst())
    }

    private func show(_ reply: ClaudeReply) {
        let id = UUID()
        presentation = id
        reading = reply
        lingering?.cancel()
        lingering = nil
        Log.info("claude reply: reading \(reply.text.count) characters aloud")
        Task { [present] in
            await present(reply, { [weak self] in self?.finished(id) }, { [weak self] in self?.closed(id) })
        }
    }

    private func finished(_ id: UUID) {
        guard id == presentation else { return }
        reading = nil
        if !queue.isEmpty {
            playNext()
            return
        }
        stopWatching()
        lingering?.cancel()
        lingering = Task { [weak self, linger] in
            try? await Task.sleep(for: .seconds(linger))
            guard !Task.isCancelled, let self, id == self.presentation, !self.windowIsReading() else { return }
            self.dismiss()
        }
    }

    private func closed(_ id: UUID) {
        guard id == presentation else { return }
        presentation = nil
        reading = nil
        queue.removeAll()
        lingering?.cancel()
        lingering = nil
        stopWatching()
    }

    private func startWatching() {
        guard watch == nil else { return }
        let timer = Timer(timeInterval: Self.watchInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.look() }
        }
        timer.tolerance = Self.watchInterval / 2
        RunLoop.main.add(timer, forMode: .common)
        watch = timer
    }

    private func stopWatching() {
        watch?.invalidate()
        watch = nil
    }
}
