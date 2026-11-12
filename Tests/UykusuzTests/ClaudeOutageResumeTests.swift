import XCTest
@testable import Uykusuz

final class ClaudeOutageResumeTests: XCTestCase {
    private var root: URL!
    private var paths: Paths!
    private let t0 = Date(timeIntervalSince1970: 2_000_000_000)
    private let identity = ProcessIdentity(startedAt: 1_999_000_000, startedAtMicros: 7, bootSession: "boot")
    private let session = "abc-123"

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("uykusuz-outage-\(UUID().uuidString)", isDirectory: true)
        paths = Paths(root: root)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: root)
    }

    /// The network, the clock and Claude, as a test sets them. A pause moves
    /// the clock on by its length; nothing sleeps.
    private final class World {
        var enabled = true
        /// Whether the host answers, by how many pauses there have been.
        var up: (Int) -> Bool = { _ in false }
        var networkDownInTranscript = false
        var claudeRuns = true
        var looks = 0
        var pauses = 0
        var awake: TimeInterval = 0
        var waiters = 0
        var said: [String] = []
        var onPause: (Int) -> Void = { _ in }
    }

    private func environment(_ world: World) -> ClaudeOutageResume.Environment {
        let t0 = self.t0
        return ClaudeOutageResume.Environment(
            enabled: { _ in world.enabled },
            reachable: {
                world.looks += 1
                return world.up(world.pauses)
            },
            networkDownInTranscript: { _ in world.networkDownInTranscript },
            awake: { world.awake },
            sleep: {
                world.awake += $0
                world.pauses += 1
                world.onPause(world.pauses)
            },
            now: { t0.addingTimeInterval(world.awake) },
            alive: { _, _ in world.claudeRuns },
            newWaiter: {
                world.waiters += 1
                return "waiter-\(world.waiters)"
            },
            say: { world.said.append($0) }
        )
    }

    @discardableResult
    private func hook(_ event: String, world: World = World(), extra: String = "") -> Int32? {
        let input = Data(#"{"session_id":"\#(session)","hook_event_name":"\#(event)"\#(extra)}"#.utf8)
        return ClaudeHookCommand.run(["--claude-hook"], readInput: { input }, paths: paths, now: t0,
                                     claudeProcess: { (4242, self.identity) }, outage: self.environment(world))
    }

    private func fail(_ error: String? = "server_error", world: World) -> Int32? {
        hook("StopFailure", world: world, extra: error.map { #","error":"\#($0)","last_assistant_message":"API Error""# } ?? "")
    }

    private var markerFile: URL { ClaudeHookCommand.markerDirectory(paths).appendingPathComponent("\(session).json") }
    private var waitFile: URL { ClaudeOutageResume.directory(paths).appendingPathComponent("\(session).json") }
    private var marker: ClaudeTaskMarker? { ClaudeHookCommand.readMarker(markerFile) }
    private var wait: ClaudeOutageResume.Wait? { ClaudeOutageResume.readWait(waitFile) }

    private func resumePrompt() -> String {
        let prompt = "<task-notification>\n<summary>Stop hook feedback</summary>\n</task-notification>\n<system-reminder>\nStop hook blocking error from command \"StopFailure:server_error\": \(ClaudeOutageResume.message)\n\n</system-reminder>"
        let json = String(decoding: try! JSONEncoder().encode(prompt), as: UTF8.self)
        return #","prompt":\#(json)"#
    }

    // MARK: Which failures

    func testAnOutageWaitsForTheNetworkAndThenWakesTheSession() throws {
        hook("UserPromptSubmit")
        let world = World()
        world.up = { pauses in pauses >= 2 }
        var whileWaiting: (marker: ClaudeTaskMarker?, state: ClaudeActivity.State)?
        world.onPause = { [self] pauses in
            guard pauses == 1 else { return }
            let alive: (Int32) -> ProcessLookup = { _ in .present(ProcessSignalState(ppid: 1, stopped: false, identity: self.identity)) }
            whileWaiting = (marker, ClaudeActivity.state(paths: paths, now: t0.addingTimeInterval(5), lookup: alive) { false })
        }

        XCTAssertEqual(fail(world: world), ClaudeOutageResume.wakeStatus)
        XCTAssertEqual(world.said, [ClaudeOutageResume.message], "what Claude reads when the session wakes")
        XCTAssertEqual(world.pauses, 2)
        XCTAssertEqual(whileWaiting?.marker, ClaudeTaskMarker(pid: 4242, identity: identity, event: "StopFailure", updatedAt: t0))
        XCTAssertEqual(whileWaiting?.state, .working, "the Mac stays awake for the network")
        XCTAssertEqual(marker?.updatedAt, t0.addingTimeInterval(10), "at work again from the moment it resumes")
        XCTAssertEqual(wait, ClaudeOutageResume.Wait(waiter: "waiter-1", resumes: 1))
    }

    func testALimitASignInProblemOrARefusedRequestIsLeftForTheUser() throws {
        for error in ["rate_limit", "billing_error", "authentication_failed", "oauth_org_not_allowed", "account_on_hold",
                      "invalid_request", "model_not_found", "overloaded", "max_output_tokens", "unknown", nil] {
            hook("UserPromptSubmit")
            let world = World()
            world.networkDownInTranscript = true
            XCTAssertEqual(fail(error, world: world), 0, error ?? "no error")
            XCTAssertEqual(world.said, [], error ?? "no error")
            XCTAssertEqual(world.looks, 0, "the network is not even asked about")
            XCTAssertNil(marker, "the turn is over")
            XCTAssertNil(wait)
        }
    }

    func testAServerErrorWithTheNetworkUpIsLeftForTheUser() throws {
        hook("UserPromptSubmit")
        let world = World()
        world.up = { _ in true }
        XCTAssertEqual(fail(world: world), 0, "an overloaded or failing API is not an outage")
        XCTAssertEqual(world.said, [])
        XCTAssertNil(marker)
        XCTAssertNil(wait)
    }

    func testAnOutageThatEndedAsTheTurnDidIsResumedAtOnce() throws {
        let world = World()
        world.up = { _ in true }
        world.networkDownInTranscript = true
        XCTAssertEqual(fail(world: world), ClaudeOutageResume.wakeStatus)
        XCTAssertEqual(world.pauses, 0)
        XCTAssertEqual(world.said, [ClaudeOutageResume.message])
    }

    func testTurnedOffNothingWaits() throws {
        hook("UserPromptSubmit")
        let world = World()
        world.enabled = false
        XCTAssertEqual(fail(world: world), 0)
        XCTAssertEqual(world.looks, 0)
        XCTAssertNil(marker)

        XCTAssertTrue(Config().resumeAfterOutage)
        let earlier = try JSONDecoder().decode(Config.self, from: Data("{}".utf8))
        XCTAssertTrue(earlier.resumeAfterOutage, "a config.json from before the setting")
    }

    func testOnlyAServerErrorWithTheNetworkDownIsAnOutage() {
        XCTAssertTrue(ClaudeOutageResume.isOutage(error: "server_error", reachable: false, networkDownInTranscript: false))
        XCTAssertTrue(ClaudeOutageResume.isOutage(error: "server_error", reachable: true, networkDownInTranscript: true))
        XCTAssertFalse(ClaudeOutageResume.isOutage(error: "server_error", reachable: true, networkDownInTranscript: false))
        XCTAssertFalse(ClaudeOutageResume.isOutage(error: "rate_limit", reachable: false, networkDownInTranscript: true))
        XCTAssertFalse(ClaudeOutageResume.isOutage(error: nil, reachable: false, networkDownInTranscript: true))
    }

    // MARK: While waiting

    func testAPromptFromTheUserWhileWaitingStandsTheHookDown() throws {
        let world = World()
        world.up = { pauses in pauses >= 3 }
        world.onPause = { [self] pauses in
            if pauses == 1 { hook("UserPromptSubmit", extra: #","prompt":"baştan başla""#) }
        }
        XCTAssertEqual(fail(world: world), 0)
        XCTAssertEqual(world.said, [], "the user went on; nothing is added to what they asked")
        XCTAssertEqual(world.pauses, 1)
        XCTAssertEqual(marker?.event, "UserPromptSubmit", "the marker is the new turn's")
        XCTAssertNil(wait)
    }

    func testALaterFailureTakesTheWaitOver() throws {
        let first = World()
        let second = World()
        second.up = { _ in true }
        second.networkDownInTranscript = true
        second.waiters = 1
        var later: Int32?
        first.onPause = { [self] pauses in
            if pauses == 1 { later = fail(world: second) }
        }
        XCTAssertEqual(fail(world: first), 0, "one hook wakes the session, not two")
        XCTAssertEqual(first.said, [])
        XCTAssertEqual(later, ClaudeOutageResume.wakeStatus)
        XCTAssertEqual(second.said, [ClaudeOutageResume.message])
        XCTAssertEqual(wait, ClaudeOutageResume.Wait(waiter: "waiter-2", resumes: 1), "the later hook's wait is left as it is")
        XCTAssertEqual(marker?.event, "StopFailure")
    }

    func testClaudeQuittingEndsTheWait() throws {
        let world = World()
        world.onPause = { pauses in
            if pauses == 2 { world.claudeRuns = false }
        }
        XCTAssertEqual(fail(world: world), 0)
        XCTAssertEqual(world.pauses, 2)
        XCTAssertEqual(world.said, [])
    }

    func testTheMacIsKeptAwakeForAnHourAndTheWaitGoesOnAfterThat() throws {
        let hour = Int(ClaudeOutageResume.keepAwake / ClaudeOutageResume.pollInterval)
        let world = World()
        world.up = { pauses in pauses >= hour + 10 }
        var markers: [Int: Bool] = [:]
        world.onPause = { [self] pauses in
            if [hour - 1, hour + 5].contains(pauses) { markers[pauses] = marker != nil }
        }
        XCTAssertEqual(fail(world: world), ClaudeOutageResume.wakeStatus)
        XCTAssertEqual(markers, [hour - 1: true, hour + 5: false], "after an hour the Mac may sleep")
        XCTAssertEqual(marker?.event, "StopFailure", "resumed: at work again")
        XCTAssertEqual(world.said, [ClaudeOutageResume.message])
    }

    func testWithoutTheNetworkTheWaitEndsAndTheSessionIsLeftForTheUser() throws {
        let world = World()
        XCTAssertEqual(fail(world: world), 0)
        XCTAssertEqual(world.awake, ClaudeOutageResume.maxWait)
        XCTAssertEqual(world.said, [])
        XCTAssertNil(marker)
        XCTAssertNil(wait)

        var pauses = 0
        var clock: TimeInterval = 0
        let outcome = ClaudeOutageResume.wait(limit: 100, interval: 30, awake: { clock }, sleep: { clock += $0; pauses += 1 },
                                              reachable: { false }, stillStopped: { true })
        XCTAssertEqual(outcome, .timedOut)
        XCTAssertEqual(pauses, 4)
    }

    // MARK: How often

    func testThreeResumesInARowAndThenTheUserDecides() throws {
        func outage() -> (status: Int32?, said: Int) {
            let world = World()
            world.up = { pauses in pauses >= 1 }
            let status = fail(world: world)
            return (status, world.said.count)
        }
        for round in 1...ClaudeOutageResume.maxResumes {
            XCTAssertEqual(outage().status, ClaudeOutageResume.wakeStatus, "resume \(round)")
            hook("UserPromptSubmit", extra: resumePrompt())
            XCTAssertEqual(wait?.resumes, round, "the prompt a resume makes is not the user's")
        }
        let fourth = outage()
        XCTAssertEqual(fourth.status, 0)
        XCTAssertEqual(fourth.said, 0)
        XCTAssertNil(marker)

        XCTAssertEqual(outage().status, ClaudeOutageResume.wakeStatus, "the count starts again after the user was left to decide")
        hook("UserPromptSubmit", extra: resumePrompt())
        XCTAssertEqual(wait?.resumes, 1)
        hook("PostToolUse")
        XCTAssertNil(wait, "Claude ran a tool: the session got somewhere")

        XCTAssertEqual(outage().status, ClaudeOutageResume.wakeStatus)
        hook("Stop")
        XCTAssertNil(wait, "a turn that ends well")
        XCTAssertEqual(outage().status, ClaudeOutageResume.wakeStatus)
        hook("UserPromptSubmit", extra: #","prompt":"devam et""#)
        XCTAssertNil(wait, "a prompt of the user's")
    }

    func testThePromptAResumeMakesIsToldFromTheUsers() {
        XCTAssertTrue(ClaudeOutageResume.isResumePrompt("<system-reminder>\nStop hook blocking error from command \"StopFailure:server_error\": \(ClaudeOutageResume.message)\n</system-reminder>"))
        XCTAssertFalse(ClaudeOutageResume.isResumePrompt("İnternet kesildi, devam et"))
        XCTAssertFalse(ClaudeOutageResume.isResumePrompt(nil))
    }

    // MARK: Transcript

    private func lines(_ entries: [String]) -> [Data.SubSequence] {
        Data(entries.joined(separator: "\n").utf8).split(separator: UInt8(ascii: "\n"))
    }

    private func apiError(networkDown: Bool, sidechain: Bool = false) -> String {
        #"{"type":"system","subtype":"api_error","isSidechain":\#(sidechain),"error":{"message":"Connection error.","connection":{"code":"ENOTFOUND"},"isNetworkDown":\#(networkDown)},"retryAttempt":10,"maxRetries":10}"#
    }

    private let prompt = #"{"type":"user","message":{"role":"user","content":"merhaba"}}"#
    private let request = #"{"type":"api-request","id":"r1"}"#
    private let failure = #"{"type":"assistant","isApiErrorMessage":true,"error":"server_error","message":{"model":"<synthetic>","content":[{"type":"text","text":"API Error"}]}}"#
    private let said = #"{"type":"assistant","message":{"model":"claude","content":[{"type":"text","text":"Tamam."}]}}"#

    func testTheTranscriptsLastAttemptSaysWhetherTheNetworkWasDown() throws {
        XCTAssertTrue(ClaudeOutageResume.networkDown(in: lines([prompt, apiError(networkDown: false), request, apiError(networkDown: true), request, failure])))
        XCTAssertFalse(ClaudeOutageResume.networkDown(in: lines([prompt, apiError(networkDown: true), request, apiError(networkDown: false), request, failure])),
                       "the last attempt counts")
        XCTAssertFalse(ClaudeOutageResume.networkDown(in: lines([apiError(networkDown: true), said, prompt, request, failure])),
                       "an earlier turn's outage is not this turn's")
        XCTAssertFalse(ClaudeOutageResume.networkDown(in: lines([prompt, apiError(networkDown: true), said])), "Claude answered since")
        XCTAssertTrue(ClaudeOutageResume.networkDown(in: lines([prompt, apiError(networkDown: true), request, apiError(networkDown: false, sidechain: true), failure])),
                      "a subagent's attempt is not the chat's")
        XCTAssertFalse(ClaudeOutageResume.networkDown(in: lines(["not json", failure])))
        XCTAssertFalse(ClaudeOutageResume.networkDown(in: []))

        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let file = root.appendingPathComponent("\(session).jsonl")
        try Data([prompt, apiError(networkDown: true), request, failure].joined(separator: "\n").utf8).write(to: file)
        XCTAssertTrue(ClaudeOutageResume.networkDown(inTranscript: file.path))
        XCTAssertFalse(ClaudeOutageResume.networkDown(inTranscript: nil))
        XCTAssertFalse(ClaudeOutageResume.networkDown(inTranscript: root.appendingPathComponent("yok.jsonl").path))
        let other = root.appendingPathComponent("notes.txt")
        try Data([prompt, apiError(networkDown: true), request, failure].joined(separator: "\n").utf8).write(to: other)
        XCTAssertFalse(ClaudeOutageResume.networkDown(inTranscript: other.path), "only a transcript is read")
    }

    // MARK: The API's host

    func testTheHostAskedIsTheSessionsUnlessThatIsThisMac() {
        func endpoint(_ base: String?) -> String {
            let found = APIHostProbe.endpoint(environment: base.map { [APIHostProbe.baseURLVariable: $0] } ?? [:])
            return "\(found.host):\(found.port)"
        }
        XCTAssertEqual(endpoint(nil), "api.anthropic.com:443")
        XCTAssertEqual(endpoint("https://api.anthropic.com"), "api.anthropic.com:443")
        XCTAssertEqual(endpoint("https://proxy.example.com:8443/v1"), "proxy.example.com:8443")
        XCTAssertEqual(endpoint("http://proxy.example.com"), "proxy.example.com:80")
        XCTAssertEqual(endpoint("http://localhost:4000"), "api.anthropic.com:443", "a proxy on this Mac answers with the network down")
        XCTAssertEqual(endpoint("http://127.0.0.1:4000"), "api.anthropic.com:443")
        XCTAssertEqual(endpoint("http://[::1]:4000"), "api.anthropic.com:443")
        XCTAssertEqual(endpoint(""), "api.anthropic.com:443")
    }

    func testAnOpenPortAnswersAndAClosedOneDoesNot() throws {
        let listener = socket(AF_INET, SOCK_STREAM, 0)
        XCTAssertGreaterThanOrEqual(listener, 0)
        var open = true
        defer { if open { close(listener) } }
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_addr.s_addr = inet_addr("127.0.0.1")
        address.sin_port = 0
        let bound = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.bind(listener, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) }
        }
        XCTAssertEqual(bound, 0)
        XCTAssertEqual(listen(listener, 1), 0)
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        _ = withUnsafeMutablePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(listener, $0, &length) }
        }
        let port = UInt16(bigEndian: address.sin_port)

        XCTAssertTrue(APIHostProbe.reachable(host: "127.0.0.1", port: port, timeout: 3))
        close(listener)
        open = false
        XCTAssertFalse(APIHostProbe.reachable(host: "127.0.0.1", port: port, timeout: 3), "nothing listens there now")
    }
}
