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
    final class Speech: SpeechSynthesizing, @unchecked Sendable {
        private let lock = NSLock()
        private var _spoken: [String] = []
        var spoken: [String] { lock.withLock { _spoken } }
        func speak(_ text: String) async { lock.withLock { _spoken.append(text) } }
    }

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
    private var result: Result<String, SummaryError> = .success("Claude testleri bitirdi, bir onay bekliyor.")

    override func setUp() async throws {
        now = t0
        config = Config()
        asked = []
        writes = []
        digest = ClaudeDigest(from: t0, to: t0, sessions: [ClaudeDigest.Session(id: "s", title: "Proje", toolCounts: ["Bash": 2], lastActivity: t0)])
    }

    private func make(key: AnthropicKeyRead = .none) -> (AwaySummary, RecordingNotifier, Speech) {
        let notifier = RecordingNotifier()
        let speech = Speech()
        let summary = AwaySummary(
            config: { [unowned self] in self.config },
            notifier: notifier,
            keyStore: InMemoryAnthropicKeyStore(key),
            speech: speech,
            digest: { [unowned self] from, to in
                self.asked.append((from, to))
                return self.digest
            },
            writer: { [unowned self] key, model in
                self.writes.append((key, model))
                return Writer(result: self.result)
            },
            clock: { [unowned self] in self.now },
            speechDelayAfterOpen: .zero
        )
        return (summary, notifier, speech)
    }

    private func eventually(_ condition: () -> Bool) async -> Bool {
        let deadline = Date().addingTimeInterval(3)
        while Date() < deadline {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return condition()
    }

    func testTheLidOpeningAfterAWhileTellsTheLocalSummaryWithoutAKey() async {
        let (summary, notifier, speech) = make()
        summary.lidChanged(closed: true)
        now = t0.addingTimeInterval(10 * 60)
        summary.lidChanged(closed: false)
        let told = await eventually { !notifier.posts.isEmpty }
        XCTAssertTrue(told)
        XCTAssertEqual(asked.first?.0, t0)
        XCTAssertEqual(asked.first?.1, t0.addingTimeInterval(10 * 60))
        XCTAssertEqual(notifier.posts.first?.title, AwaySummary.title)
        XCTAssertEqual(notifier.posts.first?.body, digest?.localSummary)
        XCTAssertTrue(writes.isEmpty, "no key, no request")
        let spoke = await eventually { speech.spoken == [self.digest!.localSummary] }
        XCTAssertTrue(spoke)
    }

    func testAShortCloseTheFeatureOffOrAnOpenWithNoCloseTellNothing() async throws {
        let (summary, notifier, _) = make()
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
        XCTAssertTrue(notifier.posts.isEmpty)
    }

    func testWithAKeyClaudeWritesItAndAFailureFallsBackToTheLocalOne() async {
        config.summaryModel = "claude-haiku-5-5"
        var (summary, notifier, _) = make(key: .key("sk-ant-k"))
        var text = await summary.summarize(from: t0, to: t0.addingTimeInterval(600), sayIfNothing: false)
        XCTAssertEqual(text, "Claude testleri bitirdi, bir onay bekliyor.")
        XCTAssertEqual(writes.first?.key, "sk-ant-k")
        XCTAssertEqual(writes.first?.model, "claude-haiku-5-5")
        XCTAssertEqual(notifier.posts.last?.body, text)
        XCTAssertTrue(summary.lastResult?.contains("Claude yazdı") ?? false, summary.lastResult ?? "")

        result = .failure(.http(401, "invalid x-api-key"))
        text = await summary.summarize(from: t0, to: t0.addingTimeInterval(600), sayIfNothing: false)
        XCTAssertEqual(text, digest?.localSummary)
        XCTAssertTrue(summary.lastResult?.contains("API anahtarı geçersiz (401)") ?? false, summary.lastResult ?? "")

        (summary, notifier, _) = make(key: .unreadable)
        text = await summary.summarize(from: t0, to: t0.addingTimeInterval(600), sayIfNothing: false)
        XCTAssertEqual(text, digest?.localSummary)
        XCTAssertTrue(summary.lastResult?.contains("yeniden kaydedin") ?? false, summary.lastResult ?? "")
    }

    func testNothingToTellIsSaidOnlyWhenAsked() async {
        digest = nil
        let (summary, notifier, speech) = make()
        let quiet = await summary.summarize(from: t0, to: t0.addingTimeInterval(600), sayIfNothing: false)
        XCTAssertNil(quiet)
        XCTAssertTrue(notifier.posts.isEmpty)
        _ = await summary.summarize(from: t0, to: t0.addingTimeInterval(600), sayIfNothing: true)
        XCTAssertEqual(notifier.posts.map(\.body), ["Bu sürede Claude'un yaptığı bir iş yok."])
        XCTAssertTrue(speech.spoken.isEmpty)
    }

    func testReadAloudOnlyIfSettingsSaysSo() async {
        config.awaySummarySpoken = false
        let (summary, notifier, speech) = make()
        _ = await summary.summarize(from: t0, to: t0.addingTimeInterval(600), sayIfNothing: false)
        XCTAssertEqual(notifier.posts.count, 1)
        XCTAssertTrue(speech.spoken.isEmpty)
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
