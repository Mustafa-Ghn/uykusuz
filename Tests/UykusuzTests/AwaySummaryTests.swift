import XCTest
@testable import Uykusuz

// Fork addition: the "while you were away" summary.

final class ClaudeDigestTests: XCTestCase {
    private var projects: URL!
    private let from = Date(timeIntervalSince1970: 2_000_000_000)
    private var to: Date { from.addingTimeInterval(40 * 60) }

    override func setUpWithError() throws {
        projects = FileManager.default.temporaryDirectory.appendingPathComponent("uykusuz-digest-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: projects, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: projects)
    }

    private func stamp(_ offset: TimeInterval) -> String {
        Date.ISO8601FormatStyle(includingFractionalSeconds: true).format(from.addingTimeInterval(offset))
    }

    private func line(_ object: [String: Any]) -> String {
        String(decoding: try! JSONSerialization.data(withJSONObject: object), as: UTF8.self)
    }

    @discardableResult
    private func transcript(_ id: String, in folder: String = "-Users-me-Documents-GitHub-insomnia-tr", _ lines: [[String: Any]]) throws -> URL {
        let dir = projects.appendingPathComponent(folder, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent("\(id).jsonl")
        try Data((lines.map(line).joined(separator: "\n") + "\n").utf8).write(to: file)
        // Written to while the lid was closed.
        try FileManager.default.setAttributes([.modificationDate: from.addingTimeInterval(30 * 60)], ofItemAtPath: file.path)
        return file
    }

    private func assistant(_ offset: TimeInterval, _ content: [[String: Any]], sidechain: Bool = false) -> [String: Any] {
        ["type": "assistant", "timestamp": stamp(offset), "cwd": "/Users/me/Documents/GitHub/insomnia-tr",
         "isSidechain": sidechain, "message": ["role": "assistant", "content": content]]
    }

    func testOneSessionIsReadHoweverManyOthersAreNewer() throws {
        try transcript("old", in: "-Users-me-other", session)
        for index in 0...ClaudeDigest.maxSessions {
            try transcript("new\(index)", [assistant(1000 + Double(index), [["type": "text", "text": "newer"]])])
        }
        XCTAssertNil(ClaudeDigest.build(from: from, to: to, projects: projects)?.sessions.first { $0.id == "old" }, "kept out of the newest few")
        let found = try XCTUnwrap(ClaudeDigest.session("old", from: from, to: to, projects: projects) { XCTAssertEqual($0, "old"); return .waiting })
        XCTAssertEqual(found.title, "Uykusuz özeti")
        XCTAssertEqual(found.status, .waiting)
        XCTAssertEqual(found.lastTexts.last, "Testlerin hepsi geçti ve değişikliği commit'ledim.")
        XCTAssertNil(ClaudeDigest.session("missing", from: from, to: to, projects: projects))
    }

    func testASessionIsFoundByItsMarkersName() throws {
        try transcript("a.b", session)
        XCTAssertEqual(ClaudeDigest.session("a_b", from: from, to: to, projects: projects)?.id, "a.b")
    }

    func testASessionWithNothingInTheSpanStillHasItsName() throws {
        try transcript("quiet", [
            ["type": "custom-title", "customTitle": "Sessiz oturum", "sessionId": "quiet"],
            assistant(-600, [["type": "text", "text": "before the span"]]),
        ])
        XCTAssertNil(ClaudeDigest.build(from: from, to: to, projects: projects), "nothing done in the span")
        let found = try XCTUnwrap(ClaudeDigest.session("quiet", from: from, to: to, projects: projects))
        XCTAssertEqual(found.title, "Sessiz oturum")
        XCTAssertEqual(found.lastTexts, [])
    }

    func testTheNameClaudeGaveIsUsedWhenNoOneNamedTheSession() throws {
        let work = assistant(100, [["type": "text", "text": "tamam"]])
        try transcript("generated", [["type": "ai-title", "aiTitle": "Üretilen ad", "sessionId": "generated"], work])
        try transcript("both", [
            ["type": "custom-title", "customTitle": "Verilen ad", "sessionId": "both"],
            ["type": "ai-title", "aiTitle": "Üretilen ad", "sessionId": "both"],
            work,
        ])
        try transcript("neither", [work])
        XCTAssertEqual(ClaudeDigest.session("generated", from: from, to: to, projects: projects)?.title, "Üretilen ad")
        XCTAssertEqual(ClaudeDigest.session("both", from: from, to: to, projects: projects)?.title, "Verilen ad")
        XCTAssertEqual(ClaudeDigest.session("neither", from: from, to: to, projects: projects)?.title, "insomnia-tr", "the folder it ran in")
    }

    private var session: [[String: Any]] {
        [
            ["type": "custom-title", "customTitle": "Uykusuz özeti", "sessionId": "s1"],
            assistant(-600, [["type": "text", "text": "before the lid closed"]]),
            ["type": "user", "timestamp": stamp(60), "message": ["role": "user", "content": "devam et"]],
            assistant(120, [
                ["type": "thinking", "thinking": "hidden"],
                ["type": "tool_use", "name": "Edit", "input": ["file_path": "/Users/me/p/Sources/AgentAutoSession.swift", "old_string": "SECRET-CODE"]],
                ["type": "tool_use", "name": "Edit", "input": ["file_path": "/Users/me/p/Sources/AgentAutoSession.swift"]],
                ["type": "tool_use", "name": "Bash", "input": ["command": "export TOKEN=SECRET-TOKEN; swift test", "description": "Run the full suite"]],
                ["type": "tool_use", "name": "Read", "input": ["file_path": "/Users/me/p/README.md"]],
            ]),
            ["type": "user", "timestamp": stamp(130), "message": ["role": "user", "content": [["type": "tool_result", "content": "SECRET-OUTPUT"]]]],
            assistant(200, [["type": "text", "text": "Testlerin hepsi geçti ve değişikliği commit'ledim."]]),
            assistant(210, [["type": "text", "text": "a subagent's words"]], sidechain: true),
            assistant(3000, [["type": "text", "text": "after the lid opened"]]),
        ]
    }

    func testOnlyTheWindowAndOnlyNamesDescriptionsAndClaudesWords() throws {
        try transcript("s1", session)
        let digest = try XCTUnwrap(ClaudeDigest.build(from: from, to: to, projects: projects) { $0 == "s1" ? .waiting : .done })
        XCTAssertEqual(digest.sessions.count, 1)
        let s = try XCTUnwrap(digest.sessions.first)
        XCTAssertEqual(s.title, "Uykusuz özeti")
        XCTAssertEqual(s.status, .waiting)
        XCTAssertEqual(s.toolCounts, ["Edit": 2, "Bash": 1, "Read": 1])
        XCTAssertEqual(s.editedFiles, ["AgentAutoSession.swift"])
        XCTAssertEqual(s.commands, ["Run the full suite"])
        XCTAssertEqual(s.lastTexts, ["Testlerin hepsi geçti ve değişikliği commit'ledim."])
        XCTAssertEqual(s.prompts, 1)

        let prompt = digest.promptText
        for secret in ["SECRET-CODE", "SECRET-TOKEN", "SECRET-OUTPUT", "hidden", "a subagent", "before the lid", "after the lid", "README.md"] {
            XCTAssertFalse(prompt.contains(secret), secret)
        }
        XCTAssertTrue(prompt.contains("Düzenlenen dosyalar: AgentAutoSession.swift"), prompt)
        XCTAssertTrue(prompt.contains("kullanıcıdan onay ya da yanıt bekliyor"), prompt)
        XCTAssertEqual(digest.localSummary,
                       "Kapak kapalıyken (40 dakika) Claude \"Uykusuz özeti\" üzerinde çalıştı: 1 dosya düzenledi, 1 komut çalıştırdı. Bir oturum yanıtınızı bekliyor.")
        XCTAssertTrue(prompt.hasPrefix("Kullanıcı 40 dakika uzaktaydı (kapak kapalıydı)."), prompt)
        var asked = digest
        asked.away = false
        XCTAssertTrue(asked.localSummary.hasPrefix("Son 40 dakikada Claude \"Uykusuz özeti\" üzerinde çalıştı"), asked.localSummary)
        XCTAssertTrue(asked.promptText.hasPrefix("Özetlenen süre: son 40 dakika."), asked.promptText)
    }

    func testAQuietStretchAndAnOlderTranscriptAreNothing() throws {
        XCTAssertNil(ClaudeDigest.build(from: from, to: to, projects: projects))
        let old = try transcript("old", session)
        try FileManager.default.setAttributes([.modificationDate: from.addingTimeInterval(-60)], ofItemAtPath: old.path)
        XCTAssertNil(ClaudeDigest.build(from: from, to: to, projects: projects), "not written to since the lid closed")
        try transcript("quiet", [["type": "user", "timestamp": stamp(60), "message": ["role": "user", "content": "merhaba"]]])
        XCTAssertNil(ClaudeDigest.build(from: from, to: to, projects: projects), "a prompt with no answer is not work")
    }

    func testWithoutATitleTheFolderNameAndTheNewestSessionFirst() throws {
        try transcript("a", [assistant(100, [["type": "text", "text": "ilk"]])])
        try transcript("b", in: "-Users-me-x", [
            ["type": "assistant", "timestamp": stamp(300), "cwd": "/Users/me/other-app", "message": ["content": [["type": "text", "text": "son"]]]],
        ])
        let digest = try XCTUnwrap(ClaudeDigest.build(from: from, to: to, projects: projects))
        XCTAssertEqual(digest.sessions.map(\.title), ["other-app", "insomnia-tr"])
        XCTAssertTrue(digest.localSummary.hasSuffix("; 1 oturumda daha çalıştı. Şu an bitmiş durumda."), digest.localSummary)
    }

    func testLongWordsAreClipped() {
        XCTAssertEqual(ClaudeDigest.clip("abcdef", to: 3, keepingEnd: true), "\u{2026}def")
        XCTAssertEqual(ClaudeDigest.clip("abcdef", to: 3, keepingEnd: false), "abc\u{2026}")
        XCTAssertEqual(ClaudeDigest.clip("a\nb", to: 10, keepingEnd: true), "a b")
    }
}

final class AnthropicSummaryClientTests: XCTestCase {
    private let digest = ClaudeDigest(
        from: Date(timeIntervalSince1970: 0),
        to: Date(timeIntervalSince1970: 600),
        sessions: [ClaudeDigest.Session(id: "s", title: "Proje", lastActivity: Date(timeIntervalSince1970: 300))]
    )

    func testTheRequestIsOneMessagesCallWithTheDigestOnly() throws {
        let client = AnthropicSummaryClient(key: "sk-ant-test", model: "claude-haiku-5-5")
        let request = try client.request(for: digest)
        XCTAssertEqual(request.url?.absoluteString, "https://api.anthropic.com/v1/messages")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "x-api-key"), "sk-ant-test")
        XCTAssertEqual(request.value(forHTTPHeaderField: "anthropic-version"), "2023-06-01")
        XCTAssertEqual(request.value(forHTTPHeaderField: "content-type"), "application/json")
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: Any])
        XCTAssertEqual(body["model"] as? String, "claude-haiku-5-5")
        XCTAssertEqual(body["max_tokens"] as? Int, AnthropicSummaryClient.maxTokens)
        XCTAssertEqual((body["output_config"] as? [String: Any])?["effort"] as? String, "low")
        XCTAssertEqual(body["system"] as? String, AnthropicSummaryClient.system)
        let messages = try XCTUnwrap(body["messages"] as? [[String: Any]])
        XCTAssertEqual(messages.count, 1)
        XCTAssertEqual(messages.first?["content"] as? String, digest.promptText)
        XCTAssertNil(body["temperature"], "removed on these models")
        XCTAssertNil(body["thinking"])
    }

    func testTheReplysTextIsKeptAndEverythingElseIsAnError() throws {
        let ok = #"{"content":[{"type":"thinking","thinking":"x"},{"type":"text","text":"Claude testleri bitirdi."}],"stop_reason":"end_turn"}"#
        XCTAssertEqual(try AnthropicSummaryClient.parse(data: Data(ok.utf8), status: 200), "Claude testleri bitirdi.")
        let refused = #"{"content":[],"stop_reason":"refusal"}"#
        XCTAssertThrowsError(try AnthropicSummaryClient.parse(data: Data(refused.utf8), status: 200)) { XCTAssertEqual($0 as? SummaryError, .refusal) }
        let empty = #"{"content":[{"type":"thinking","thinking":"x"}],"stop_reason":"end_turn"}"#
        XCTAssertThrowsError(try AnthropicSummaryClient.parse(data: Data(empty.utf8), status: 200)) { XCTAssertEqual($0 as? SummaryError, .empty) }
        let denied = #"{"type":"error","error":{"type":"authentication_error","message":"invalid x-api-key"}}"#
        XCTAssertThrowsError(try AnthropicSummaryClient.parse(data: Data(denied.utf8), status: 401)) { error in
            XCTAssertEqual(error as? SummaryError, .http(401, "invalid x-api-key"))
            XCTAssertEqual(error.localizedDescription, "API anahtarı geçersiz (401)")
        }
    }

    func testSummarizeSendsAndAFailedSendIsANetworkError() async throws {
        var client = AnthropicSummaryClient(key: "k", model: AnthropicSummaryClient.defaultModel)
        client.send = { request in
            let reply = #"{"content":[{"type":"text","text":"Bitti."}],"stop_reason":"end_turn"}"#
            return (Data(reply.utf8), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
        let text = try await client.summarize(digest)
        XCTAssertEqual(text, "Bitti.")
        client.send = { _ in throw URLError(.notConnectedToInternet) }
        do {
            _ = try await client.summarize(digest)
            XCTFail("expected a network error")
        } catch let error as SummaryError {
            guard case .transport = error else { return XCTFail("\(error)") }
        }
    }

    func testAKeyIsShownMasked() {
        XCTAssertEqual(KeychainAnthropicKeyStore.masked("sk-ant-api03-abcdefghijklmnop"), "sk-ant-\u{2026}mnop")
        XCTAssertEqual(KeychainAnthropicKeyStore.masked("short"), "\u{2026}")
    }
}

@MainActor
final class AwaySummaryTests: XCTestCase {
    struct Writer: SummaryWriting {
        var result: Result<String, SummaryError>
        func summarize(_ digest: ClaudeDigest) async throws -> String { try result.get() }
    }

    private let t0 = Date(timeIntervalSince1970: 2_000_000_000)
    private var now: Date!
    private var config = Config()
    private var asked: [(Date, Date)] = []
    private var digest: ClaudeDigest?
    private var writes: [(key: String, model: String)] = []
    private var shown: [(text: String, told: Date)] = []
    private var dismissed = 0
    private var screenLocked = false
    private var idle: TimeInterval = 0
    private var result: Result<String, SummaryError> = .success("Claude testleri bitirdi, bir onay bekliyor.")

    override func setUp() async throws {
        now = t0
        config = Config()
        asked = []
        writes = []
        shown = []
        dismissed = 0
        screenLocked = false
        idle = 0
        digest = ClaudeDigest(from: t0, to: t0, sessions: [ClaudeDigest.Session(id: "s", title: "Proje", toolCounts: ["Bash": 2], lastActivity: t0)])
    }

    private func make(key: AnthropicKeyRead = .none) -> AwaySummary {
        AwaySummary(
            config: { [unowned self] in self.config },
            present: { [unowned self] text, told in self.shown.append((text, told)) },
            dismiss: { [unowned self] in self.dismissed += 1 },
            keyStore: InMemoryAnthropicKeyStore(key),
            digest: { [unowned self] from, to in
                self.asked.append((from, to))
                return self.digest
            },
            writer: { [unowned self] key, model in
                self.writes.append((key, model))
                return Writer(result: self.result)
            },
            clock: { [unowned self] in self.now },
            screenIsLocked: { [unowned self] in self.screenLocked },
            idleSeconds: { [unowned self] in self.idle }
        )
    }

    private func eventually(_ condition: () -> Bool) async -> Bool {
        let deadline = Date().addingTimeInterval(3)
        while Date() < deadline {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return condition()
    }

    func testTheLidOpeningAfterAWhilePutsTheSummaryUpWithoutSpeaking() async {
        let summary = make()
        summary.lidChanged(closed: true)
        XCTAssertEqual(dismissed, 1, "a summary that is up comes down when the lid closes")
        now = t0.addingTimeInterval(10 * 60)
        summary.lidChanged(closed: false)
        let told = await eventually { !self.shown.isEmpty }
        XCTAssertTrue(told)
        XCTAssertEqual(asked.first?.0, t0)
        XCTAssertEqual(asked.first?.1, t0.addingTimeInterval(10 * 60))
        XCTAssertEqual(shown.first?.text, digest?.localSummary)
        XCTAssertTrue(writes.isEmpty, "no key, no request")
        XCTAssertEqual(summary.last?.text, digest?.localSummary)
    }

    func testAnUnlockAfterTheIdleBlackScreensLockTellsFromTheLastInput() async {
        let summary = make()
        now = t0.addingTimeInterval(16 * 60)
        idle = 16 * 60
        summary.lockChanged(locked: true)
        XCTAssertEqual(dismissed, 1)
        now = t0.addingTimeInterval(40 * 60)
        summary.lockChanged(locked: false)
        let told = await eventually { !self.shown.isEmpty }
        XCTAssertTrue(told)
        XCTAssertEqual(asked.first?.0, t0, "from when the user last touched the Mac, not from the lock")
        XCTAssertEqual(asked.first?.1, t0.addingTimeInterval(40 * 60))
    }

    func testALidOpenedOnTheLockScreenWaitsForTheUnlockAndTellsOnce() async throws {
        let summary = make()
        summary.lidChanged(closed: true)
        now = t0.addingTimeInterval(5)
        screenLocked = true
        summary.lockChanged(locked: true)
        now = t0.addingTimeInterval(20 * 60)
        summary.lidChanged(closed: false)
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertTrue(asked.isEmpty, "behind the lock screen: not yet")
        now = t0.addingTimeInterval(21 * 60)
        screenLocked = false
        summary.lockChanged(locked: false)
        let told = await eventually { !self.shown.isEmpty }
        XCTAssertTrue(told)
        XCTAssertEqual(asked.count, 1, "one absence, one summary")
        XCTAssertEqual(asked.first?.0, t0, "from the close, the earlier of the two")
    }

    func testAShortLockOrALockWithTheLidClosedTellsNothing() async throws {
        let summary = make()
        summary.lockChanged(locked: true)
        now = t0.addingTimeInterval(AwaySummary.minimumAway - 1)
        summary.lockChanged(locked: false)
        summary.lidChanged(closed: true)
        summary.lockChanged(locked: true)
        now = now.addingTimeInterval(3600)
        summary.lockChanged(locked: false)
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertTrue(asked.isEmpty, "unlocked with the lid still closed: not back yet")
    }

    func testAShortCloseTheFeatureOffOrAnOpenWithNoCloseTellNothing() async throws {
        let summary = make()
        summary.lidChanged(closed: false)
        summary.lidChanged(closed: true)
        now = t0.addingTimeInterval(AwaySummary.minimumAway - 1)
        summary.lidChanged(closed: false)
        config.awaySummary = false
        summary.lidChanged(closed: true)
        now = now.addingTimeInterval(3600)
        summary.lidChanged(closed: false)
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertTrue(asked.isEmpty)
        XCTAssertTrue(shown.isEmpty)
    }

    func testWithAKeyClaudeWritesItAndAFailureFallsBackToTheLocalOne() async {
        config.summaryModel = "claude-haiku-5-5"
        var summary = make(key: .key("sk-ant-k"))
        var text = await summary.summarize(from: t0, to: t0.addingTimeInterval(600), away: true, sayIfNothing: false)
        XCTAssertEqual(text, "Claude testleri bitirdi, bir onay bekliyor.")
        XCTAssertEqual(writes.first?.key, "sk-ant-k")
        XCTAssertEqual(writes.first?.model, "claude-haiku-5-5")
        XCTAssertEqual(shown.last?.text, text)
        XCTAssertTrue(summary.lastResult?.contains("Claude yazdı") ?? false, summary.lastResult ?? "")

        result = .failure(.http(401, "invalid x-api-key"))
        text = await summary.summarize(from: t0, to: t0.addingTimeInterval(600), away: true, sayIfNothing: false)
        XCTAssertEqual(text, digest?.localSummary)
        XCTAssertTrue(summary.lastResult?.contains("API anahtarı geçersiz (401)") ?? false, summary.lastResult ?? "")

        summary = make(key: .unreadable)
        text = await summary.summarize(from: t0, to: t0.addingTimeInterval(600), away: true, sayIfNothing: false)
        XCTAssertEqual(text, digest?.localSummary)
        XCTAssertTrue(summary.lastResult?.contains("yeniden kaydedin") ?? false, summary.lastResult ?? "")
    }

    func testNothingToTellIsShownOnlyWhenAsked() async {
        digest = nil
        let summary = make()
        let quiet = await summary.summarize(from: t0, to: t0.addingTimeInterval(600), away: true, sayIfNothing: false)
        XCTAssertNil(quiet)
        XCTAssertTrue(shown.isEmpty)
        _ = await summary.summarize(from: t0, to: t0.addingTimeInterval(600), away: false, sayIfNothing: true)
        XCTAssertEqual(shown.map(\.text), [AwaySummary.nothingToTell])
        XCTAssertNil(summary.last, "nothing to put up again")
    }

    func testTheLastSummaryCanBePutUpAgain() async {
        let summary = make()
        await summary.showLast()
        XCTAssertTrue(shown.isEmpty, "none yet")
        _ = await summary.summarize(from: t0, to: t0.addingTimeInterval(600), away: true, sayIfNothing: false)
        await summary.showLast()
        XCTAssertEqual(shown.count, 2)
        XCTAssertEqual(shown.last?.text, digest?.localSummary)
    }

    func testASessionsStateComesFromItsMarker() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("uykusuz-away-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let paths = Paths(root: root)
        let dir = ClaudeHookCommand.markerDirectory(paths)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(ClaudeTaskMarker(pid: 0, identity: nil, event: "PermissionRequest", updatedAt: t0, waitingSince: t0))
            .write(to: dir.appendingPathComponent("w.json"))
        try encoder.encode(ClaudeTaskMarker(pid: 0, identity: nil, event: "PostToolUse", updatedAt: t0))
            .write(to: dir.appendingPathComponent("b.json"))
        XCTAssertEqual(AwaySummary.status(ofSession: "w", paths: paths, now: t0.addingTimeInterval(60)), .waiting)
        XCTAssertEqual(AwaySummary.status(ofSession: "b", paths: paths, now: t0.addingTimeInterval(60)), .working)
        XCTAssertEqual(AwaySummary.status(ofSession: "gone", paths: paths, now: t0.addingTimeInterval(60)), .done)
        XCTAssertEqual(AwaySummary.status(ofSession: "b", paths: paths, now: t0.addingTimeInterval(ClaudeActivity.markerMaxAge + 1)), .done, "stale")
    }
}

final class SummaryPlayerTests: XCTestCase {
    func testWordsAndWhereABarPositionLands() {
        let text = "Claude testleri bitirdi, bir onay bekliyor."
        let words = SummaryPlayer.words(in: text)
        XCTAssertEqual(words.map { (text as NSString).substring(with: $0) }, ["Claude", "testleri", "bitirdi", "bir", "onay", "bekliyor"])
        XCTAssertEqual(SummaryPlayer.wordIndex(atFraction: 0, count: words.count), 0)
        XCTAssertEqual(SummaryPlayer.wordIndex(atFraction: 1, count: words.count), 5)
        XCTAssertEqual(SummaryPlayer.wordIndex(atFraction: 0.5, count: words.count), 3)
        XCTAssertEqual(SummaryPlayer.wordIndex(atFraction: 7, count: words.count), 5, "clamped")
        XCTAssertEqual(SummaryPlayer.wordIndex(atFraction: 0.5, count: 0), 0)
        // A report from an utterance started at "bir" (offset 25): "onay" is 4 into it.
        let onay = (text as NSString).range(of: "onay")
        XCTAssertEqual(SummaryPlayer.wordIndex(containing: onay.location, in: words), 4)
        XCTAssertEqual(SummaryPlayer.wordIndex(containing: (text as NSString).range(of: ",").location, in: words), 2, "punctuation belongs to the word before")
    }

    @MainActor
    func testMovesStayInsideTheTextAndHighlightTheWord() {
        let player = SummaryPlayer(text: "Bir iki üç dört beş altı yedi", voiceIdentifier: nil)
        XCTAssertNil(player.currentWord)
        XCTAssertEqual(player.progress, 0)
        player.back()
        XCTAssertEqual(player.currentWord, 0)
        player.forward()
        XCTAssertEqual(player.currentWord, 5)
        player.forward()
        XCTAssertEqual(player.currentWord, 6, "the last word")
        player.seek(to: 0.5)
        XCTAssertEqual(player.currentWord, 3)
        XCTAssertFalse(player.isPlaying, "moving does not start the reading")
        let highlighted = player.highlighted(paragraph: 0)
        let marked = highlighted.runs.filter { $0.backgroundColor != nil }.map { String(highlighted[$0.range].characters) }
        XCTAssertEqual(marked, ["dört"])
    }

    func testTheMenuOffersTheLastSummary() {
        func titles(_ has: Bool) -> [String] {
            StatusMenu.items(sessionActive: false, sleepHeld: false, hasSummary: has, machine: nil, actions: nil, throttledBrowsers: [], error: nil).map(\.title)
        }
        XCTAssertTrue(titles(true).contains(StatusMenu.showSummaryTitle))
        XCTAssertFalse(titles(false).contains(StatusMenu.showSummaryTitle))
    }
}

final class LaunchGuardTests: XCTestCase {
    func testOnlyAPlainRunWithNoOtherAppLaunches() {
        XCTAssertEqual(LaunchGuard.verdict(arguments: []) { [] }, .launch)
        XCTAssertEqual(LaunchGuard.verdict(arguments: ["--away-digesst"]) { [] }, .unknownOption("--away-digesst"))
        XCTAssertEqual(LaunchGuard.verdict(arguments: ["-NSDocumentRevisionsDebugMode", "YES"]) { [] }, .launch,
                       "AppKit's own single-dash arguments")
        XCTAssertEqual(LaunchGuard.verdict(arguments: []) { [(pid: 77, argv: ["/Applications/Uykusuz.app/Contents/MacOS/Uykusuz"])] },
                       .alreadyRunning(77))
        XCTAssertEqual(LaunchGuard.verdict(arguments: []) { [(pid: 78, argv: ["/x/Uykusuz", "--claude-hook"])] }, .launch,
                       "a hook running beside it is not an app")
    }

    func testThisProcessArgumentsReadBack() throws {
        let argv = try XCTUnwrap(LaunchGuard.argv(getpid()))
        XCTAssertEqual(argv.count, CommandLine.arguments.count)
        XCTAssertEqual(argv.last, CommandLine.arguments.last)
    }
}

@MainActor
final class BashToolWatcherTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 2_000_000_000)
    private var processes: [BashToolWatcher.Process] = []
    private var cpu: [pid_t: TimeInterval] = [:]
    private var toolShells: Set<pid_t> = []

    private func watcher() -> BashToolWatcher {
        BashToolWatcher(
            read: { [unowned self] in self.processes },
            isToolShell: { [unowned self] in self.toolShells.contains($0.pid) },
            cpuTime: { [unowned self] in self.cpu[$0] }
        )
    }

    private func process(_ pid: pid_t, parent: pid_t, _ name: String, startedAgo: TimeInterval) -> BashToolWatcher.Process {
        .init(pid: pid, ppid: parent, name: name, started: t0.addingTimeInterval(-startedAgo))
    }

    func testAServerLeftRunningIsWorkOnlyWhileItWorks() {
        processes = [process(10, parent: 1, "zsh", startedAgo: 2 * 86400), process(11, parent: 10, "cloud-sql-proxy", startedAgo: 2 * 86400)]
        toolShells = [10]
        cpu = [10: 0.5, 11: 300]
        let w = watcher()
        XCTAssertFalse(w.isWorking(now: t0), "days of CPU are a baseline, not work just done")
        cpu[11] = 300.05
        XCTAssertFalse(w.isWorking(now: t0.addingTimeInterval(15)), "idle between readings")
        cpu[11] = 302
        XCTAssertTrue(w.isWorking(now: t0.addingTimeInterval(30)), "a burst of work")
        XCTAssertTrue(w.isWorking(now: t0.addingTimeInterval(30 + 240)), "still within the window")
        XCTAssertFalse(w.isWorking(now: t0.addingTimeInterval(31 + BashToolWatcher.activeWindow)))
    }

    func testANewCommandCountsUntilItHasHadTimeToWork() {
        processes = [process(20, parent: 1, "zsh", startedAgo: 60)]
        toolShells = [20]
        cpu = [20: 0.01]
        let w = watcher()
        XCTAssertTrue(w.isWorking(now: t0))
        XCTAssertFalse(w.isWorking(now: t0.addingTimeInterval(BashToolWatcher.newGrace)), "five minutes on and idle")
    }

    func testProcessesStartedSinceTheLastReadingCountWhole() {
        processes = [process(30, parent: 1, "zsh", startedAgo: 3600), process(31, parent: 30, "make", startedAgo: 3600)]
        toolShells = [30]
        cpu = [30: 0, 31: 1]
        let w = watcher()
        XCTAssertFalse(w.isWorking(now: t0))
        processes.append(process(32, parent: 31, "clang", startedAgo: -5))
        cpu[32] = 0.8
        XCTAssertTrue(w.isWorking(now: t0.addingTimeInterval(15)), "a compiler that came and is still going")
    }

    func testNestedToolShellsAreOneCommandAndAReusedPidStartsAgain() {
        processes = [process(40, parent: 1, "zsh", startedAgo: 3600), process(41, parent: 40, "zsh", startedAgo: 3600), process(42, parent: 41, "sleep", startedAgo: 3600)]
        toolShells = [40, 41]
        cpu = [40: 0, 41: 0, 42: 5]
        let w = watcher()
        XCTAssertFalse(w.isWorking(now: t0))
        // pid 42 is now another process, started just now, with 1 s of CPU.
        processes[2] = process(42, parent: 41, "swift-build", startedAgo: -10)
        cpu[42] = 1
        XCTAssertTrue(w.isWorking(now: t0.addingTimeInterval(15)))
    }

    func testNothingRunningIsNotWork() {
        processes = [process(50, parent: 1, "zsh", startedAgo: 10)]
        toolShells = []
        XCTAssertFalse(watcher().isWorking(now: t0), "a shell that is not a Bash tool command")
    }

    func testTheLiveReadingsWork() throws {
        let me = try XCTUnwrap(BashToolWatcher.liveProcesses().first { $0.pid == getpid() })
        XCTAssertEqual(me.ppid, getppid())
        XCTAssertLessThan(me.started.timeIntervalSinceNow, 0)
        XCTAssertNotNil(BashToolWatcher.liveCPUTime(getpid()))
    }
}

final class TurkishVoiceTests: XCTestCase {
    private func voice(_ id: String, _ language: String, _ quality: Int, name: String = "Yelda") -> TurkishVoice.Voice {
        .init(identifier: id, name: name, language: language, quality: quality)
    }

    func testTheBestTurkishVoiceWins() {
        let compact = voice("com.apple.voice.compact.tr-TR.Yelda", "tr-TR", 1)
        let enhanced = voice("com.apple.voice.enhanced.tr-TR.Yelda", "tr-TR", 2)
        let english = voice("com.apple.voice.premium.en-US.Zoe", "en-US", 3, name: "Zoe")
        XCTAssertEqual(TurkishVoice.best(among: [compact, english])?.identifier, compact.identifier, "another language never")
        XCTAssertEqual(TurkishVoice.best(among: [compact, enhanced, english])?.identifier, enhanced.identifier)
        XCTAssertEqual(TurkishVoice.best(among: [compact, enhanced])?.label, "Yelda (Gelişmiş)")
        XCTAssertEqual(TurkishVoice.best(among: [compact])?.label, "Yelda (basit)")
        XCTAssertNil(TurkishVoice.best(among: [english]))
        XCTAssertEqual(TurkishVoice.best(among: [voice("x.premium.tr-TR.Yelda", "tr-TR", 3)])?.quality, .premium)
    }

    func testThisMacHasATurkishVoice() async {
        let choice = await TurkishVoice.current(fresh: true)
        XCTAssertFalse(choice.identifier.isEmpty)
    }
}

final class HotspotJoinModeTests: XCTestCase {
    func testOnlyTheKnownValueIsAutomatic() {
        XCTAssertEqual(HotspotJoinMode.from(raw: 3), .automatic)
        XCTAssertEqual(HotspotJoinMode.from(raw: 1), .notAutomatic(1))
        XCTAssertEqual(HotspotJoinMode.from(raw: 2), .notAutomatic(2))
        XCTAssertEqual(HotspotJoinMode.from(raw: nil), .unknown)
        XCTAssertEqual(HotspotJoinMode.read(osMajorVersion: 27), .unknown, "a macOS the call was not measured on")
        // The live call on this Mac answers without crashing, whatever it says.
        _ = HotspotJoinMode.read()
    }
}

final class WiFiReturnPolicyTests: XCTestCase {
    private typealias P = WiFiReturnPolicy

    func testLeavesOnlyForAStrongKnownNetworkWithAPassword() {
        let known = [P.Known(ssid: "OrnekAg", open: false), P.Known(ssid: "IkinciAg", open: false), P.Known(ssid: "iPhone", open: false)]
        XCTAssertEqual(P.decide(hotspot: "iPhone", seen: [.init(ssid: "OrnekAg", rssi: -60, open: false)], known: known), .leave("OrnekAg"))
        XCTAssertEqual(P.decide(hotspot: "iPhone", seen: [.init(ssid: "OrnekAg", rssi: -80, open: false)], known: known),
                       .stay("çevrede yeterince güçlü, bilinen ve parolalı bir ağ yok"), "too weak")
        XCTAssertEqual(P.decide(hotspot: "iPhone", seen: [.init(ssid: "YabanciAg", rssi: -40, open: false)], known: known),
                       .stay("çevrede yeterince güçlü, bilinen ve parolalı bir ağ yok"), "never a network not joined before")
        XCTAssertEqual(P.decide(hotspot: "iPhone", seen: [.init(ssid: "iPhone", rssi: -30, open: false)], known: known),
                       .stay("çevrede yeterince güçlü, bilinen ve parolalı bir ağ yok"), "the hotspot itself")
        XCTAssertEqual(P.decide(hotspot: "iPhone", seen: [.init(ssid: "OrnekAg", rssi: -65, open: false), .init(ssid: "IkinciAg", rssi: -50, open: false)], known: known),
                       .leave("IkinciAg"), "the strongest")
    }

    func testStaysWhileAKnownNetworkWithoutAPasswordIsAround() {
        let known = [P.Known(ssid: "OrnekAg", open: false), P.Known(ssid: "Kafe Misafir", open: true)]
        XCTAssertEqual(P.decide(hotspot: "iPhone", seen: [.init(ssid: "OrnekAg", rssi: -50, open: false), .init(ssid: "Kafe Misafir", rssi: -85, open: true)], known: known),
                       .stay("bilinen parolasız bir ağ çevrede (Kafe Misafir)"), "macOS might pick it, however weak")
        XCTAssertEqual(P.decide(hotspot: "iPhone", seen: [.init(ssid: "OrnekAg", rssi: -50, open: true)], known: known),
                       .stay("bilinen parolasız bir ağ çevrede (OrnekAg)"), "a network seen open under a known secured name")
    }
}

@MainActor
final class WiFiReturnTests: XCTestCase {
    final class Radio: WiFiRadio, @unchecked Sendable {
        private let lock = NSLock()
        var ssids: [String?] = []
        var open: Bool? = false
        var seen: [WiFiReturnPolicy.Seen] = []
        var knownNetworks: [WiFiReturnPolicy.Known] = []
        private(set) var scans = 0
        private(set) var disassociations = 0
        func currentSSID() -> String? { lock.withLock { ssids.count > 1 ? ssids.removeFirst() : ssids.first ?? nil } }
        func currentIsOpen() -> Bool? { lock.withLock { open } }
        func scan() throws -> [WiFiReturnPolicy.Seen] { lock.withLock { scans += 1; return seen } }
        func known() -> [WiFiReturnPolicy.Known] { lock.withLock { knownNetworks } }
        func disassociate() { lock.withLock { disassociations += 1 } }
    }

    private var config = Config()
    private var now = Date(timeIntervalSince1970: 2_000_000_000)
    private var rejoins = 0

    private func make(_ radio: Radio) -> WiFiReturn {
        config.hotspotSSID = "iPhone"
        return WiFiReturn(config: { [unowned self] in self.config }, radio: radio, clock: { [unowned self] in self.now }) { [unowned self] in
            self.rejoins += 1
        }
    }

    func testLeavesTheHotspotForHomeAndThenWaits() async {
        let radio = Radio()
        radio.ssids = ["iPhone", "OrnekAg"]
        radio.seen = [.init(ssid: "OrnekAg", rssi: -55, open: false)]
        radio.knownNetworks = [.init(ssid: "OrnekAg", open: false)]
        let back = make(radio)
        await back.check(settle: .zero)
        XCTAssertEqual(radio.disassociations, 1)
        XCTAssertEqual(rejoins, 0, "now on a known network with a password")

        radio.ssids = ["iPhone"]
        now = now.addingTimeInterval(60)
        await back.check(settle: .zero)
        XCTAssertEqual(radio.scans, 1, "no new try within the cooldown")
    }

    func testANetworkWithoutAPasswordIsLeftForTheHotspot() async {
        let radio = Radio()
        radio.ssids = ["iPhone", "Otel Misafir"]
        radio.open = true
        radio.seen = [.init(ssid: "OrnekAg", rssi: -55, open: false)]
        radio.knownNetworks = [.init(ssid: "OrnekAg", open: false)]
        await make(radio).check(settle: .zero)
        XCTAssertEqual(radio.disassociations, 2, "left the hotspot, then the open network")
        XCTAssertEqual(rejoins, 1)
    }

    func testNothingOffTheHotspotOrWithTheSettingOff() async {
        let radio = Radio()
        radio.ssids = ["OrnekAg"]
        let back = make(radio)
        await back.check(settle: .zero)
        XCTAssertEqual(radio.scans, 0, "not on the hotspot")
        radio.ssids = ["iPhone"]
        config.returnToKnownWiFi = false
        await back.check(settle: .zero)
        XCTAssertEqual(radio.scans, 0, "turned off")
    }
}

@MainActor
final class WaitingAlertsTests: XCTestCase {
    final class Sender: MessageSending, @unchecked Sendable {
        private let lock = NSLock()
        private var _sent: [(text: String, handle: String)] = []
        var sent: [(text: String, handle: String)] { lock.withLock { _sent } }
        var fail = false
        func send(_ text: String, to handle: String) async throws {
            if fail { throw MessageSendError(message: "izin yok") }
            lock.withLock { _sent.append((text, handle)) }
        }
    }

    private var config = Config()
    private var current: [String: ClaudeTaskMarker] = [:]
    private var open = true
    private var isAway = true
    private var now = Date(timeIntervalSince1970: 2_000_000_000)
    private let sender = Sender()

    private func make() -> WaitingAlerts {
        config.imessageAlerts = true
        config.imessageHandle = "+905550000000"
        return WaitingAlerts(
            config: { [unowned self] in self.config },
            sessions: { [unowned self] in self.current },
            stillOpen: { [unowned self] _ in self.open },
            away: { [unowned self] in self.isAway },
            compose: { id, event in "\(id) \(event == .waiting ? "bekliyor" : "bitti")" },
            sender: sender,
            clock: { [unowned self] in self.now }
        )
    }

    private func working(updated: TimeInterval = 0) -> ClaudeTaskMarker {
        ClaudeTaskMarker(pid: 0, identity: nil, event: "PostToolUse", updatedAt: now.addingTimeInterval(-updated))
    }

    private func waiting() -> ClaudeTaskMarker {
        ClaudeTaskMarker(pid: 0, identity: nil, event: "Notification", updatedAt: now, waitingSince: now)
    }

    private func advance(_ seconds: TimeInterval) { now = now.addingTimeInterval(seconds) }

    func testAWaitThatLastsWhileAwayIsSentOnce() async {
        let alerts = make()
        current = ["s1": working()]
        await alerts.tick()
        current = ["s1": waiting()]
        await alerts.tick()
        XCTAssertTrue(sender.sent.isEmpty, "not yet settled")
        advance(WaitingAlerts.settle)
        await alerts.tick()
        XCTAssertEqual(sender.sent.map(\.text), ["s1 bekliyor"])
        XCTAssertEqual(sender.sent.first?.handle, "+905550000000")
        advance(60)
        await alerts.tick()
        XCTAssertEqual(sender.sent.count, 1, "the same wait once")
    }

    func testAFinishIsSentButNotOneThatWorkResumedAfter() async {
        let alerts = make()
        current = ["s1": working(), "s2": working()]
        await alerts.tick()
        current = ["s2": working()]
        await alerts.tick()
        advance(10)
        current = ["s1": working(), "s2": working()]
        await alerts.tick()
        advance(WaitingAlerts.settle)
        await alerts.tick()
        XCTAssertTrue(sender.sent.isEmpty, "a turn ended and the next began at once")
        current = ["s1": working()]
        await alerts.tick()
        advance(WaitingAlerts.settle)
        await alerts.tick()
        XCTAssertEqual(sender.sent.map(\.text), ["s2 bitti"])
    }

    func testAMarkerThatGoesAwayWithoutAStopIsNoFinish() async {
        let alerts = make()
        current = ["stale": working(updated: ClaudeActivity.markerMaxAge - 5)]
        await alerts.tick()
        advance(10)
        current = [:]
        await alerts.tick()
        advance(WaitingAlerts.settle)
        await alerts.tick()
        XCTAssertTrue(sender.sent.isEmpty, "a marker that went stale: an interrupted turn")

        current = ["closed": working()]
        await alerts.tick()
        open = false
        current = [:]
        await alerts.tick()
        advance(WaitingAlerts.settle)
        await alerts.tick()
        XCTAssertTrue(sender.sent.isEmpty, "Claude was closed")

        open = true
        current = ["waited": waiting()]
        await alerts.tick()
        advance(WaitingAlerts.settle)
        await alerts.tick()
        XCTAssertEqual(sender.sent.map(\.text), ["waited bekliyor"])
        advance(WaitingAlerts.perSessionGap)
        current = [:]
        await alerts.tick()
        advance(WaitingAlerts.settle)
        await alerts.tick()
        XCTAssertEqual(sender.sent.count, 1, "a wait that ended unanswered is not a finish")
    }

    func testAWaitSeenAtTheMacIsToldIfTheUserLeavesSoon() async {
        let alerts = make()
        isAway = false
        current = ["s1": waiting(), "s2": waiting()]
        await alerts.tick()
        advance(WaitingAlerts.settle)
        await alerts.tick()
        XCTAssertTrue(sender.sent.isEmpty, "at the Mac")
        advance(60)
        isAway = true
        await alerts.tick()
        XCTAssertEqual(Set(sender.sent.map(\.text)), ["s1 bekliyor", "s2 bekliyor"], "left within \(Int(WaitingAlerts.pendingLimit / 60)) min")

        current = ["s3": waiting()]
        isAway = false
        await alerts.tick()
        advance(WaitingAlerts.pendingLimit)
        await alerts.tick()
        isAway = true
        advance(60)
        await alerts.tick()
        XCTAssertEqual(sender.sent.count, 2, "left later: the wait was on the screen long enough")
    }

    func testNothingWhileAtTheMacOrTurnedOffAndAGapPerSession() async {
        let alerts = make()
        current = ["s1": working()]
        await alerts.tick()
        isAway = false
        current = ["s1": waiting()]
        await alerts.tick()
        advance(WaitingAlerts.settle)
        await alerts.tick()
        XCTAssertTrue(sender.sent.isEmpty, "at the Mac: the session is on the screen")

        isAway = true
        current = ["s1": working()]
        await alerts.tick()
        current = ["s1": waiting()]
        await alerts.tick()
        advance(WaitingAlerts.settle)
        await alerts.tick()
        XCTAssertEqual(sender.sent.count, 1)
        current = ["s1": working()]
        await alerts.tick()
        current = ["s1": waiting()]
        await alerts.tick()
        advance(WaitingAlerts.settle)
        await alerts.tick()
        XCTAssertEqual(sender.sent.count, 1, "at most one per session in \(Int(WaitingAlerts.perSessionGap / 60)) min")

        config.imessageAlerts = false
        current = ["s2": working()]
        await alerts.tick()
        current = ["s2": waiting()]
        await alerts.tick()
        advance(WaitingAlerts.settle)
        await alerts.tick()
        XCTAssertEqual(sender.sent.count, 1, "turned off")
    }

    func testTheTestMessageAndAFailureAreReported() async {
        let alerts = make()
        await alerts.sendTest()
        XCTAssertEqual(sender.sent.map(\.text), [WaitingAlerts.testText])
        XCTAssertTrue(alerts.lastResult?.hasSuffix("gönderildi") ?? false, alerts.lastResult ?? "")
        sender.fail = true
        await alerts.sendTest()
        XCTAssertTrue(alerts.lastResult?.contains("gönderilemedi: izin yok") ?? false, alerts.lastResult ?? "")
    }

    func testTheLocalTextAndTheScriptArguments() {
        let session = ClaudeDigest.Session(id: "s", title: "Uykusuz", lastTexts: ["Testler geçti; push için onayınızı bekliyorum."], lastActivity: Date())
        XCTAssertEqual(WaitingAlerts.localText(event: .waiting, session: session),
                       "Uykusuz · Uykusuz: Claude sizi bekliyor; onay ya da yanıt istiyor. Son mesajı: Testler geçti; push için onayınızı bekliyorum.")
        XCTAssertEqual(WaitingAlerts.localText(event: .finished, session: nil),
                       "Uykusuz: Claude işini bitirdi ve yeni isteğinizi bekliyor.")
        let args = IMessageSender.arguments(text: "\" & do shell script \"x", handle: "+90555")
        XCTAssertEqual(Array(args.suffix(2)), ["\" & do shell script \"x", "+90555"], "the text is an argument, never script")
        XCTAssertEqual(args.filter { $0 == "-e" }.count, IMessageSender.script.count)
        XCTAssertTrue(IMessageSender.explain("execution error: Not authorized to send Apple events to Messages. (-1743)").contains("Otomasyon"))
    }

    /// A finished session is named however many others are at work: the
    /// digest of a span keeps only its newest few.
    func testTheMessageNamesASessionThatManyOthersOutran() async throws {
        let projects = FileManager.default.temporaryDirectory.appendingPathComponent("uykusuz-alert-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: projects) }
        let dir = projects.appendingPathComponent("-Users-me-p", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let stampText = { (offset: TimeInterval) in
            Date.ISO8601FormatStyle(includingFractionalSeconds: true).format(self.now.addingTimeInterval(offset))
        }
        func write(_ id: String, title: String, at offset: TimeInterval) throws {
            let lines: [[String: Any]] = [
                ["type": "custom-title", "customTitle": title, "sessionId": id],
                ["type": "assistant", "timestamp": stampText(offset), "cwd": "/Users/me/p",
                 "message": ["role": "assistant", "content": [["type": "text", "text": "\(title) tamam."]]]],
            ]
            let text = try lines.map { String(decoding: try JSONSerialization.data(withJSONObject: $0), as: UTF8.self) }.joined(separator: "\n")
            let file = dir.appendingPathComponent("\(id).jsonl")
            try Data((text + "\n").utf8).write(to: file)
            try FileManager.default.setAttributes([.modificationDate: now.addingTimeInterval(offset)], ofItemAtPath: file.path)
        }
        try write("finished", title: "Biten oturum", at: -120)
        for index in 0..<ClaudeDigest.maxSessions + 1 {
            try write("busy\(index)", title: "Diğer \(index)", at: -Double(index + 1))
        }
        let text = await WaitingAlerts.liveCompose(
            session: "finished",
            event: .finished,
            keyStore: InMemoryAnthropicKeyStore(),
            model: "claude-haiku-5-5",
            projects: projects,
            now: now
        )
        XCTAssertEqual(text, "Uykusuz · Biten oturum: Claude işini bitirdi ve yeni isteğinizi bekliyor. Son mesajı: Biten oturum tamam.")
    }

    func testAMessageThatIsAboutNoSessionGoesTheSameWay() async {
        let alerts = make()
        await alerts.tell("Uykusuz · Docker: iş bitti.", what: "docker finished")
        XCTAssertEqual(sender.sent.map(\.text), ["Uykusuz · Docker: iş bitti."])
        XCTAssertEqual(sender.sent.first?.handle, "+905550000000")
        XCTAssertTrue(alerts.lastResult?.hasSuffix("gönderildi") ?? false, alerts.lastResult ?? "")
        config.imessageHandle = " "
        await alerts.tell("x", what: "docker finished")
        XCTAssertEqual(sender.sent.count, 1, "no one to tell")
    }

    func testAClientWithItsOwnInstructions() throws {
        let client = AnthropicSummaryClient(key: "k", model: "claude-haiku-5-5", system: WaitingAlerts.system)
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(client.request(text: "Olay: x").httpBody)) as? [String: Any])
        XCTAssertEqual(body["system"] as? String, WaitingAlerts.system)
        XCTAssertEqual((body["messages"] as? [[String: Any]])?.first?["content"] as? String, "Olay: x")
    }
}
