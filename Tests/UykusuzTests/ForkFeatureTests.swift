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
        endFloor: Int = 20
    ) -> AutoSessionPolicy.Inputs {
        .init(
            now: t0.addingTimeInterval(offset),
            agentActive: active,
            sessionStartedAt: started,
            sessionEndsAt: endsAt,
            batteryPercent: percent,
            isCharging: charging,
            thermal: thermal,
            endFloor: endFloor
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
}

@MainActor
final class CodeModeDimmerTests: XCTestCase {
    final class Idle: @unchecked Sendable { var seconds: Double = 0 }

    private func make(display: Float = 0.7, keyboard: Float? = 0.5) -> (CodeModeDimmer, FakeDisplayDimmer, FakeKeyboardBacklight, Idle) {
        let d = FakeDisplayDimmer(brightness: display)
        let k = FakeKeyboardBacklight(brightness: keyboard)
        let idle = Idle()
        let config = Config()
        let dimmer = CodeModeDimmer(display: d, keyboard: k, idleSeconds: { idle.seconds }, config: { config })
        dimmer.setActive(true, startTimer: false)
        return (dimmer, d, k, idle)
    }

    func testKeyboardGoesOffThenTheDisplayDims() {
        let (dimmer, d, k, idle) = make()
        let level = Config().codeModeDimLevel
        idle.seconds = 10
        dimmer.tick()
        XCTAssertEqual(d.brightness, 0.7)
        XCTAssertEqual(k.brightness, 0.5)
        idle.seconds = 30
        dimmer.tick()
        XCTAssertEqual(k.brightness, 0)
        XCTAssertEqual(d.brightness, 0.7)
        XCTAssertTrue(dimmer.isHoldingKeyboard)
        XCTAssertFalse(dimmer.isHoldingDisplay)
        idle.seconds = 60
        dimmer.tick()
        XCTAssertEqual(d.brightness, level)
        XCTAssertTrue(dimmer.isHoldingDisplay)
        idle.seconds = 120
        dimmer.tick()
        XCTAssertEqual(d.sets, [level], "a dim panel is not dimmed again")
        XCTAssertEqual(k.sets, [0])
    }

    func testInputBringsBothBack() {
        let (dimmer, d, k, idle) = make()
        idle.seconds = 90
        dimmer.tick()
        idle.seconds = 0.2
        dimmer.tick()
        XCTAssertEqual(d.brightness, 0.7)
        XCTAssertEqual(k.brightness, 0.5)
        XCTAssertFalse(dimmer.isHoldingDisplay)
        XCTAssertFalse(dimmer.isHoldingKeyboard)
    }

    func testTurningOffRestoresAndStopsDimming() {
        let (dimmer, d, k, idle) = make()
        idle.seconds = 90
        dimmer.tick()
        dimmer.setActive(false)
        XCTAssertEqual(d.brightness, 0.7)
        XCTAssertEqual(k.brightness, 0.5)
        idle.seconds = 300
        dimmer.tick()
        XCTAssertEqual(d.brightness, 0.7, "an inactive dimmer changes nothing")
    }

    func testADimPanelAndADarkKeyboardAreLeftAlone() {
        let (dimmer, d, k, idle) = make(display: 0.1, keyboard: 0)
        idle.seconds = 300
        dimmer.tick()
        XCTAssertEqual(d.sets, [])
        XCTAssertEqual(k.sets, [])
        XCTAssertFalse(dimmer.isHoldingDisplay)
        XCTAssertFalse(dimmer.isHoldingKeyboard)
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
        XCTAssertEqual(VoiceAnnouncer.endSentence(.agentIdle, batteryPercent: nil), "Claude kapandı. Oturum bitiyor, Mac uyuyacak.")
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
        XCTAssertEqual(c.codeModeDimAfter, 60)
        XCTAssertEqual(c.codeModeKeyboardOffAfter, 30)
        XCTAssertEqual(c.codeModeDimLevel, 0.15)
        XCTAssertTrue(FreezePlanner.builtInProtected.contains("ch.protonvpn.mac"))
        XCTAssertTrue(FreezePlanner.builtInProtected.contains("com.philandro.anydesk"))
    }

    func testAConfigWithoutTheForkKeysGetsTheirDefaults() throws {
        let c = try JSONDecoder().decode(Config.self, from: Data("{}".utf8))
        XCTAssertTrue(c.voiceAlerts)
        XCTAssertTrue(c.autoSession)
        XCTAssertTrue(c.codeMode)
        XCTAssertEqual(c.codeModeDimAfter, 60)
        XCTAssertFalse(c.freezeAllApps, "a config.json without the key never opts in to freezing every app")
    }

    func testTheForkKeysRoundTrip() throws {
        var c = Config()
        c.voiceAlerts = false
        c.autoSession = false
        c.autoSessionAgents = ["com.example.agent"]
        c.codeMode = false
        c.codeModeDimAfter = 120
        c.codeModeDimLevel = 0.3
        c.codeModeKeyboardOffAfter = 45
        let back = try JSONDecoder().decode(Config.self, from: JSONEncoder().encode(c))
        XCTAssertEqual(back, c)
    }
}
