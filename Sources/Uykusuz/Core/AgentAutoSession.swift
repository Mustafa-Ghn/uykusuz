import Foundation

/// When to start, extend and end a session for an agent at work (fork
/// addition). Pure: `AgentAutoSession` feeds it readings and runs what it
/// returns. A session is "ours" only if this policy started it and the
/// user has not set a time on it since (`handOver`); a session the user
/// started or took over is never extended or ended here.
///
/// - Start: an agent is at work, no session is active, the last start did
///   not fail within `retryAfterFailedStart`, the Mac is not hot, and on
///   battery the charge is more than `startMargin` above the end floor.
/// - Extend: our session has less than `extendBelow` left while the agent
///   is still at work, by `chunk`.
/// - End: the agent has not been at work for `idleGrace`.
/// - Paused (`Inputs.pausedUntil`, the user's choice): no start before
///   then, and our session, if one still runs, ends.
/// - Hands off after an end it did not ask for (the user held the end
///   control, a floor or the timer ended it): no new start until the agent
///   lets go once, so a session the user ended is not started again under
///   them. The same when a session of the user's ends before its time; one
///   that ran its time out lets ours follow while the agent works.
struct AutoSessionPolicy: Equatable, Sendable {
    enum Action: Equatable, Sendable {
        case start(TimeInterval)
        case extend(TimeInterval)
        case end
    }

    struct Inputs: Equatable, Sendable {
        var now: Date
        var agentActive: Bool
        /// nil when no session is active.
        var sessionStartedAt: Date?
        var sessionEndsAt: Date?
        var batteryPercent: Int?
        var isCharging: Bool
        var thermal: ProcessInfo.ThermalState
        var endFloor: Int
        /// `Config.autoPausedUntil`.
        var pausedUntil: Date? = nil

        var paused: Bool { pausedUntil.map { now < $0 } ?? false }
    }

    static let chunk: TimeInterval = 2 * 3600
    static let extendBelow: TimeInterval = 3600
    static let idleGrace: TimeInterval = 5 * 60
    static let retryAfterFailedStart: TimeInterval = 10 * 60
    static let startMargin = 5

    /// `startedAt` of the session this policy started, while it lasts.
    private(set) var ownSession: Date?
    private(set) var lastActive: Date?
    private(set) var suppressed = false
    private(set) var retryAt: Date?
    /// Set when this policy asked for our session's end, so its going away
    /// is not taken for an end someone else made.
    private(set) var ending = false

    /// A session of the user's (started by them, taken over, or one a
    /// relaunch reconciled) as last seen, so its end can be told apart:
    /// before its time (the end control, a floor, a quit) or at it.
    struct UserSession: Equatable, Sendable {
        var startedAt: Date
        var endsAt: Date
    }
    private(set) var userSession: UserSession?

    mutating func step(_ i: Inputs) -> Action? {
        if i.agentActive { lastActive = i.now }
        if let own = ownSession, i.sessionStartedAt != own {
            // Ours is gone: through the end asked for below (`ending`), or
            // one someone else made.
            ownSession = nil
            if i.agentActive, !ending { suppressed = true }
            ending = false
        }
        if let user = userSession, i.sessionStartedAt != user.startedAt {
            // Theirs is gone: ended before its time, so no start under them;
            // at its time, what they set has run out.
            userSession = nil
            if i.agentActive, i.now < user.endsAt { suppressed = true }
        }
        // Letting go clears the hand-off; so does a pause the user chose,
        // which takes its place: once it is over, ours starts again if the
        // agent is still at work.
        if !i.agentActive || i.paused { suppressed = false }

        if let started = i.sessionStartedAt {
            guard started == ownSession else {
                if let endsAt = i.sessionEndsAt {
                    userSession = UserSession(startedAt: started, endsAt: endsAt)
                }
                return nil
            }
            if i.paused {
                ending = true
                return .end
            }
            if i.agentActive {
                ending = false
                if let endsAt = i.sessionEndsAt, endsAt.timeIntervalSince(i.now) < Self.extendBelow {
                    return .extend(Self.chunk)
                }
                return nil
            }
            if let last = lastActive, i.now.timeIntervalSince(last) < Self.idleGrace { return nil }
            // Kept until the session is gone: an end refused by a busy
            // lock is asked for again on the next step.
            ending = true
            return .end
        }

        guard i.agentActive, !suppressed, !i.paused else { return nil }
        if let retryAt, i.now < retryAt { return nil }
        guard Self.powerAllowsStart(i) else { return nil }
        return .start(Self.chunk)
    }

    mutating func started(at startedAt: Date) {
        ownSession = startedAt
        retryAt = nil
        ending = false
    }

    mutating func startFailed(at now: Date) {
        retryAt = now.addingTimeInterval(Self.retryAfterFailedStart)
    }

    /// The user set a time on our session (or turned the feature off): it is
    /// theirs from now on.
    mutating func handOver() {
        ownSession = nil
        ending = false
    }

    static func powerAllowsStart(_ i: Inputs) -> Bool {
        if i.thermal == .serious || i.thermal == .critical { return false }
        if !i.isCharging, let p = i.batteryPercent, p <= i.endFloor + startMargin { return false }
        return true
    }
}

/// Runs `AutoSessionPolicy` every `interval` seconds for the life of the
/// app (fork addition), and reports whether an agent is at work so code
/// mode can follow it (`onAgentActivityChange`).
@MainActor
final class AgentAutoSession {
    static let interval: TimeInterval = 15

    private let manager: SessionManager
    private let isAgentActive: @MainActor (Config) -> Bool
    private let readPower: @MainActor () -> (percent: Int?, isCharging: Bool)
    private let thermal: @MainActor () -> ProcessInfo.ThermalState
    private let clock: @MainActor () -> Date
    private(set) var policy = AutoSessionPolicy()
    private var timer: (any DispatchSourceTimer)?
    private var ticking = false
    private(set) var agentActive = false
    var onAgentActivityChange: (@MainActor (Bool) -> Void)?

    init(
        manager: SessionManager,
        isAgentActive: @escaping @MainActor (Config) -> Bool = { AgentActivity.isActive(config: $0, paths: .fromEnvironment()) },
        readPower: @escaping @MainActor () -> (percent: Int?, isCharging: Bool) = AgentAutoSession.livePower,
        thermal: @escaping @MainActor () -> ProcessInfo.ThermalState = { ProcessInfo.processInfo.thermalState },
        clock: @escaping @MainActor () -> Date = { Date() }
    ) {
        self.manager = manager
        self.isAgentActive = isAgentActive
        self.readPower = readPower
        self.thermal = thermal
        self.clock = clock
    }

    func start() {
        guard timer == nil else { return }
        let t = DispatchSource.makeTimerSource(queue: .main)
        t.schedule(deadline: .now(), repeating: Self.interval, leeway: .seconds(2))
        t.setEventHandler { [weak self] in
            Task { @MainActor in await self?.tick() }
        }
        timer = t
        t.resume()
    }

    func stop() {
        timer?.cancel()
        timer = nil
    }

    /// One reading and at most one action. Internal so tests drive it.
    func tick() async {
        guard !ticking else { return }
        ticking = true
        defer { ticking = false }
        let config = manager.config
        let active = isAgentActive(config)
        if active != agentActive {
            agentActive = active
            Log.info("agent \(active ? "at work" : "idle")")
            onAgentActivityChange?(active)
        }
        guard config.autoSession else {
            // Turned off: a session of ours runs out its time as the user's.
            if policy.ownSession != nil { policy.handOver() }
            if manager.isAutoSession { manager.releaseAutoSession() }
            return
        }
        // The user set a time on ours (`SessionManager.takeOver`).
        if let own = policy.ownSession, manager.session?.startedAt == own, !manager.isAutoSession {
            policy.handOver()
        }
        let power = readPower()
        let now = clock()
        if let until = config.autoPausedUntil, now >= until {
            await manager.pauseAutoSessions(until: nil)
        }
        let action = policy.step(.init(
            now: now,
            agentActive: active,
            sessionStartedAt: manager.session?.startedAt,
            sessionEndsAt: manager.session?.endsAt,
            batteryPercent: power.percent,
            isCharging: power.isCharging,
            thermal: thermal(),
            endFloor: config.endFloor,
            pausedUntil: manager.config.autoPausedUntil
        ))
        switch action {
        case let .start(duration)?:
            Log.info("auto session: starting for \(Int(duration / 60)) min, an agent is at work")
            await manager.start(duration: duration, auto: true)
            if let started = manager.session?.startedAt {
                policy.started(at: started)
            } else {
                Log.info("auto session: start did not take; retrying in \(Int(AutoSessionPolicy.retryAfterFailedStart / 60)) min")
                policy.startFailed(at: now)
            }
        case let .extend(extra)?:
            Log.info("auto session: extending by \(Int(extra / 60)) min, the agent is still at work")
            await manager.extend(by: extra)
        case .end? where manager.autoSessionsPaused(at: now):
            Log.info("auto session: ending, automatic sessions are paused")
            _ = await manager.end(reason: .user)
        case .end?:
            Log.info("auto session: ending, the agent has been idle for \(Int(AutoSessionPolicy.idleGrace / 60)) min")
            _ = await manager.end(reason: .agentIdle)
        case nil:
            break
        }
    }

    static func livePower() -> (percent: Int?, isCharging: Bool) {
        let monitor = PowerMonitor()
        monitor.refreshBattery()
        return (monitor.percent, monitor.isCharging)
    }
}
