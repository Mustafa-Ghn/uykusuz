import AppKit
import Foundation
import Observation

/// "While you were away" (fork addition): when the user is back after
/// `minimumAway` with the lid closed or the screen locked (the idle black
/// screen locks it too), what Claude Code did in between is told in one
/// or two Turkish sentences, in a small window at the top right
/// (`SummaryPanel`) that reads them aloud only when asked: the user may
/// have opened the lid somewhere quiet, or for something else. With a
/// Claude API key saved, Claude writes the sentences
/// (`AnthropicSummaryClient`); without one, or when the request fails, they
/// are put together here from counts (`ClaudeDigest.localSummary`), and
/// nothing leaves the Mac.
///
/// It watches the lid and the lock on its own, whether or not a session
/// runs: Claude may have finished, and its session ended, long before the
/// lid opens. The absence starts at the close or the lock, whichever came
/// first; a lock after a while without input (the idle black screen's)
/// starts it at the last input. The user is back once the lid is open and
/// the screen unlocked, so the summary never waits behind the lock screen.
@MainActor
@Observable
final class AwaySummary {
    static let minimumAway: TimeInterval = 3 * 60
    static let title = "Sen yokken Claude"
    static let nothingToTell = "Bu sürede Claude'un yaptığı bir iş yok."

    @ObservationIgnored private let config: @MainActor () -> Config
    @ObservationIgnored private let present: @MainActor (_ text: String, _ told: Date) async -> Void
    @ObservationIgnored private let dismiss: @MainActor () -> Void
    @ObservationIgnored let keyStore: any AnthropicKeyStoring
    @ObservationIgnored private let digest: @MainActor (Date, Date) -> ClaudeDigest?
    @ObservationIgnored private let writer: @MainActor (_ key: String, _ model: String) -> any SummaryWriting
    @ObservationIgnored private let clock: @MainActor () -> Date
    @ObservationIgnored private let screenIsLocked: @MainActor () -> Bool
    @ObservationIgnored private let idleSeconds: @MainActor () -> TimeInterval
    @ObservationIgnored private var lid: LidObserver?
    @ObservationIgnored private var lockObservers: [any NSObjectProtocol] = []
    @ObservationIgnored private var awaySince: Date?
    @ObservationIgnored private var lidClosed = false

    /// The last summary, or why there was none, for Settings.
    private(set) var lastResult: String?
    /// The last summary told and when, for the menu's "Son özeti göster".
    private(set) var last: (text: String, told: Date)?
    private(set) var isSummarizing = false

    init(
        config: @escaping @MainActor () -> Config,
        present: @escaping @MainActor (String, Date) async -> Void,
        dismiss: @escaping @MainActor () -> Void = {},
        paths: Paths = .fromEnvironment(),
        keyStore: any AnthropicKeyStoring = KeychainAnthropicKeyStore(),
        digest: (@MainActor (Date, Date) -> ClaudeDigest?)? = nil,
        writer: (@MainActor (String, String) -> any SummaryWriting)? = nil,
        clock: @escaping @MainActor () -> Date = { Date() },
        screenIsLocked: @escaping @MainActor () -> Bool = { UserPresence.screenIsLocked() },
        idleSeconds: @escaping @MainActor () -> TimeInterval = { UserInput.secondsSinceLastInput() }
    ) {
        self.config = config
        self.present = present
        self.dismiss = dismiss
        self.keyStore = keyStore
        self.digest = digest ?? { from, to in
            ClaudeDigest.build(from: from, to: to) { AwaySummary.status(ofSession: $0, paths: paths, now: to) }
        }
        self.writer = writer ?? { key, model in AnthropicSummaryClient(key: key, model: model) }
        self.clock = clock
        self.screenIsLocked = screenIsLocked
        self.idleSeconds = idleSeconds
    }

    /// Starts watching the lid and the lock, for the life of the app.
    func start() {
        guard lid == nil else { return }
        let observer = LidObserver()
        observer.onChange = { [weak self] closed in self?.lidChanged(closed: closed) }
        observer.start()
        lid = observer
        let center = DistributedNotificationCenter.default()
        for (name, isLocked) in [("com.apple.screenIsLocked", true), ("com.apple.screenIsUnlocked", false)] {
            lockObservers.append(center.addObserver(forName: Notification.Name(name), object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.lockChanged(locked: isLocked) }
            })
        }
    }

    /// Internal so tests drive it. A lid close takes a summary that is up
    /// down, so it is never read aloud into a closed Mac.
    func lidChanged(closed: Bool) {
        lidClosed = closed
        if closed {
            leave(at: clock())
        } else if !screenIsLocked() {
            back()
        }
    }

    /// Internal so tests drive it. A lock takes a summary that is up down;
    /// the absence it starts began at the last input.
    func lockChanged(locked isLocked: Bool) {
        if isLocked {
            leave(at: clock().addingTimeInterval(-max(0, idleSeconds())))
        } else if !lidClosed {
            back()
        }
    }

    /// The earliest start of an absence is kept: a lock after a close, or a
    /// close after a lock, is the same absence.
    private func leave(at start: Date) {
        awaySince = min(awaySince ?? start, start)
        dismiss()
    }

    private func back() {
        guard let since = awaySince else { return }
        awaySince = nil
        let now = clock()
        guard config().awaySummary, now.timeIntervalSince(since) >= Self.minimumAway else { return }
        Task { await summarize(from: since, to: now, away: true, sayIfNothing: false) }
    }

    /// Puts the last summary up again.
    func showLast() async {
        guard let last else { return }
        await present(last.text, last.told)
    }

    /// Tells what Claude did between `from` and `to`. `away`: the span is
    /// the lid closed, not one asked for. `sayIfNothing`: the Settings
    /// button, which reports a quiet stretch as well. Returns the text told.
    @discardableResult
    func summarize(from: Date, to: Date, away: Bool, sayIfNothing: Bool) async -> String? {
        guard !isSummarizing else { return nil }
        isSummarizing = true
        defer { isSummarizing = false }
        guard var digest = digest(from, to) else {
            Log.info("away summary: nothing Claude did to tell")
            if sayIfNothing {
                lastResult = Self.nothingToTell
                await present(Self.nothingToTell, clock())
            }
            return nil
        }
        digest.away = away
        var text = digest.localSummary
        var note = "yerel özet; API anahtarı yok"
        switch await keyStore.read() {
        case let .key(key):
            do {
                text = try await writer(key, config().summaryModel).summarize(digest)
                note = "Claude yazdı"
            } catch {
                Log.error("away summary: the API request failed (\(error.localizedDescription)); told the local summary")
                note = "yerel özet; API isteği başarısız: \(error.localizedDescription)"
            }
        case .unreadable:
            Log.info("away summary: the API key was saved by another build; told the local summary")
            note = "yerel özet; anahtarı bu sürüm okuyamıyor, Ayarlar'dan yeniden kaydedin"
        case let .error(message):
            Log.error("away summary: the API key could not be read (\(message)); told the local summary")
            note = "yerel özet; anahtar okunamadı: \(message)"
        case .none:
            break
        }
        let told = clock()
        Log.info("away summary told (\(note))")
        lastResult = "\(Self.clockText(told)): \(text) (\(note))"
        last = (text, told)
        await present(text, told)
        return text
    }

    /// A session's state now, from its hook marker (`ClaudeHookCommand`).
    nonisolated static func status(ofSession id: String, paths: Paths, now: Date) -> ClaudeDigest.Status {
        guard let name = ClaudeHookCommand.markerName(id),
              let marker = ClaudeHookCommand.readMarker(ClaudeHookCommand.markerDirectory(paths).appendingPathComponent(name)),
              now.timeIntervalSince(marker.updatedAt) < ClaudeActivity.markerMaxAge else { return .done }
        return marker.waitingSince == nil ? .working : .waiting
    }

    private static func clockText(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "tr_TR")
        f.dateFormat = "HH:mm"
        return f.string(from: date)
    }
}

/// `Uykusuz --away-digest [minutes]`: prints what the away summary would be
/// made from for the last `minutes` (60 by default) and the summary made
/// here, to check either without closing the lid. Nothing is sent.
enum AwayDigestCommand {
    static let flag = "--away-digest"

    static func run(_ arguments: [String], paths: Paths = .fromEnvironment(), now: Date = Date()) -> Int32? {
        guard arguments.first == flag else { return nil }
        let minutes = arguments.dropFirst().first.flatMap(Double.init) ?? 60
        let from = now.addingTimeInterval(-minutes * 60)
        guard var digest = ClaudeDigest.build(from: from, to: now, status: { AwaySummary.status(ofSession: $0, paths: paths, now: now) }) else {
            print("Son \(Int(minutes)) dakikada Claude'un yaptığı bir iş yok.")
            return 0
        }
        digest.away = false
        print(digest.promptText)
        print("")
        print("Yerel özet: \(digest.localSummary)")
        return 0
    }
}
