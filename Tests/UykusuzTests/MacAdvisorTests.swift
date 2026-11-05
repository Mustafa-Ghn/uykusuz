import UserNotifications
import XCTest
@testable import Uykusuz

private let simulatorUDID = "6B1F0C9E-2D7A-4C55-9A0B-3E8F5D2C1A47"
private let containerID = "0123456789ab"

/// A Mac with one simulator, one container and a few apps; nothing here is real.
private func sampleMac(now: Date, simulator: Bool = true, container: Bool = true) -> MacSnapshot {
    var mac = MacSnapshot(taken: now)
    if simulator {
        mac.simulators = [.init(udid: simulatorUDID, name: "iPhone 17 Pro", runtime: "iOS 26.0", bootedAt: now.addingTimeInterval(-5 * 3600))]
    }
    if container {
        mac.containers = [.init(id: containerID, name: "ornek-db", image: "postgres:16", status: "Up 3 days", cpu: "0.10%", memory: "120MiB / 7.6GiB")]
    }
    mac.apps = [
        .init(name: "Örnek Tarayıcı", bundleID: "com.example.browser", memory: 3_000_000_000, cpu: 4, lastActive: now.addingTimeInterval(-120), canQuit: true),
        .init(name: "Terminal", bundleID: "com.apple.Terminal", memory: 200_000_000, cpu: 1, lastActive: nil, canQuit: true),
        .init(name: "Claude", bundleID: "com.anthropic.claudefordesktop", memory: 900_000_000, cpu: 2, lastActive: nil, canQuit: true),
        .init(name: MacSnapshot.simulatorsGroup, bundleID: nil, memory: 2_500_000_000, cpu: 9, lastActive: nil, canQuit: false),
    ]
    mac.runningBundleIDs = ["com.example.browser", "com.apple.Terminal", "com.anthropic.claudefordesktop"]
    mac.memoryTotal = 24 * 1_073_741_824
    mac.memoryPressure = 2
    mac.swapUsed = 20 * 1_073_741_824
    mac.swapTotal = 22 * 1_073_741_824
    mac.batteryPercent = 41
    mac.uptime = 3 * 86400
    mac.watchingSince = now.addingTimeInterval(-6 * 3600)
    return mac
}

private func advice(
    tell: Bool = true,
    _ message: String = "",
    approve: Bool = false,
    decline: Bool = false,
    offer: Advice.Proposal = .none,
    notes: [String] = []
) -> Advice {
    Advice(tell: tell, message: message, approveOpenOffer: approve, declineOpenOffer: decline, offer: offer, notes: notes)
}

final class FakeAdviceWriter: AdviceWriting, @unchecked Sendable {
    private let lock = NSLock()
    private var queue: [Result<Advice, Error>] = []
    private var _prompts: [String] = []
    var prompts: [String] { lock.withLock { _prompts } }

    func enqueue(_ advice: Advice) { lock.withLock { queue.append(.success(advice)) } }
    func enqueue(error: Error) { lock.withLock { queue.append(.failure(error)) } }

    func advise(_ prompt: String) async throws -> Advice {
        let next = lock.withLock { () -> Result<Advice, Error>? in
            _prompts.append(prompt)
            return queue.isEmpty ? nil : queue.removeFirst()
        }
        guard let next else { return advice(tell: false) }
        return try next.get()
    }
}

final class FakeOfferRunner: OfferRunning, @unchecked Sendable {
    private let lock = NSLock()
    private var _runs: [Notebook.Offer] = []
    var runs: [Notebook.Offer] { lock.withLock { _runs } }
    var succeeds = true

    func run(_ offer: Notebook.Offer) async -> Bool {
        lock.withLock { _runs.append(offer) }
        return succeeds
    }
}

@MainActor
final class MacAdvisorTests: XCTestCase {
    var now = Date(timeIntervalSince1970: 1_800_000_000)
    var away = false
    var config = Config()
    var mac: MacSnapshot!
    var saved: [Notebook] = []
    let writer = FakeAdviceWriter()
    let runner = FakeOfferRunner()
    let notifier = RecordingAdviceNotifier()

    override func setUp() async throws {
        mac = sampleMac(now: now)
    }

    private func make(notebook: Notebook = Notebook(), key: AnthropicKeyRead = .key("sk-ant-test")) -> MacAdvisor {
        MacAdvisor(
            config: { [unowned self] in config },
            notebook: notebook,
            save: { [unowned self] in saved.append($0) },
            keyStore: InMemoryAnthropicKeyStore(key),
            writer: { [writer] _, _ in writer },
            snapshot: { [unowned self] _, _ in mac },
            runner: runner,
            notifier: notifier,
            clock: { [unowned self] in now },
            isAway: { [unowned self] in away },
            ownBundleID: "com.mustafaghn.uykusuz"
        )
    }

    private func later(_ seconds: TimeInterval) {
        now = now.addingTimeInterval(seconds)
        mac = sampleMac(now: now)
    }

    private let shutdown = Advice.Proposal(kind: "shutdown_simulator", target: simulatorUDID)

    // MARK: When it looks

    func testItLooksOnlyWhileTheUserIsThereAndNotTooOften() async {
        let a = make()
        XCTAssertFalse(a.isDue(now: now), "not right after launch")
        later(MacAdvisor.firstLookAfter)
        XCTAssertTrue(a.isDue(now: now))
        away = true
        XCTAssertFalse(a.isDue(now: now), "not while the user is away")
        away = false
        config.macAdvisor = false
        XCTAssertFalse(a.isDue(now: now), "not when it is off")
        config.macAdvisor = true
        await a.tick()
        XCTAssertEqual(writer.prompts.count, 1)
        later(MacAdvisor.lookEvery - 60)
        await a.tick()
        XCTAssertEqual(writer.prompts.count, 1, "not again before two hours")
        later(60)
        await a.tick()
        XCTAssertEqual(writer.prompts.count, 2)
    }

    func testWithoutAKeyNothingIsSent() async {
        let a = make(key: .none)
        await a.lookNow()
        XCTAssertTrue(writer.prompts.isEmpty)
        XCTAssertNotNil(a.statusLine)
    }

    func testAFailedLookCountsSoABrokenKeyDoesNotAskEveryFiveMinutes() async {
        writer.enqueue(error: SummaryError.http(401, ""))
        let a = make()
        later(MacAdvisor.firstLookAfter)
        await a.tick()
        XCTAssertEqual(a.notebook.lastLook, now)
        XCTAssertTrue(a.statusLine?.contains("401") ?? false)
        later(MacAdvisor.tickInterval)
        await a.tick()
        XCTAssertEqual(writer.prompts.count, 1)
    }

    // MARK: What it writes

    func testAnOfferIsWrittenAndNotifiedWithItsButton() async {
        writer.enqueue(advice("iPhone 17 Pro simülatörü 5 saattir açık ve 2,5 GB bellek tutuyor; kapatayım mı?", offer: shutdown, notes: ["Kullanıcı simülatörleri gün içinde kullanıyor."]))
        let a = make()
        later(MacAdvisor.firstLookAfter)
        await a.tick()
        let entry = try? XCTUnwrap(a.notebook.entries.last)
        XCTAssertEqual(entry?.author, .uykusuz)
        XCTAssertEqual(entry?.offer, Notebook.Offer(kind: .shutdownSimulator, target: simulatorUDID, label: "iPhone 17 Pro"))
        XCTAssertEqual(a.notebook.notes, ["Kullanıcı simülatörleri gün içinde kullanıyor."])
        XCTAssertEqual(notifier.posts.count, 1)
        XCTAssertEqual(notifier.posts.first?.offer, .shutdownSimulator)
        XCTAssertEqual(notifier.posts.first?.entry, entry?.id)
        XCTAssertEqual(saved.last, a.notebook, "saved")
    }

    func testNotificationsAreAtLeastFourHoursApart() async {
        let a = make()
        writer.enqueue(advice("Birinci."))
        later(MacAdvisor.firstLookAfter)
        await a.tick()
        writer.enqueue(advice("İkinci."))
        later(MacAdvisor.lookEvery)
        await a.tick()
        XCTAssertEqual(a.notebook.entries.map(\.text), ["Birinci.", "İkinci."], "both are in the notebook")
        XCTAssertEqual(notifier.posts.map(\.body), ["Birinci."], "only the first is notified")
        writer.enqueue(advice("Üçüncü."))
        later(MacAdvisor.notifyGap - MacAdvisor.lookEvery)
        await a.tick()
        XCTAssertEqual(notifier.posts.map(\.body), ["Birinci.", "Üçüncü."])
    }

    func testNothingToTellWritesNothing() async {
        writer.enqueue(advice(tell: false))
        let a = make()
        await a.lookNow()
        XCTAssertTrue(a.notebook.entries.isEmpty)
        XCTAssertTrue(notifier.posts.isEmpty)
        XCTAssertNotNil(a.notebook.lastLook)
        XCTAssertTrue(a.statusLine?.contains("söylenecek bir şey yok") ?? false)
    }

    func testLookingNowDoesNotNotify() async {
        writer.enqueue(advice("Bir şey var."))
        let a = make()
        await a.lookNow()
        XCTAssertEqual(a.notebook.entries.count, 1)
        XCTAssertTrue(notifier.posts.isEmpty, "the user is reading the notebook")
    }

    // MARK: Offers are checked

    func testOnlyWhatTheSnapshotHoldsCanBeOffered() {
        let a = make()
        XCTAssertNil(a.validated(.init(kind: "shutdown_simulator", target: "11111111-2222-3333-4444-555555555555"), in: mac), "no such simulator")
        XCTAssertNil(a.validated(.init(kind: "erase_simulator", target: simulatorUDID), in: mac), "not a kind Uykusuz does")
        XCTAssertNil(a.validated(.init(kind: "quit_app", target: "com.apple.Terminal"), in: mac), "Claude Code runs there")
        XCTAssertNil(a.validated(.init(kind: "quit_app", target: "com.anthropic.claudefordesktop"), in: mac), "an agent app")
        XCTAssertNil(a.validated(.init(kind: "quit_app", target: "com.example.missing"), in: mac))
        XCTAssertEqual(a.validated(.init(kind: "quit_app", target: "com.example.browser"), in: mac)?.label, "Örnek Tarayıcı")
        XCTAssertEqual(a.validated(.init(kind: "stop_container", target: "ornek-db"), in: mac)?.target, containerID, "by name, kept by id")
        XCTAssertEqual(a.validated(.init(kind: "stop_container", target: containerID), in: mac)?.label, "ornek-db")
        XCTAssertNil(a.validated(.init(kind: "stop_container", target: "0"), in: mac), "a short prefix could be any container")
        XCTAssertEqual(a.validated(.init(kind: "shutdown_simulator", target: simulatorUDID.lowercased()), in: mac)?.target, simulatorUDID)
    }

    func testAnOfferForSomethingNotThereIsDroppedButTheMessageStays() async {
        writer.enqueue(advice("Terminal'den çıkın.", offer: .init(kind: "quit_app", target: "com.apple.Terminal")))
        let a = make()
        await a.lookNow()
        XCTAssertEqual(a.notebook.entries.last?.text, "Terminal'den çıkın.")
        XCTAssertNil(a.notebook.entries.last?.offer)
    }

    func testADeclinedOfferIsNotMadeAgainForADay() async {
        let a = make()
        writer.enqueue(advice("Kapatayım mı?", offer: shutdown))
        await a.lookNow()
        let id = try? XCTUnwrap(a.notebook.openOffer?.entry.id)
        a.decline(id!)
        XCTAssertEqual(a.notebook.entries.last?.text, "Gerek yok.")
        XCTAssertEqual(a.notebook.entries.first?.offer?.state, .declined)
        writer.enqueue(advice("Kapatayım mı?", offer: shutdown))
        later(MacAdvisor.lookEvery)
        await a.lookNow()
        XCTAssertEqual(a.notebook.entries.count, 2, "not said again")
        writer.enqueue(advice("Kapatayım mı?", offer: shutdown))
        later(MacAdvisor.declinedFor)
        await a.lookNow()
        XCTAssertEqual(a.notebook.entries.count, 3, "a day later it may be")
    }

    func testAnOfferWhoseSimulatorWentAwayExpires() async {
        let a = make()
        writer.enqueue(advice("Kapatayım mı?", offer: shutdown))
        await a.lookNow()
        mac = sampleMac(now: now, simulator: false)
        await a.lookNow()
        XCTAssertEqual(a.notebook.entries.first?.offer?.state, .expired)
        XCTAssertNil(a.notebook.openOffer)
    }

    // MARK: Saying yes

    func testTheButtonDoesItOnce() async {
        let a = make()
        writer.enqueue(advice("Kapatayım mı?", offer: shutdown))
        await a.lookNow()
        let id = a.notebook.openOffer?.entry.id
        await a.accept(id)
        await a.accept(id)
        XCTAssertEqual(runner.runs.map(\.target), [simulatorUDID], "once")
        XCTAssertEqual(a.notebook.entries.first?.offer?.state, .done)
        XCTAssertEqual(a.notebook.entries.last?.text, "iPhone 17 Pro simülatörünü kapattım.")
    }

    func testAFailureIsWrittenDown() async {
        runner.succeeds = false
        let a = make()
        writer.enqueue(advice("Durdurayım mı?", offer: .init(kind: "stop_container", target: containerID)))
        await a.lookNow()
        await a.accept(a.notebook.openOffer?.entry.id)
        XCTAssertEqual(a.notebook.entries.first?.offer?.state, .failed)
        XCTAssertEqual(a.notebook.entries.last?.text, "ornek-db kapsayıcısı durdurulamadı.")
    }

    func testAReplyThatSaysYesRunsTheOpenOfferAndAnswersInTheNotification() async {
        let a = make()
        writer.enqueue(advice("Kapatayım mı?", offer: shutdown))
        await a.lookNow()
        writer.enqueue(advice("Tamam, kapatıyorum.", approve: true, offer: .init(kind: "quit_app", target: "com.example.browser")))
        await a.reply("kapat", fromNotification: true)
        XCTAssertEqual(runner.runs.map(\.kind), [.shutdownSimulator], "only the offer that was open, never a new one with it")
        XCTAssertEqual(a.notebook.entries.map(\.author), [.uykusuz, .user, .uykusuz, .uykusuz])
        XCTAssertEqual(a.notebook.entries[1].text, "kapat")
        XCTAssertNil(a.notebook.openOffer)
        XCTAssertEqual(notifier.posts.last?.body, "iPhone 17 Pro simülatörünü kapattım.")
        XCTAssertTrue(writer.prompts.last?.hasPrefix("Görev: kullanıcının defterdeki son yazdığına yanıt ver.") ?? false)
        XCTAssertTrue(writer.prompts.last?.contains("Kullanıcı: kapat") ?? false)
    }

    func testAReplyThatSaysNoDeclinesAndANewOfferIsChecked() async {
        let a = make()
        writer.enqueue(advice("Kapatayım mı?", offer: shutdown))
        await a.lookNow()
        writer.enqueue(advice("Peki, açık kalsın. Tarayıcıdan çıkayım mı?", decline: true, offer: .init(kind: "quit_app", target: "com.example.browser"), notes: ["iPhone 17 Pro simülatörü açık kalsın."]))
        await a.reply("lazım, kapatma")
        XCTAssertTrue(runner.runs.isEmpty)
        XCTAssertEqual(a.notebook.entries.first?.offer?.state, .declined)
        XCTAssertEqual(a.notebook.openOffer?.offer.kind, .quitApp)
        XCTAssertEqual(a.notebook.notes, ["iPhone 17 Pro simülatörü açık kalsın."])
        XCTAssertTrue(notifier.posts.isEmpty, "written in the window: no notification")
    }

    func testAYesToAnOfferThatWentAwaySaysSo() async {
        let a = make()
        writer.enqueue(advice("Kapatayım mı?", offer: shutdown))
        await a.lookNow()
        mac = sampleMac(now: now, simulator: false)
        writer.enqueue(advice("Kapatıyorum.", approve: true))
        await a.reply("kapat", fromNotification: true)
        XCTAssertTrue(runner.runs.isEmpty)
        XCTAssertEqual(a.notebook.entries.map(\.text), ["Kapatayım mı?", "kapat", MacAdvisor.gone], "not Claude's \"Kapatıyorum.\"")
        XCTAssertEqual(notifier.posts.last?.body, MacAdvisor.gone)
    }

    func testWhileTheNotebookIsOpenNothingIsNotifiedOrNew() async {
        let a = make()
        a.isReading = { true }
        writer.enqueue(advice("Bir şey var."))
        later(MacAdvisor.firstLookAfter)
        await a.tick()
        XCTAssertEqual(a.notebook.entries.count, 1)
        XCTAssertTrue(notifier.posts.isEmpty)
        XCTAssertEqual(a.notebook.unread, 0)
    }

    func testAnAnswerFromANotificationForAGoneOfferSaysSo() async {
        let a = make()
        await a.handle(.accept(UUID())) {}
        XCTAssertTrue(runner.runs.isEmpty)
        XCTAssertEqual(notifier.posts.last?.body, MacAdvisor.gone)
    }

    // MARK: The request

    func testThePromptCarriesTheNotebookAndTheMac() async {
        var notebook = Notebook()
        notebook.notes = ["ornek-db açık kalsın."]
        notebook.append(.init(date: now, author: .uykusuz, text: "Kapatayım mı?", offer: .init(kind: .shutdownSimulator, target: simulatorUDID, label: "iPhone 17 Pro")))
        let prompt = MacAdvisor.prompt(.look, notebook: notebook, snapshot: mac, now: now)
        XCTAssertTrue(prompt.hasPrefix("Görev: bak."))
        XCTAssertTrue(prompt.contains("Açık öneri: iPhone 17 Pro simülatörünü kapat (shutdown_simulator, hedef \(simulatorUDID))."))
        XCTAssertTrue(prompt.contains("- ornek-db açık kalsın."))
        XCTAssertTrue(prompt.contains("Uykusuz: Kapatayım mı? [öneri: iPhone 17 Pro simülatörünü kapat; yanıt bekliyor]"))
        XCTAssertTrue(prompt.contains("- iPhone 17 Pro (iOS 26.0), udid \(simulatorUDID), 5 saat önce açıldı"))
        XCTAssertTrue(prompt.contains("- ornek-db (postgres:16), id \(containerID), Up 3 days, işlemci 0.10%, bellek 120MiB / 7.6GiB"))
        XCTAssertTrue(prompt.contains("- Örnek Tarayıcı (com.example.browser): 2,8 GB bellek, işlemci %4, en son 2 dakika önce öne geldi"))
        XCTAssertTrue(prompt.contains("takas 20,0 GB / 22,0 GB dolu"))
        XCTAssertTrue(prompt.contains("Pil: %41, pilde"))
    }

    func testTheRequestAsksForTheSchemaAndFallsBackOnlyWhereItCan() throws {
        let opus = try AnthropicAdviceClient(key: "k", model: "claude-opus-5-5").request("p", fallbacks: true)
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(opus.httpBody)) as? [String: Any])
        let output = try XCTUnwrap(body["output_config"] as? [String: Any])
        XCTAssertEqual(output["effort"] as? String, "low")
        let format = try XCTUnwrap(output["format"] as? [String: Any])
        XCTAssertEqual(format["type"] as? String, "json_schema")
        let schema = try XCTUnwrap(format["schema"] as? [String: Any])
        XCTAssertEqual(schema["additionalProperties"] as? Bool, false)
        let offer = try XCTUnwrap((schema["properties"] as? [String: Any])?["offer"] as? [String: Any])
        XCTAssertEqual(offer["additionalProperties"] as? Bool, false, "every object closed")
        XCTAssertEqual(body["fallbacks"] as? String, "default")
        XCTAssertEqual(opus.value(forHTTPHeaderField: "anthropic-beta"), AnthropicAdviceClient.fallbackBeta)
        XCTAssertTrue(AnthropicAdviceClient.fallsBack("claude-sonnet-5-5"))
        XCTAssertFalse(AnthropicAdviceClient.fallsBack("claude-haiku-5-5"), "Haiku has no fallback")
        let plain = try AnthropicAdviceClient(key: "k", model: "claude-haiku-5-5").request("p", fallbacks: false)
        let plainBody = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(plain.httpBody)) as? [String: Any])
        XCTAssertNil(plainBody["fallbacks"])
        XCTAssertNil(plain.value(forHTTPHeaderField: "anthropic-beta"))
    }

    func testTheAnswerIsReadAfterAFallback() throws {
        let json = #"{"tell":true,"message":"Tamam.","approve_open_offer":false,"decline_open_offer":false,"offer":{"kind":"none","target":""},"notes":[]}"#
        let reply: [String: Any] = [
            "stop_reason": "end_turn",
            "content": [
                ["type": "text", "text": "{\"tell\":"],
                ["type": "fallback"],
                ["type": "thinking", "thinking": ""],
                ["type": "text", "text": json],
            ],
        ]
        let advice = try AnthropicAdviceClient.parse(data: JSONSerialization.data(withJSONObject: reply), status: 200)
        XCTAssertEqual(advice.message, "Tamam.")
        let refused = try JSONSerialization.data(withJSONObject: ["stop_reason": "refusal", "content": []] as [String: Any])
        XCTAssertThrowsError(try AnthropicAdviceClient.parse(data: refused, status: 200)) { XCTAssertEqual($0 as? SummaryError, .refusal) }
        let error = try JSONSerialization.data(withJSONObject: ["error": ["message": "bad"]])
        XCTAssertThrowsError(try AnthropicAdviceClient.parse(data: error, status: 400)) { XCTAssertEqual($0 as? SummaryError, .http(400, "bad")) }
    }

    func testAnAccountWithoutTheFallbackIsAskedAgainWithout() async throws {
        let json = #"{"tell":false,"message":"","approve_open_offer":false,"decline_open_offer":false,"offer":{"kind":"none","target":""},"notes":[]}"#
        let ok = try JSONSerialization.data(withJSONObject: ["stop_reason": "end_turn", "content": [["type": "text", "text": json]]] as [String: Any])
        let refusedParam = try JSONSerialization.data(withJSONObject: ["error": ["message": "fallbacks: not available"]])
        let calls = Calls()
        var client = AnthropicAdviceClient(key: "k", model: "claude-opus-5-5")
        client.send = { request in
            let withFallback = request.value(forHTTPHeaderField: "anthropic-beta") != nil
            calls.add(withFallback)
            let response = HTTPURLResponse(url: request.url!, statusCode: withFallback ? 400 : 200, httpVersion: nil, headerFields: nil)!
            return (withFallback ? refusedParam : ok, response)
        }
        let advice = try await client.advise("p")
        XCTAssertFalse(advice.tell)
        XCTAssertEqual(calls.all, [true, false])
    }

    final class Calls: @unchecked Sendable {
        private let lock = NSLock()
        private var calls: [Bool] = []
        var all: [Bool] { lock.withLock { calls } }
        func add(_ value: Bool) { lock.withLock { calls.append(value) } }
    }
}

final class MacSnapshotTests: XCTestCase {
    func testBootedSimulatorsAreRead() {
        let json = """
        {"devices":{
          "com.apple.CoreSimulator.SimRuntime.iOS-26-0":[
            {"udid":"\(simulatorUDID)","name":"iPhone 17 Pro","state":"Booted","lastBootedAt":"2026-11-05T10:00:00Z"},
            {"udid":"6B1F0C9E-2D7A-4C55-9A0B-3E8F5D2C1A48","name":"iPad","state":"Shutdown"},
            {"udid":"--help","name":"Bozuk","state":"Booted"}
          ]}}
        """
        let simulators = MacSnapshot.parseSimulators(Data(json.utf8))
        XCTAssertEqual(simulators.map(\.name), ["iPhone 17 Pro"], "booted only, and only a real UDID")
        XCTAssertEqual(simulators.first?.runtime, "iOS 26.0")
        XCTAssertNotNil(simulators.first?.bootedAt)
        XCTAssertTrue(MacSnapshot.parseSimulators(Data("not json".utf8)).isEmpty)
    }

    func testContainersAreJoinedWithTheirFigures() {
        let ps = "\(containerID)\tornek-db\tpostgres:16\tUp 3 days\nNOTANID\tx\ty\tUp\n"
        let stats = "\(containerID)\t0.10%\t120MiB / 7.6GiB\n"
        let containers = MacSnapshot.parseContainers(ps: ps, stats: stats)
        XCTAssertEqual(containers, [.init(id: containerID, name: "ornek-db", image: "postgres:16", status: "Up 3 days", cpu: "0.10%", memory: "120MiB / 7.6GiB")])
        XCTAssertNil(MacSnapshot.parseContainers(ps: ps, stats: "").first?.cpu)
    }

    func testProcessesAreCountedUnderTheirApp() {
        XCTAssertEqual(MacSnapshot.group(path: "/Applications/Örnek.app/Contents/Frameworks/Helper.app/Contents/MacOS/Helper", name: "Helper").name, "Örnek")
        XCTAssertEqual(MacSnapshot.group(path: "/Users/me/Library/Developer/CoreSimulator/Devices/X/data/App.app/App", name: "App").name, MacSnapshot.simulatorsGroup)
        XCTAssertEqual(MacSnapshot.group(path: "/usr/local/bin/node", name: "node").name, "node")
        XCTAssertEqual(MacSnapshot.group(path: nil, name: "kısa").name, "kısa")
        let readings: [pid_t: MacSnapshot.ProcessReading] = [
            1: .init(path: "/Applications/Örnek.app/Contents/MacOS/Örnek", name: "Örnek", memory: 100, cpuTime: 10),
            2: .init(path: "/Applications/Örnek.app/Contents/Frameworks/H.app/Contents/MacOS/H", name: "H", memory: 50, cpuTime: 4),
            3: .init(path: "/Applications/Uykusuz.app/Contents/MacOS/Uykusuz", name: "Uykusuz", memory: 999, cpuTime: 0),
        ]
        let running = [
            MacSnapshot.RunningApp(path: "/Applications/Örnek.app", bundleID: "com.example.ornek", canQuit: true),
            MacSnapshot.RunningApp(path: "/Applications/Uykusuz.app", bundleID: "com.mustafaghn.uykusuz", canQuit: true, menuBar: true),
        ]
        let apps = MacSnapshot.apps(readings, before: [1: 9, 2: 3], seconds: 2, running: running, lastActive: [:], ownBundleID: "com.mustafaghn.uykusuz")
        XCTAssertEqual(apps.count, 1, "Uykusuz itself is left out")
        XCTAssertEqual(apps.first?.memory, 150)
        XCTAssertEqual(apps.first?.cpu ?? 0, 100, accuracy: 0.001, "two CPU seconds over two seconds")
        XCTAssertEqual(apps.first?.bundleID, "com.example.ornek")
        XCTAssertEqual(apps.first?.canQuit, true)
        var many = readings
        for i in 10..<30 { many[pid_t(i)] = .init(path: "/usr/bin/agir\(i)", name: "agir\(i)", memory: 10_000, cpuTime: 0) }
        many[99] = .init(path: "/Applications/Docker.app/Contents/MacOS/com.docker.backend", name: "com.docker.backend", memory: 1, cpuTime: 0)
        let docker = running + [MacSnapshot.RunningApp(path: "/Applications/Docker.app", bundleID: MacSnapshot.dockerBundleID, canQuit: true, menuBar: true)]
        let listed = MacSnapshot.apps(many, before: [:], seconds: 2, running: docker, lastActive: [:], ownBundleID: "com.mustafaghn.uykusuz")
        XCTAssertEqual(listed.count, MacSnapshot.appsByMemory + 1)
        XCTAssertEqual(listed.last?.bundleID, MacSnapshot.dockerBundleID, "Docker Desktop is listed however little it holds")
    }

    func testFiguresReadTurkish() {
        XCTAssertEqual(MacSnapshot.bytes(3_000_000_000), "2,8 GB")
        XCTAssertEqual(MacSnapshot.bytes(120 * 1_048_576), "120 MB")
        XCTAssertEqual(MacSnapshot.span(30), "1 dakika")
        XCTAssertEqual(MacSnapshot.span(3 * 3600), "3 saat")
        XCTAssertEqual(MacSnapshot.span(3 * 86400), "3 gün")
    }
}

final class NotebookTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    func testOneOfferIsOpenAtATime() {
        var notebook = Notebook()
        let offer = Notebook.Offer(kind: .stopContainer, target: containerID, label: "ornek-db")
        notebook.append(.init(date: now, author: .uykusuz, text: "Bir.", offer: offer))
        notebook.append(.init(date: now, author: .uykusuz, text: "İki.", offer: offer))
        XCTAssertEqual(notebook.entries.first?.offer?.state, .expired)
        XCTAssertEqual(notebook.openOffer?.entry.text, "İki.")
    }

    func testOldEntriesGoAndNotesStayShort() {
        var notebook = Notebook()
        for i in 0..<(Notebook.maxEntries + 5) {
            notebook.append(.init(date: now, author: .user, text: "\(i)"))
        }
        XCTAssertEqual(notebook.entries.count, Notebook.maxEntries)
        XCTAssertEqual(notebook.entries.first?.text, "5")
        notebook.replaceNotes(Array(repeating: " not ", count: 20) + [""] + [String(repeating: "x", count: 500)])
        XCTAssertEqual(notebook.notes.count, Notebook.maxNotes)
        XCTAssertEqual(notebook.notes.first, "not")
    }

    func testUnreadCountsUykusuzSinceTheLastLook() {
        var notebook = Notebook()
        notebook.append(.init(date: now, author: .uykusuz, text: "a"))
        notebook.append(.init(date: now, author: .user, text: "b"))
        XCTAssertEqual(notebook.unread, 1)
        notebook.lastRead = now
        XCTAssertEqual(notebook.unread, 0)
    }

    func testItIsSavedOwnerOnly() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("notebook-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = Store(paths: Paths(root: root))
        XCTAssertEqual(store.loadNotebook(), Notebook(), "none yet: an empty one")
        var notebook = Notebook()
        notebook.notes = ["bir not"]
        notebook.append(.init(date: now, author: .uykusuz, text: "Merhaba.", offer: .init(kind: .quitApp, target: "com.example.browser", label: "Örnek")))
        try store.saveNotebook(notebook)
        XCTAssertEqual(store.loadNotebook(), notebook)
        let mode = try FileManager.default.attributesOfItem(atPath: store.paths.notebookFile.path)[.posixPermissions] as? Int
        XCTAssertEqual(mode, 0o600)
        try Data("bozuk".utf8).write(to: store.paths.notebookFile)
        XCTAssertEqual(store.loadNotebook(), Notebook(), "an unreadable one starts over")
    }

    func testTheOfferSaysWhatItDoes() {
        let offer = Notebook.Offer(kind: .shutdownSimulator, target: simulatorUDID, label: "iPhone 17 Pro")
        XCTAssertEqual(offer.actionTitle, "iPhone 17 Pro simülatörünü kapat")
        XCTAssertEqual(offer.outcome(succeeded: true), "iPhone 17 Pro simülatörünü kapattım.")
    }
}

final class AdviceNotificationsTests: XCTestCase {
    func testAnswersAreReadFromTheNotebooksNotificationsOnly() {
        let id = UUID()
        XCTAssertEqual(AdviceNotifications.response(action: AdviceNotifications.replyAction, entry: id.uuidString, text: " kapat "), .reply(id, "kapat"))
        XCTAssertNil(AdviceNotifications.response(action: AdviceNotifications.replyAction, entry: id.uuidString, text: "  "))
        XCTAssertEqual(AdviceNotifications.response(action: AdviceNotifications.acceptAction, entry: id.uuidString, text: nil), .accept(id))
        XCTAssertEqual(AdviceNotifications.response(action: UNNotificationDefaultActionIdentifier, entry: id.uuidString, text: nil), .open(id))
        XCTAssertNil(AdviceNotifications.response(action: UNNotificationDefaultActionIdentifier, entry: nil, text: nil), "another notification")
    }

    func testEachOfferHasItsButtonAndAReplyField() {
        let categories = AdviceNotifications.categories()
        XCTAssertEqual(categories.count, Notebook.Offer.Kind.allCases.count + 1)
        let plain = categories.first { $0.identifier == AdviceNotifications.category(nil) }
        XCTAssertEqual(plain?.actions.map(\.identifier), [AdviceNotifications.replyAction])
        let shutdown = categories.first { $0.identifier == AdviceNotifications.category(.shutdownSimulator) }
        XCTAssertEqual(shutdown?.actions.map(\.title), ["Simülatörü kapat", "Yanıtla"])
        XCTAssertTrue(shutdown?.actions.last is UNTextInputNotificationAction)
    }

    func testTheMenuOffersTheNotebook() {
        XCTAssertEqual(StatusMenu.notebookTitle(unread: 0), "Defter")
        XCTAssertEqual(StatusMenu.notebookTitle(unread: 2), "Defter (2 yeni)")
        let items = StatusMenu.items(sessionActive: false, sleepHeld: false, notebookTitle: "Defter", machine: nil, actions: nil, throttledBrowsers: [], error: nil)
        XCTAssertTrue(items.contains(StatusMenu.Item(title: "Defter", kind: .showNotebook)))
        let none = StatusMenu.items(sessionActive: false, sleepHeld: false, machine: nil, actions: nil, throttledBrowsers: [], error: nil)
        XCTAssertFalse(none.contains { $0.kind == .showNotebook })
    }

    func testTheSettingIsOnByDefaultAndKept() throws {
        XCTAssertTrue(Config().macAdvisor)
        XCTAssertTrue(try JSONDecoder().decode(Config.self, from: Data("{}".utf8)).macAdvisor)
        var off = Config()
        off.macAdvisor = false
        XCTAssertFalse(try JSONDecoder().decode(Config.self, from: JSONEncoder().encode(off)).macAdvisor)
    }
}
