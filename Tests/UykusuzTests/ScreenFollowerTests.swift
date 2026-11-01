import AppKit
import SwiftUI
import XCTest
@testable import Uykusuz

final class WordAlignerTests: XCTestCase {
    private func words(_ text: String) -> [String] {
        text.split(separator: " ").map { WordAligner.fold(String($0)) }
    }

    func testAscreenWithOtherTextAroundItStillFindsEveryWord() {
        let found = WordAligner.align(
            reading: words("bugün sürümü yayımladım ve testleri çalıştırdım"),
            screen: words("Oturumlar Ayarlar bugün sürümü yayımladım ve testleri çalıştırdım Yanıtla")
        )
        XCTAssertEqual(found, [2, 3, 4, 5, 6, 7])
    }

    func testWordsScrolledAwayAreNotFound() {
        let found = WordAligner.align(
            reading: words("ilk cümle ekranın üstünde kaldı sonraki cümle ekranda görünüyor ve okunuyor"),
            screen: words("sonraki cümle ekranda görünüyor ve okunuyor")
        )
        XCTAssertEqual(Array(found.prefix(5)), [nil, nil, nil, nil, nil], "above the screen")
        XCTAssertEqual(Array(found.suffix(6)), [0, 1, 2, 3, 4, 5])
    }

    func testAWordMisreadBetweenGoodOnesStaysInPlace() {
        let found = WordAligner.align(
            reading: words("SwiftUI tarafındaki hatayı düzelttim ve testler geçti"),
            screen: words("SwiftUl tarafındaki hatayı düzeittim ve testler geçti")
        )
        XCTAssertEqual(found[1], 1)
        XCTAssertEqual(found[3], 3, "the word between two good ones")
    }

    func testAWordRecognizedAsTwoStaysAboutThere() {
        let found = WordAligner.align(
            reading: words("hatayı burada düzeltmiş olduk ve testler geçti"),
            screen: words("hatayı burada düzelt miş olduk ve testler geçti")
        )
        XCTAssertEqual(found[1], 1)
        XCTAssertEqual(found[2], 2)
        XCTAssertEqual(found[3], 4)
    }

    func testACodeBlockOnTheScreenIsStepped() {
        let code = (0..<30).map { "kod\($0)" }.joined(separator: " ")
        let found = WordAligner.align(
            reading: words("önce bunu çalıştırın lütfen Kod bloğu atlandı sonra bunu deneyin artık"),
            screen: words("önce bunu çalıştırın lütfen \(code) sonra bunu deneyin artık")
        )
        XCTAssertEqual(Array(found.prefix(4)), [0, 1, 2, 3])
        XCTAssertEqual(Array(found[4...6]), [nil, nil, nil], "its name is not on the screen")
        XCTAssertEqual(Array(found.suffix(4)), [34, 35, 36, 37])
    }

    func testWordsThatOnlyHappenToOccurDoNotCount() {
        let found = WordAligner.align(
            reading: words("bu bir deneme ve bu da ikinci bir deneme oldu"),
            screen: words("elma bir armut ve kiraz bu üzüm da incir oldu karpuz")
        )
        XCTAssertTrue(found.allSatisfy { $0 == nil }, "\(found)")
    }

    func testTheLaterOccurrenceWins() {
        let sentence = "aynı cümle sohbette iki kez geçiyor burada"
        let found = WordAligner.align(reading: words(sentence), screen: words("\(sentence) araya giren başka yazılar \(sentence)"))
        XCTAssertEqual(found.first, 11, "the last reply is at the bottom")
    }

    func testAShortTextHasToBeThereWhole() {
        XCTAssertEqual(WordAligner.align(reading: words("Tamam bitti"), screen: words("bir şey Tamam bitti diye")), [2, 3])
        XCTAssertEqual(WordAligner.align(reading: words("Tamam bitti"), screen: words("Tamam mı değil mi")), [nil, nil])
    }

    func testNoWordsNoPlaces() {
        XCTAssertEqual(WordAligner.align(reading: [], screen: words("bir şey")), [])
        XCTAssertEqual(WordAligner.align(reading: words("bir şey"), screen: []), [nil, nil])
    }

    func testRecognitionWithoutTurkishLettersAgrees() {
        for (written, recognized) in [("Düzelttim", "duzelttim"), ("IŞIK", "isik"), ("İstanbul", "Istanbul"), ("çığ", "cig"), ("öğleden", "ogleden")] {
            XCTAssertEqual(WordAligner.fold(written), WordAligner.fold(recognized), written)
        }
    }

    /// Thousands of words against a full screen.
    func testALongTextFindsThePartOnTheScreen() {
        let reading = (0..<4000).map { "kelime\($0)" }
        let found = WordAligner.align(reading: reading, screen: Array(reading[2000..<2900]))
        XCTAssertEqual(found.compactMap { $0 }.count, 900)
        XCTAssertEqual(found[3000], nil)
        XCTAssertEqual(found[2500], 500)
    }
}

final class ScreenFollowerPlaceTests: XCTestCase {
    private let a = CGRect(x: 10, y: 10, width: 20, height: 10)
    private let b = CGRect(x: 40, y: 10, width: 20, height: 10)

    func testAWordOnTheScreenHasItsPlace() {
        XCTAssertEqual(ScreenFollower.place(of: 2, in: [nil, nil, a, b, nil]), .marked(a))
        XCTAssertEqual(ScreenFollower.place(of: 3, in: [nil, nil, a, b, nil]), .marked(b))
    }

    func testAWordMissingBetweenOthersStaysOnTheOneBefore() {
        XCTAssertEqual(ScreenFollower.place(of: 2, in: [a, nil, nil, b]), .marked(a))
    }

    func testScrolledAwayWordsSayWhichWay() {
        XCTAssertEqual(ScreenFollower.place(of: 0, in: [nil, a, b, nil]), .above)
        XCTAssertEqual(ScreenFollower.place(of: 3, in: [nil, a, b, nil]), .below)
    }

    func testNoPlaceAtAllIsNowhere() {
        XCTAssertEqual(ScreenFollower.place(of: 0, in: [nil, nil]), .nowhere)
        XCTAssertEqual(ScreenFollower.place(of: 0, in: []), .nowhere)
    }
}

@MainActor
final class ScreenFollowerTests: XCTestCase {
    private final class Screen: @unchecked Sendable {
        var words: [ScreenWord] = []
        var fails = false
        var looks = 0
        var nears: [CGPoint?] = []
        /// Set: a look waits here until the test lets it go.
        var held: [CheckedContinuation<Void, Never>] = []
        var holds = false
    }

    private let screen = Screen()
    private var granted = true
    private var marks: [CGRect?] = []
    private var word: Int? = 0
    private var playing = true
    private var moved: (@MainActor (Bool) -> Void)?
    private var unwatched = 0
    private let reading = "bugün sürümü yayımladım ve testleri çalıştırdım hepsi geçti".split(separator: " ").map { WordAligner.fold(String($0)) }

    private func rect(_ index: Int, y: CGFloat = 100) -> CGRect {
        CGRect(x: CGFloat(index) * 50, y: y, width: 40, height: 14)
    }

    /// The words from `from` on are on the screen.
    private func show(from: Int = 0, to: Int? = nil, y: CGFloat = 100) {
        let last = to ?? reading.count - 1
        screen.words = (from...last).map { ScreenWord(text: reading[$0], rect: rect($0, y: y)) }
    }

    private func follower(interval: Duration = .seconds(60), settle: Duration = .milliseconds(1)) -> ScreenFollower {
        let screen = screen
        return ScreenFollower(
            reading: reading,
            hasPermission: { [unowned self] in self.granted },
            look: { near in
                screen.looks += 1
                screen.nears.append(near)
                if screen.holds { await withCheckedContinuation { screen.held.append($0) } }
                if screen.fails { throw CocoaError(.fileNoSuchFile) }
                return screen.words
            },
            mark: { [unowned self] in self.marks.append($0) },
            watch: { [unowned self] moved in
                self.moved = moved
                return { [unowned self] in self.unwatched += 1 }
            },
            word: { [unowned self] in self.word },
            isPlaying: { [unowned self] in self.playing },
            interval: interval,
            settle: settle
        )
    }

    private func until(_ condition: @MainActor () -> Bool, _ what: String = "") async throws {
        for _ in 0..<400 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(5))
        }
        XCTFail("never happened: \(what)")
    }

    func testTheWordIsMarkedOnTheScreenAndTheWindowHasNoText() async throws {
        show()
        word = 2
        let f = follower()
        XCTAssertFalse(f.textBelongsInWindow, "not while looking, or the window would jump")
        f.start()
        try await until({ f.place == .marked(rect(2)) })
        XCTAssertEqual(marks.last, rect(2))
        XCTAssertFalse(f.textBelongsInWindow)
        XCTAssertNil(f.note)
        f.stop()
    }

    func testTheMarkFollowsTheReading() async throws {
        show()
        let f = follower()
        f.start()
        try await until({ f.place == .marked(rect(0)) })
        word = 3
        f.readingChanged()
        XCTAssertEqual(marks.last, rect(3))
        f.stop()
    }

    func testWithoutThePermissionNothingLooksAndTheTextStaysInTheWindow() async throws {
        granted = false
        let f = follower()
        f.start()
        XCTAssertEqual(f.place, .noPermission)
        XCTAssertTrue(f.textBelongsInWindow)
        XCTAssertEqual(f.note, ScreenFollower.permissionNote)
        try await Task.sleep(for: .milliseconds(30))
        XCTAssertEqual(screen.looks, 0)
        XCTAssertNil(moved, "nothing listens either")
        f.stop()
    }

    func testATextThatIsNotOnTheScreenStaysInTheWindow() async throws {
        screen.words = [ScreenWord(text: "baska", rect: rect(0))]
        let f = follower()
        f.start()
        try await until({ f.place == .nowhere })
        XCTAssertTrue(f.textBelongsInWindow)
        XCTAssertEqual(f.note, ScreenFollower.nowhereNote)
        XCTAssertNil(marks.last ?? nil)
        f.stop()
    }

    func testALookThatFailsIsLikeNotFinding() async throws {
        screen.fails = true
        let f = follower()
        f.start()
        try await until({ f.place == .nowhere })
        XCTAssertTrue(f.textBelongsInWindow)
        f.stop()
    }

    func testAWordScrolledAwaySaysWhichWayAndTheTextComesBack() async throws {
        show(from: 2, to: 6)
        word = 0
        let f = follower()
        f.start()
        try await until({ f.place == .above })
        XCTAssertTrue(f.textBelongsInWindow)
        XCTAssertEqual(f.note, ScreenFollower.aboveNote)
        word = 7
        f.readingChanged()
        XCTAssertEqual(f.place, .below)
        XCTAssertEqual(f.note, ScreenFollower.belowNote)
        XCTAssertNil(marks.last ?? nil)
        f.stop()
    }

    func testScrollingTakesTheMarkOffAtOnceAndPutsItWhereTheWordWentTo() async throws {
        show()
        let f = follower()
        f.start()
        try await until({ f.place == .marked(rect(0)) })
        moved?(true)
        XCTAssertNil(marks.last ?? nil, "stale the moment the screen moves")
        XCTAssertEqual(f.place, .marked(rect(0)), "the window does not jump for a scroll")
        show(y: 300)
        try await until({ f.place == .marked(rect(0, y: 300)) })
        XCTAssertEqual(marks.last, rect(0, y: 300))
        f.stop()
    }

    func testTheMarkStaysHiddenWhileTheScreenIsStillMoving() async throws {
        show()
        let f = follower(settle: .seconds(60))
        f.start()
        try await until({ f.place == .marked(rect(0)) })
        moved?(true)
        word = 1
        f.readingChanged()
        XCTAssertNil(marks.last ?? nil)
        f.stop()
    }

    func testAClickLeavesTheMarkUntilTheNextLook() async throws {
        show()
        let f = follower()
        f.start()
        try await until({ f.place == .marked(rect(0)) })
        let looks = screen.looks
        moved?(false)
        XCTAssertEqual(marks.last, rect(0))
        try await until({ self.screen.looks > looks })
        f.stop()
    }

    func testOneMissedLookDoesNotChangeTheWindowButTwoDo() async throws {
        show()
        let f = follower()
        f.start()
        try await until({ f.place == .marked(rect(0)) })
        screen.words = []
        moved?(false)
        try await until({ self.marks.last == .some(nil) }, "the mark comes off")
        XCTAssertEqual(f.place, .marked(rect(0)), "one look can miss what is there")
        moved?(false)
        try await until({ f.place == .nowhere })
        XCTAssertTrue(f.textBelongsInWindow)
        f.stop()
    }

    func testAPictureTakenBeforeAScrollIsNotUsed() async throws {
        show()
        let f = follower()
        f.start()
        try await until({ f.place == .marked(rect(0)) })
        screen.holds = true
        let looks = screen.looks
        moved?(false)
        try await until({ self.screen.looks == looks + 1 })
        // The screen moves while that look is under way.
        moved?(true)
        try await Task.sleep(for: .milliseconds(10))
        show(y: 300)
        screen.holds = false
        for held in screen.held { held.resume() }
        screen.held = []
        try await until({ f.place == .marked(rect(0, y: 300)) })
        XCTAssertEqual(marks.last, rect(0, y: 300))
        f.stop()
    }

    func testItLooksEveryIntervalOnlyWhileReading() async throws {
        show()
        let f = follower(interval: .milliseconds(5))
        f.start()
        try await until({ self.screen.looks >= 3 })
        playing = false
        try await Task.sleep(for: .milliseconds(20))
        let paused = screen.looks
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertLessThanOrEqual(screen.looks, paused + 1, "a pause does not look")
        f.stop()
    }

    func testItLooksNearTheLastPlace() async throws {
        show()
        let f = follower()
        f.start()
        try await until({ f.place == .marked(rect(0)) })
        moved?(false)
        try await until({ self.screen.nears.count == 2 })
        XCTAssertNil(screen.nears[0], "every display at first")
        XCTAssertEqual(screen.nears[1], CGPoint(x: rect(0).midX, y: rect(0).midY))
        f.stop()
    }

    func testTheEndOfAReadingTakesTheMarkOff() async throws {
        show()
        let f = follower()
        f.start()
        try await until({ f.place == .marked(rect(0)) })
        word = nil
        f.readingChanged()
        XCTAssertNil(marks.last ?? nil)
        f.stop()
    }

    func testStoppingEndsEverything() async throws {
        show()
        let f = follower(interval: .milliseconds(5))
        f.start()
        try await until({ f.place == .marked(rect(0)) })
        f.stop()
        XCTAssertEqual(unwatched, 1)
        XCTAssertNil(marks.last ?? nil)
        try await Task.sleep(for: .milliseconds(20))
        let looks = screen.looks
        try await Task.sleep(for: .milliseconds(40))
        XCTAssertEqual(screen.looks, looks, "nothing looks at the screen after the window goes")
        marks = []
        word = 1
        f.readingChanged()
        XCTAssertEqual(marks, [], "and nothing is marked")
    }
}

final class ScreenWordsTests: XCTestCase {
    func testABoxInAPictureBecomesAPlaceOnTheScreen() {
        let main = CGRect(x: 0, y: 0, width: 1728, height: 1117)
        XCTAssertEqual(
            ScreenText.place(CGRect(x: 0.5, y: 0.25, width: 0.1, height: 0.02), in: main),
            CGRect(x: 864, y: 279.25, width: 172.8, height: 22.34)
        )
        // A second display to the left of the first and lower than it.
        let side = CGRect(x: -1920, y: -200, width: 1920, height: 1080)
        XCTAssertEqual(
            ScreenText.place(CGRect(x: 0.5, y: 0.5, width: 0.1, height: 0.1), in: side),
            CGRect(x: -960, y: 340, width: 192, height: 108)
        )
    }

    /// Recognition itself, on a picture of the kind the screen gives.
    @MainActor
    func testTurkishOnADarkWindowIsFoundWordByWordInItsPlace() throws {
        let text = "README dosyasını güncelledim, commit'i main dalına gönderdim. Çığ düşmüş, ağaçlar eğilmişti. Işıklar söndüğünde köyde üşüyen çocuklar şöminenin önünde toplandı. Öğleden sonra yağmur yağacakmış."
        let width: CGFloat = 620, height: CGFloat = 120
        let rep = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(width * 2), pixelsHigh: Int(height * 2), bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        rep.size = NSSize(width: width, height: height)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSColor(white: 0.13, alpha: 1).setFill()
        NSRect(x: 0, y: 0, width: width, height: height).fill()
        NSAttributedString(string: text, attributes: [.font: NSFont.systemFont(ofSize: 14), .foregroundColor: NSColor.white])
            .draw(with: NSRect(x: 20, y: 0, width: width - 40, height: height - 16), options: [.usesLineFragmentOrigin, .usesFontLeading])
        NSGraphicsContext.restoreGraphicsState()
        let image = try XCTUnwrap(rep.cgImage)

        let frame = CGRect(x: 100, y: 200, width: width, height: height)
        let words = try ScreenText.words(in: image, frame: frame)
        var reading: [String] = []
        text.enumerateSubstrings(in: text.startIndex..., options: .byWords) { word, _, _, _ in
            if let word { reading.append(WordAligner.fold(word)) }
        }
        let aligned = WordAligner.align(reading: reading, screen: words.map(\.text))
        XCTAssertGreaterThanOrEqual(aligned.compactMap { $0 }.count * 10, reading.count * 9, "\(words.map(\.text))")

        let first = try XCTUnwrap(aligned[0].map { words[$0] })
        XCTAssertEqual(first.text, "readme")
        XCTAssertEqual(first.rect.minX, frame.minX + 20, accuracy: 6, "the first word is at the left")
        XCTAssertEqual(first.rect.maxY, frame.maxY - 16, accuracy: 8, "and on the top line")
        XCTAssertLessThan(first.rect.height, 26)
        for word in words {
            XCTAssertTrue(frame.insetBy(dx: -2, dy: -2).contains(word.rect), "\(word)")
        }
    }

    func testAPictureWithNoTextHasNoWords() throws {
        let context = try XCTUnwrap(CGContext(data: nil, width: 400, height: 200, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(gray: 0.13, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 400, height: 200))
        let image = try XCTUnwrap(context.makeImage())
        XCTAssertEqual(try ScreenText.words(in: image, frame: CGRect(x: 0, y: 0, width: 200, height: 100)), [])
    }
}

@MainActor
final class SummaryPlayerChangeTests: XCTestCase {
    func testEachMoveSaysSo() {
        let player = SummaryPlayer(text: "Bir iki üç dört beş altı yedi sekiz.", voiceIdentifier: nil)
        var changes = 0
        player.onChange = { changes += 1 }
        player.forward()
        XCTAssertEqual(changes, 1)
        XCTAssertEqual(player.currentWord, SummaryPlayer.step)
    }

    func testTheWordsToMatchAreTheOnesTheWindowWouldMark() {
        let player = SummaryPlayer(text: "Işıklar söndü, README güncellendi.\nİkinci satır.", voiceIdentifier: nil)
        XCTAssertEqual(ScreenFollower.foldedWords(of: player), ["isiklar", "sondu", "readme", "guncellendi", "ikinci", "satir"])
    }
}

final class FollowSettingTests: XCTestCase {
    func testOnByDefaultAndInAConfigWithoutTheKey() throws {
        XCTAssertTrue(Config().followOnScreen)
        XCTAssertTrue(try JSONDecoder().decode(Config.self, from: Data("{}".utf8)).followOnScreen)
    }

    func testTheSettingSurvivesSavingAndLoading() throws {
        var config = Config()
        config.followOnScreen = false
        XCTAssertFalse(try JSONDecoder().decode(Config.self, from: JSONEncoder().encode(config)).followOnScreen)
    }
}

@MainActor
final class ReadingWindowLayoutTests: XCTestCase {
    private let text = "Yayın sırasında iki sürüm birlikte çalışır. Yeni sürüm açılırken eski sürüm hemen kapanmaz.\nAçık bağlantıları bitene kadar birkaç dakika yaşar."

    private func height(place: (@MainActor () -> [ScreenWord])?, word: Int? = 0) async throws -> CGFloat {
        let player = SummaryPlayer(text: text, voiceIdentifier: nil)
        var follower: ScreenFollower?
        if let place {
            let found = place()
            let made = ScreenFollower(
                reading: ScreenFollower.foldedWords(of: player),
                hasPermission: { true },
                look: { _ in found },
                mark: { _ in },
                watch: { _ in {} },
                word: { word },
                isPlaying: { false }
            )
            made.start()
            for _ in 0..<200 where made.place == .looking {
                try await Task.sleep(for: .milliseconds(2))
            }
            made.stop()
            follower = made
        }
        let view = SummaryPlayerView(player: player, title: "Başlık", told: "12:00", follower: follower, onClose: {})
        return NSHostingView(rootView: view).fittingSize.height
    }

    private func wordsOnScreen() -> [ScreenWord] {
        let player = SummaryPlayer(text: text, voiceIdentifier: nil)
        return ScreenFollower.foldedWords(of: player).enumerated().map { index, word in
            ScreenWord(text: word, rect: CGRect(x: CGFloat(index) * 50, y: 100, width: 40, height: 14))
        }
    }

    func testOnlyTheTitleAndTheControlsStayWhileTheWordIsMarkedOnTheScreen() async throws {
        let marked = try await height(place: { self.wordsOnScreen() })
        let whole = try await height(place: nil)
        XCTAssertLessThan(marked, whole - 30, "the text is gone from the window")
        XCTAssertLessThan(marked, 110)
    }

    func testTheTextComesBackWithANoteWhenItIsNotOnTheScreen() async throws {
        let away = try await height(place: { [] })
        let whole = try await height(place: nil)
        XCTAssertGreaterThan(away, whole, "the text, and a line saying why")
    }
}
