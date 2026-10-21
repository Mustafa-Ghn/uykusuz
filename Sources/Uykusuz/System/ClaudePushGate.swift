import CoreGraphics
import Foundation

/// Whether the user is at the Mac, for what goes to their phone (fork
/// addition): away while the lid is closed, the screen is locked, or
/// nothing was typed or clicked for `idleLimit` (the screen gone dark).
enum UserPresence {
    static let idleLimit: TimeInterval = 2 * 60

    static func isAway(lidClosed: Bool, screenLocked: Bool, idle: TimeInterval, idleLimit: TimeInterval = idleLimit) -> Bool {
        lidClosed || screenLocked || idle >= idleLimit
    }

    static func liveIsAway() -> Bool {
        isAway(
            lidClosed: LidObserver.readClamshellState() ?? false,
            screenLocked: screenIsLocked(),
            idle: UserInput.secondsSinceLastInput()
        )
    }

    /// The lock screen is up: from the login session's dictionary, which
    /// carries the key only while it is.
    static func screenIsLocked() -> Bool {
        guard let session = CGSessionCopyCurrentDictionary() as? [String: Any] else { return false }
        return (session["CGSSessionScreenIsLocked"] as? Bool) ?? false
    }
}

/// Claude's own phone pushes only while the user is away (fork addition).
/// With Remote Control on, Claude Code pushes to the Claude app on the
/// phone when a permission prompt or a question waits and when it decides
/// a finished task is worth it, but skips those pushes while the file that
/// `CLAUDE_CLIENT_PRESENCE_FILE` names exists. With "Telefondan yanıt" on,
/// that variable names `file` in the user's Claude Code settings
/// (`ClaudeHooks.installPresence`), and this keeps the file there exactly
/// while the user is at the Mac (`UserPresence`). Turned off, or Uykusuz
/// quitting, takes the file away, so the pushes go out as they would
/// without it.
@MainActor
final class ClaudePushGate {
    static let interval: TimeInterval = 5
    nonisolated static let fileName = "claude-present"

    let file: URL
    private let enabled: @MainActor () -> Bool
    private let away: @MainActor () -> Bool
    private var timer: Timer?

    init(
        file: URL,
        enabled: @escaping @MainActor () -> Bool,
        away: @escaping @MainActor () -> Bool = { UserPresence.liveIsAway() }
    ) {
        self.file = file
        self.enabled = enabled
        self.away = away
    }

    nonisolated static func file(in paths: Paths) -> URL {
        paths.appSupport.appendingPathComponent(fileName)
    }

    func start() {
        guard timer == nil else { return }
        tick()
        let t = Timer(timeInterval: Self.interval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    /// Stops and takes the file away: with Uykusuz gone, nothing would
    /// take it away when the user leaves.
    func stop() {
        timer?.invalidate()
        timer = nil
        setPresent(false)
    }

    /// One look. Internal so tests drive it.
    func tick() {
        setPresent(enabled() && !away())
    }

    private func setPresent(_ present: Bool) {
        let fm = FileManager.default
        let exists = fm.fileExists(atPath: file.path)
        if present, !exists {
            if !fm.createFile(atPath: file.path, contents: nil, attributes: [.posixPermissions: 0o600]) {
                Log.error("phone replies: could not create \(file.path)")
            }
        } else if !present, exists {
            do {
                try fm.removeItem(at: file)
            } catch {
                Log.error("phone replies: could not remove \(file.path): \(error.localizedDescription)")
            }
        }
    }
}
