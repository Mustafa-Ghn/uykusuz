import XCTest
@testable import Uykusuz

private let voiceFolder = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    .appendingPathComponent("Resources/Voice", isDirectory: true)

final class SpokenTurkishTests: XCTestCase {
    private let front = SpokenTurkish()

    func testDeveloperWordsAreSaidTheTurkishWay() {
        XCTAssertEqual(
            front.spoken("README dosyasını güncelledim, commit'i main dalına push'ladım."),
            "ridmi dosyasını güncelledim, komiti meyn dalına puşladım."
        )
        XCTAssertEqual(
            front.spoken("SwiftUI tarafındaki hatayı düzelttim; API anahtarı artık Keychain'den okunuyor."),
            "Svift Yu Ay tarafındaki hatayı düzelttim; Ey Pi Ay anahtarı artık Kiçeynden okunuyor."
        )
        XCTAssertEqual(front.spoken("Claude Code hook'ları çalışıyor."), "Klod Kod hukları çalışıyor.")
        XCTAssertEqual(front.spoken("Mac'i kapat, iPhone'a bak."), "Meki kapat, Ayfona bak.")
    }

    func testASuffixFollowsTheNewSound() {
        XCTAssertEqual(front.spoken("API'leri"), "Ey Pi Ayları", "the back vowel of Ay")
        XCTAssertEqual(front.spoken("SDK'yı"), "Es Di Keyi", "no buffer y after a consonant")
        XCTAssertEqual(front.spoken("URL'yi"), "Yu Ar Eli")
        XCTAssertEqual(front.spoken("PR'a"), "Pi Ara")
        XCTAssertEqual(front.spoken("GitHub'a"), "Githaba")
        XCTAssertEqual(front.spoken("README'yi"), "ridmiyi", "a vowel keeps its buffer")
        XCTAssertEqual(SpokenTurkish.harmonize("ridmi", "e"), "ye", "a vowel needs one")
        XCTAssertEqual(SpokenTurkish.harmonize("ridmi", "in"), "nin")
        XCTAssertEqual(SpokenTurkish.harmonize("huk", "yor"), "yor", "fixed suffixes stay")
    }

    func testVerbsWithTurkishEndings() {
        XCTAssertEqual(front.spoken("Dosyayı pushladım, sonra commitledim ve mergeledim."), "Dosyayı puşladım, sonra komitledim ve mörçledim.")
    }

    /// These are all in the English dictionary and rare in Turkish text, which is
    /// why nothing converts on its own.
    func testTurkishWordsAreLeftAlone() {
        for text in [
            "Yarın sabah Ahmet'le test yapacağız; bu film çok güzel, bank kartını al.",
            "Pedal, zebra, magma, idol, kramp ve dogma burada yokum dedi; pille çalışan bir branda.",
            "Çığ düşmüş, ağaçlar eğilmişti. Işıklar söndüğünde köyde üşüyen çocuklar şöminenin önünde toplandı.",
        ] {
            XCTAssertEqual(front.spoken(text), text)
        }
    }

    func testSymbols() {
        XCTAssertEqual(front.spoken("Ayarlar > Uygulama bölümü."), "Ayarlar, Uygulama bölümü.")
        XCTAssertEqual(front.spoken("Bitti → sorun kalmadı."), "Bitti, sorun kalmadı.")
        XCTAssertEqual(front.spoken("Sen \"yokken\" özeti & mesaj."), "Sen yokken özeti ve mesaj.")
        XCTAssertEqual(front.spoken("~5 dakika sürer."), "yaklaşık 5 dakika sürer.")
        XCTAssertEqual(front.spoken("Sorun #12 kapandı."), "Sorun numara 12 kapandı.")
        XCTAssertEqual(front.spoken("Bir &amp; iki"), "Bir ve iki", "a stray entity")
    }

    func testKeyChordsAreSaidOnce() {
        XCTAssertEqual(front.spoken("Control+Option+D (⌃⌥D) tuşlarına basın."), "Kontrol Opşın de tuşlarına basın.")
        XCTAssertEqual(front.spoken("⌃⌥D kısayolu."), "Kontrol Opşın de kısayolu.")
    }

    func testCodeNames() {
        XCTAssertEqual(front.spoken("Süreyi okur (CGEventSource.secondsSinceLastEventType); bunun için."), "Süreyi okur; bunun için.", "a code name in brackets is not read")
        XCTAssertEqual(front.spoken("gizli (DERİ) ve özel (private) çerçeve."), "gizli, DERİ, ve özel, private, çerçeve.", "words in brackets are")
        XCTAssertEqual(front.spoken("swift test --filter komutu."), "svift test filtır komutu.")
        XCTAssertEqual(front.spoken("CHANGELOG.md dosyasına yazdım."), "çeync log nokta em di dosyasına yazdım.")
        XCTAssertEqual(front.spoken("Wi-Fi koparsa."), "Vayfay koparsa.", "one word, not two")
        XCTAssertEqual(front.spoken("Sürüm v0.9.2 çıktı."), "Sürüm 0.9.2 çıktı.", "the number rules read it")
        XCTAssertEqual(front.spoken("M5 Pro'da."), "Em 5 Pro'da.")
        XCTAssertEqual(front.spoken("İkincisi, E.Koli ise bulunur."), "İkincisi, E.Koli ise bulunur.", "an initial and a name, not code")
    }

    func testAddressesAreLeftToTheNumberRules() {
        XCTAssertEqual(front.spoken("Alanlar api.anthropic.com'a gider."), "Alanlar api.anthropic.com'a gider.")
    }

    func testCamelCaseUsesTheDictionary() {
        let dictionary = ["recovery": "rikavri", "tests": "tests", "player": "pleyır", "summary": "samıri"]
        let front = SpokenTurkish(english: { dictionary[$0] })
        XCTAssertEqual(front.spoken("ReleaseWorkflowTests geçti."), "riliz vörkflov tests geçti.")
        XCTAssertEqual(front.spoken("SummaryPlayer sınıfı."), "samıri pleyır sınıfı.")
        XCTAssertEqual(front.spoken("NWPathMonitor izler."), "En Dabılyu Path Monitor izler.", "a part the dictionary lacks stays as written")
        XCTAssertEqual(front.spoken("en az -72 dBm çeken."), "en az -72 di Bm çeken.", "a single letter by its name")
    }

    func testAllCapsWords() {
        let front = SpokenTurkish(capsWords: ["NASA", "ROMEO"])
        XCTAssertEqual(front.wordForm("NASA"), "nasa")
        XCTAssertEqual(front.wordForm("HOHENSCHONHAUSEN"), "hohenschonhausen", "too long to spell")
        XCTAssertEqual(front.wordForm("KIYAFETLER"), "kıyafetler", "Turkish lowercase")
        XCTAssertNil(front.wordForm("DNA"), "the number rules spell it")
    }
}

final class TurkishNumbersTests: XCTestCase {
    func testNumbersDatesAndSuffixes() throws {
        let numbers = try TurkishNumbers(script: voiceFolder.appendingPathComponent("trnorm.js"))
        XCTAssertEqual(numbers.normalize("Pil yüzde 18'e düştü, saat 14:30'da."), "Pil yüzde on sekize düştü, saat on dört otuzda.")
        XCTAssertEqual(numbers.normalize("Sürüm 0.9.2 çıktı."), "Sürüm sıfır nokta dokuz nokta iki çıktı.")
        XCTAssertEqual(numbers.normalize("Toplam 42 test, 3 dakika 15 saniye."), "Toplam kırk iki test, üç dakika on beş saniye.")
        XCTAssertEqual(numbers.normalize("12 MB ve %30'u."), "on iki megabayt ve yüzde otuzu.")
        XCTAssertEqual(numbers.normalize("Düz bir cümle."), "Düz bir cümle.")
    }
}

final class SpokenPiecesTests: XCTestCase {
    func testTheAlphabet() {
        XCTAssertEqual(SpokenPieces.alphabet("Işık İstanbul’da “Çığ” — é ❤ ß"), "ışık istanbul'da \"çığ\" - e")
        XCTAssertEqual(SpokenPieces.alphabet("  a   b\n c "), "a b c")
    }

    func testAShortTextIsOnePiece() {
        XCTAssertEqual(SpokenPieces.chunk("merhaba dünya"), [SpokenPiece(text: "merhaba dünya.", pause: 0)])
        XCTAssertEqual(SpokenPieces.chunk("nasılsın?"), [SpokenPiece(text: "nasılsın?", pause: 0)])
        XCTAssertEqual(SpokenPieces.chunk("merhaba,"), [SpokenPiece(text: "merhaba.", pause: 0)], "every piece ends like a sentence")
        XCTAssertEqual(SpokenPieces.chunk(""), [])
        XCTAssertEqual(SpokenPieces.chunk(". , -"), [], "no letters, nothing to say")
    }

    func testALongTextIsCutAtTheLastGoodSpot() {
        let sentence = String(repeating: "kelime ", count: 15).trimmingCharacters(in: .whitespaces) + "."
        let two = SpokenPieces.chunk(sentence + " " + sentence + " " + sentence)
        XCTAssertGreaterThan(two.count, 1)
        XCTAssertTrue(two.allSatisfy { $0.text.hasSuffix(".") })
        XCTAssertEqual(two.first?.pause, SpokenPieces.sentencePause)
        XCTAssertEqual(two.last?.pause, 0, "nothing after the last piece")

        let clauses = SpokenPieces.chunk(Array(repeating: "kelime kelime kelime kelime", count: 12).joined(separator: ", "))
        XCTAssertEqual(clauses.first?.pause, SpokenPieces.clausePause)
        XCTAssertTrue(clauses[0].text.hasSuffix("."), clauses[0].text)
        XCTAssertLessThanOrEqual(clauses[0].text.count, 181)

        let spaces = SpokenPieces.chunk(Array(repeating: "kelime", count: 60).joined(separator: " "))
        XCTAssertEqual(spaces.first?.pause, SpokenPieces.clausePause)
        XCTAssertFalse(spaces[0].text.contains("  "))
    }
}

final class SpeechModelSumsTests: XCTestCase {
    func testTheAlphabetMatchesTheModel() {
        XCTAssertEqual(SpeechModel.alphabet.count, 47, "49 with padding and unknown")
        XCTAssertEqual(SpeechModel.letterIDs[" "], 2)
        XCTAssertEqual(SpeechModel.letterIDs["a"], 17)
        XCTAssertEqual(SpeechModel.letterIDs["ş"], 48)
    }

    func testASpaceBelongsToTheWordBeforeIt() {
        let w = SpeechModel.wordsOfLetters("bir iki")
        XCTAssertEqual(w.word, [0, 0, 0, 0, 1, 1, 1])
        XCTAssertEqual(w.first, [0, 0, 0, 0, 4, 4, 4])
    }

    func testThePlanRoundsHalfToEvenAndClamps() {
        // Two words: 2.5 frames rounds to 2, 0.2 to the minimum of 1.
        let plan = SpeechModel.plan(duration: [1, 1, 0.5, 0.2], wordOfLetter: [0, 0, 0, 1], firstOfWord: [0, 0, 0, 3])
        XCTAssertEqual(plan.framesOfWord, [2, 1])
        XCTAssertEqual(plan.wordOfFrame, [0, 0, 1])
        XCTAssertEqual(plan.framePosition, [0, 1.5, 3], "word offset plus place inside it")
        XCTAssertEqual(plan.letterPosition.count, 4)
        XCTAssertEqual(plan.letterPosition[0], 0.6, accuracy: 1e-5, "(1 - 0 - 0.5) / 2.5 of three letters")
        XCTAssertEqual(plan.letterPosition[3], 3.5, accuracy: 1e-5, "the middle of the one-letter word")
        let long = SpeechModel.plan(duration: [1000], wordOfLetter: [0], firstOfWord: [0])
        XCTAssertEqual(long.framesOfWord, [SpeechModel.maxWordFrames])
    }

    func testAFrameReadsItsWordAndTheOnesBesideIt() {
        let allowed = SpeechModel.allowed(wordOfLetter: [0, 1, 2, 3], wordOfFrame: [0, 3])
        XCTAssertEqual(allowed, [1, 1, 0, 0, 0, 0, 1, 1])
    }

    /// Values from torch.randn with the same seeds and shapes.
    func testTheNoiseIsPyTorchs() {
        let a = TorchNoise.normal(seed: 0, count: 4 * 3 * 64)
        for (value, expected) in zip(a[..<6], [-1.12584, -1.15236, -0.250579, -0.433879, 0.84871, 0.692009] as [Float]) {
            XCTAssertEqual(value, expected, accuracy: 1e-5)
        }
        XCTAssertEqual(a.last ?? 0, -0.232616, accuracy: 1e-5)
        XCTAssertEqual(TorchNoise.pieceSeed(1, 0), 1_000_003)
        XCTAssertEqual(TorchNoise.pieceSeed(0, 2), 2)
        let b = TorchNoise.normal(seed: TorchNoise.pieceSeed(1, 0), count: 4 * 2 * 64)
        for (value, expected) in zip(b[..<4], [-0.392161, -1.169517, 1.511705, -0.826775] as [Float]) {
            XCTAssertEqual(value, expected, accuracy: 1e-5)
        }
    }

    func testTheModelSpeaks() throws {
        let model = try SpeechModel(directory: voiceFolder)
        let piece = SpokenPiece(text: "merhaba, ben uykusuz.", pause: 0.1)
        let first = try model.render(piece, seed: 0)
        XCTAssertEqual(first.pause, 0.1)
        XCTAssertEqual(first.wordFrames.count, 3)
        XCTAssertEqual(first.samples.count, first.wordFrames.reduce(0, +) * SpeechModel.hop)
        let seconds = Double(first.samples.count) / SpeechModel.sampleRate
        XCTAssertGreaterThan(seconds, 0.5)
        XCTAssertLessThan(seconds, 5)
        let energy = first.samples.reduce(Float(0)) { $0 + $1 * $1 } / Float(first.samples.count)
        XCTAssertGreaterThan(energy.squareRoot(), 0.01, "not silence")
        XCTAssertLessThanOrEqual(first.samples.map(abs).max() ?? 2, 1)
        XCTAssertEqual(try model.render(piece, seed: 0).samples, first.samples, "the same seed, the same audio")
        XCTAssertNotEqual(try model.render(piece, seed: 1).samples, first.samples)
    }

    func testAMissingModelIsAnError() {
        XCTAssertThrowsError(try SpeechModel(directory: URL(fileURLWithPath: "/nonexistent")))
    }
}

final class ReadingPlanTests: XCTestCase {
    func testSpokenWordsSpreadOverWrittenOnes() {
        let text = "Sürüm 0.9.2 çıktı. Bitti."
        let words = SummaryPlayer.words(in: text)
        let plan = ReadingPlan.make(text: text, words: words, paragraphs: SummaryPlayer.paragraphs(in: text)) { sentence in
            sentence.hasPrefix("Sürüm") ? "sürüm sıfır nokta dokuz nokta iki çıktı." : "bitti."
        }
        XCTAssertEqual(plan.paragraphs.count, 1)
        let paragraph = plan.paragraphs[0]
        XCTAssertEqual(paragraph.letters, "sürüm sıfır nokta dokuz nokta iki çıktı. bitti.")
        XCTAssertEqual(paragraph.sentences.map(\.spokenCount), [7, 1])
        // The mark never leaves its sentence, whichever way the words are split.
        let lastWord = words.count - 1
        XCTAssertEqual(paragraph.word(ofSpoken: 0), 0)
        XCTAssertEqual(paragraph.word(ofSpoken: 7), lastWord, "the second sentence's word")
        XCTAssertEqual(paragraph.word(ofSpoken: 99), lastWord, "past the end")
        let marks = (0..<7).compactMap(paragraph.word(ofSpoken:))
        XCTAssertEqual(marks, marks.sorted())
        XCTAssertLessThan(marks.last ?? 99, lastWord)
    }

    func testNothingToSayMakesNoParagraph() {
        let text = "→ →"
        let plan = ReadingPlan.make(text: text, words: SummaryPlayer.words(in: text), paragraphs: SummaryPlayer.paragraphs(in: text)) { _ in "" }
        XCTAssertEqual(plan.paragraphs, [])
    }

    func testTheTimelineFindsWordsAndTimes() {
        var timeline = ReadingTimeline()
        timeline.append(time: 0, word: 0)
        timeline.append(time: 0.5, word: 0)
        timeline.append(time: 1, word: 2)
        timeline.append(time: 2, word: 3)
        XCTAssertEqual(timeline.words, [0, 2, 3], "a word starts once")
        XCTAssertEqual(timeline.word(at: 0.9), 0)
        XCTAssertEqual(timeline.word(at: 1), 2)
        XCTAssertEqual(timeline.word(at: 99), 3)
        XCTAssertEqual(timeline.time(ofWord: 1), 1, "a word with no sound of its own: the next one's")
        XCTAssertEqual(timeline.time(ofWord: 3), 2)
        XCTAssertNil(timeline.time(ofWord: 4), "not there yet")
    }
}

@MainActor
final class NaturalReadingTests: XCTestCase {
    /// An output a test advances by hand.
    final class ManualOutput: ReadingOutput {
        var onInterrupted: (@MainActor () -> Void)?
        var started = false
        var shut = false
        var pauses = 0
        var resumes = 0
        var resets = 0
        var position: Double? = 0
        var queued: [(count: Int, played: @MainActor () -> Void)] = []
        var fail = false

        func start() throws {
            if fail { throw SpeechModelError.missing("an output") }
            started = true
        }

        func schedule(_ samples: ArraySlice<Float>, played: @escaping @MainActor () -> Void) {
            queued.append((samples.count, played))
        }

        func pause() { pauses += 1 }
        func resume() throws { resumes += 1 }
        func reset() {
            resets += 1
            queued = []
        }
        func shutDown() { shut = true }

        func playAll() {
            while !queued.isEmpty { queued.removeFirst().played() }
        }
    }

    private func waitUntil(_ condition: @escaping @MainActor () -> Bool, _ message: String) async throws {
        for _ in 0..<600 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(25))
        }
        XCTFail("timed out: \(message)")
    }

    private func reading(_ text: String, output: ManualOutput, voice: NaturalVoice? = nil) -> NaturalReading {
        NaturalReading(
            text: text,
            words: SummaryPlayer.words(in: text),
            paragraphs: SummaryPlayer.paragraphs(in: text),
            voice: voice ?? NaturalVoice(directory: { voiceFolder }, idle: .milliseconds(1)),
            makeOutput: { output }
        )
    }

    func testAReadingVoicesPlaysAndEnds() async throws {
        let output = ManualOutput()
        let text = "Birinci satır burada.\nİkinci satır da burada."
        let reading = reading(text, output: output)
        var finished = 0
        var marked: [Int] = []
        reading.onFinish = { finished += 1 }
        reading.onWord = { marked.append($0) }
        reading.start(fromWord: 0)
        XCTAssertTrue(output.started)
        try await waitUntil({ output.queued.count >= 3 }, "two lines and the pause between them")
        XCTAssertGreaterThan(output.queued[0].count, 1000)

        output.position = 0
        reading.mark()
        XCTAssertEqual(marked, [0])
        output.position = 0.001
        reading.mark()
        XCTAssertEqual(marked, [0], "only when the word changes")

        try await Task.sleep(for: .milliseconds(50))
        output.playAll()
        try await waitUntil({ finished == 1 }, "the end")
        XCTAssertTrue(output.shut, "nothing keeps running")
        XCTAssertEqual(finished, 1)
    }

    func testAMoveStartsFromThatWordWithoutVoicingAgain() async throws {
        let output = ManualOutput()
        let text = "Bir iki üç dört beş altı yedi sekiz dokuz on."
        let reading = reading(text, output: output)
        reading.start(fromWord: 0)
        try await waitUntil({ !output.queued.isEmpty }, "the first audio")
        let whole = output.queued[0].count
        let resets = output.resets

        reading.start(fromWord: 6)
        XCTAssertEqual(output.resets, resets + 1)
        XCTAssertEqual(output.queued.count, 1, "the same audio, from further on")
        XCTAssertLessThan(output.queued[0].count, whole)
        XCTAssertGreaterThan(output.queued[0].count, 0)
        reading.stop()
    }

    func testHeadphonesComingOrGoingDoNotEndTheReading() async throws {
        let output = ManualOutput()
        let text = "Bir iki üç dört beş altı yedi sekiz dokuz on."
        let reading = reading(text, output: output)
        var marked: [Int] = []
        reading.onWord = { marked.append($0) }
        reading.start(fromWord: 0)
        try await waitUntil({ !output.queued.isEmpty }, "the first audio")
        let whole = output.queued[0].count
        output.position = 0.9
        reading.mark()
        let word = try XCTUnwrap(marked.last)
        XCTAssertGreaterThan(word, 0)

        // While it plays: it starts again from the word being heard.
        output.onInterrupted?()
        XCTAssertEqual(output.resumes, 1)
        XCTAssertEqual(output.queued.count, 1)
        XCTAssertLessThan(output.queued[0].count, whole, "from that word, not from the start")

        // During a pause: nothing plays until the user asks.
        XCTAssertTrue(reading.pause())
        let queued = output.queued.count
        output.onInterrupted?()
        XCTAssertEqual(output.queued.count, queued)
        XCTAssertTrue(reading.resume())
        XCTAssertEqual(output.queued.count, 1, "queued again on the way out of the pause")
        reading.stop()
    }

    func testPauseAndResumeReachTheOutput() async throws {
        let output = ManualOutput()
        let reading = reading("Kısa bir cümle.", output: output)
        XCTAssertFalse(reading.pause(), "nothing playing")
        XCTAssertFalse(reading.resume(), "nothing started")
        reading.start(fromWord: 0)
        XCTAssertTrue(reading.pause())
        XCTAssertEqual(output.pauses, 1)
        XCTAssertFalse(reading.pause(), "already paused")
        XCTAssertTrue(reading.resume())
        XCTAssertEqual(output.resumes, 1)
        reading.stop()
        XCTAssertTrue(output.shut)
    }

    func testAVoiceThatCannotLoadSaysSo() async throws {
        let output = ManualOutput()
        let reading = reading("Kısa bir cümle.", output: output, voice: NaturalVoice(directory: { URL(fileURLWithPath: "/nonexistent") }))
        var failed = false
        reading.onFailure = { failed = true }
        reading.start(fromWord: 0)
        try await waitUntil({ failed }, "the failure")
        XCTAssertTrue(output.shut)
    }

    func testAnOutputThatCannotStartSaysSo() {
        let output = ManualOutput()
        output.fail = true
        let reading = reading("Kısa bir cümle.", output: output)
        var failed = false
        reading.onFailure = { failed = true }
        reading.start(fromWord: 0)
        XCTAssertTrue(failed)
    }

    func testTextWithNothingToSayEnds() async throws {
        let output = ManualOutput()
        let reading = NaturalReading(
            text: "bir",
            words: SummaryPlayer.words(in: "bir"),
            paragraphs: [],
            voice: NaturalVoice(directory: { voiceFolder }, idle: .milliseconds(1)),
            makeOutput: { output }
        )
        var finished = false
        reading.onFinish = { finished = true }
        reading.start(fromWord: 0)
        try await waitUntil({ finished }, "the end")
    }

    func testTheModelIsLetGoAfterAReading() async throws {
        let voice = NaturalVoice(directory: { voiceFolder }, idle: .milliseconds(20))
        let output = ManualOutput()
        let reading = reading("Kısa bir cümle.", output: output, voice: voice)
        reading.start(fromWord: 0)
        // Audio can only come from a loaded model.
        try await waitUntil({ !output.queued.isEmpty }, "the audio")
        reading.stop()
        var loaded = true
        for _ in 0..<200 {
            loaded = await voice.isLoaded
            if !loaded { break }
            try await Task.sleep(for: .milliseconds(25))
        }
        XCTAssertFalse(loaded, "nothing stays in memory")
    }

    /// The real audio engine, with its volume at zero, so nothing is heard.
    func testTheRealOutputPlaysToTheEnd() async throws {
        let text = "Bu cümle sessizce çalınır."
        let player = SummaryPlayer(
            text: text,
            voice: .natural,
            naturalOutput: { EngineOutput(volume: 0) },
            naturalVoice: NaturalVoice(directory: { voiceFolder }, idle: .milliseconds(1))
        )
        var finished = false
        var seen = Set<Int>()
        player.onFinish = { finished = true }
        player.play()
        XCTAssertTrue(player.isPlaying)
        for _ in 0..<800 {
            if let word = player.currentWord { seen.insert(word) }
            if finished { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        try XCTSkipIf(!finished && seen.isEmpty, "no audio output on this machine")
        XCTAssertTrue(finished, "the reading ends")
        XCTAssertFalse(player.isPlaying)
        XCTAssertNil(player.currentWord, "the next play starts over")
        XCTAssertGreaterThan(seen.count, 1, "the mark moved")
        XCTAssertEqual(seen.min(), 0)
        XCTAssertEqual(seen.max(), player.words.count - 1, "to the last word")
    }

    func testMovingWhilePausedStartsFromThereOnPlay() async throws {
        let text = "Bir iki üç dört beş altı yedi sekiz dokuz on."
        let output = ManualOutput()
        let player = SummaryPlayer(
            text: text,
            voice: .natural,
            naturalOutput: { output },
            naturalVoice: NaturalVoice(directory: { voiceFolder }, idle: .milliseconds(1))
        )
        player.play()
        try await waitUntil({ !output.queued.isEmpty }, "the first audio")
        let whole = output.queued[0].count
        player.pause()
        XCTAssertFalse(player.isPlaying)
        player.seek(to: 0.7)
        XCTAssertEqual(player.currentWord, 6)
        XCTAssertFalse(player.isPlaying, "moving does not start the reading")
        player.play()
        XCTAssertTrue(player.isPlaying)
        XCTAssertLessThan(output.queued[0].count, whole)
        player.stop()
    }
}

final class AppSpeechTests: XCTestCase {
    final class Recording: SpeechSynthesizing, @unchecked Sendable {
        var said: [String] = []
        func speak(_ text: String) async { said.append(text) }
    }

    func testTheSystemVoiceWhenOffOrWhenTheNaturalOneCannot() async {
        let recording = Recording()
        await AppSpeech(natural: { false }, voice: NaturalVoice(directory: { voiceFolder }), fallback: recording).speak("bir")
        XCTAssertEqual(recording.said, ["bir"], "off")
        await AppSpeech(natural: { true }, voice: NaturalVoice(directory: { URL(fileURLWithPath: "/nonexistent") }), fallback: recording).speak("iki")
        XCTAssertEqual(recording.said, ["bir", "iki"], "no model")
    }

    func testTheSettingIsOnByDefaultAndOldConfigsKeepIt() throws {
        XCTAssertTrue(Config().naturalVoice)
        let old = try JSONDecoder().decode(Config.self, from: Data("{}".utf8))
        XCTAssertTrue(old.naturalVoice)
        var off = Config()
        off.naturalVoice = false
        let back = try JSONDecoder().decode(Config.self, from: JSONEncoder().encode(off))
        XCTAssertFalse(back.naturalVoice)
    }
}

final class NaturalVoiceAlertTests: XCTestCase {
    /// At volume zero, so nothing is heard.
    func testAnAlertIsSaidAndTheModelLetGo() async throws {
        let voice = NaturalVoice(directory: { voiceFolder }, idle: .milliseconds(1))
        let said = await voice.speak("Süre doldu.", volume: 0)
        XCTAssertTrue(said)
        var loaded = true
        for _ in 0..<200 {
            loaded = await voice.isLoaded
            if !loaded { break }
            try await Task.sleep(for: .milliseconds(25))
        }
        XCTAssertFalse(loaded)
    }

    func testNothingToSayIsNotSaid() async {
        let said = await NaturalVoice(directory: { voiceFolder }).speak("→ →", volume: 0)
        XCTAssertFalse(said)
    }

    func testNoModelIsNotSaid() async {
        let said = await NaturalVoice(directory: { URL(fileURLWithPath: "/nonexistent") }).speak("Süre doldu.", volume: 0)
        XCTAssertFalse(said)
    }
}

final class VoiceCheckCommandTests: XCTestCase {
    func testTheCheckRunsOnTheFlagOnly() {
        XCTAssertNil(VoiceCheckCommand.run([]))
        XCTAssertNil(VoiceCheckCommand.run(["--other"]))
        XCTAssertEqual(VoiceCheckCommand.run([VoiceCheckCommand.flag], directory: voiceFolder), 0)
        XCTAssertEqual(VoiceCheckCommand.run([VoiceCheckCommand.flag, "Merhaba."], directory: voiceFolder), 0)
        XCTAssertEqual(VoiceCheckCommand.run([VoiceCheckCommand.flag], directory: URL(fileURLWithPath: "/nonexistent")), 1)
        XCTAssertEqual(VoiceCheckCommand.run([VoiceCheckCommand.flag], directory: nil), 1)
    }
}

final class WavFileTests: XCTestCase {
    func testAHeaderAndClampedSamples() {
        let data = WavFile.data(samples: [0, 1, -2], rate: 48000)
        XCTAssertEqual(data.count, 44 + 6)
        XCTAssertEqual(String(data: data[0..<4], encoding: .ascii), "RIFF")
        XCTAssertEqual(String(data: data[36..<40], encoding: .ascii), "data")
        let last = data[48..<50].withUnsafeBytes { $0.loadUnaligned(as: Int16.self) }
        XCTAssertEqual(last, -32767, "clamped")
    }
}
