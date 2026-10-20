import XCTest
@testable import Uykusuz

// Fork additions: the automatic session for an agent, code mode, spoken
// alerts and this fork's defaults.

final class AutoSessionPolicyTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 2_000_000_000)

    private func inputs(
        _ offset: TimeInterval,
        active: Bool,
        started: Date? = nil,
        endsAt: Date? = nil,
        percent: Int? = 80,
        charging: Bool = false,
        thermal: ProcessInfo.ThermalState = .nominal,
        endFloor: Int = 20,
        pausedUntil: Date? = nil
    ) -> AutoSessionPolicy.Inputs {
        .init(
            now: t0.addingTimeInterval(offset),
            agentActive: active,
            sessionStartedAt: started,
            sessionEndsAt: endsAt,
            batteryPercent: percent,
            isCharging: charging,
            thermal: thermal,
            endFloor: endFloor,
            pausedUntil: pausedUntil
        )
    }

    func testStartsWhenTheAgentWorksAndNoSessionRuns() {
        var p = AutoSessionPolicy()
        XCTAssertEqual(p.step(inputs(0, active: true)), .start(AutoSessionPolicy.chunk))
    }

    func testNothingWhileTheAgentIsIdle() {
        var p = AutoSessionPolicy()
        XCTAssertNil(p.step(inputs(0, active: false)))
    }

    func testNoStartWhenHotOrNearTheEndFloorOnBattery() {
        var p = AutoSessionPolicy()
        XCTAssertNil(p.step(inputs(0, active: true, thermal: .serious)))
        XCTAssertNil(p.step(inputs(1, active: true, thermal: .critical)))
        XCTAssertNil(p.step(inputs(2, active: true, percent: 25)), "25 is within the margin above an end floor of 20")
        XCTAssertEqual(p.step(inputs(3, active: true, percent: 25, charging: true)), .start(AutoSessionPolicy.chunk))
        XCTAssertEqual(p.step(inputs(4, active: true, percent: 26)), .start(AutoSessionPolicy.chunk))
    }

    func testExtendsItsOwnSessionWhileTheAgentWorks() {
        var p = AutoSessionPolicy()
        XCTAssertEqual(p.step(inputs(0, active: true)), .start(AutoSessionPolicy.chunk))
        p.started(at: t0)
        let endsAt = t0.addingTimeInterval(AutoSessionPolicy.chunk)
        XCTAssertNil(p.step(inputs(600, active: true, started: t0, endsAt: endsAt)))
        let late = AutoSessionPolicy.chunk - AutoSessionPolicy.extendBelow + 1
        XCTAssertEqual(p.step(inputs(late, active: true, started: t0, endsAt: endsAt)), .extend(AutoSessionPolicy.chunk))
    }

    func testEndsItsOwnSessionAfterTheIdleGraceAndStartsAgainLater() {
        var p = AutoSessionPolicy()
        XCTAssertEqual(p.step(inputs(0, active: true)), .start(AutoSessionPolicy.chunk))
        p.started(at: t0)
        let endsAt = t0.addingTimeInterval(AutoSessionPolicy.chunk)
        XCTAssertNil(p.step(inputs(60, active: false, started: t0, endsAt: endsAt)))
        XCTAssertEqual(p.step(inputs(AutoSessionPolicy.idleGrace, active: false, started: t0, endsAt: endsAt)), .end)
        XCTAssertEqual(p.step(inputs(AutoSessionPolicy.idleGrace + 15, active: false, started: t0, endsAt: endsAt)), .end,
                       "an end refused by a busy lock is asked for again")
        XCTAssertEqual(p.step(inputs(AutoSessionPolicy.idleGrace + 30, active: true)), .start(AutoSessionPolicy.chunk),
                       "an end the policy asked for does not hold the next start back")
        XCTAssertFalse(p.suppressed)
    }

    func testNeverTouchesASessionTheUserStarted() {
        var p = AutoSessionPolicy()
        let manual = t0.addingTimeInterval(-100)
        let endsAt = t0.addingTimeInterval(60)
        XCTAssertNil(p.step(inputs(0, active: true, started: manual, endsAt: endsAt)))
        XCTAssertNil(p.step(inputs(AutoSessionPolicy.idleGrace * 2, active: false, started: manual, endsAt: endsAt)))
    }

    func testHandsOffAfterAnEndItDidNotAskForUntilTheAgentLetsGo() {
        var p = AutoSessionPolicy()
        XCTAssertEqual(p.step(inputs(0, active: true)), .start(AutoSessionPolicy.chunk))
        p.started(at: t0)
        // The user ended it while the agent is still at work.
        XCTAssertNil(p.step(inputs(30, active: true)))
        XCTAssertTrue(p.suppressed)
        XCTAssertNil(p.step(inputs(45, active: true)))
        XCTAssertNil(p.step(inputs(60, active: false)))
        XCTAssertEqual(p.step(inputs(75, active: true)), .start(AutoSessionPolicy.chunk))
    }

    func testAFailedStartWaitsBeforeTryingAgain() {
        var p = AutoSessionPolicy()
        XCTAssertEqual(p.step(inputs(0, active: true)), .start(AutoSessionPolicy.chunk))
        p.startFailed(at: t0)
        XCTAssertNil(p.step(inputs(60, active: true)))
        XCTAssertEqual(p.step(inputs(AutoSessionPolicy.retryAfterFailedStart, active: true)), .start(AutoSessionPolicy.chunk))
    }

    func testASessionTheUserTookOverIsNoLongerExtendedOrEnded() {
        var p = AutoSessionPolicy()
        XCTAssertEqual(p.step(inputs(0, active: true)), .start(AutoSessionPolicy.chunk))
        p.started(at: t0)
        p.handOver()
        XCTAssertNil(p.ownSession)
        let endsAt = t0.addingTimeInterval(1800)
        XCTAssertNil(p.step(inputs(60, active: true, started: t0, endsAt: endsAt)), "under an hour left, but not ours to extend")
        XCTAssertNil(p.step(inputs(60 + AutoSessionPolicy.idleGrace * 2, active: false, started: t0, endsAt: endsAt)),
                     "idle long enough, but not ours to end")
        XCTAssertEqual(p.step(inputs(1800 + 15, active: true)), .start(AutoSessionPolicy.chunk),
                       "the time the user set ran out with the agent at work: ours follows")
    }

    func testAUserSessionEndedBeforeItsTimeHoldsTheNextStartBackUntilTheAgentLetsGo() {
        var p = AutoSessionPolicy()
        let manual = t0.addingTimeInterval(-100)
        XCTAssertNil(p.step(inputs(0, active: true, started: manual, endsAt: t0.addingTimeInterval(3600))))
        // The user held the end control with the agent still at work.
        XCTAssertNil(p.step(inputs(30, active: true)))
        XCTAssertTrue(p.suppressed)
        XCTAssertNil(p.step(inputs(45, active: true)))
        XCTAssertNil(p.step(inputs(60, active: false)))
        XCTAssertEqual(p.step(inputs(75, active: true)), .start(AutoSessionPolicy.chunk))
    }

    func testNothingStartsWhilePausedAndOursEndsWhenAPauseBegins() {
        var p = AutoSessionPolicy()
        let until = t0.addingTimeInterval(900)
        XCTAssertNil(p.step(inputs(0, active: true, pausedUntil: until)))
        XCTAssertEqual(p.step(inputs(900, active: true, pausedUntil: until)), .start(AutoSessionPolicy.chunk), "the pause is over")
        p.started(at: t0.addingTimeInterval(900))
        let later = t0.addingTimeInterval(4000)
        XCTAssertEqual(p.step(inputs(960, active: true, started: t0.addingTimeInterval(900),
                                     endsAt: t0.addingTimeInterval(900 + AutoSessionPolicy.chunk), pausedUntil: later)), .end)
    }

    func testAPauseTakesTheHandOffsPlace() {
        var p = AutoSessionPolicy()
        XCTAssertEqual(p.step(inputs(0, active: true)), .start(AutoSessionPolicy.chunk))
        p.started(at: t0)
        // The user held the end control and chose 15 minutes, the agent
        // still at work throughout.
        let until = t0.addingTimeInterval(30 + 900)
        XCTAssertNil(p.step(inputs(30, active: true, pausedUntil: until)))
        XCTAssertFalse(p.suppressed)
        XCTAssertEqual(p.step(inputs(30 + 900, active: true, pausedUntil: until)), .start(AutoSessionPolicy.chunk),
                       "once the pause is over a session starts again for the work still going on")
    }

    func testAUserSessionThatRanItsTimeOutLetsTheAgentsSessionFollow() {
        var p = AutoSessionPolicy()
        let manual = t0.addingTimeInterval(-100)
        XCTAssertNil(p.step(inputs(0, active: true, started: manual, endsAt: t0.addingTimeInterval(60))))
        XCTAssertEqual(p.step(inputs(75, active: true)), .start(AutoSessionPolicy.chunk))
        XCTAssertFalse(p.suppressed)
    }
}

/// Ending the automatic session by hand offers a pause; the menu offers
/// one at any time and shows it while it lasts.
@MainActor
final class AutoSessionPauseTests: XCTestCase {
    var h: Harness!

    override func setUp() async throws {
        h = Harness()
    }

    override func tearDown() async throws {
        h.home.destroy()
    }

    private func eventually(_ condition: @MainActor () -> Bool) async -> Bool {
        let deadline = Date().addingTimeInterval(3)
        while Date() < deadline {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return condition()
    }

    private func automatic(_ m: SessionManager, agent: @escaping @MainActor () -> Bool = { true }) -> AgentAutoSession {
        m.config.autoSession = true
        let clock = h.clock
        return AgentAutoSession(manager: m, isAgentActive: { _ in agent() }, readPower: { (80, false) }, thermal: { .nominal }, clock: { clock.now })
    }

    func testAPauseEndsTheAutomaticSessionAndHoldsTheNextOneUntilItIsOver() async throws {
        let m = h.makeManager()
        let auto = automatic(m)
        await auto.tick()
        XCTAssertTrue(m.isAutoSession)

        await m.pauseAutoSessions(until: h.clock.now.addingTimeInterval(900))
        XCTAssertNil(m.session)
        XCTAssertNotNil(try h.store.loadConfig()?.autoPausedUntil, "saved, so a relaunch keeps it")
        h.clock.advance(60)
        await auto.tick()
        XCTAssertNil(m.session, "paused, with Claude still at work")

        h.clock.advance(900)
        await auto.tick()
        XCTAssertNil(m.config.autoPausedUntil, "the pause is over and cleared")
        XCTAssertTrue(m.isAutoSession, "Claude is still at work, so the automatic session is back")
    }

    func testAPauseLeavesASessionTheUserStartedAlone() async throws {
        let m = h.makeManager()
        m.config.autoSession = true
        await m.start(duration: 3600)
        await m.pauseAutoSessions(until: h.clock.now.addingTimeInterval(900))
        XCTAssertNotNil(m.session)
    }

    func testHoldingTheEndOnTheAutomaticSessionOffersThePauseChoices() async throws {
        let m = h.makeManager()
        let auto = automatic(m)
        await auto.tick()
        var offered: NSMenu?
        let clock = h.clock
        let controller = StatusItemController(
            manager: m, status: PlaceholderStatus(), showSettings: {},
            askPauseUntil: { nil }, presentPauseMenu: { offered = $0 }, clock: { clock.now }
        )
        controller.holdToEnd()
        let shown = await eventually { offered != nil }
        XCTAssertTrue(shown)
        XCTAssertNil(m.session)
        let titles = offered?.items.map(\.title) ?? []
        XCTAssertEqual(titles, [StatusMenu.pauseTitle, "15 dakika", "1 saat", "3 saat", "Saat seç\u{2026}", "", "Duraklatma"])

        let oneHour = try XCTUnwrap(offered?.items.first { $0.title == "1 saat" })
        controller.choose(oneHour)
        let paused = await eventually { m.config.autoPausedUntil != nil }
        XCTAssertTrue(paused)
        XCTAssertEqual(m.config.autoPausedUntil, clock.now.addingTimeInterval(3600))
    }

    func testEndingASessionTheUserStartedOffersNoPause() async throws {
        let m = h.makeManager()
        await m.start(duration: 3600)
        var offered = false
        let controller = StatusItemController(manager: m, status: PlaceholderStatus(), showSettings: {}, presentPauseMenu: { _ in offered = true })
        controller.holdToEnd()
        let ended = await eventually { m.session == nil }
        XCTAssertTrue(ended)
        try? await Task.sleep(for: .milliseconds(50))
        XCTAssertFalse(offered)
    }

    func testAPickedTimeIsTheNextOneToCome() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Istanbul")!
        let now = calendar.date(from: DateComponents(year: 2026, month: 10, day: 20, hour: 23, minute: 10))!
        let seven = calendar.date(from: DateComponents(year: 2026, month: 10, day: 20, hour: 7, minute: 0))!
        XCTAssertEqual(StatusItemController.nextOccurrence(of: seven, after: now, calendar: calendar),
                       calendar.date(from: DateComponents(year: 2026, month: 10, day: 21, hour: 7, minute: 0)))
        let half = calendar.date(from: DateComponents(year: 2026, month: 10, day: 20, hour: 23, minute: 30))!
        XCTAssertEqual(StatusItemController.nextOccurrence(of: half, after: now, calendar: calendar), half)
    }

    func testTheMenuOffersAPauseAndShowsOneThatLasts() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Istanbul")!
        let now = calendar.date(from: DateComponents(year: 2026, month: 10, day: 20, hour: 23, minute: 10))!
        func items(on: Bool, until: Date?) -> [StatusMenu.Item] {
            StatusMenu.items(sessionActive: false, sleepHeld: false, autoSessionOn: on, autoPausedUntil: until, now: now,
                             machine: nil, actions: nil, throttledBrowsers: [], error: nil)
        }
        XCTAssertEqual(items(on: true, until: nil).first?.kind, .pauseAuto)
        XCTAssertFalse(items(on: false, until: nil).contains { $0.kind == .pauseAuto }, "nothing to pause with the feature off")
        let paused = items(on: true, until: now.addingTimeInterval(600))
        XCTAssertEqual(paused.prefix(2).map(\.kind), [.info, .resumeAuto])
        XCTAssertEqual(paused.first?.title, StatusMenu.pauseLine(until: now.addingTimeInterval(600), now: now, calendar: calendar))
        XCTAssertEqual(items(on: true, until: now.addingTimeInterval(-1)).first?.kind, .pauseAuto, "a pause that is over")

        XCTAssertEqual(StatusMenu.pauseLine(until: now.addingTimeInterval(600), now: now, calendar: calendar),
                       "Otomatik oturum duraklatıldı; saat 23:20 itibarıyla yeniden açılır")
        XCTAssertEqual(StatusMenu.pauseLine(until: now.addingTimeInterval(8 * 3600), now: now, calendar: calendar),
                       "Otomatik oturum duraklatıldı; yarın 07:10 itibarıyla yeniden açılır")
    }

    func testThePauseMarkOnlyWhileIdleAndPaused() {
        XCTAssertTrue(StatusRootView.showsPauseMark(phase: .idle, isRunning: false, autoSessionOn: true, paused: true))
        XCTAssertFalse(StatusRootView.showsPauseMark(phase: .idle, isRunning: true, autoSessionOn: true, paused: true))
        XCTAssertFalse(StatusRootView.showsPauseMark(phase: .entering(.start), isRunning: false, autoSessionOn: true, paused: true))
        XCTAssertFalse(StatusRootView.showsPauseMark(phase: .idle, isRunning: false, autoSessionOn: false, paused: true))
        XCTAssertFalse(StatusRootView.showsPauseMark(phase: .idle, isRunning: false, autoSessionOn: true, paused: false))
    }

    func testTheChoicesRoundTripThroughTheirTags() {
        for choice in StatusMenu.PauseChoice.menuChoices + [.none] {
            XCTAssertEqual(StatusMenu.PauseChoice(tag: choice.tag), choice)
        }
    }
}

/// The automatic session shows "Claude" instead of a countdown, and becomes
/// the user's when they set a time on it.
@MainActor
final class AutoSessionDisplayTests: XCTestCase {
    var h: Harness!

    override func setUp() async throws {
        h = Harness()
    }

    override func tearDown() async throws {
        h.home.destroy()
    }

    func testOnlyAnAutomaticStartIsTheAutomaticSession() async throws {
        let m = h.makeManager()
        await m.start(duration: 3600, auto: true)
        XCTAssertTrue(m.isAutoSession)
        _ = await m.end(reason: .user)
        XCTAssertFalse(m.isAutoSession)
        await m.start(duration: 3600)
        XCTAssertNotNil(m.session)
        XCTAssertFalse(m.isAutoSession)
    }

    func testTakingOverEndsThatLongFromNowAndMakesItTheUsers() async throws {
        let m = h.makeManager()
        await m.start(duration: AutoSessionPolicy.chunk, auto: true)
        let started = try XCTUnwrap(m.session)
        h.clock.advance(600)
        await m.takeOver(duration: 1800)
        let s = try XCTUnwrap(m.session)
        XCTAssertEqual(s.startedAt, started.startedAt)
        XCTAssertEqual(s.endsAt, h.clock.now.addingTimeInterval(1800), "sooner than the automatic session would have ended")
        XCTAssertEqual(s.extensions, [600 + 1800 - AutoSessionPolicy.chunk])
        XCTAssertEqual(try h.store.loadSession(), s)
        XCTAssertEqual(m.scheduledDeadline, s.endsAt)
        XCTAssertFalse(m.isAutoSession)

        await m.takeOver(duration: 3 * 3600)
        XCTAssertEqual(m.session?.endsAt, h.clock.now.addingTimeInterval(3 * 3600), "or later")
    }

    func testTheAutomaticSessionIsLeftAloneOnceTheUserSetsATime() async throws {
        let m = h.makeManager()
        m.config.autoSession = true
        var agent = true
        let clock = h.clock
        let auto = AgentAutoSession(
            manager: m,
            isAgentActive: { _ in agent },
            readPower: { (80, false) },
            thermal: { .nominal },
            clock: { clock.now }
        )
        await auto.tick()
        XCTAssertTrue(m.isAutoSession)
        await m.takeOver(duration: 3600)
        agent = false
        await auto.tick()
        clock.advance(AutoSessionPolicy.idleGrace + 60)
        await auto.tick()
        XCTAssertNotNil(m.session, "idle past the grace, but the session is the user's now")
        XCTAssertNil(auto.policy.ownSession)
    }

    func testTurningTheFeatureOffLeavesTheSessionToRunOutItsTime() async throws {
        let m = h.makeManager()
        m.config.autoSession = true
        let clock = h.clock
        let auto = AgentAutoSession(manager: m, isAgentActive: { _ in true }, readPower: { (80, false) }, thermal: { .nominal }, clock: { clock.now })
        await auto.tick()
        XCTAssertTrue(m.isAutoSession)
        m.config.autoSession = false
        await auto.tick()
        XCTAssertFalse(m.isAutoSession)
        XCTAssertNotNil(m.session)
        XCTAssertNil(auto.policy.ownSession)
    }

    func testTheStatusItemReadsClaudeAndNeverTheCountdown() {
        XCTAssertEqual(StatusRootView.liveText(isAutoSession: true, countdown: {
            XCTFail("the countdown is not read for the automatic session")
            return "1:59:59"
        }), MenuBarModel.autoSessionText)
        XCTAssertEqual(StatusRootView.liveText(isAutoSession: false, countdown: { "1:59:59" }), "1:59:59")
        XCTAssertEqual(StatusRootView.countdownText(pending: "0:30:00", live: MenuBarModel.autoSessionText, phase: .running), "0:30:00",
                       "a time being set shows its countdown at once")
    }

    func testTheMenuSaysHowTheAutomaticSessionEnds() {
        func titles(auto: Bool, active: Bool = true) -> [String] {
            StatusMenu.items(sessionActive: active, sleepHeld: active, autoSession: auto, machine: nil, actions: nil,
                             throttledBrowsers: [], error: nil).map(\.title)
        }
        XCTAssertEqual(titles(auto: true).prefix(2).last, StatusMenu.autoSessionLine)
        XCTAssertFalse(titles(auto: false).contains(StatusMenu.autoSessionLine))
        XCTAssertFalse(titles(auto: true, active: false).contains(StatusMenu.autoSessionLine))
    }
}

@MainActor
final class IdleBlackoutTests: XCTestCase {
    final class Idle: @unchecked Sendable { var seconds: Double = 0 }
    final class Awake: DisplayAwakeHolding {
        private(set) var holds = 0
        private(set) var releases = 0
        var held: Bool { holds > releases }
        func hold() { holds += 1 }
        func release() { releases += 1 }
    }

    private func make(display: Float = 0.7, keyboard: Float? = 0.5) -> (IdleBlackout, FakeDisplayDimmer, FakeKeyboardBacklight, Idle, Awake) {
        let d = FakeDisplayDimmer(brightness: display)
        let k = FakeKeyboardBacklight(brightness: keyboard)
        let idle = Idle()
        let awake = Awake()
        let config = Config()
        let blackout = IdleBlackout(display: d, keyboard: k, idleSeconds: { idle.seconds }, config: { config }, awake: awake)
        blackout.setActive(true, startTimer: false)
        return (blackout, d, k, idle, awake)
    }

    func testHoldsOffTheScreenSaverThenTurnsTheKeyboardAndTheDisplayOff() {
        let (blackout, d, k, idle, awake) = make()
        XCTAssertTrue(awake.held, "no screen saver or display sleep while on")
        idle.seconds = 10
        blackout.tick()
        XCTAssertEqual(d.brightness, 0.7)
        XCTAssertEqual(k.brightness, 0.5)
        idle.seconds = 30
        blackout.tick()
        XCTAssertEqual(k.brightness, 0)
        XCTAssertEqual(d.brightness, 0.7)
        idle.seconds = 60
        blackout.tick()
        XCTAssertEqual(d.brightness, 0, "black: no backlight")
        XCTAssertTrue(blackout.isHoldingDisplay)
        XCTAssertTrue(blackout.isHoldingKeyboard)
        idle.seconds = 120
        blackout.tick()
        XCTAssertEqual(d.sets, [0], "a black panel is not set again")
    }

    func testAPanelLitAgainWhileIdleIsDarkenedAgainAndTheUsersLevelKept() {
        let (blackout, d, _, idle, _) = make()
        idle.seconds = 90
        blackout.tick()
        d.brightness = 0.3 // auto-brightness under a change of light
        blackout.tick()
        XCTAssertEqual(d.brightness, 0)
        idle.seconds = 0.2
        blackout.tick()
        XCTAssertEqual(d.brightness, 0.7, "the level from before the black, not the one auto-brightness set")
    }

    func testInputBringsBothBack() {
        let (blackout, d, k, idle, _) = make()
        idle.seconds = 90
        blackout.tick()
        idle.seconds = 0.2
        blackout.tick()
        XCTAssertEqual(d.brightness, 0.7)
        XCTAssertEqual(k.brightness, 0.5)
        XCTAssertFalse(blackout.isHoldingDisplay)
        XCTAssertFalse(blackout.isHoldingKeyboard)
    }

    func testTurningOffRestoresAndLetsTheDisplayIdleAgain() {
        let (blackout, d, k, idle, awake) = make()
        idle.seconds = 90
        blackout.tick()
        blackout.setActive(false)
        XCTAssertEqual(d.brightness, 0.7)
        XCTAssertEqual(k.brightness, 0.5)
        XCTAssertFalse(awake.held, "the assertion goes, so a lid close can sleep the display")
        idle.seconds = 300
        blackout.tick()
        XCTAssertEqual(d.brightness, 0.7, "an inactive blackout changes nothing")
    }

    func testABlackPanelAndADarkKeyboardAreLeftAlone() {
        let (blackout, d, k, idle, _) = make(display: 0, keyboard: 0)
        idle.seconds = 300
        blackout.tick()
        XCTAssertEqual(d.sets, [])
        XCTAssertEqual(k.sets, [])
        XCTAssertFalse(blackout.isHoldingDisplay)
        XCTAssertFalse(blackout.isHoldingKeyboard)
    }
}

@MainActor
final class VoiceAnnouncerTests: XCTestCase {
    final class RecordingSpeech: SpeechSynthesizing, @unchecked Sendable {
        let audio: FakeAudioControl
        private let lock = NSLock()
        private var _spoken: [(text: String, volume: Float, muted: Bool)] = []
        var spoken: [(text: String, volume: Float, muted: Bool)] { lock.withLock { _spoken } }
        init(audio: FakeAudioControl) { self.audio = audio }
        func speak(_ text: String) async {
            let entry = (text: text, volume: audio.volume, muted: audio.muted)
            lock.withLock { _spoken.append(entry) }
        }
    }

    final class Lid: @unchecked Sendable { var closed: Bool; init(_ closed: Bool) { self.closed = closed } }

    private func make(lidClosed: Bool, enabled: Bool = true) -> (VoiceAnnouncer, FakeAudioControl, RecordingSpeech, Lid) {
        let audio = FakeAudioControl(volume: 0.6, muted: true)
        let speech = RecordingSpeech(audio: audio)
        let lid = Lid(lidClosed)
        let announcer = VoiceAnnouncer(
            audio: audio,
            speech: speech,
            lidClosed: { lid.closed },
            enabled: { enabled }
        )
        return (announcer, audio, speech, lid)
    }

    func testSpeaksUnmutedThenPutsTheVolumeAndMuteBack() async {
        let (announcer, audio, speech, _) = make(lidClosed: true)
        await announcer.announce("Pil yüzde 29. Düşük Güç Modu açıldı.")
        XCTAssertEqual(speech.spoken.map(\.text), ["Pil yüzde 29. Düşük Güç Modu açıldı."])
        XCTAssertEqual(speech.spoken.first?.muted, false)
        XCTAssertEqual(speech.spoken.first?.volume, VoiceAnnouncer.volume)
        XCTAssertEqual(audio.volume, 0.6)
        XCTAssertTrue(audio.muted, "the lid-close mute is back once the sentence is over")
    }

    func testSilentWithTheLidOpenOrAlertsOff() async {
        let (open, openAudio, openSpeech, _) = make(lidClosed: false)
        await open.announce("x")
        XCTAssertTrue(openSpeech.spoken.isEmpty)
        XCTAssertTrue(openAudio.applied.isEmpty)
        let (off, offAudio, offSpeech, _) = make(lidClosed: true, enabled: false)
        await off.announce("x")
        XCTAssertTrue(offSpeech.spoken.isEmpty)
        XCTAssertTrue(offAudio.applied.isEmpty)
    }

    func testALidOpenedWhileSpeakingLeavesTheOutputToTheOpen() async {
        let audio = FakeAudioControl(volume: 0.6, muted: true)
        let lid = Lid(true)
        final class OpeningSpeech: SpeechSynthesizing, @unchecked Sendable {
            let lid: Lid
            init(lid: Lid) { self.lid = lid }
            func speak(_ text: String) async { lid.closed = false }
        }
        let announcer = VoiceAnnouncer(audio: audio, speech: OpeningSpeech(lid: lid), lidClosed: { lid.closed }, enabled: { true })
        await announcer.announce("x")
        XCTAssertEqual(audio.applied.count, 1, "unmuted for the sentence, then left to the lid open's restore")
        XCTAssertFalse(audio.muted)
    }

    func testEndSentences() {
        XCTAssertEqual(VoiceAnnouncer.endSentence(.batteryFloor, batteryPercent: 19), "Pil yüzde 19. Oturum bitiyor, Mac uyuyacak.")
        XCTAssertEqual(VoiceAnnouncer.endSentence(.agentIdle, batteryPercent: nil), "Claude çalışmayı bıraktı. Oturum bitiyor, Mac uyuyacak.")
        XCTAssertNotNil(VoiceAnnouncer.endSentence(.thermalCritical, batteryPercent: nil))
        XCTAssertNotNil(VoiceAnnouncer.endSentence(.timer, batteryPercent: nil))
        XCTAssertNil(VoiceAnnouncer.endSentence(.user, batteryPercent: nil), "an end the user asked for is not announced")
        XCTAssertNil(VoiceAnnouncer.endSentence(.quit, batteryPercent: nil))
    }
}

final class CodeModeFloorTests: XCTestCase {
    func testCodeModeIsALowPowerCauseOnlyWithTheLidOpenAndAnAgentAtWork() {
        var c = Config()
        XCTAssertEqual(FloorRules.lowPowerCause(percent: 80, isCharging: true, thermal: .nominal, lidClosed: false, agentActive: true, config: c), .codeMode)
        XCTAssertNil(FloorRules.lowPowerCause(percent: 80, isCharging: true, thermal: .nominal, lidClosed: false, agentActive: false, config: c))
        XCTAssertEqual(FloorRules.lowPowerCause(percent: 80, isCharging: true, thermal: .nominal, lidClosed: true, agentActive: true, config: c), .lid)
        XCTAssertEqual(FloorRules.lowPowerCause(percent: 10, isCharging: false, thermal: .nominal, lidClosed: false, agentActive: true, config: c), .battery,
                       "the battery floor still names itself, so its notification is posted")
        c.codeMode = false
        XCTAssertNil(FloorRules.lowPowerCause(percent: 80, isCharging: true, thermal: .nominal, lidClosed: false, agentActive: true, config: c))
    }

    func testTheModeFollowsTheAgent() {
        let c = Config()
        XCTAssertEqual(
            FloorRules.evaluate(battery: .percent(80), isCharging: true, thermal: .nominal, lidClosed: false, lowPowerSetByUs: false, agentActive: true, config: c),
            [.enableLowPower(.codeMode)]
        )
        XCTAssertEqual(
            FloorRules.evaluate(battery: .percent(80), isCharging: true, thermal: .nominal, lidClosed: false, lowPowerSetByUs: true, agentActive: false, config: c),
            [.disableLowPower]
        )
    }
}

final class AgentActivityTests: XCTestCase {
    func testOnlySystemSleepAssertionsCount() {
        let byProcess: [NSNumber: [[String: Any]]] = [
            100: [["AssertType": "NoIdleSleepAssertion", "AssertName": "Electron"]],
            200: [["AssertType": "PreventUserIdleDisplaySleep", "AssertName": "video"]],
            300: [["AssertType": "PreventUserIdleSystemSleep"]],
        ]
        XCTAssertEqual(AgentActivity.pidsHoldingSleepAssertions(byProcess), [100, 300])
    }

    func testActiveOnlyForTheListedApps() {
        let bundles: [pid_t: String] = [100: "com.anthropic.claudefordesktop", 300: "com.apple.Music"]
        let claude = ["com.anthropic.claudefordesktop"]
        XCTAssertTrue(AgentActivity.isActive(pids: [100, 300], bundleIDs: claude) { bundles[$0] })
        XCTAssertFalse(AgentActivity.isActive(pids: [300], bundleIDs: claude) { bundles[$0] })
        XCTAssertFalse(AgentActivity.isActive(pids: [100], bundleIDs: []) { bundles[$0] })
    }
}

final class ForkConfigTests: XCTestCase {
    func testForkDefaults() {
        let c = Config()
        XCTAssertTrue(c.voiceAlerts)
        XCTAssertTrue(c.autoSession)
        XCTAssertEqual(c.autoSessionAgents, ["com.anthropic.claudefordesktop"])
        XCTAssertTrue(c.codeMode)
        XCTAssertTrue(c.idleBlackout)
        XCTAssertEqual(c.idleBlackoutAfter, 60)
        XCTAssertEqual(c.keyboardOffAfter, 30)
        XCTAssertTrue(FreezePlanner.builtInProtected.contains("ch.protonvpn.mac"))
        XCTAssertTrue(FreezePlanner.builtInProtected.contains("com.philandro.anydesk"))
    }

    func testAConfigWithoutTheForkKeysGetsTheirDefaults() throws {
        let c = try JSONDecoder().decode(Config.self, from: Data("{}".utf8))
        XCTAssertTrue(c.voiceAlerts)
        XCTAssertTrue(c.autoSession)
        XCTAssertTrue(c.codeMode)
        XCTAssertTrue(c.idleBlackout)
        XCTAssertEqual(c.idleBlackoutAfter, 60)
        XCTAssertFalse(c.freezeAllApps, "a config.json without the key never opts in to freezing every app")
    }

    func testTheForkKeysRoundTrip() throws {
        var c = Config()
        c.voiceAlerts = false
        c.autoSession = false
        c.autoSessionAgents = ["com.example.agent"]
        c.codeMode = false
        c.idleBlackout = false
        c.idleBlackoutAfter = 120
        c.keyboardOffAfter = 45
        let back = try JSONDecoder().decode(Config.self, from: JSONEncoder().encode(c))
        XCTAssertEqual(back, c)
    }
}

final class ClaudeHooksSettingsTests: XCTestCase {
    private var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("uykusuz-hooks-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: dir)
    }

    private func json(_ url: URL) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
    }

    func testInstallKeepsEverythingElseBacksUpOnceAndIsIdempotent() throws {
        let settings = dir.appendingPathComponent("settings.json")
        let original = #"{"model":"opus","permissions":{"allow":["Bash(ls:*)"]},"hooks":{"Stop":[{"hooks":[{"type":"command","command":"say done"}]}]}}"#
        try Data(original.utf8).write(to: settings)

        XCTAssertFalse(ClaudeHooks.isInstalled(settingsURL: settings))
        XCTAssertEqual(try ClaudeHooks.install(settingsURL: settings), .installed)
        XCTAssertTrue(ClaudeHooks.isInstalled(settingsURL: settings))
        let root = try json(settings)
        XCTAssertEqual(root["model"] as? String, "opus")
        XCTAssertNotNil(root["permissions"])
        let hooks = try XCTUnwrap(root["hooks"] as? [String: Any])
        for event in ClaudeHooks.events {
            let groups = try XCTUnwrap(hooks[event] as? [[String: Any]], event)
            let commands = groups.flatMap { ($0["hooks"] as? [[String: Any]] ?? []).compactMap { $0["command"] as? String } }
            XCTAssertTrue(commands.contains(ClaudeHooks.command), event)
        }
        let stopCommands = (hooks["Stop"] as? [[String: Any]] ?? []).flatMap { ($0["hooks"] as? [[String: Any]] ?? []).compactMap { $0["command"] as? String } }
        XCTAssertTrue(stopCommands.contains("say done"), "an existing hook stays")
        XCTAssertEqual(try String(contentsOf: URL(fileURLWithPath: settings.path + ClaudeHooks.backupSuffix), encoding: .utf8), original)

        let afterInstall = try Data(contentsOf: settings)
        XCTAssertEqual(try ClaudeHooks.install(settingsURL: settings), .unchanged)
        XCTAssertEqual(try Data(contentsOf: settings), afterInstall, "a second install writes nothing")

        XCTAssertEqual(try ClaudeHooks.remove(settingsURL: settings), .removed)
        XCTAssertFalse(ClaudeHooks.isInstalled(settingsURL: settings))
        let removed = try json(settings)
        XCTAssertEqual(removed["model"] as? String, "opus")
        let left = try XCTUnwrap(removed["hooks"] as? [String: Any])
        XCTAssertEqual(Set(left.keys), ["Stop"], "only the user's own hook is left")
        XCTAssertEqual(try ClaudeHooks.remove(settingsURL: settings), .unchanged)
        XCTAssertEqual(try String(contentsOf: URL(fileURLWithPath: settings.path + ClaudeHooks.backupSuffix), encoding: .utf8), original,
                       "the backup is the file before the first change, never overwritten")
    }

    func testInstallCreatesAMissingFileAndRefusesOneThatIsNotAnObject() throws {
        let fresh = dir.appendingPathComponent("new/settings.json")
        XCTAssertEqual(try ClaudeHooks.install(settingsURL: fresh), .installed)
        XCTAssertTrue(ClaudeHooks.isInstalled(settingsURL: fresh))
        XCTAssertFalse(FileManager.default.fileExists(atPath: fresh.path + ClaudeHooks.backupSuffix), "nothing to back up")

        let odd = dir.appendingPathComponent("odd.json")
        try Data("[1, 2]".utf8).write(to: odd)
        XCTAssertThrowsError(try ClaudeHooks.install(settingsURL: odd))
        XCTAssertEqual(try String(contentsOf: odd, encoding: .utf8), "[1, 2]", "a file it cannot read as settings is left alone")
    }

    func testTheCommandIsSilentAndNeverFails() {
        XCTAssertTrue(ClaudeHooks.command.contains(">/dev/null 2>&1 || true"), ClaudeHooks.command)
        XCTAssertTrue(ClaudeHooks.command.contains("Uykusuz.app/Contents/MacOS/Uykusuz\" --claude-hook"))
    }
}

final class ClaudeHookCommandTests: XCTestCase {
    private var root: URL!
    private var paths: Paths!
    private let t0 = Date(timeIntervalSince1970: 2_000_000_000)
    private let identity = ProcessIdentity(startedAt: 1_999_000_000, startedAtMicros: 7, bootSession: "boot")

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("uykusuz-hook-\(UUID().uuidString)", isDirectory: true)
        paths = Paths(root: root)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: root)
    }

    @discardableResult
    private func hook(_ event: String, session: String = "abc-123", at offset: TimeInterval = 0) -> Int32? {
        let input = Data(#"{"session_id":"\#(session)","hook_event_name":"\#(event)"}"#.utf8)
        return ClaudeHookCommand.run(["--claude-hook"], readInput: { input }, paths: paths, now: t0.addingTimeInterval(offset)) { (4242, self.identity) }
    }

    private func marker(_ session: String = "abc-123") throws -> ClaudeTaskMarker? {
        let file = ClaudeHookCommand.markerDirectory(paths).appendingPathComponent("\(session).json")
        guard FileManager.default.fileExists(atPath: file.path) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(ClaudeTaskMarker.self, from: Data(contentsOf: file))
    }

    func testATaskWritesTheMarkerToolUseRefreshesItAndStopRemovesIt() throws {
        XCTAssertEqual(hook("UserPromptSubmit"), 0)
        XCTAssertEqual(try marker(), ClaudeTaskMarker(pid: 4242, identity: identity, event: "UserPromptSubmit", updatedAt: t0))
        hook("PostToolUse", at: 90)
        XCTAssertEqual(try marker()?.updatedAt, t0.addingTimeInterval(90))
        XCTAssertEqual(try marker()?.event, "PostToolUse")
        hook("Stop", at: 120)
        XCTAssertNil(try marker())
        hook("UserPromptSubmit", at: 200)
        hook("SessionEnd", at: 300)
        XCTAssertNil(try marker(), "the session ending removes it too")
    }

    func testOtherArgumentsAreNotThisModeAndBadInputChangesNothing() throws {
        XCTAssertNil(ClaudeHookCommand.run(["--resume-frozen"], readInput: { Data() }, paths: paths, now: t0) { nil })
        XCTAssertEqual(ClaudeHookCommand.run(["--claude-hook"], readInput: { Data("not json".utf8) }, paths: paths, now: t0) { nil }, 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: ClaudeHookCommand.markerDirectory(paths).path))
    }

    func testSessionIdsBecomeSafeFileNames() {
        XCTAssertEqual(ClaudeHookCommand.markerName("dd2097ca-a8bf-495e"), "dd2097ca-a8bf-495e.json")
        XCTAssertEqual(ClaudeHookCommand.markerName("../x"), "___x.json")
        XCTAssertNil(ClaudeHookCommand.markerName(""))
        XCTAssertNil(ClaudeHookCommand.markerName("/.."))
        XCTAssertNil(ClaudeHookCommand.markerName(nil))
    }

    func testAMarkerCountsWhileFreshAndItsClaudeIsTheSameProcess() throws {
        hook("UserPromptSubmit")
        let alive: (Int32) -> ProcessLookup = { _ in .present(ProcessSignalState(ppid: 1, stopped: false, identity: self.identity)) }
        XCTAssertTrue(ClaudeActivity.markerBusy(paths: paths, now: t0.addingTimeInterval(60), lookup: alive))

        let reused: (Int32) -> ProcessLookup = { _ in
            .present(ProcessSignalState(ppid: 1, stopped: false, identity: ProcessIdentity(startedAt: 1, startedAtMicros: 0, bootSession: "boot")))
        }
        XCTAssertFalse(ClaudeActivity.markerBusy(paths: paths, now: t0.addingTimeInterval(60), lookup: reused), "a pid another process now has")
        XCTAssertNil(try marker(), "an orphaned marker is cleared")

        hook("UserPromptSubmit")
        XCTAssertFalse(ClaudeActivity.markerBusy(paths: paths, now: t0.addingTimeInterval(60)) { _ in .absent }, "Claude has exited")

        hook("UserPromptSubmit")
        XCTAssertFalse(ClaudeActivity.markerBusy(paths: paths, now: t0.addingTimeInterval(ClaudeActivity.markerMaxAge + 1), lookup: alive),
                       "no hook for too long: interrupted, which skips Stop")
        XCTAssertNil(try marker())
    }
}
