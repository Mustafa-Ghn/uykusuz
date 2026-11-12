import Foundation
import Network
import os

/// Going on with a Claude Code session that a network outage stopped (fork
/// addition).
///
/// Claude Code tries a request it cannot send ten times, about three
/// minutes, and then ends the turn with an API error. The session stays
/// there until the user asks again, however soon the network is back. Its
/// `StopFailure` hook runs this app with `asyncRewake` (`ClaudeHooks`): such
/// a hook goes on in the background, and when it exits with `wakeStatus`
/// Claude Code starts a turn with what the hook wrote to stderr. So for a
/// turn an outage ended, the hook waits for the API's host to answer again
/// and then exits that way, with `message`.
///
/// Only an outage is resumed (`isOutage`). Claude Code must have filed the
/// failure as a server error, which leaves out a usage or spend limit, a
/// billing or sign-in problem and a request the API turned down; and the
/// network must be the reason: the API's host cannot be reached now, or
/// Claude Code's last attempt found the network down. Anything else is left
/// as it is, for the user to try again.
enum ClaudeOutageResume {
    /// The exit status on which Claude Code wakes the session.
    static let wakeStatus: Int32 = 2
    /// What Claude Code files a failure under when it is neither the
    /// account's nor the request's.
    static let serverError = "server_error"
    /// The marker's event while the hook waits for the network.
    static let waitingEvent = "StopFailure"
    /// For this long the waiting session counts as at work, so the automatic
    /// session keeps the Mac awake for the network to come back.
    static let keepAwake: TimeInterval = 60 * 60
    /// The hook gives up after waiting this long.
    static let maxWait: TimeInterval = 6 * 3600
    static let pollInterval: TimeInterval = 5
    /// Resumes in a row for one session. A real prompt, a tool Claude runs
    /// or a turn that ends well starts the count again.
    static let maxResumes = 3
    /// How much of the transcript's end is read for the failed attempt.
    static let transcriptTail = 512 << 10

    /// What Claude reads when the session wakes. Claude Code puts "Stop hook
    /// blocking error" in front of it, hence the second sentence.
    static let message = "Uykusuz: İnternet bağlantısı kesildiği için önceki istek yanıtsız kaldı; bağlantı geri geldi. Bu bir hata değildir ve kullanıcı yeni bir şey yazmadı. Yarım kalan işi kaldığınız yerden sürdürün; yapılacak bir şey kalmadıysa bunu tek cümleyle söyleyin."

    /// A turn to resume: a server error, with the network as its reason.
    static func isOutage(error: String?, reachable: Bool, networkDownInTranscript: Bool) -> Bool {
        error == serverError && (!reachable || networkDownInTranscript)
    }

    /// Whether a prompt is the one a resume made, which is not the user's.
    static func isResumePrompt(_ prompt: String?) -> Bool {
        prompt?.contains(message) ?? false
    }

    // MARK: State

    /// One session's wait, kept beside the markers.
    struct Wait: Codable, Equatable, Sendable {
        /// The hook waiting for this session. A later failure's hook takes
        /// its place, and the earlier one stands down.
        var waiter: String
        /// Resumes made since the session last got somewhere.
        var resumes: Int
    }

    static func directory(_ paths: Paths) -> URL {
        paths.appSupport.appendingPathComponent("claude-outages", isDirectory: true)
    }

    static func readWait(_ file: URL) -> Wait? {
        (try? Data(contentsOf: file)).flatMap { try? JSONDecoder().decode(Wait.self, from: $0) }
    }

    private static func write(_ wait: Wait, to file: URL) {
        do {
            _ = try OwnerOnly.createDirectory(file.deletingLastPathComponent())
            try JSONEncoder().encode(wait).write(to: file, options: .atomic)
            chmod(file.path, 0o600)
        } catch {
            Log.error("claude outage: could not write \(file.path): \(error.localizedDescription)")
        }
    }

    /// The session got somewhere, or the user took over: no hook waits for
    /// it any more and its resumes count from zero. `name` is the session's
    /// marker file name.
    static func clear(session name: String, paths: Paths) {
        try? FileManager.default.removeItem(at: directory(paths).appendingPathComponent(name))
    }

    // MARK: Waiting

    enum Outcome: Equatable, Sendable {
        case resume
        /// The session went on without this hook, or ended.
        case movedOn
        case timedOut
    }

    /// Looks every `interval` until the host answers, the session moves on
    /// or `limit` passes. `tick` gets the time waited so far before each
    /// pause. The session is asked after the host: a look can take seconds.
    static func wait(
        limit: TimeInterval = maxWait,
        interval: TimeInterval = pollInterval,
        awake: () -> TimeInterval,
        sleep: (TimeInterval) -> Void,
        reachable: () -> Bool,
        stillStopped: () -> Bool,
        tick: (TimeInterval) -> Void = { _ in }
    ) -> Outcome {
        let start = awake()
        while true {
            let up = reachable()
            guard stillStopped() else { return .movedOn }
            if up { return .resume }
            let waited = awake() - start
            guard waited < limit else { return .timedOut }
            tick(waited)
            sleep(interval)
        }
    }

    /// What the hook needs from outside, so tests can stand in for the
    /// network, the clock and the transcript.
    struct Environment {
        /// The setting, read from config.json.
        var enabled: (Paths) -> Bool
        /// Whether the API's host answers now.
        var reachable: () -> Bool
        /// Whether the transcript at this path says the last attempt found
        /// the network down.
        var networkDownInTranscript: (String?) -> Bool
        /// Seconds that only pass while the Mac is awake.
        var awake: () -> TimeInterval
        var sleep: (TimeInterval) -> Void
        var now: () -> Date
        var alive: (Int32, ProcessIdentity?) -> Bool
        var newWaiter: () -> String
        /// Writes to stderr, which is what Claude Code hands to Claude.
        var say: (String) -> Void

        static var live: Environment {
            let endpoint = APIHostProbe.endpoint()
            return Environment(
                enabled: { (try? Store(paths: $0).loadConfig())?.resumeAfterOutage ?? Config().resumeAfterOutage },
                reachable: { APIHostProbe.reachable(host: endpoint.host, port: endpoint.port) },
                networkDownInTranscript: { ClaudeOutageResume.networkDown(inTranscript: $0) },
                awake: { TimeInterval(clock_gettime_nsec_np(CLOCK_UPTIME_RAW)) / 1_000_000_000 },
                sleep: { Thread.sleep(forTimeInterval: $0) },
                now: { Date() },
                alive: { pid, identity in
                    guard case let .present(state) = SignalProcessControl.processTableState(pid: pid) else { return false }
                    return identity == nil || state.identity == identity
                },
                newWaiter: { UUID().uuidString },
                say: { FileHandle.standardError.write(Data(($0 + "\n").utf8)) }
            )
        }
    }

    /// What `--claude-hook` does for `StopFailure`. For anything but an
    /// outage, and with the setting off, the turn is over as it always was:
    /// the marker goes and the status is 0. For an outage it waits, keeping
    /// the session's marker so the Mac stays awake for `keepAwake`, and
    /// returns `wakeStatus` once the host answers.
    static func handle(
        session name: String,
        error: String?,
        transcript: String?,
        paths: Paths,
        now: Date,
        claudeProcess: () -> (pid: Int32, identity: ProcessIdentity?)?,
        environment env: Environment
    ) -> Int32 {
        let marker = ClaudeHookCommand.markerDirectory(paths).appendingPathComponent(name)
        let state = directory(paths).appendingPathComponent(name)
        let session = String(name.dropLast(".json".count))

        func over() -> Int32 {
            try? FileManager.default.removeItem(at: marker)
            try? FileManager.default.removeItem(at: state)
            return 0
        }
        guard error == serverError, env.enabled(paths) else { return over() }
        guard isOutage(error: error, reachable: env.reachable(), networkDownInTranscript: env.networkDownInTranscript(transcript)) else { return over() }
        let resumes = readWait(state)?.resumes ?? 0
        guard resumes < maxResumes else {
            Log.info("claude outage: session \(session) failed again after \(resumes) resumes in a row; left for the user")
            return over()
        }

        let waiter = env.newWaiter()
        write(Wait(waiter: waiter, resumes: resumes), to: state)
        let process = claudeProcess()
        func mark(at date: Date) {
            ClaudeHookCommand.writeMarker(
                ClaudeTaskMarker(pid: process?.pid ?? 0, identity: process?.identity, event: waitingEvent, updatedAt: date),
                to: marker
            )
        }
        mark(at: now)
        Log.info("claude outage: a network outage stopped session \(session); waiting for the API host")

        var holding = true
        let began = env.awake()
        let outcome = wait(
            awake: env.awake,
            sleep: env.sleep,
            reachable: env.reachable,
            stillStopped: {
                guard readWait(state)?.waiter == waiter else { return false }
                // Another event's marker: a prompt the user sent, a tool.
                if let current = ClaudeHookCommand.readMarker(marker), current.event != waitingEvent { return false }
                if let process, !env.alive(process.pid, process.identity) { return false }
                return true
            },
            tick: { elapsed in
                guard holding, elapsed >= keepAwake else { return }
                holding = false
                try? FileManager.default.removeItem(at: marker)
                Log.info("claude outage: session \(session) has waited \(FailoverMachine.humanGap(elapsed)); the Mac is no longer kept awake for it")
            }
        )
        switch outcome {
        case .resume:
            write(Wait(waiter: waiter, resumes: resumes + 1), to: state)
            mark(at: env.now())
            env.say(message)
            Log.info("claude outage: the API host answers again after \(FailoverMachine.humanGap(env.awake() - began)); resuming session \(session)")
            return wakeStatus
        case .movedOn:
            // The marker and the state are someone else's now.
            Log.info("claude outage: session \(session) went on or ended while waiting; nothing to resume")
            return 0
        case .timedOut:
            Log.info("claude outage: no network for session \(session) after \(FailoverMachine.humanGap(maxWait)); left for the user")
            if ClaudeHookCommand.readMarker(marker)?.event == waitingEvent { try? FileManager.default.removeItem(at: marker) }
            try? FileManager.default.removeItem(at: state)
            return 0
        }
    }

    // MARK: Transcript

    /// Whether the transcript's last attempt found the network down. Only a
    /// `.jsonl` file is read, and only its end.
    static func networkDown(inTranscript path: String?) -> Bool {
        guard let path, path.hasPrefix("/"), path.hasSuffix(".jsonl"),
              let data = ClaudeDigest.tail(of: URL(fileURLWithPath: path), bytes: transcriptTail) else { return false }
        return networkDown(in: data.split(separator: UInt8(ascii: "\n")))
    }

    /// Walking back from the end, the failed turn's last `api_error` line
    /// says whether Claude Code found the network down. The walk stops at
    /// what came before that turn's attempts: a prompt, a tool's result or
    /// something Claude said.
    static func networkDown(in lines: [Data.SubSequence]) -> Bool {
        for line in lines.reversed() {
            guard let entry = (try? JSONSerialization.jsonObject(with: Data(line))) as? [String: Any],
                  entry["isSidechain"] as? Bool != true else { continue }
            switch entry["type"] as? String {
            case "system" where entry["subtype"] as? String == "api_error":
                return (entry["error"] as? [String: Any])?["isNetworkDown"] as? Bool ?? false
            case "user":
                return false
            case "assistant" where entry["isApiErrorMessage"] as? Bool != true:
                return false
            default:
                continue
            }
        }
        return false
    }
}

/// Whether the host Claude Code sends its requests to answers (fork
/// addition): one TCP connection, over which nothing is sent.
enum APIHostProbe {
    static let defaultHost = "api.anthropic.com"
    static let baseURLVariable = "ANTHROPIC_BASE_URL"
    static let timeout: TimeInterval = 5

    /// The session's `ANTHROPIC_BASE_URL` when it names another machine,
    /// otherwise Anthropic's API. A base URL on this Mac, a local proxy,
    /// answers with the network down, so it is not the one asked.
    static func endpoint(environment: [String: String] = ProcessInfo.processInfo.environment) -> (host: String, port: UInt16) {
        guard let raw = environment[baseURLVariable], let url = URL(string: raw),
              let host = url.host, !host.isEmpty, !isLocal(host) else { return (defaultHost, 443) }
        let port = url.port ?? (url.scheme?.lowercased() == "http" ? 80 : 443)
        return (host, UInt16(exactly: port) ?? 443)
    }

    static func isLocal(_ host: String) -> Bool {
        let name = host.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
        return name == "localhost" || name.hasSuffix(".localhost") || name == "::1" || name.hasPrefix("127.")
    }

    static func reachable(host: String, port: UInt16, timeout: TimeInterval = timeout) -> Bool {
        guard let port = NWEndpoint.Port(rawValue: port) else { return false }
        let connection = NWConnection(host: NWEndpoint.Host(host), port: port, using: .tcp)
        let opened = OSAllocatedUnfairLock(initialState: false)
        let settled = DispatchSemaphore(value: 0)
        connection.stateUpdateHandler = { state in
            switch state {
            case .ready:
                opened.withLock { $0 = true }
                settled.signal()
            // Waiting is no route or no name: an outage, as far as one look goes.
            case .waiting, .failed, .cancelled:
                settled.signal()
            default:
                break
            }
        }
        connection.start(queue: DispatchQueue(label: "com.mustafaghn.uykusuz.api-probe"))
        _ = settled.wait(timeout: .now() + timeout)
        connection.cancel()
        return opened.withLock { $0 }
    }
}
