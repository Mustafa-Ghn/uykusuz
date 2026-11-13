import XCTest
@testable import Uykusuz

/// The device as the failover asks it: what it is asked for, what it
/// answers, and a gate that holds the answer back until a test opens it.
final class FakeHotspotWaker: HotspotWaking, @unchecked Sendable {
    private let lock = NSLock()
    private var _asked: [String] = []
    private var held: CheckedContinuation<Void, Never>?
    private var holding = false
    let answer: HotspotWakeAnswer
    let reached = XCTestExpectation(description: "the device was asked")

    init(_ answer: HotspotWakeAnswer, holdingTheAnswer: Bool = false) {
        self.answer = answer
        holding = holdingTheAnswer
        reached.assertForOverFulfill = false
    }

    var asked: [String] { lock.withLock { _asked } }

    func release() {
        let waiting = lock.withLock { () -> CheckedContinuation<Void, Never>? in
            holding = false
            defer { held = nil }
            return held
        }
        waiting?.resume()
    }

    func wake(named name: String) async -> HotspotWakeAnswer {
        lock.withLock { _asked.append(name) }
        reached.fulfill()
        await withCheckedContinuation { continuation in
            let open = lock.withLock { () -> Bool in
                if holding { held = continuation }
                return !holding
            }
            if open { continuation.resume() }
        }
        return answer
    }
}

/// A keychain no test expects to be opened.
struct UntouchedKeychain: KeychainStoring {
    struct Opened: Error {}
    func get(service: String, account: String) throws -> String? { throw Opened() }
    func set(service: String, account: String, value: String) throws { throw Opened() }
    func delete(service: String, account: String) throws { throw Opened() }
}

final class HotspotSSIDTests: XCTestCase {
    private let typed = "Ada'n\u{131}n iPhone'u"
    private let phone = "Ada\u{2019}n\u{131}n iPhone\u{2019}u"

    func testOneNameInTwoApostrophesIsTheSameName() {
        XCTAssertTrue(HotspotSSID.same(typed, phone))
        XCTAssertTrue(HotspotSSID.same("  \(typed)\n", phone), "as Settings saves it")
        XCTAssertTrue(HotspotSSID.same("OrnekTelefon", "OrnekTelefon"))
        XCTAssertFalse(HotspotSSID.same(typed, "Ece\u{2019}nin iPhone\u{2019}u"), "another phone")
        XCTAssertFalse(HotspotSSID.same("iPhone", "iphone"), "a network name is case sensitive")
        XCTAssertEqual(HotspotSSID.plain(phone), typed)
    }

    /// The scan filter matches byte for byte: the name is asked for as it
    /// was typed first, then as a phone spells it.
    func testANameIsScannedForInEachOfItsSpellings() {
        XCTAssertEqual(HotspotSSID.spellings(typed), [typed, phone])
        XCTAssertEqual(HotspotSSID.spellings(phone), [phone, typed])
        XCTAssertEqual(HotspotSSID.spellings("OrnekTelefon"), ["OrnekTelefon"], "nothing to respell")
    }

    func testAskingTheDeviceIsOnUnlessTurnedOff() throws {
        XCTAssertTrue(Config().wakeHotspot)
        XCTAssertTrue(try JSONDecoder().decode(Config.self, from: Data("{}".utf8)).wakeHotspot, "a config.json from before the setting")
        XCTAssertFalse(try JSONDecoder().decode(Config.self, from: Data(#"{"wakeHotspot": false}"#.utf8)).wakeHotspot)
    }

    /// A test run asks no real device, and neither does a macOS the call
    /// was not measured on.
    func testTheLiveWakerAsksNothingWhereItWasNotMeasured() async {
        let here = await SharingHotspotWaker().wake(named: "OrnekTelefon")
        XCTAssertEqual(here, .unavailable, "inside a test run")
        let elsewhere = await SharingHotspotWaker(osMajorVersion: 15).wake(named: "OrnekTelefon")
        XCTAssertEqual(elsewhere, .unavailable)
    }
}

@MainActor
final class HotspotWakeTests: XCTestCase {
    private let typed = "Ada'n\u{131}n iPhone'u"
    private let phone = "Ada\u{2019}n\u{131}n iPhone\u{2019}u"
    var home: TempHome!

    override func setUp() async throws { home = TempHome() }
    override func tearDown() async throws { home.destroy() }

    private func driver(
        _ waker: FakeHotspotWaker,
        keychain: any KeychainStoring = FakeKeychainStore(),
        joiner: RecordingHotspotJoiner,
        notifier: RecordingNotifier = RecordingNotifier(),
        clock: FakeClock = FakeClock(Date(timeIntervalSince1970: 1_800_000_000)),
        configure: @escaping @MainActor (inout Config) -> Void = { _ in }
    ) -> NetworkFailover {
        let name = typed
        return NetworkFailover(
            paths: home.paths,
            keychain: keychain,
            hotspotJoiner: joiner,
            hotspotWaker: waker,
            notifier: notifier,
            wifiInterface: "en0",
            clock: { clock.now }
        ) {
            var config = Config()
            config.hotspotSSID = name
            configure(&config)
            return config
        }
    }

    /// The device answers with the network's own name and password: that
    /// is what is joined, and the keychain is never opened.
    func testAWokenDeviceIsJoinedUnderItsOwnNameWithItsOwnPassword() async {
        let waker = FakeHotspotWaker(.woken(HotspotWake(ssid: phone, password: "from the phone")))
        let joiner = RecordingHotspotJoiner()
        let notifier = RecordingNotifier()
        let n = driver(waker, keychain: UntouchedKeychain(), joiner: joiner, notifier: notifier)

        await n.joinHotspot()

        XCTAssertEqual(waker.asked, [typed], "asked by the configured name")
        XCTAssertEqual(joiner.calls, [.init(ssid: phone, password: "from the phone", interfaceName: "en0")])
        XCTAssertNil(n.passwordReport)
        XCTAssertEqual(notifier.posts.map(\.title), [])
    }

    /// No device answered (another maker's phone, or the iPhone is not in
    /// reach): the saved password and a scan for the configured name.
    func testWithoutAnAnswerTheSavedPasswordIsUsed() async throws {
        let keychain = FakeKeychainStore()
        try keychain.set(service: KeychainStore.service, account: typed, value: "saved")
        let waker = FakeHotspotWaker(.noAnswer)
        let joiner = RecordingHotspotJoiner()
        let n = driver(waker, keychain: keychain, joiner: joiner)

        await n.joinHotspot()

        XCTAssertEqual(waker.asked, [typed])
        XCTAssertEqual(joiner.calls, [.init(ssid: typed, password: "saved", interfaceName: "en0")])
        XCTAssertNil(n.passwordReport)
    }

    /// A hotspot that is asked for needs no saved password, so none saved
    /// is no password problem: the menu stays clean, and the outage says
    /// once that the device did not answer.
    func testNoAnswerAndNoSavedPasswordIsSaidOnceAndIsNoPasswordProblem() async {
        let waker = FakeHotspotWaker(.noAnswer)
        let joiner = RecordingHotspotJoiner()
        let notifier = RecordingNotifier()
        let clock = FakeClock(Date(timeIntervalSince1970: 1_800_000_000))
        let n = driver(waker, joiner: joiner, notifier: notifier, clock: clock)
        let published = Locked<[HotspotPasswordProblem?]>([])
        n.onPasswordReport = { published.value.append($0?.problem) }

        await n.simulate(satisfied: false)
        for _ in 0..<3 {
            clock.advance(30)
            await n.fireTimer().value
        }

        XCTAssertEqual(waker.asked.count, 3, "asked again on every retry")
        XCTAssertEqual(joiner.calls, [])
        XCTAssertNil(n.passwordReport)
        XCTAssertEqual(published.value, [])
        XCTAssertEqual(notifier.posts.map(\.title), ["Hotspot'a bağlanılmadı"])
        XCTAssertEqual(notifier.posts.map(\.body), [NetworkFailover.noAnswerExplanation])
    }

    /// On a Mac that cannot ask, the hotspot still needs its password.
    func testWhereNoDeviceCanBeAskedAMissingPasswordIsStillAProblem() async {
        let waker = FakeHotspotWaker(.unavailable)
        let joiner = RecordingHotspotJoiner()
        let notifier = RecordingNotifier()
        let n = driver(waker, joiner: joiner, notifier: notifier)

        await n.joinHotspot()

        XCTAssertEqual(joiner.calls, [])
        XCTAssertEqual(n.passwordReport, HotspotPasswordReport(ssid: typed, problem: .missing))
        XCTAssertEqual(notifier.posts.map(\.body), [HotspotPasswordProblem.missing.explanation])
    }

    func testWithTheSettingOffNoDeviceIsAsked() async throws {
        let keychain = FakeKeychainStore()
        try keychain.set(service: KeychainStore.service, account: typed, value: "saved")
        let waker = FakeHotspotWaker(.woken(HotspotWake(ssid: phone, password: "from the phone")))
        let joiner = RecordingHotspotJoiner()
        let n = driver(waker, keychain: keychain, joiner: joiner) { $0.wakeHotspot = false }

        await n.joinHotspot()

        XCTAssertEqual(waker.asked, [])
        XCTAssertEqual(joiner.calls, [.init(ssid: typed, password: "saved", interfaceName: "en0")])
    }

    /// The device takes a moment to answer. If Wi-Fi came back meanwhile,
    /// the answer must not move the recovered connection to the hotspot.
    func testAnAnswerThatComesAfterWiFiRecoveredJoinsNothing() async {
        let waker = FakeHotspotWaker(.woken(HotspotWake(ssid: phone, password: "from the phone")), holdingTheAnswer: true)
        let joiner = RecordingHotspotJoiner()
        let clock = FakeClock(Date(timeIntervalSince1970: 1_800_000_000))
        let n = driver(waker, keychain: UntouchedKeychain(), joiner: joiner, clock: clock)

        await n.simulate(satisfied: false)
        clock.advance(30)
        let tick = n.fireTimer()
        await fulfillment(of: [waker.reached], timeout: 5)
        await n.simulate(satisfied: true)
        waker.release()
        await tick.value

        XCTAssertEqual(joiner.calls, [])
        XCTAssertNil(n.passwordReport)
        XCTAssertNil(n.retryTimer, "no retry for an outage that is over")
    }

    /// The same when the session ended while the device was asked.
    func testAnAnswerThatComesAfterTheSessionEndedJoinsNothing() async {
        let waker = FakeHotspotWaker(.woken(HotspotWake(ssid: phone, password: "from the phone")), holdingTheAnswer: true)
        let joiner = RecordingHotspotJoiner()
        let clock = FakeClock(Date(timeIntervalSince1970: 1_800_000_000))
        let n = driver(waker, keychain: UntouchedKeychain(), joiner: joiner, clock: clock)

        await n.simulate(satisfied: false)
        clock.advance(30)
        let tick = n.fireTimer()
        await fulfillment(of: [waker.reached], timeout: 5)
        n.stop()
        waker.release()
        await tick.value

        XCTAssertEqual(joiner.calls, [])
    }
}
