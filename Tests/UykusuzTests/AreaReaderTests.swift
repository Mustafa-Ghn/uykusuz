import AppKit
import Carbon.HIToolbox
import XCTest
@testable import Uykusuz

@MainActor
final class AreaReaderTests: XCTestCase {
    private struct CaptureFailed: Error {}

    private var config = Config()
    private var granted = true
    private var asks = 0
    private var draws = 0
    private var gaveUp = 0
    private var answer: Result<String?, Error> = .success("Okunacak yazı.")
    /// Set: drawing stays open until `giveUp` or the test ends it.
    private var drawingStaysOpen = false
    private var drawing: CheckedContinuation<String?, Error>?
    private var shown: [String] = []
    private var autoplays: [Bool] = []
    private var finishers: [@MainActor () -> Void] = []
    private var closers: [@MainActor () -> Void] = []
    private var dismissals = 0
    private var windowReading = false
    private var shortcutCalls: [Bool] = []
    private var shortcutFree = true

    private func reader(linger: TimeInterval = 60) -> AreaReader {
        AreaReader(
            config: { [unowned self] in self.config },
            hasPermission: { [unowned self] in self.granted },
            askPermission: { [unowned self] in self.asks += 1 },
            read: { [unowned self] in
                self.draws += 1
                if self.drawingStaysOpen {
                    return try await withCheckedThrowingContinuation { self.drawing = $0 }
                }
                return try self.answer.get()
            },
            giveUp: { [unowned self] in
                self.gaveUp += 1
                self.drawing?.resume(returning: nil)
                self.drawing = nil
            },
            present: { [unowned self] text, autoplay, onFinish, onClose in
                // As the window does: a new one closes the one before.
                self.closers.last?()
                self.shown.append(text)
                self.autoplays.append(autoplay)
                self.finishers.append(onFinish)
                self.closers.append(onClose)
            },
            dismiss: { [unowned self] in
                self.dismissals += 1
                self.closers.last?()
            },
            windowIsReading: { [unowned self] in self.windowReading },
            setShortcut: { [unowned self] on in
                self.shortcutCalls.append(on)
                return !on || self.shortcutFree
            },
            linger: linger
        )
    }

    private func settle() async {
        for _ in 0..<5 { await Task.yield() }
    }

    func testNothingLooksAtTheScreenUntilAsked() async {
        let r = reader()
        r.start()
        await settle()
        XCTAssertEqual(draws, 0)
        XCTAssertEqual(shown, [])
    }

    func testAPressDrawsAndReadsWhatTheAreaSays() async {
        let r = reader()
        await r.listen()
        XCTAssertEqual(draws, 1)
        XCTAssertEqual(shown, ["Okunacak yazı."])
        XCTAssertEqual(autoplays, [true], "the press asked for the sound")
    }

    func testGivingUpReadsNothing() async {
        answer = .success(nil)
        let r = reader()
        await r.listen()
        XCTAssertEqual(draws, 1)
        XCTAssertEqual(shown, [])
    }

    func testAnAreaWithNoTextSaysSo() async {
        answer = .success("")
        let r = reader()
        await r.listen()
        XCTAssertEqual(shown, [AreaReader.nothingToRead])
    }

    func testAPictureThatCannotBeHadSaysSo() async {
        answer = .failure(CaptureFailed())
        let r = reader()
        await r.listen()
        XCTAssertEqual(shown, [AreaReader.unreadable])
    }

    func testWithoutThePermissionItAsksAndDrawsNothing() async {
        granted = false
        let r = reader()
        await r.listen()
        XCTAssertEqual(asks, 1)
        XCTAssertEqual(draws, 0)
        XCTAssertEqual(shown, [AreaReader.needsPermission])
        XCTAssertEqual(autoplays, [false], "the way out is to be read, not heard over the Settings window")
    }

    func testAPressWhileDrawingGivesUp() async {
        drawingStaysOpen = true
        let r = reader()
        let first = Task { await r.listen() }
        await settle()
        XCTAssertEqual(draws, 1)
        await r.listen()
        XCTAssertEqual(gaveUp, 1)
        await first.value
        XCTAssertEqual(draws, 1, "the second press draws nothing of its own")
        XCTAssertEqual(shown, [])
    }

    func testDrawingCanStartAgainAfterGivingUp() async {
        drawingStaysOpen = true
        let r = reader()
        let first = Task { await r.listen() }
        await settle()
        await r.listen()
        await first.value
        drawingStaysOpen = false
        await r.listen()
        XCTAssertEqual(draws, 2)
        XCTAssertEqual(shown, ["Okunacak yazı."])
    }

    func testAPressDuringItsReadingEndsIt() async {
        let r = reader()
        await r.listen()
        windowReading = true
        await r.listen()
        XCTAssertEqual(dismissals, 1)
        XCTAssertEqual(draws, 1)
    }

    func testAPressDuringAnotherReadingDrawsAndReplacesIt() async {
        windowReading = true
        let r = reader()
        await r.listen()
        XCTAssertEqual(dismissals, 0, "Claude's reply is not this reader's to end")
        XCTAssertEqual(draws, 1)
        XCTAssertEqual(shown, ["Okunacak yazı."])
    }

    func testAPressOnceTheWindowHasBeenReplacedDraws() async {
        let r = reader()
        await r.listen()
        // Claude's reply took the window.
        closers[0]()
        windowReading = true
        await r.listen()
        XCTAssertEqual(dismissals, 0)
        XCTAssertEqual(draws, 2)
    }

    func testAPressAfterTheEndDrawsAgain() async {
        let r = reader()
        await r.listen()
        finishers[0]()
        await r.listen()
        XCTAssertEqual(draws, 2)
        XCTAssertEqual(dismissals, 0)
    }

    func testTheWindowGoesAWhileAfterTheEnd() async throws {
        let r = reader(linger: 0.01)
        await r.listen()
        finishers[0]()
        for _ in 0..<200 where dismissals == 0 {
            try await Task.sleep(for: .milliseconds(5))
        }
        XCTAssertEqual(dismissals, 1)
    }

    func testTheWindowStaysIfAnotherAreaIsBeingRead() async throws {
        let r = reader(linger: 0.01)
        await r.listen()
        finishers[0]()
        await r.listen()
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(dismissals, 0)
    }

    func testTheSettingTakesAndGivesUpTheShortcut() {
        let r = reader()
        r.start()
        XCTAssertEqual(shortcutCalls, [true])
        XCTAssertFalse(r.shortcutTaken)
        config.listenAreaShortcut = false
        r.settingChanged()
        XCTAssertEqual(shortcutCalls, [true, false])
    }

    func testAShortcutAnotherAppHoldsIsReported() {
        shortcutFree = false
        let r = reader()
        r.start()
        XCTAssertTrue(r.shortcutTaken)
        config.listenAreaShortcut = false
        r.settingChanged()
        XCTAssertFalse(r.shortcutTaken, "off: nothing to report")
    }
}

final class AreaSettingTests: XCTestCase {
    func testOnByDefaultAndInAConfigWithoutTheKey() throws {
        XCTAssertTrue(Config().listenAreaShortcut)
        XCTAssertTrue(try JSONDecoder().decode(Config.self, from: Data("{}".utf8)).listenAreaShortcut)
    }

    func testTheSettingSurvivesSavingAndLoading() throws {
        var config = Config()
        config.listenAreaShortcut = false
        XCTAssertFalse(try JSONDecoder().decode(Config.self, from: JSONEncoder().encode(config)).listenAreaShortcut)
    }

    private func items(listenAreaShortcut: Bool? = nil) -> [StatusMenu.Item] {
        StatusMenu.items(sessionActive: false, sleepHeld: false, listenAreaShortcut: listenAreaShortcut, machine: nil, actions: nil, throttledBrowsers: [], error: nil)
    }

    func testTheMenuOffersAnAreaAndSaysWhetherTheShortcutIsOn() {
        XCTAssertTrue(items(listenAreaShortcut: true).contains { $0.kind == .listenToArea(shortcut: true) && $0.title == StatusMenu.listenToAreaTitle })
        XCTAssertTrue(items(listenAreaShortcut: false).contains { $0.kind == .listenToArea(shortcut: false) })
        XCTAssertFalse(items().contains { $0.title == StatusMenu.listenToAreaTitle })
    }

    @MainActor
    func testTheMenuItemShowsTheShortcutOnlyWhileItIsOn() {
        func entry(_ on: Bool) -> NSMenuItem? {
            let selector = #selector(NSObject.description)
            return StatusMenu.menu(
                items(listenAreaShortcut: on),
                target: nil,
                settings: selector,
                quit: selector,
                relaunchBrowser: selector,
                stopWaitingForOutput: selector,
                listenToArea: selector
            ).items.first { $0.title == StatusMenu.listenToAreaTitle }
        }
        XCTAssertEqual(entry(true)?.keyEquivalent, "s")
        XCTAssertEqual(entry(true)?.keyEquivalentModifierMask, [.control, .option])
        XCTAssertEqual(entry(false)?.keyEquivalent, "")
    }
}

@MainActor
final class ScreenTextTests: XCTestCase {
    func testAParagraphsLinesAreOneLine() {
        XCTAssertEqual(ScreenText.speech([["Bir iki", "üç dört."], ["Beş altı."]]), "Bir iki üç dört.\nBeş altı.")
    }

    func testAWordCutAtTheEndOfALineIsOneWord() {
        XCTAssertEqual(ScreenText.speech([["Bu da okunabi-", "lir bir satır."]]), "Bu da okunabilir bir satır.")
    }

    func testAHyphenBeforeACapitalStays() {
        XCTAssertEqual(ScreenText.speech([["Ankara-", "İstanbul hattı."]]), "Ankara- İstanbul hattı.")
    }

    func testListMarksAreNotRead() {
        XCTAssertEqual(ScreenText.speech([["• Pil düştü"], ["•Sürüm çıktı"], ["- Bitti"]]), "Pil düştü.\nSürüm çıktı.\nBitti.")
    }

    func testAddressesAndPathsAreNotSpelledOut() {
        XCTAssertEqual(
            ScreenText.speech([["Bakın https://example.com/a?b=1 ve Sources/Uykusuz/main.swift dosyası."]]),
            "Bakın bağlantı ve main.swift dosyası."
        )
    }

    func testNoTextIsNoText() {
        XCTAssertEqual(ScreenText.speech([]), "")
        XCTAssertEqual(ScreenText.speech([[], ["  "]]), "")
    }

    func testOnlyALineTheEdgeRunsThroughAndVisionDoubtsIsCut() {
        XCTAssertTrue(ScreenText.isCut(top: 0, bottom: 0.8, confidence: 0.73))
        XCTAssertTrue(ScreenText.isCut(top: 0.8, bottom: 0.002, confidence: 0.5))
        XCTAssertFalse(ScreenText.isCut(top: 0, bottom: 0.8, confidence: 1), "a tightly drawn area touches whole lines")
        XCTAssertFalse(ScreenText.isCut(top: 0.76, bottom: 0.025, confidence: 0.28), "Vision is unsure of whole lines too")
    }

    /// Vision itself, on a picture of the kind the screen gives.
    func testTurkishOnADarkWindowIsRead() async throws {
        let body = NSFont.systemFont(ofSize: 14)
        let picture = try XCTUnwrap(Self.picture(width: 620, dark: true, paragraphs: [
            ("Kurulum notları", NSFont.boldSystemFont(ofSize: 18)),
            ("README dosyasını güncelledim, API anahtarı artık Keychain'den okunuyor ve günlüğe hiçbir şey yazılmıyor. Çığ düşmüş, ağaçlar eğilmişti. Işıklar söndüğünde köyde üşüyen çocuklar şöminenin önünde toplandı.", body),
            ("• Pil yüzde 18'e düştü", body),
            ("• Sürüm 0.10.4 yayımlandı", body),
        ]))
        let text = try await ScreenText.read(picture)
        let lines = text.components(separatedBy: "\n")
        XCTAssertEqual(lines.first, "Kurulum notları", text)
        XCTAssertTrue(text.contains("Çığ düşmüş, ağaçlar eğilmişti. Işıklar söndüğünde köyde üşüyen çocuklar şöminenin önünde toplandı."), text)
        XCTAssertTrue(lines.contains("Pil yüzde 18'e düştü."), text)
        XCTAssertTrue(lines.contains("Sürüm 0.10.4 yayımlandı."), text)
        XCTAssertFalse(text.contains("•"), text)
    }

    func testAPictureWithNoTextIsNoText() async throws {
        let picture = try XCTUnwrap(Self.picture(width: 200, dark: true, paragraphs: []))
        let text = try await ScreenText.read(picture)
        XCTAssertEqual(text, "")
    }

    private static func picture(width: CGFloat, dark: Bool, paragraphs: [(String, NSFont)]) -> CGImage? {
        let string = NSMutableAttributedString()
        for (text, font) in paragraphs {
            let style = NSMutableParagraphStyle()
            style.paragraphSpacing = 10
            string.append(NSAttributedString(string: text + "\n", attributes: [.font: font, .foregroundColor: dark ? NSColor.white : NSColor.black, .paragraphStyle: style]))
        }
        let bounds = string.boundingRect(with: NSSize(width: width, height: 4000), options: [.usesLineFragmentOrigin, .usesFontLeading])
        let size = NSSize(width: width + 40, height: bounds.height + 40)
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * 2), pixelsHigh: Int(size.height * 2), bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
        rep.size = size
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        (dark ? NSColor(white: 0.13, alpha: 1) : NSColor.white).setFill()
        NSRect(origin: .zero, size: size).fill()
        string.draw(with: NSRect(x: 20, y: 20, width: width, height: bounds.height), options: [.usesLineFragmentOrigin, .usesFontLeading])
        NSGraphicsContext.restoreGraphicsState()
        return rep.cgImage
    }
}

@MainActor
final class AreaViewTests: XCTestCase {
    private func mouse(_ type: NSEvent.EventType, _ x: CGFloat, _ y: CGFloat) -> NSEvent {
        NSEvent.mouseEvent(with: type, location: NSPoint(x: x, y: y), modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
    }

    private func view() -> (AreaView, () -> [CGRect?]) {
        var done: [CGRect?] = []
        let view = AreaView(frame: CGRect(x: 0, y: 0, width: 800, height: 600))
        view.onDone = { done.append($0) }
        return (view, { done })
    }

    func testADragIsTheAreaWhicheverWayItIsDrawn() {
        let (view, done) = view()
        view.mouseDown(with: mouse(.leftMouseDown, 300, 400))
        view.mouseDragged(with: mouse(.leftMouseDragged, 200, 350))
        view.mouseUp(with: mouse(.leftMouseUp, 100, 300))
        XCTAssertEqual(done(), [CGRect(x: 100, y: 300, width: 200, height: 100)])
    }

    func testTheAreaIsCountedFromItsDisplaysTopLeft() {
        XCTAssertEqual(
            AreaView.fromTopLeft(CGRect(x: 100, y: 700, width: 200, height: 100), height: 900),
            CGRect(x: 100, y: 100, width: 200, height: 100)
        )
    }

    func testASlipOfTheMouseIsNoArea() {
        let (view, done) = view()
        view.mouseDown(with: mouse(.leftMouseDown, 300, 400))
        view.mouseUp(with: mouse(.leftMouseUp, 303, 402))
        XCTAssertEqual(done(), [nil])
    }

    func testEscGivesUp() throws {
        let (view, done) = view()
        let esc = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil, characters: "\u{1B}", charactersIgnoringModifiers: "\u{1B}", isARepeat: false, keyCode: UInt16(kVK_Escape)))
        view.keyDown(with: esc)
        XCTAssertEqual(done(), [nil])
    }

    func testGivingUpWithNothingOpenDoesNothing() {
        AreaPicker().cancel()
    }
}

@MainActor
final class GlobalHotKeySeparationTests: XCTestCase {
    /// As the system tells the app of a press.
    private func press(_ hotKey: GlobalHotKey) throws {
        var event: EventRef?
        XCTAssertEqual(CreateEvent(nil, OSType(kEventClassKeyboard), UInt32(kEventHotKeyPressed), 0, EventAttributes(kEventAttributeNone), &event), noErr)
        let made = try XCTUnwrap(event)
        defer { ReleaseEvent(made) }
        var id = hotKey.hotKeyID
        XCTAssertEqual(SetEventParameter(made, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), MemoryLayout<EventHotKeyID>.size, &id), noErr)
        XCTAssertEqual(SendEventToEventTarget(made, GetApplicationEventTarget()), noErr)
    }

    func testEachShortcutHearsOnlyItsOwnPress() throws {
        _ = NSApplication.shared
        // F19 and F20 with three modifiers, so they never meet the running app's.
        let first = GlobalHotKey(keyCode: kVK_F19, modifiers: controlKey | optionKey | shiftKey)
        let second = GlobalHotKey(keyCode: kVK_F20, modifiers: controlKey | optionKey | shiftKey)
        var heard: [String] = []
        first.onPress = { heard.append("first") }
        second.onPress = { heard.append("second") }
        XCTAssertTrue(first.set(true))
        XCTAssertTrue(second.set(true))
        defer {
            _ = first.set(false)
            _ = second.set(false)
        }
        try press(first)
        XCTAssertEqual(heard, ["first"])
        try press(second)
        XCTAssertEqual(heard, ["first", "second"])
    }

    func testAShortcutThatIsGoneLeavesTheOtherWorking() throws {
        _ = NSApplication.shared
        let kept = GlobalHotKey(keyCode: kVK_F19, modifiers: controlKey | optionKey | shiftKey)
        var heard = 0
        kept.onPress = { heard += 1 }
        XCTAssertTrue(kept.set(true))
        defer { _ = kept.set(false) }
        do {
            let gone = GlobalHotKey(keyCode: kVK_F20, modifiers: controlKey | optionKey | shiftKey)
            XCTAssertTrue(gone.set(true))
        }
        try press(kept)
        XCTAssertEqual(heard, 1)
    }

    func testPressesOfAShortcutTurnedOffAreNotHeard() throws {
        _ = NSApplication.shared
        let hotKey = GlobalHotKey(keyCode: kVK_F19, modifiers: controlKey | optionKey | shiftKey)
        var heard = 0
        hotKey.onPress = { heard += 1 }
        XCTAssertTrue(hotKey.set(true))
        XCTAssertTrue(hotKey.set(false))
        XCTAssertEqual(heard, 0)
    }
}
