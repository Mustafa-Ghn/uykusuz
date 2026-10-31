import Darwin
import XCTest
@testable import Uykusuz

// Fork addition: telling the phone when Docker Desktop is in use.

@MainActor
final class DockerWatcherTests: XCTestCase {
    private struct Failure: Error {}

    private var table: [BashToolWatcher.Process] = []
    private var argumentsByPID: [pid_t: [String]] = [:]
    private var stopped: Set<pid_t> = []
    private var running: [DockerWatcher.Container] = []
    private var failing = false
    private var asked = 0
    private var now = Date(timeIntervalSince1970: 2_000_000_000)

    private func process(_ pid: pid_t, _ name: String) -> BashToolWatcher.Process {
        BashToolWatcher.Process(pid: pid, ppid: 1, name: name, started: now)
    }

    private var engine: [BashToolWatcher.Process] {
        [process(10, "com.docker.backe"), process(11, "com.docker.virtu")]
    }

    private func make() -> DockerWatcher {
        DockerWatcher(
            processes: { [unowned self] in self.table },
            isStopped: { [unowned self] in self.stopped.contains($0) },
            arguments: { [unowned self] in self.argumentsByPID[$0] },
            containers: { [unowned self] in
                self.asked += 1
                if self.failing { throw Failure() }
                return self.running
            }
        )
    }

    private func container(_ name: String, cpu: Double = 0.1) -> DockerWatcher.Container {
        DockerWatcher.Container(id: "id-\(name)", name: name, cpu: cpu)
    }

    private func advance(_ seconds: TimeInterval) { now = now.addingTimeInterval(seconds) }

    func testAContainerLeftRunningIsNoUse() async throws {
        let watcher = make()
        table = engine
        running = [container("db")]
        let first = await watcher.look(now: now)
        XCTAssertEqual(first, DockerActivity(working: [], idle: ["db"]), "up before Uykusuz looked, and doing nothing")
        XCTAssertFalse(try XCTUnwrap(first).isBusy)
        advance(30)
        let second = await watcher.look(now: now)
        XCTAssertEqual(second, DockerActivity(working: [], idle: ["db"]))
    }

    func testANewContainerCountsUntilItsGraceIsOverUnlessItWorks() async {
        let watcher = make()
        table = engine
        running = [container("db")]
        _ = await watcher.look(now: now)
        running = [container("db"), container("probe", cpu: 0)]
        var activity = await watcher.look(now: now)
        XCTAssertEqual(activity, DockerActivity(working: ["probe"], idle: ["db"]))
        advance(DockerWatcher.newGrace - 1)
        activity = await watcher.look(now: now)
        XCTAssertEqual(activity?.working, ["probe"], "still new")
        advance(1)
        activity = await watcher.look(now: now)
        XCTAssertEqual(activity, DockerActivity(working: [], idle: ["db", "probe"]), "up and idle: left running")
        running = [container("db"), container("probe", cpu: DockerWatcher.cpuThreshold)]
        activity = await watcher.look(now: now)
        XCTAssertEqual(activity?.working, ["probe"], "working again")
    }

    func testAContainerThatWasThereCountsWhileItWorks() async {
        let watcher = make()
        table = engine
        running = [container("db")]
        _ = await watcher.look(now: now)
        running = [container("db", cpu: 80)]
        var activity = await watcher.look(now: now)
        XCTAssertEqual(activity, DockerActivity(working: ["db"], idle: []))
        running = [container("db", cpu: DockerWatcher.cpuThreshold - 0.1)]
        activity = await watcher.look(now: now)
        XCTAssertEqual(activity, DockerActivity(working: [], idle: ["db"]))
    }

    func testAContainerThatCameBackIsNewAgain() async {
        let watcher = make()
        table = engine
        running = [container("db")]
        _ = await watcher.look(now: now)
        running = []
        _ = await watcher.look(now: now)
        running = [container("db")]
        let activity = await watcher.look(now: now)
        XCTAssertEqual(activity?.working, ["db"])
    }

    func testNoAnswerIsUnknownAndIsNoFirstLook() async {
        let watcher = make()
        table = engine
        running = [container("db")]
        failing = true
        var activity = await watcher.look(now: now)
        XCTAssertNil(activity)
        failing = false
        activity = await watcher.look(now: now)
        XCTAssertEqual(activity, DockerActivity(working: [], idle: ["db"]), "the first answer is what was there before")
    }

    func testAClosedOrSleepingDockerIsNotAsked() async {
        let watcher = make()
        table = [process(10, "com.docker.backe")]
        var activity = await watcher.look(now: now)
        XCTAssertEqual(activity, DockerActivity(), "no virtual machine: no container")
        XCTAssertEqual(asked, 0)
        table = []
        activity = await watcher.look(now: now)
        XCTAssertEqual(activity, DockerActivity())
        XCTAssertEqual(asked, 0)
        // What a command woke it for counts: the first look saw none of it.
        table = engine
        running = [container("probe", cpu: 0)]
        activity = await watcher.look(now: now)
        XCTAssertEqual(activity?.working, ["probe"])
        XCTAssertEqual(asked, 1)
    }

    func testAPausedDockerIsNotAskedAndForgetsNothing() async {
        let watcher = make()
        table = engine
        running = [container("db")]
        _ = await watcher.look(now: now)
        XCTAssertEqual(asked, 1)
        stopped = [10]
        var activity = await watcher.look(now: now)
        XCTAssertEqual(activity, DockerActivity(), "asking would only wait for the timeout")
        XCTAssertEqual(asked, 1)
        stopped = []
        activity = await watcher.look(now: now)
        XCTAssertEqual(activity, DockerActivity(working: [], idle: ["db"]), "not new for having been paused")
    }

    func testCommandsAtWorkAreTheOnesThatRunUntilDone() async {
        let cases: [(name: String, arguments: [String]?, label: String?)] = [
            ("docker-buildx", ["docker-buildx", "buildx", "build", "."], "docker build"),
            ("docker", ["docker", "build", "-t", "x", "."], "docker build"),
            ("docker", ["docker", "--host", "unix:///s", "image", "pull", "x"], "docker pull"),
            ("docker", ["docker", "push", "x"], "docker push"),
            ("docker-compose", ["docker-compose", "compose", "up", "--build"], "docker build"),
            ("docker-compose", ["docker-compose", "compose", "build"], "docker build"),
            ("docker-buildx", ["docker-buildx", "buildx", "bake"], "docker build"),
            ("docker", ["docker", "ps"], nil),
            ("docker", ["docker", "exec", "db", "psql"], nil),
            ("docker", ["docker", "run", "-it", "x"], nil),
            ("docker", ["docker", "logs", "-f", "db"], nil),
            ("docker-compose", ["docker-compose", "compose", "up"], nil),
            ("docker", nil, nil),
            // The program's own name is no verb.
            ("docker", ["build"], nil),
            // Long-lived helpers Docker Desktop keeps, whatever they run.
            ("docker-sandbox", ["docker-sandbox", "build"], nil),
            ("build", ["build", "pull"], nil),
        ]
        for (name, arguments, label) in cases {
            let found = DockerWatcher.commandsAtWork([process(20, name)]) { _ in arguments }
            XCTAssertEqual(found, label.map { [$0] } ?? [], "\(name) \(arguments ?? [])")
        }

        // Each once, the parent and its plugin alike, and counted with
        // Docker's virtual machine down or the containers' answer missing.
        table = [process(20, "docker"), process(21, "docker-buildx"), process(22, "docker")]
        argumentsByPID = [20: ["docker", "build", "."], 21: ["docker-buildx", "buildx", "build", "."], 22: ["docker", "pull", "x"]]
        let watcher = make()
        let activity = await watcher.look(now: now)
        XCTAssertEqual(activity?.working, ["docker build", "docker pull"])
    }

    func testTheAnswerOfDockerStats() {
        XCTAssertEqual(DockerWatcher.parseStats("abc\tprobe\t12.50%\ndef\tdb\t0.07%\n"), [
            DockerWatcher.Container(id: "abc", name: "probe", cpu: 12.5),
            DockerWatcher.Container(id: "def", name: "db", cpu: 0.07),
        ])
        XCTAssertEqual(DockerWatcher.parseStats("abc\t--\t--\n"), [DockerWatcher.Container(id: "abc", name: "abc", cpu: 0)], "going away")
        XCTAssertEqual(DockerWatcher.parseStats(""), [])
        XCTAssertEqual(DockerWatcher.parseStats("not a line\n--\t--\t--\n"), [])
        let arguments = DockerWatcher.statsArguments(host: "unix:///s")
        XCTAssertEqual(Array(arguments.prefix(3)), ["--host", "unix:///s", "stats"], "Docker Desktop's own engine, whatever the environment says")
        XCTAssertTrue(arguments.contains("--no-stream"))
    }

    func testArgumentsAreReadWithoutTheEnvironment() {
        var buffer = withUnsafeBytes(of: Int32(3)) { Array($0) }
        buffer += Array("/usr/local/bin/docker".utf8) + [0, 0, 0, 0]
        buffer += Array("docker".utf8) + [0] + Array("--host".utf8) + [0] + Array("build".utf8) + [0]
        buffer += Array("SECRET=hunter2".utf8) + [0]
        XCTAssertEqual(DockerWatcher.parseArguments(buffer), ["docker", "--host", "build"])
        XCTAssertNil(DockerWatcher.parseArguments([1, 0]))
        XCTAssertNil(DockerWatcher.parseArguments(withUnsafeBytes(of: Int32(2)) { Array($0) } + Array("/x".utf8) + [0, 0] + Array("one".utf8) + [0]), "fewer than it says")
    }

    func testTheEngineIsToldFromTheShortenedProcessNames() {
        XCTAssertTrue(DockerWatcher.isVirtualMachine("com.docker.virtu"))
        XCTAssertTrue(DockerWatcher.isVirtualMachine("com.docker.krun"))
        XCTAssertFalse(DockerWatcher.isVirtualMachine("com.docker.backe"))
    }
}

@MainActor
final class DockerAlertsTests: XCTestCase {
    private var config = Config()
    private var reading: DockerActivity? = DockerActivity()
    private var isAway = true
    private var now = Date(timeIntervalSince1970: 2_000_000_000)
    private var sent: [(text: String, what: String)] = []

    private let busy = DockerActivity(working: ["probe"], idle: ["db"])
    private let quiet = DockerActivity(working: [], idle: ["db"])

    private func make() -> DockerAlerts {
        config.imessageAlerts = true
        config.imessageHandle = "+905550000000"
        return DockerAlerts(
            config: { [unowned self] in self.config },
            activity: { [unowned self] in self.reading },
            away: { [unowned self] in self.isAway },
            send: { [unowned self] in self.sent.append(($0, $1)) },
            clock: { [unowned self] in self.now }
        )
    }

    /// Ticks at the timer's pace for `seconds`, ending on one at that moment.
    private func run(_ alerts: DockerAlerts, for seconds: TimeInterval) async {
        var left = seconds
        repeat {
            await alerts.tick()
            guard left > 0 else { return }
            let step = min(left, DockerAlerts.interval)
            now = now.addingTimeInterval(step)
            left -= step
        } while true
    }

    private var what: [String] { sent.map(\.what) }

    func testWorkIsToldOnceAndItsEndOnce() async {
        let alerts = make()
        reading = busy
        await run(alerts, for: DockerAlerts.settle - 1)
        XCTAssertEqual(what, [], "has to last")
        await run(alerts, for: 15 * 60)
        XCTAssertEqual(what, ["docker active"], "once, however long it lasts")
        XCTAssertEqual(sent.first?.text, "Uykusuz · Docker: aktif kullanılıyor (probe). İş bitince yine haber vereceğim.")
        reading = quiet
        await run(alerts, for: DockerAlerts.finishSettle - 1)
        XCTAssertEqual(what, ["docker active"], "steps a little apart are one job")
        await run(alerts, for: 1)
        XCTAssertEqual(what, ["docker active", "docker finished"])
        XCTAssertEqual(sent.last?.text, "Uykusuz · Docker: iş bitti, 16 dakika sürdü. Açık ama boşta: db.")
        await run(alerts, for: 15 * 60)
        XCTAssertEqual(sent.count, 2)
    }

    func testAQuickCommandTellsNothing() async {
        let alerts = make()
        for _ in 0..<5 {
            reading = busy
            await run(alerts, for: DockerAlerts.settle - 1)
            reading = quiet
            await run(alerts, for: 1)
        }
        XCTAssertEqual(what, [], "the clock starts over when it stops")
    }

    func testAtTheMacNothingGoesAndLeavingTellsWorkStillGoingOn() async {
        let alerts = make()
        isAway = false
        reading = busy
        await run(alerts, for: 3600)
        XCTAssertEqual(what, [], "at the Mac")
        isAway = true
        await run(alerts, for: 0)
        XCTAssertEqual(what, ["docker active"], "still at work, however long ago it began")
    }

    func testWorkDoneAtTheMacIsNeverTold() async {
        let alerts = make()
        isAway = false
        reading = busy
        await run(alerts, for: 3600)
        reading = quiet
        await run(alerts, for: DockerAlerts.finishSettle)
        isAway = true
        await run(alerts, for: 3600)
        XCTAssertEqual(what, [])
    }

    func testAnEndThatIsOwedIsToldBackAtTheMac() async {
        let alerts = make()
        reading = busy
        await run(alerts, for: DockerAlerts.settle)
        XCTAssertEqual(what, ["docker active"])
        isAway = false
        reading = quiet
        await run(alerts, for: DockerAlerts.finishSettle)
        XCTAssertEqual(what, ["docker active", "docker finished"])
    }

    func testWorkThatResumesInTimeIsTheSameJob() async {
        let alerts = make()
        reading = busy
        await run(alerts, for: DockerAlerts.settle)
        reading = quiet
        await run(alerts, for: DockerAlerts.finishSettle - 1)
        reading = busy
        await run(alerts, for: 60)
        reading = quiet
        await run(alerts, for: DockerAlerts.finishSettle - 1)
        XCTAssertEqual(what, ["docker active"])
        await run(alerts, for: 1)
        XCTAssertEqual(what, ["docker active", "docker finished"])
    }

    func testOneStretchPerGap() async {
        let alerts = make()
        reading = busy
        await run(alerts, for: DockerAlerts.settle)
        reading = quiet
        await run(alerts, for: DockerAlerts.finishSettle)
        XCTAssertEqual(sent.count, 2)
        reading = busy
        await run(alerts, for: DockerAlerts.settle)
        XCTAssertEqual(sent.count, 2, "another so soon waits")
        reading = quiet
        await run(alerts, for: DockerAlerts.finishSettle)
        XCTAssertEqual(sent.count, 2, "and has no end to tell if it was not told")
        reading = busy
        await run(alerts, for: DockerAlerts.gap)
        XCTAssertEqual(what, ["docker active", "docker finished", "docker active"], "still at work after the gap")
    }

    func testTurnedOffNothingIsToldAndDockerIsNotAsked() async {
        var asked = 0
        config.imessageAlerts = true
        config.imessageHandle = "+905550000000"
        let alerts = DockerAlerts(
            config: { [unowned self] in self.config },
            activity: { [unowned self] in asked += 1; return self.reading },
            away: { [unowned self] in self.isAway },
            send: { [unowned self] in self.sent.append(($0, $1)) },
            clock: { [unowned self] in self.now }
        )
        reading = busy
        await run(alerts, for: DockerAlerts.settle)
        XCTAssertEqual(what, ["docker active"])
        let before = asked
        config.dockerAlerts = false
        await run(alerts, for: 60)
        XCTAssertEqual(asked, before)
        reading = quiet
        config.dockerAlerts = true
        await run(alerts, for: 3600)
        XCTAssertEqual(what, ["docker active"], "turned off: no end is owed any more")

        config.imessageAlerts = false
        reading = busy
        await run(alerts, for: 3600)
        config.imessageAlerts = true
        config.imessageHandle = " "
        await run(alerts, for: 3600)
        XCTAssertEqual(what, ["docker active"])
    }

    func testNoAnswerChangesNothing() async {
        let alerts = make()
        reading = busy
        await run(alerts, for: DockerAlerts.settle)
        reading = nil
        await run(alerts, for: 3600)
        XCTAssertEqual(what, ["docker active"], "not known to have ended")
        reading = busy
        await run(alerts, for: 60)
        XCTAssertEqual(what, ["docker active"], "not a new stretch")
        reading = quiet
        await run(alerts, for: DockerAlerts.finishSettle)
        XCTAssertEqual(what, ["docker active", "docker finished"])
    }

    func testTheTexts() {
        XCTAssertEqual(DockerAlerts.activeText(DockerActivity(working: ["docker build", "probe"])),
                       "Uykusuz · Docker: aktif kullanılıyor (docker build, probe). İş bitince yine haber vereceğim.")
        XCTAssertEqual(DockerAlerts.activeText(DockerActivity(working: (1...7).map { "k\($0)" })),
                       "Uykusuz · Docker: aktif kullanılıyor (k1, k2, k3, k4, k5 ve 2 tane daha). İş bitince yine haber vereceğim.")
        XCTAssertEqual(DockerAlerts.finishedText(DockerActivity(), lasted: 30),
                       "Uykusuz · Docker: iş bitti, 1 dakika sürdü. Çalışan kapsayıcı kalmadı.")
        XCTAssertEqual(DockerAlerts.finishedText(DockerActivity(idle: ["db", "cache"]), lasted: 12 * 60),
                       "Uykusuz · Docker: iş bitti, 12 dakika sürdü. Açık ama boşta: db, cache.")
    }

    func testAnOldConfigGetsTheMessages() throws {
        let decoded = try JSONDecoder().decode(Config.self, from: Data("{}".utf8))
        XCTAssertTrue(decoded.dockerAlerts)
        XCTAssertFalse(decoded.imessageAlerts, "nothing goes unless iMessage was turned on")
    }
}
