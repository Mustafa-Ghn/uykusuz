import Carbon.HIToolbox
import XCTest
@testable import Uykusuz

final class ClaudeChatsTests: XCTestCase {
    private var root: URL!
    private var sessions: URL { root.appendingPathComponent("claude-code-sessions", isDirectory: true) }
    private var projects: URL { root.appendingPathComponent("projects", isDirectory: true) }
    private let fm = FileManager.default

    override func setUpWithError() throws {
        root = fm.temporaryDirectory.appendingPathComponent("uykusuz-chats-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? fm.removeItem(at: root)
    }

    private func record(_ name: String, session: String?, focus: Double?, account: String = "hesap") throws {
        let dir = sessions.appendingPathComponent("\(account)/kurum", isDirectory: true)
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        var object: [String: Any] = ["title": "yok sayılır"]
        if let session { object["cliSessionId"] = session }
        if let focus { object["lastFocusedAt"] = focus }
        try JSONSerialization.data(withJSONObject: object).write(to: dir.appendingPathComponent("local_\(name).json"))
    }

    @discardableResult
    private func transcript(_ session: String, folder: String = "-Users-me-proje", lines: [String]) throws -> URL {
        let dir = projects.appendingPathComponent(folder, isDirectory: true)
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent("\(session).jsonl")
        try lines.joined(separator: "\n").write(to: file, atomically: true, encoding: .utf8)
        return file
    }

    private func said(_ text: String, id: String = "m1", extra: String = "") -> String {
        let quoted = String(decoding: try! JSONSerialization.data(withJSONObject: [text], options: .fragmentsAllowed), as: UTF8.self).dropFirst().dropLast()
        return #"{"type":"assistant","timestamp":"2026-10-31T10:00:00Z","cwd":"/Users/me/proje"\#(extra),"message":{"id":"\#(id)","model":"claude","content":[{"type":"text","text":\#(quoted)}]}}"#
    }

    private func ran(id: String) -> String {
        #"{"type":"assistant","message":{"id":"\#(id)","model":"claude","content":[{"type":"tool_use","name":"Bash","input":{}}]}}"#
    }

    private func thought(id: String) -> String {
        #"{"type":"assistant","message":{"id":"\#(id)","model":"claude","content":[{"type":"thinking","thinking":"gizli"}]}}"#
    }

    private let prompt = #"{"type":"user","message":{"role":"user","content":"yap"}}"#

    func testTheNewestFocusIsTheChatInFront() throws {
        try record("a", session: "eski", focus: 1_000)
        try record("b", session: "yeni", focus: 3_000, account: "baska")
        try record("c", session: "orta", focus: 2_000)
        try record("d", session: "odaksiz", focus: nil)
        try record("e", session: nil, focus: 9_000)
        XCTAssertEqual(ClaudeChats.focusedSession(in: sessions), "yeni")
    }

    func testARecordThatCannotBeReadIsPassedOver() throws {
        try record("a", session: "iyi", focus: 1_000)
        let broken = sessions.appendingPathComponent("hesap/kurum/local_bozuk.json")
        try "{bozuk".write(to: broken, atomically: true, encoding: .utf8)
        XCTAssertEqual(ClaudeChats.focusedSession(in: sessions), "iyi")
    }

    func testOnlyTheLastMessageIsTakenNotTheStepsBeforeIt() throws {
        let file = try transcript("s1", lines: [
            prompt,
            said("ARA ADIM: komutu çalıştırıyorum.", id: "m1"),
            ran(id: "m1"),
            said("İKİNCİ ADIM: bakıyorum.", id: "m2"),
            ran(id: "m2"),
            thought(id: "m3"),
            said("Bitti, testler geçti.", id: "m3"),
        ])
        let reply = try XCTUnwrap(ClaudeChats.reply(in: file))
        XCTAssertEqual(reply.text, "Bitti, testler geçti.")
        XCTAssertEqual(reply.session, "s1")
        XCTAssertEqual(reply.title, "proje", "the folder, with no title in the transcript")
        XCTAssertEqual(reply.at, ClaudeDigest.timestamp("2026-10-31T10:00:00Z"))
    }

    func testAMessageOfSeveralBlocksIsReadWhole() throws {
        let file = try transcript("s1", lines: [said("Önceki.", id: "m1"), said("Birinci.", id: "m2"), said("İkinci.", id: "m2")])
        XCTAssertEqual(ClaudeChats.reply(in: file)?.text, "Birinci.\n\nİkinci.")
    }

    func testWhileClaudeWorksTheLastThingItSaidIsTaken() throws {
        let file = try transcript("s1", lines: [said("Başlıyorum.", id: "m1"), ran(id: "m1"), ran(id: "m2")])
        XCTAssertEqual(ClaudeChats.reply(in: file)?.text, "Başlıyorum.")
    }

    func testSubagentsAndWhatClaudeDidNotWriteAreLeftOut() throws {
        let synthetic = #"{"type":"assistant","message":{"id":"m3","model":"<synthetic>","content":[{"type":"text","text":"No response requested."}]}}"#
        let file = try transcript("s1", lines: [
            said("Asıl yanıt.", id: "m1"),
            said("Alt ajanın raporu.", id: "m2", extra: #","isSidechain":true"#),
            said("API hatası.", id: "m4", extra: #","isApiErrorMessage":true"#),
            synthetic,
        ])
        XCTAssertEqual(ClaudeChats.reply(in: file)?.text, "Asıl yanıt.")
    }

    func testTheTitleIsTheNewestOneInTheTranscript() throws {
        let title = { (name: String) in #"{"type":"custom-title","customTitle":"\#(name)"}"# }
        let file = try transcript("s1", lines: [title("Eski başlık"), said("Yanıt."), title("Yeni başlık"), prompt])
        XCTAssertEqual(ClaudeChats.reply(in: file)?.title, "Yeni başlık")
        let mentioned = try transcript("s2", lines: [#"{"type":"user","text":"customTitle geçen bir metin"}"#, said("Yanıt.")])
        XCTAssertEqual(ClaudeChats.reply(in: mentioned)?.title, "proje")
    }

    func testAChatWhereClaudeSaidNothingHasNoReply() throws {
        let file = try transcript("s1", lines: [prompt, ran(id: "m1")])
        XCTAssertNil(ClaudeChats.reply(in: file))
        XCTAssertNil(ClaudeChats.reply(in: root.appendingPathComponent("yok.jsonl")))
    }

    func testTheReplyComesFromTheChatInFrontNotTheNewestTranscript() throws {
        try record("a", session: "onde", focus: 2_000)
        try record("b", session: "arkada", focus: 1_000)
        try transcript("onde", lines: [said("Öndeki sohbet.")])
        try transcript("arkada", folder: "-Users-me-baska", lines: [said("Arkadaki sohbet.")])
        XCTAssertEqual(ClaudeChats.lastReply(sessions: sessions, projects: projects)?.text, "Öndeki sohbet.")
    }

    func testAChatInFrontWithNoTranscriptDoesNotReadAnother() throws {
        try record("a", session: "yeni-sohbet", focus: 2_000)
        try transcript("baska", lines: [said("Başka sohbet.")])
        XCTAssertNil(ClaudeChats.lastReply(sessions: sessions, projects: projects))
    }

    func testWithoutTheDesktopAppTheNewestTranscriptStandsIn() throws {
        let old = try transcript("eski", lines: [said("Eski.")])
        try fm.setAttributes([.modificationDate: Date(timeIntervalSinceNow: -600)], ofItemAtPath: old.path)
        try transcript("yeni", folder: "-Users-me-baska", lines: [said("Yeni.")])
        try transcript("agent-1", folder: "-Users-me-baska", lines: [said("Alt ajan.")])
        let agent = projects.appendingPathComponent("-Users-me-baska/agent-1.jsonl")
        try fm.setAttributes([.modificationDate: Date(timeIntervalSinceNow: 60)], ofItemAtPath: agent.path)
        XCTAssertEqual(ClaudeChats.lastReply(sessions: sessions, projects: projects)?.text, "Yeni.")
    }

    func testASessionIDThatIsNotOneGoesIntoNoPath() throws {
        try transcript("gizli", lines: [said("Okunmamalı.")])
        XCTAssertNil(ClaudeChats.transcript(of: "../-Users-me-proje/gizli", in: projects))
        XCTAssertNotNil(ClaudeChats.transcript(of: "gizli", in: projects))
    }

    func testTheCommandSaysWhatWouldBeRead() {
        XCTAssertNil(LastReplyCommand.run(["--resume-frozen"]))
        XCTAssertEqual(LastReplyCommand.run([LastReplyCommand.flag], find: { nil }), 0)
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
    final class Found: @unchecked Sendable { var reply: ClaudeReply? }

    private var root: URL!
    private var config = Config()
    private let found = Found()
    private var shown: [String] = []
    private var finishers: [@MainActor () -> Void] = []
    private var closers: [@MainActor () -> Void] = []
    private var dismissals = 0
    private var resumes = 0
    private var windowReading = false
    private var shortcutCalls: [Bool] = []
    private var shortcutFree = true
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    override func setUp() async throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("uykusuz-reader-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func reader(linger: TimeInterval = 60) -> ClaudeReplyReader {
        let found = found
        return ClaudeReplyReader(
            config: { [unowned self] in self.config },
            find: { found.reply },
            present: { [unowned self] reply, onFinish, onClose in
                // As the window does: a new one closes the one before.
                self.closers.last?()
                self.shown.append(reply.text)
                self.finishers.append(onFinish)
                self.closers.append(onClose)
            },
            dismiss: { [unowned self] in
                self.dismissals += 1
                self.closers.last?()
            },
            resume: { [unowned self] in self.resumes += 1 },
            windowIsReading: { [unowned self] in self.windowReading },
            setShortcut: { [unowned self] on in
                self.shortcutCalls.append(on)
                return !on || self.shortcutFree
            },
            paths: Paths(root: root),
            clock: { [unowned self] in self.t0 },
            linger: linger
        )
    }

    private func reply(_ text: String, session: String = "s1") -> ClaudeReply {
        ClaudeReply(session: session, title: "t", text: text, at: t0)
    }

    /// `present` runs in a task the reader starts.
    private func settle() async {
        for _ in 0..<5 { await Task.yield() }
    }

    private func press(_ r: ClaudeReplyReader) async {
        await r.listen()
        await settle()
    }

    func testNothingIsReadUntilAsked() async {
        found.reply = reply("Bitti.")
        let r = reader()
        r.start()
        await settle()
        XCTAssertEqual(shown, [])
    }

    func testAPressReadsTheChatInFront() async {
        found.reply = reply("Bitti.")
        let r = reader()
        await press(r)
        XCTAssertEqual(shown, ["Bitti."])
    }

    func testPressingAgainInTheSameChatEndsTheReading() async {
        found.reply = reply("Bitti.")
        let r = reader()
        await press(r)
        windowReading = true
        await press(r)
        XCTAssertEqual(shown, ["Bitti."])
        XCTAssertEqual(dismissals, 1)
        windowReading = false
        await press(r)
        XCTAssertEqual(shown, ["Bitti.", "Bitti."], "closed: the next press reads it from the start")
    }

    func testPressingOnAPausedOrFinishedWindowGoesOn() async {
        found.reply = reply("Bitti.")
        let r = reader()
        await press(r)
        windowReading = false
        await press(r)
        XCTAssertEqual(resumes, 1)
        XCTAssertEqual(dismissals, 0)
        XCTAssertEqual(shown, ["Bitti."])
    }

    func testAPressInAnotherChatReadsThatInstead() async {
        found.reply = reply("Birinci.", session: "a")
        let r = reader()
        await press(r)
        windowReading = true
        found.reply = reply("İkinci.", session: "b")
        await press(r)
        XCTAssertEqual(shown, ["Birinci.", "İkinci."])
        XCTAssertEqual(dismissals, 0)
    }

    func testAPressAfterClaudeSaidSomethingNewReadsThat() async {
        found.reply = reply("Birinci.")
        let r = reader()
        await press(r)
        windowReading = true
        found.reply = reply("Yeni yanıt.")
        await press(r)
        XCTAssertEqual(shown, ["Birinci.", "Yeni yanıt."])
    }

    func testReplacingTheWindowDoesNotCountAsTheUserClosingIt() async {
        found.reply = reply("Birinci.", session: "a")
        let r = reader()
        await press(r)
        found.reply = reply("İkinci.", session: "b")
        await press(r)
        windowReading = true
        await press(r)
        XCTAssertEqual(dismissals, 1, "the second window is still known as up")
        XCTAssertEqual(shown, ["Birinci.", "İkinci."])
    }

    func testWithNoReplyItSaysSo() async {
        found.reply = nil
        let r = reader()
        await press(r)
        XCTAssertEqual(shown, [ClaudeReplyReader.nothingToRead])
    }

    func testAReplyWithNothingToSayCountsAsNone() async {
        found.reply = reply("---")
        let r = reader()
        await press(r)
        XCTAssertEqual(shown, [ClaudeReplyReader.nothingToRead])
    }

    func testTheWindowGoesAfterTheReading() async throws {
        found.reply = reply("A")
        let r = reader(linger: 0)
        await press(r)
        finishers[0]()
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(dismissals, 1)
    }

    func testTheWindowStaysWhileTheUserListensAgainInIt() async throws {
        found.reply = reply("A")
        let r = reader(linger: 0)
        await press(r)
        windowReading = true
        finishers[0]()
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(dismissals, 0)
    }

    func testAFinishFromAWindowAlreadyGoneChangesNothing() async throws {
        found.reply = reply("A", session: "a")
        let r = reader(linger: 0)
        await press(r)
        found.reply = reply("B", session: "b")
        await press(r)
        finishers[0]()
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(dismissals, 0)
    }

    func testTheSettingTakesAndGivesUpTheShortcut() {
        let r = reader()
        r.start()
        XCTAssertEqual(shortcutCalls, [true])
        XCTAssertFalse(r.shortcutTaken)
        config.listenShortcut = false
        r.settingChanged()
        XCTAssertEqual(shortcutCalls, [true, false])
    }

    func testAShortcutAnotherAppHoldsIsReported() {
        shortcutFree = false
        let r = reader()
        r.start()
        XCTAssertTrue(r.shortcutTaken)
        config.listenShortcut = false
        r.settingChanged()
        XCTAssertFalse(r.shortcutTaken, "off: nothing to report")
    }

    func testStartRemovesWhatEarlierBuildsLeft() throws {
        let leftover = Paths(root: root).appSupport.appendingPathComponent("claude-replies", isDirectory: true)
        try FileManager.default.createDirectory(at: leftover, withIntermediateDirectories: true)
        try "{}".write(to: leftover.appendingPathComponent("eski.json"), atomically: true, encoding: .utf8)
        reader().start()
        XCTAssertFalse(FileManager.default.fileExists(atPath: leftover.path))
    }
}

final class ClaudeReplySettingTests: XCTestCase {
    func testOnByDefaultAndInAConfigWithoutTheKey() throws {
        XCTAssertTrue(Config().listenShortcut)
        XCTAssertTrue(try JSONDecoder().decode(Config.self, from: Data("{}".utf8)).listenShortcut)
    }

    func testTheSettingSurvivesSavingAndLoading() throws {
        var config = Config()
        config.listenShortcut = false
        XCTAssertFalse(try JSONDecoder().decode(Config.self, from: JSONEncoder().encode(config)).listenShortcut)
    }

    private func items(listenShortcut: Bool? = nil) -> [StatusMenu.Item] {
        StatusMenu.items(sessionActive: false, sleepHeld: false, listenShortcut: listenShortcut, machine: nil, actions: nil, throttledBrowsers: [], error: nil)
    }

    func testTheMenuOffersTheLastReplyAndSaysWhetherTheShortcutIsOn() {
        XCTAssertTrue(items(listenShortcut: true).contains { $0.kind == .listenToReply(shortcut: true) && $0.title == StatusMenu.listenToReplyTitle })
        XCTAssertTrue(items(listenShortcut: false).contains { $0.kind == .listenToReply(shortcut: false) })
        XCTAssertFalse(items().contains { $0.title == StatusMenu.listenToReplyTitle })
    }

    @MainActor
    func testAShortcutCanBeTakenTwiceAndGivenUp() {
        // F20 with three modifiers, so it never meets the running app's.
        let hotKey = GlobalHotKey(keyCode: kVK_F20, modifiers: controlKey | optionKey | shiftKey)
        XCTAssertTrue(hotKey.set(true))
        XCTAssertTrue(hotKey.set(true))
        XCTAssertTrue(hotKey.set(false))
        XCTAssertTrue(hotKey.set(false))
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
