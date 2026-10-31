import Foundation

/// "Docker is in use" and "its work is done" on the phone (fork addition),
/// by the same iMessage as `WaitingAlerts`: one message for a stretch of work
/// however many containers come and go in it, and one when it ends.
///
/// The work has to last `settle`, so a quick command tells nothing, and has
/// to stay over for `finishSettle`, so steps a little apart are one job. At
/// the Mac nothing is sent, but the use is a state rather than a moment:
/// leaving while Docker is still at work tells it then, however long ago the
/// work began. A work that was told is always told to have ended, wherever
/// the user is by then. At most one stretch per `gap`.
@MainActor
final class DockerAlerts {
    static let interval: TimeInterval = 30
    static let settle: TimeInterval = WaitingAlerts.settle
    static let finishSettle: TimeInterval = 2 * 60
    static let gap: TimeInterval = WaitingAlerts.perSessionGap
    static let lead = "Uykusuz · Docker: "
    static let maxNames = 5

    private let config: @MainActor () -> Config
    private let activity: @MainActor () async -> DockerActivity?
    private let away: @MainActor () -> Bool
    private let send: @MainActor (_ text: String, _ what: String) async -> Void
    private let clock: @MainActor () -> Date
    private var timer: Timer?
    private var ticking = false
    private var busySince: Date?
    private var idleSince: Date?
    /// The stretch going on was told, so its end is owed.
    private var told = false
    private var lastTold: Date?

    init(
        config: @escaping @MainActor () -> Config,
        activity: @escaping @MainActor () async -> DockerActivity?,
        away: @escaping @MainActor () -> Bool,
        send: @escaping @MainActor (String, String) async -> Void,
        clock: @escaping @MainActor () -> Date = { Date() }
    ) {
        self.config = config
        self.activity = activity
        self.away = away
        self.send = send
        self.clock = clock
    }

    func start() {
        guard timer == nil else { return }
        let t = Timer(timeInterval: Self.interval, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.tick() }
        }
        t.tolerance = Self.interval / 3
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    /// One look. Internal so tests drive it.
    func tick() async {
        guard !ticking else { return }
        ticking = true
        defer { ticking = false }
        let c = config()
        guard c.imessageAlerts, c.dockerAlerts, !c.imessageHandle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            busySince = nil
            idleSince = nil
            told = false
            return
        }
        guard let reading = await activity() else { return }
        let now = clock()
        if reading.isBusy {
            idleSince = nil
            let since = busySince ?? now
            busySince = since
            guard !told, now.timeIntervalSince(since) >= Self.settle, away() else { return }
            if let lastTold, now.timeIntervalSince(lastTold) < Self.gap { return }
            told = true
            lastTold = now
            await send(Self.activeText(reading), "docker active")
        } else {
            guard told else {
                busySince = nil
                return
            }
            let quietSince = idleSince ?? now
            idleSince = quietSince
            guard now.timeIntervalSince(quietSince) >= Self.finishSettle else { return }
            let lasted = quietSince.timeIntervalSince(busySince ?? quietSince)
            busySince = nil
            idleSince = nil
            told = false
            await send(Self.finishedText(reading, lasted: lasted), "docker finished")
        }
    }

    // MARK: Text

    static func activeText(_ activity: DockerActivity) -> String {
        lead + "aktif kullanılıyor (\(names(activity.working))). İş bitince yine haber vereceğim."
    }

    static func finishedText(_ activity: DockerActivity, lasted: TimeInterval) -> String {
        let rest = activity.idle.isEmpty ? "Çalışan kapsayıcı kalmadı." : "Açık ama boşta: \(names(activity.idle))."
        return lead + "iş bitti, \(ClaudeDigest.minutes(lasted)) dakika sürdü. \(rest)"
    }

    private static func names(_ all: [String]) -> String {
        let shown = all.prefix(maxNames).joined(separator: ", ")
        return all.count > maxNames ? "\(shown) ve \(all.count - maxNames) tane daha" : shown
    }
}
