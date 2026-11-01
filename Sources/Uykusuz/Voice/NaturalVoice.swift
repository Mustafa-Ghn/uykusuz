import AVFoundation
import Foundation

/// The voice that ships with the app, loaded when a reading needs it and let
/// go soon after: no process, thread or memory stays behind between readings.
/// It runs on the CPU at a fraction of its capacity (about 0.01 s of CPU per
/// second of speech), so a reading does not warm the Mac.
actor NaturalVoice {
    static let shared = NaturalVoice()
    /// How long the model stays after the last reading, for a listen again.
    static let idleRelease: Duration = .seconds(30)

    private struct Tools {
        let model: SpeechModel
        let numbers: TurkishNumbers
        let words: SpokenTurkish
    }

    private let directory: @Sendable () -> URL?
    private let idle: Duration
    private var tools: Tools?
    private var users = 0
    private var release: Task<Void, Never>?

    init(directory: @escaping @Sendable () -> URL? = { NaturalVoice.bundledDirectory }, idle: Duration = NaturalVoice.idleRelease) {
        self.directory = directory
        self.idle = idle
    }

    nonisolated static var bundledDirectory: URL? {
        Bundle.main.resourceURL?.appendingPathComponent("Voice", isDirectory: true)
    }

    /// Whether the model is in memory right now.
    var isLoaded: Bool { tools != nil }

    /// A reading starts: loads the model if it is not there. Every `begin` needs an `end`.
    func begin() throws {
        release?.cancel()
        release = nil
        users += 1
        do {
            _ = try loaded()
        } catch {
            users -= 1
            throw error
        }
    }

    func end() {
        users = max(users - 1, 0)
        guard users == 0 else { return }
        release?.cancel()
        release = Task { [idle] in
            try? await Task.sleep(for: idle)
            guard !Task.isCancelled else { return }
            self.dropIfIdle()
        }
    }

    private func dropIfIdle() {
        guard users == 0 else { return }
        tools = nil
        release = nil
        Log.info("natural voice: unloaded")
    }

    private func loaded() throws -> Tools {
        if let tools { return tools }
        guard let directory = directory() else { throw SpeechModelError.missing("its folder") }
        let started = Date()
        let model = try SpeechModel(directory: directory)
        let numbers = try TurkishNumbers(script: directory.appendingPathComponent("trnorm.js"))
        let words = SpokenTurkish(
            english: EnglishWords(file: directory.appendingPathComponent("english.tsv")).lookup,
            capsWords: Self.capsWords(directory.appendingPathComponent("caps.txt"))
        )
        let tools = Tools(model: model, numbers: numbers, words: words)
        self.tools = tools
        Log.info("natural voice: loaded in \(String(format: "%.2f", Date().timeIntervalSince(started))) s")
        return tools
    }

    private static func capsWords(_ file: URL) -> Set<String> {
        let text = (try? String(contentsOf: file, encoding: .utf8)) ?? ""
        return Set(text.split(separator: "\n").map(String.init))
    }

    /// One sentence as the model's letters.
    func letters(of sentence: String) throws -> String {
        let tools = try loaded()
        return SpokenPieces.alphabet(tools.numbers.normalize(tools.words.spoken(sentence)))
    }

    func render(_ piece: SpokenPiece, seed: UInt64) throws -> RenderedPiece {
        var rendered = try loaded().model.render(piece, seed: seed)
        rendered.samples = SpeechLevel.raised(rendered.samples)
        return rendered
    }

    /// Says `text` and returns when it is over, or false if the voice could not
    /// (a missing file, no output): the caller then falls back on the system's.
    func speak(_ text: String, volume: Float = 1) async -> Bool {
        do {
            try begin()
        } catch {
            Log.error("natural voice: \(error.localizedDescription)")
            return false
        }
        defer { end() }
        do {
            let letters = try letters(of: text)
            var samples: [Float] = []
            for (i, piece) in SpokenPieces.chunk(letters).enumerated() {
                try Task.checkCancellation()
                let rendered = try self.render(piece, seed: TorchNoise.pieceSeed(0, i))
                samples += rendered.samples
                samples += [Float](repeating: 0, count: Int((rendered.pause * SpeechModel.sampleRate).rounded()))
            }
            guard !samples.isEmpty else { return false }
            let player = try AVAudioPlayer(data: WavFile.data(samples: samples, rate: Int(SpeechModel.sampleRate)))
            player.volume = volume
            guard player.play() else { return false }
            let seconds = Double(samples.count) / SpeechModel.sampleRate
            try await Task.sleep(for: .seconds(seconds + 0.2))
            player.stop()
            return true
        } catch {
            Log.error("natural voice: \(error.localizedDescription)")
            return false
        }
    }
}

/// `english.tsv` read once, when a camelCase name first needs it.
final class EnglishWords: @unchecked Sendable {
    private let file: URL
    private let lock = NSLock()
    private var table: [String: String]?

    init(file: URL) {
        self.file = file
    }

    var lookup: @Sendable (String) -> String? {
        { [self] word in
            lock.lock()
            defer { lock.unlock() }
            if table == nil {
                var read: [String: String] = [:]
                let text = (try? String(contentsOf: file, encoding: .utf8)) ?? ""
                for line in text.split(separator: "\n") {
                    let parts = line.split(separator: "\t")
                    if parts.count == 2 { read[String(parts[0])] = String(parts[1]) }
                }
                table = read
            }
            return table?[word]
        }
    }
}

enum WavFile {
    /// 16-bit mono PCM in a WAV container.
    static func data(samples: [Float], rate: Int) -> Data {
        var out = Data(capacity: 44 + samples.count * 2)
        func add(_ value: UInt32) { withUnsafeBytes(of: value.littleEndian) { out.append(contentsOf: $0) } }
        func add(_ value: UInt16) { withUnsafeBytes(of: value.littleEndian) { out.append(contentsOf: $0) } }
        out.append(contentsOf: Array("RIFF".utf8))
        add(UInt32(36 + samples.count * 2))
        out.append(contentsOf: Array("WAVEfmt ".utf8))
        add(UInt32(16))
        add(UInt16(1))
        add(UInt16(1))
        add(UInt32(rate))
        add(UInt32(rate * 2))
        add(UInt16(2))
        add(UInt16(16))
        out.append(contentsOf: Array("data".utf8))
        add(UInt32(samples.count * 2))
        for sample in samples {
            let value = Int16((max(-1, min(1, sample)) * 32767).rounded())
            withUnsafeBytes(of: value.littleEndian) { out.append(contentsOf: $0) }
        }
        return out
    }
}

/// How a text is divided for reading, and which written word each spoken word
/// belongs to. The two lists differ (0.9.2 is six spoken words), so each written
/// sentence is spoken on its own and its spoken words spread over its written
/// ones: the mark can lag a little inside a sentence and never beyond one.
struct ReadingPlan: Equatable, Sendable {
    struct Sentence: Equatable, Sendable {
        var firstWord: Int
        var wordCount: Int
        var spokenCount: Int
    }

    struct Paragraph: Equatable, Sendable {
        var letters: String
        var sentences: [Sentence]

        /// The written word of the `index`th spoken word.
        func word(ofSpoken index: Int) -> Int? {
            var seen = 0
            var last: Sentence?
            for sentence in sentences where sentence.wordCount > 0 {
                last = sentence
                if index < seen + sentence.spokenCount {
                    let inside = index - seen
                    let place = Int(Double(inside) / Double(max(sentence.spokenCount, 1)) * Double(sentence.wordCount))
                    return sentence.firstWord + min(place, sentence.wordCount - 1)
                }
                seen += sentence.spokenCount
            }
            return last.map { $0.firstWord + $0.wordCount - 1 }
        }
    }

    var paragraphs: [Paragraph]

    /// `spoken` turns one sentence into the model's letters.
    static func make(text: String, words: [NSRange], paragraphs ranges: [NSRange], spoken: (String) throws -> String) rethrows -> ReadingPlan {
        let ns = text as NSString
        var out: [Paragraph] = []
        for range in ranges {
            var sentences: [Sentence] = []
            var letters: [String] = []
            var pieces: [NSRange] = []
            ns.enumerateSubstrings(in: range, options: [.bySentences, .substringNotRequired]) { _, sentence, _, _ in
                pieces.append(sentence)
            }
            if pieces.isEmpty { pieces = [range] }
            for piece in pieces {
                let said = try spoken(ns.substring(with: piece))
                let spokenCount = said.split(separator: " ").count
                let inside = words.indices.filter { NSLocationInRange(words[$0].location, piece) }
                guard spokenCount > 0 else { continue }
                sentences.append(Sentence(firstWord: inside.first ?? 0, wordCount: inside.count, spokenCount: spokenCount))
                letters.append(said)
            }
            if !letters.isEmpty {
                out.append(Paragraph(letters: letters.joined(separator: " "), sentences: sentences))
            }
        }
        return ReadingPlan(paragraphs: out)
    }
}

/// When each written word is heard, built up as the audio arrives.
struct ReadingTimeline: Equatable, Sendable {
    private(set) var times: [Double] = []
    private(set) var words: [Int] = []

    mutating func append(time: Double, word: Int) {
        // A written word is marked from the first spoken word that reaches it.
        if let last = words.last, last >= word { return }
        times.append(time)
        words.append(word)
    }

    /// The word being heard at `time`.
    func word(at time: Double) -> Int? {
        guard let index = lastIndex(of: time, in: times) else { return words.first }
        return words[index]
    }

    /// When `word` starts, or nil while the audio has not got there yet.
    func time(ofWord word: Int) -> Double? {
        guard let index = words.firstIndex(where: { $0 >= word }) else { return nil }
        return times[index]
    }

    private func lastIndex(of value: Double, in list: [Double]) -> Int? {
        var low = 0, high = list.count
        while low < high {
            let middle = (low + high) / 2
            if list[middle] <= value { low = middle + 1 } else { high = middle }
        }
        return low == 0 ? nil : low - 1
    }
}

/// `Uykusuz --voice-check [text]`: voices a text with the bundled model and
/// says how it went, in silence. Nothing is played and nothing is written.
enum VoiceCheckCommand {
    static let flag = "--voice-check"
    static let sample = "Merhaba, ben Uykusuz. API anahtarı Keychain'de duruyor, saat 14:30'da bitti."

    static func run(_ arguments: [String], directory: URL? = NaturalVoice.bundledDirectory) -> Int32? {
        guard arguments.first == flag else { return nil }
        let text = arguments.count > 1 ? arguments.dropFirst().joined(separator: " ") : sample
        guard let directory else {
            print("Ses dosyaları bulunamadı.")
            return 1
        }
        do {
            let started = Date()
            let model = try SpeechModel(directory: directory)
            let numbers = try TurkishNumbers(script: directory.appendingPathComponent("trnorm.js"))
            let words = SpokenTurkish(english: EnglishWords(file: directory.appendingPathComponent("english.tsv")).lookup)
            let loaded = Date().timeIntervalSince(started)
            let spoken = numbers.normalize(words.spoken(text))
            print("Okunan: \(spoken)")
            let voicing = Date()
            var seconds = 0.0
            for (i, piece) in SpokenPieces.chunk(SpokenPieces.alphabet(spoken)).enumerated() {
                let rendered = try model.render(piece, seed: TorchNoise.pieceSeed(0, i))
                seconds += Double(rendered.samples.count) / SpeechModel.sampleRate + rendered.pause
            }
            let took = Date().timeIntervalSince(voicing)
            print(String(format: "Yükleme %.2f sn; %.1f sn ses, %.2f sn'de üretildi.", loaded, seconds, took))
            return seconds > 0 ? 0 : 1
        } catch {
            print("Ses çalışmıyor: \(error.localizedDescription)")
            return 1
        }
    }
}
