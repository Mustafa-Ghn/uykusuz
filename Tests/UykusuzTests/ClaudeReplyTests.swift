import XCTest
@testable import Uykusuz

final class ClaudeReplyHookTests: XCTestCase {
    private var root: URL!
    private var paths: Paths!
    /// Now, to the second as the files keep it: `put` sweeps by the real age
    /// of what it finds.
    private let t0 = Date(timeIntervalSince1970: Date().timeIntervalSince1970.rounded(.down))

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("uykusuz-reply-\(UUID().uuidString)", isDirectory: true)
        paths = Paths(root: root)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: root)
    }

    private func hook(_ event: String, session: String = "abc-123", extra: String = "", readReplies: Bool = true, at offset: TimeInterval = 0) {
        let input = Data(#"{"session_id":"\#(session)","hook_event_name":"\#(event)"\#(extra)}"#.utf8)
        _ = ClaudeHookCommand.run(["--claude-hook"], readInput: { input }, paths: paths, now: t0.addingTimeInterval(offset),
                                  claudeProcess: { nil }, autoApprove: { _ in false }, readReplies: { _ in readReplies }, write: { _ in })
    }

    private func marker(_ session: String = "abc-123") -> ClaudeTaskMarker? {
        ClaudeHookCommand.readMarker(ClaudeHookCommand.markerDirectory(paths).appendingPathComponent("\(session).json"))
    }

    func testStopLeavesClaudesLastMessageAndNothingElse() throws {
        hook("Stop", extra: #","last_assistant_message":"  Bitti.\n","cwd":"/Users/me/proje""#)
        let replies = ClaudeReplyInbox.take(paths: paths)
        XCTAssertEqual(replies, [ClaudeReply(session: "abc-123", title: "proje", text: "Bitti.", at: t0)])
        XCTAssertEqual(ClaudeReplyInbox.take(paths: paths), [], "taken once: the file is gone")
    }

    func testTheFileAndItsFolderAreTheOwnersAlone() throws {
        hook("Stop", extra: #","last_assistant_message":"Bitti.""#)
        let dir = ClaudeReplyInbox.directory(paths)
        let names = try FileManager.default.contentsOfDirectory(atPath: dir.path)
        XCTAssertEqual(names, ["abc-123.json"], "no temp file left")
        let file = dir.appendingPathComponent("abc-123.json")
        XCTAssertEqual(try FileManager.default.attributesOfItem(atPath: file.path)[.posixPermissions] as? Int, 0o600)
        XCTAssertEqual(try FileManager.default.attributesOfItem(atPath: dir.path)[.posixPermissions] as? Int, 0o700)
    }

    func testNothingIsLeftWhenOffOrWithNothingToRead() {
        hook("Stop", extra: #","last_assistant_message":"Bitti.""#, readReplies: false)
        hook("Stop", session: "bos", extra: #","last_assistant_message":"  \n ""#)
        hook("Stop", session: "yok")
        hook("StopFailure", session: "hata", extra: #","last_assistant_message":"API hatası""#)
        hook("SessionEnd", session: "son", extra: #","last_assistant_message":"Bitti.""#)
        hook("PostToolUse", session: "arac", extra: #","last_assistant_message":"Sürüyor""#)
        XCTAssertEqual(ClaudeReplyInbox.take(paths: paths), [])
    }

    func testASessionsNewerReplyReplacesItsOlderOne() {
        hook("Stop", extra: #","last_assistant_message":"Birinci""#)
        hook("Stop", extra: #","last_assistant_message":"İkinci""#, at: 5)
        hook("Stop", session: "baska", extra: #","last_assistant_message":"Öteki""#, at: 3)
        XCTAssertEqual(ClaudeReplyInbox.take(paths: paths).map(\.text), ["Öteki", "İkinci"], "oldest first")
    }

    func testRepliesLeftWhileTheAppWasNotRunningDoNotPileUp() throws {
        let old = Date().addingTimeInterval(-ClaudeReplyInbox.maxAge - 60)
        try ClaudeReplyInbox.put(ClaudeReply(session: "eski", title: "t", text: "Eski", at: old), paths: paths)
        let file = ClaudeReplyInbox.directory(paths).appendingPathComponent("eski.json")
        try FileManager.default.setAttributes([.modificationDate: old], ofItemAtPath: file.path)
        try ClaudeReplyInbox.put(ClaudeReply(session: "yeni", title: "t", text: "Yeni", at: Date()), paths: paths)
        XCTAssertEqual(ClaudeReplyInbox.take(paths: paths).map(\.session), ["yeni"])
    }

    func testAPromptIsRememberedAcrossToolUsesAndANewTurnResetsIt() {
        hook("UserPromptSubmit")
        XCTAssertEqual(marker()?.promptedAt, t0)
        hook("PostToolUse", extra: #","tool_name":"Bash""#, at: 5)
        XCTAssertEqual(marker()?.promptedAt, t0)
        hook("Stop", at: 10)
        hook("PostToolUse", extra: #","tool_name":"Bash""#, at: 15)
        XCTAssertNil(marker()?.promptedAt, "background work after the turn is not a prompt")
        hook("UserPromptSubmit", at: 20)
        XCTAssertEqual(marker()?.promptedAt, t0.addingTimeInterval(20))
    }

    func testAMarkerFromAnEarlierBuildStillReads() throws {
        let dir = ClaudeHookCommand.markerDirectory(paths)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent("eski.json")
        try Data(#"{"pid":1,"event":"PostToolUse","updatedAt":"2026-10-20T19:53:35Z"}"#.utf8).write(to: file)
        XCTAssertEqual(ClaudeHookCommand.readMarker(file)?.event, "PostToolUse")
        XCTAssertNil(ClaudeHookCommand.readMarker(file)?.promptedAt)
    }

    func testTheTitleIsTheSidebarsThenTheFolders() throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let transcript = root.appendingPathComponent("oturum.jsonl")
        let lines = [
            #"{"type":"custom-title","customTitle":"Eski başlık"}"#,
            #"{"type":"assistant","message":{"content":"custom-title geçen bir metin"}}"#,
            #"{"type":"custom-title","customTitle":"Yeni başlık"}"#,
            #"{"type":"assistant","message":{"content":"son"}}"#,
        ]
        try lines.joined(separator: "\n").write(to: transcript, atomically: true, encoding: .utf8)
        XCTAssertEqual(ClaudeReplyInbox.title(transcript: transcript.path, cwd: "/Users/me/proje"), "Yeni başlık")
        XCTAssertEqual(ClaudeReplyInbox.title(transcript: root.appendingPathComponent("yok").path, cwd: "/Users/me/proje"), "proje")
        XCTAssertEqual(ClaudeReplyInbox.title(transcript: nil, cwd: nil), "Claude")
    }
}

final class ClaudeReplySpeechTests: XCTestCase {
    private func plain(_ text: String) -> String { ClaudeReplySpeech.plain(text) }

    func testPlainSentencesStayAsTheyAre() {
        XCTAssertEqual(plain("Hazır. Testler geçti."), "Hazır. Testler geçti.")
        XCTAssertEqual(plain("Birinci satır\nikinci satır.\n\nYeni paragraf."), "Birinci satır ikinci satır.\nYeni paragraf.")
    }

    func testTheMarksAreDropped() {
        XCTAssertEqual(plain("**Kalın** ve *eğik* ve __altı__ ve ~~çizik~~ yazı."), "Kalın ve eğik ve altı ve çizik yazı.")
        XCTAssertEqual(plain("**Uykusuz**'u ve **Claude**un yanıtını."), "Uykusuz'u ve Claudeun yanıtını.")
        XCTAssertEqual(plain("snake_case_adı ve 2*3*4 kalır."), "snake_case_adı ve 2*3*4 kalır.")
    }

    func testHeadingsAndListsPauseOnTheirOwnLine() {
        XCTAssertEqual(plain("## Sonuç\n- Birinci\n- İkinci:\n* [x] Üçüncü\n1. Dördüncü"), "Sonuç.\nBirinci.\nİkinci:\nÜçüncü.\n1. Dördüncü.")
        XCTAssertEqual(plain("> Alıntı burada."), "Alıntı burada.")
        XCTAssertEqual(plain("Üst\n\n---\n\nAlt."), "Üst\nAlt.")
    }

    func testACodeBlockIsNamedNotSpelledOut() {
        let text = "Şunu çalıştırın:\n\n```bash\nswift test --filter Foo\n```\n\nSonra bitti."
        XCTAssertEqual(plain(text), "Şunu çalıştırın:\n\(ClaudeReplySpeech.codeBlock)\nSonra bitti.")
        XCTAssertEqual(plain("```\nkapanmamış\nblok"), ClaudeReplySpeech.codeBlock)
    }

    func testLinksAndPathsAreSaidShort() {
        XCTAssertEqual(plain("Bkz. [ClaudeHooks.swift:42](Sources/Uykusuz/System/ClaudeHooks.swift:42)."), "Bkz. ClaudeHooks.swift.")
        XCTAssertEqual(plain("Kaynak: https://ornek.com/a/b?c=d burada."), "Kaynak: \(ClaudeReplySpeech.link) burada.")
        XCTAssertEqual(plain("`~/.claude/settings.json` dosyası."), "settings.json dosyası.")
        XCTAssertEqual(plain("`Sources/Uykusuz/UI` klasörü."), "UI klasörü.")
        XCTAssertEqual(plain("![çizim](docs/a.svg)"), "çizim")
    }

    func testWhatOnlyLooksLikeAPathStays() {
        XCTAssertEqual(plain("ve/veya, 1/2 ve 31/10/2026 kalır."), "ve/veya, 1/2 ve 31/10/2026 kalır.")
        XCTAssertEqual(plain("Sürüm 0.7.5 ve saat 12.30:45."), "Sürüm 0.7.5 ve saat 12.30:45.")
    }

    func testATableIsReadRowByRow() {
        XCTAssertEqual(plain("| Ad | Değer |\n| --- | :-: |\n| `a` | 1 |"), "Ad, Değer.\na, 1.")
    }

    func testNothingToSay() {
        XCTAssertEqual(plain(""), "")
        XCTAssertEqual(plain("---\n\n***"), "")
    }
}

@MainActor
final class ClaudeReplyReaderTests: XCTestCase {
    private var root: URL!
    private var paths: Paths!
    private var config = Config()
    private var shown: [String] = []
    private var finishers: [@MainActor () -> Void] = []
    private var closers: [@MainActor () -> Void] = []
    private var dismissals = 0
    private var windowReading = false
    private var speakable = true
    private let t0 = Date()

    override func setUp() async throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("uykusuz-reader-\(UUID().uuidString)", isDirectory: true)
        paths = Paths(root: root)
        config.readClaudeReplies = true
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func reader(linger: TimeInterval = 60) -> ClaudeReplyReader {
        ClaudeReplyReader(
            config: { [unowned self] in self.config },
            present: { [unowned self] reply, onFinish, onClose in
                self.shown.append(reply.text)
                self.finishers.append(onFinish)
                self.closers.append(onClose)
            },
            dismiss: { [unowned self] in
                self.dismissals += 1
                // As the window does: its close reports back.
                self.closers.last?()
            },
            windowIsReading: { [unowned self] in self.windowReading },
            canSpeak: { [unowned self] in self.speakable },
            paths: paths,
            clock: { [unowned self] in self.t0 },
            linger: linger
        )
    }

    private func reply(_ text: String, session: String = "s1", at offset: TimeInterval = 0) -> ClaudeReply {
        ClaudeReply(session: session, title: "t", text: text, at: t0.addingTimeInterval(offset))
    }

    /// `present` runs in a task the reader starts.
    private func settle() async {
        for _ in 0..<5 { await Task.yield() }
    }

    private func prompt(session: String, at offset: TimeInterval) throws {
        let dir = ClaudeHookCommand.markerDirectory(paths)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let marker = ClaudeTaskMarker(pid: 0, event: "UserPromptSubmit", updatedAt: t0.addingTimeInterval(offset), promptedAt: t0.addingTimeInterval(offset))
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(marker).write(to: dir.appendingPathComponent("\(session).json"))
    }

    func testAReplyIsReadWhenItArrives() async {
        let r = reader()
        r.arrived(reply("Bitti."))
        await settle()
        XCTAssertEqual(shown, ["Bitti."])
        XCTAssertEqual(r.last?.text, "Bitti.")
    }

    func testOffNothingIsReadOrKept() async {
        config.readClaudeReplies = false
        let r = reader()
        r.arrived(reply("Bitti."))
        await settle()
        XCTAssertEqual(shown, [])
        XCTAssertNil(r.last)
    }

    func testAReplyWithNothingToSayIsSkipped() async {
        let r = reader()
        r.arrived(reply("---"))
        await settle()
        XCTAssertEqual(shown, [])
        XCTAssertNil(r.last)
    }

    func testWithTheLidClosedOrLockedItIsKeptNotRead() async {
        speakable = false
        let r = reader()
        r.arrived(reply("Bitti."))
        await settle()
        XCTAssertEqual(shown, [])
        XCTAssertEqual(r.last?.text, "Bitti.", "for the menu")
    }

    func testAReplyTheAppFoundLaterIsKeptNotRead() async {
        let r = reader()
        r.arrived(reply("Eski", at: -ClaudeReplyInbox.maxAge - 1))
        await settle()
        XCTAssertEqual(shown, [])
        XCTAssertEqual(r.last?.text, "Eski")
    }

    func testRepliesAreReadInTurnAndANewerOneTakesItsSessionsPlace() async {
        let r = reader()
        r.arrived(reply("A", session: "a"))
        r.arrived(reply("B1", session: "b", at: 1))
        r.arrived(reply("C", session: "c", at: 2))
        r.arrived(reply("B2", session: "b", at: 3))
        await settle()
        XCTAssertEqual(shown, ["A"], "nothing cuts the reading off")
        finishers[0]()
        await settle()
        XCTAssertEqual(shown, ["A", "C"])
        finishers[1]()
        await settle()
        XCTAssertEqual(shown, ["A", "C", "B2"])
        XCTAssertEqual(r.last?.text, "B2")
    }

    func testAReadingTheUserAskedForIsNotCutOff() async {
        windowReading = true
        let r = reader()
        r.arrived(reply("Bitti."))
        await settle()
        XCTAssertEqual(shown, [], "a summary is being read")
        windowReading = false
        r.look()
        await settle()
        XCTAssertEqual(shown, ["Bitti."])
    }

    func testWhatWaitsBehindASummaryIsNotReadOnceTheLidCloses() async {
        windowReading = true
        let r = reader()
        r.arrived(reply("Bitti."))
        await settle()
        windowReading = false
        speakable = false
        r.look()
        speakable = true
        r.look()
        await settle()
        XCTAssertEqual(shown, [])
    }

    func testClosingTheWindowEndsTheReadingAndWhatWaits() async {
        let r = reader()
        r.arrived(reply("A", session: "a"))
        r.arrived(reply("B", session: "b", at: 1))
        await settle()
        closers[0]()
        finishers[0]()
        r.look()
        await settle()
        XCTAssertEqual(shown, ["A"])
    }

    func testANewPromptEndsItsSessionsReadingAndNoOthers() async throws {
        let r = reader()
        r.arrived(reply("A", session: "a"))
        r.arrived(reply("B", session: "b", at: 1))
        await settle()
        r.look()
        XCTAssertEqual(dismissals, 0, "no prompt yet")
        try prompt(session: "a", at: 5)
        r.look()
        await settle()
        XCTAssertEqual(dismissals, 1)
        XCTAssertEqual(shown, ["A", "B"], "the other session's reply goes on")
    }

    func testANewPromptDropsItsSessionsWaitingReply() async throws {
        let r = reader()
        r.arrived(reply("A", session: "a"))
        r.arrived(reply("B", session: "b", at: 1))
        await settle()
        try prompt(session: "b", at: 5)
        r.look()
        finishers[0]()
        await settle()
        XCTAssertEqual(shown, ["A"])
    }

    func testAPromptBeforeTheReplyChangesNothing() async throws {
        let r = reader()
        r.arrived(reply("A", session: "a", at: 5))
        await settle()
        try prompt(session: "a", at: 0)
        r.look()
        XCTAssertEqual(dismissals, 0)
    }

    func testTheWindowGoesAfterTheLastReading() async throws {
        let r = reader(linger: 0)
        r.arrived(reply("A"))
        await settle()
        finishers[0]()
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(dismissals, 1)
    }

    func testTheWindowStaysWhileTheUserListensAgainInIt() async throws {
        let r = reader(linger: 0)
        r.arrived(reply("A"))
        await settle()
        windowReading = true
        finishers[0]()
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(dismissals, 0)
    }

    func testListeningAgainPlaysTheLastEvenWhereItWouldNotBeRead() async throws {
        speakable = false
        let r = reader()
        r.arrived(reply("Bitti."))
        r.listenAgain()
        await settle()
        XCTAssertEqual(shown, ["Bitti."])
        try prompt(session: "s1", at: 5)
        r.look()
        XCTAssertEqual(dismissals, 0, "asked for: a prompt since does not end it")
    }

    func testTurningItOffEndsTheReading() async {
        let r = reader()
        r.arrived(reply("A", session: "a"))
        r.arrived(reply("B", session: "b", at: 1))
        await settle()
        r.settingChanged()
        XCTAssertEqual(dismissals, 0, "still on")
        config.readClaudeReplies = false
        r.settingChanged()
        XCTAssertEqual(dismissals, 1)
        r.look()
        await settle()
        XCTAssertEqual(shown, ["A"])
    }

    func testTheInboxIsReadThroughToTheWindow() async throws {
        let r = reader()
        try ClaudeReplyInbox.put(reply("Dosyadan"), paths: paths)
        r.takeReplies()
        await settle()
        XCTAssertEqual(shown, ["Dosyadan"])
    }

    func testTheKernelReportsANewReply() async throws {
        let r = reader()
        r.start()
        try ClaudeReplyInbox.put(reply("Bitti."), paths: paths)
        for _ in 0..<100 where shown.isEmpty {
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertEqual(shown, ["Bitti."])
    }
}

final class ClaudeReplySettingTests: XCTestCase {
    func testOffByDefaultAndInAConfigWithoutTheKey() throws {
        XCTAssertFalse(Config().readClaudeReplies)
        let decoded = try JSONDecoder().decode(Config.self, from: Data("{}".utf8))
        XCTAssertFalse(decoded.readClaudeReplies)
    }

    func testTheSettingSurvivesSavingAndLoading() throws {
        var config = Config()
        config.readClaudeReplies = true
        let decoded = try JSONDecoder().decode(Config.self, from: JSONEncoder().encode(config))
        XCTAssertTrue(decoded.readClaudeReplies)
    }

    private func items(hasReply: Bool = false, readReplies: Bool? = nil) -> [StatusMenu.Item] {
        StatusMenu.items(sessionActive: false, sleepHeld: false, hasReply: hasReply, readReplies: readReplies, machine: nil, actions: nil, throttledBrowsers: [], error: nil)
    }

    func testTheMenuOffersTheLastReplyOnlyWhenThereIsOne() {
        XCTAssertTrue(items(hasReply: true).contains { $0.kind == .listenToReply && $0.title == StatusMenu.listenToReplyTitle })
        XCTAssertFalse(items().contains { $0.kind == .listenToReply })
    }

    func testTheMenuTogglesReadingAndShowsWhichWayItIs() {
        XCTAssertTrue(items(readReplies: true).contains { $0.kind == .readReplies(on: true) && $0.title == StatusMenu.readRepliesTitle })
        XCTAssertTrue(items(readReplies: false).contains { $0.kind == .readReplies(on: false) })
        XCTAssertFalse(items().contains { $0.title == StatusMenu.readRepliesTitle }, "no hooks: nothing to turn on")
    }
}

@MainActor
final class SummaryPlayerParagraphTests: XCTestCase {
    func testParagraphsAreTheLinesThatHaveText() {
        let text = "Bir iki.\n\nÜç dört.\nBeş"
        let ranges = SummaryPlayer.paragraphs(in: text).map { (text as NSString).substring(with: $0) }
        XCTAssertEqual(ranges, ["Bir iki.", "Üç dört.", "Beş"])
    }

    func testTheWordIsMarkedInItsOwnParagraph() {
        let player = SummaryPlayer(text: "Bir iki üç.\nDört beş altı yedi.", voiceIdentifier: nil)
        XCTAssertNil(player.currentParagraph)
        player.forward()
        XCTAssertEqual(player.currentWord, 5)
        XCTAssertEqual(player.currentParagraph, 1)
        func marked(_ paragraph: Int) -> [String] {
            let text = player.highlighted(paragraph: paragraph)
            return text.runs.filter { $0.backgroundColor != nil }.map { String(text[$0.range].characters) }
        }
        XCTAssertEqual(marked(0), [])
        XCTAssertEqual(marked(1), ["altı"])
    }

    func testOnlyALongTextScrolls() {
        XCTAssertFalse(SummaryPlayerView.needsScrolling("Kısa bir özet.", paragraphs: 1))
        let long = Array(repeating: "Claude uzun bir yanıt yazdı ve bu yanıt pencereye sığmayacak kadar uzun oldu.", count: 40).joined(separator: "\n")
        XCTAssertTrue(SummaryPlayerView.needsScrolling(long, paragraphs: 40))
    }
}
