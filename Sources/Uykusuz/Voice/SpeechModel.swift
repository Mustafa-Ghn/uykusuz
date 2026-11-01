import Accelerate
import CoreML
import Foundation

/// One stretch of spoken text the model reads in a single pass (`SpokenPieces`).
struct SpokenPiece: Equatable, Sendable {
    /// Turkish lowercase, in the model's own alphabet.
    var text: String
    /// Seconds of silence after it.
    var pause: Double
}

/// The audio of a piece, and how long each of its words lasts.
struct RenderedPiece: Sendable {
    /// Mono, 48 kHz, in [-1, 1].
    var samples: [Float]
    /// Frames (1/25 s) per word, in the order of `text.split(" ")`.
    var wordFrames: [Int]
    var pause: Double
}

enum SpeechModelError: LocalizedError {
    case missing(String)
    case badOutput(String)

    var errorDescription: String? {
        switch self {
        case let .missing(what): "the speech model is missing \(what)"
        case let .badOutput(what): "the speech model returned no \(what)"
        }
    }
}

/// The speech model that ships with the app: four Core ML programs under
/// `Contents/Resources/Voice`, 8.6 million parameters, running on the CPU.
/// Nothing leaves the Mac and nothing runs until the first reading asks for it.
///
/// Letters become durations and features (`text`), a frame timeline and the
/// aligner turn those into a condition (`align`), four steps turn noise into
/// latents (`step`), and windows of latents become sound (`decode`). The
/// sums between the programs are here, so the programs need no dynamically
/// sized arithmetic. tools/voice/convert_ema.py makes the programs and checks
/// each against the original.
final class SpeechModel: @unchecked Sendable {
    static let sampleRate = 48000.0
    static let hop = 1920
    static let framesPerSecond = 25.0
    static let latentDimension = 64
    static let maxWordFrames = 250
    static let maxFrames = 3000
    static let window = 100
    static let context = 8
    /// The letters a frame may read: its own word and one on each side.
    static let lookaround = 1
    static let times: [Float] = [0, 0.25, 0.5, 0.75]
    /// The model's alphabet; a letter's id is its place here. 0 is padding, 1 unknown.
    static let alphabet: [Unicode.Scalar] = Array(" !\"%&'(),-./:;?abcdefghijklmnopqrstuvwxyzçöüğış".unicodeScalars)
    static let letterIDs: [Unicode.Scalar: Int32] = {
        var ids: [Unicode.Scalar: Int32] = [:]
        for (i, scalar) in alphabet.enumerated() { ids[scalar] = Int32(i + 2) }
        return ids
    }()

    private let text: MLModel
    private let align: MLModel
    private let step: MLModel
    private let decode: MLModel

    init(directory: URL) throws {
        let configuration = MLModelConfiguration()
        configuration.computeUnits = .cpuOnly
        func load(_ name: String) throws -> MLModel {
            let url = directory.appendingPathComponent("\(name).mlmodelc", isDirectory: true)
            guard FileManager.default.fileExists(atPath: url.path) else { throw SpeechModelError.missing(url.lastPathComponent) }
            return try MLModel(contentsOf: url, configuration: configuration)
        }
        text = try load("text")
        align = try load("align")
        step = try load("step")
        decode = try load("decode")
    }

    /// The piece's audio. The same text and seed give the same audio.
    func render(_ piece: SpokenPiece, seed: UInt64, speed: Float = 1) throws -> RenderedPiece {
        let ids = piece.text.unicodeScalars.map { Self.letterIDs[$0] ?? 1 }
        let words = Self.wordsOfLetters(piece.text)
        guard !ids.isEmpty else { return RenderedPiece(samples: [], wordFrames: [], pause: piece.pause) }

        // Letters to features and durations.
        let textOut = try predict(text, ["ids": array(ids, [1, ids.count])])
        guard let h = textOut.featureValue(for: "h")?.multiArrayValue, let durArray = textOut.featureValue(for: "dur")?.multiArrayValue else {
            throw SpeechModelError.badOutput("features")
        }
        let duration = floats(durArray).map { $0 / speed }

        let plan = Self.plan(duration: duration, wordOfLetter: words.word, firstOfWord: words.first)
        let frames = plan.wordOfFrame.count

        // The condition every step reads.
        let alignOut = try predict(align, [
            "h": h,
            "cg": array(plan.letterPosition, [1, ids.count]),
            "fg": array(plan.framePosition, [1, frames]),
            "allow": array(Self.allowed(wordOfLetter: words.word, wordOfFrame: plan.wordOfFrame), [1, frames, ids.count]),
        ])
        guard let condition = alignOut.featureValue(for: "cond")?.multiArrayValue else { throw SpeechModelError.badOutput("condition") }

        // Four steps from seeded noise.
        let dim = Self.latentDimension
        let count = frames * dim
        let noise = TorchNoise.normal(seed: seed, count: Self.times.count * count)
        let position = (0..<frames).map(Float.init)
        var x = Array(noise[0..<count])
        var result: [Float] = []
        for (k, t) in Self.times.enumerated() {
            let out = try predict(step, [
                "x": array(x, [1, frames, dim]),
                "cond": condition,
                "t": array([t], [1]),
                "pos": array(position, [1, frames]),
            ])
            guard let x1 = out.featureValue(for: "x1")?.multiArrayValue else { throw SpeechModelError.badOutput("latents") }
            result = floats(x1)
            if k + 1 < Self.times.count {
                let next = Self.times[k + 1]
                let start = (k + 1) * count
                for i in 0..<count { x[i] = (1 - next) * noise[start + i] + next * result[i] }
            }
        }

        // Windows of latents to sound, each with margins on both sides.
        var samples = [Float]()
        samples.reserveCapacity(frames * Self.hop)
        var s = 0
        while s < frames {
            let e = min(frames, s + Self.window)
            let a = max(0, s - Self.context)
            let b = min(frames, e + Self.context)
            var z = [Float](repeating: 0, count: dim * (b - a))
            for t in a..<b {
                for c in 0..<dim { z[c * (b - a) + (t - a)] = result[t * dim + c] }
            }
            let out = try predict(decode, ["z": array(z, [1, dim, b - a])])
            guard let audio = out.featureValue(for: "audio")?.multiArrayValue else { throw SpeechModelError.badOutput("audio") }
            let all = floats(audio)
            let from = (s - a) * Self.hop
            let to = (e - a) * Self.hop
            guard all.count >= to else { throw SpeechModelError.badOutput("audio of the right length") }
            samples.append(contentsOf: all[from..<to])
            s = e
        }
        return RenderedPiece(samples: samples, wordFrames: plan.framesOfWord, pause: piece.pause)
    }

    // MARK: The sums between the programs

    struct Plan: Equatable {
        var wordOfFrame: [Int32]
        var framesOfWord: [Int]
        var letterPosition: [Float]
        var framePosition: [Float]
    }

    /// Each letter's word and the first letter of that word: a space belongs to the word before it.
    static func wordsOfLetters(_ text: String) -> (word: [Int32], first: [Int]) {
        let scalars = Array(text.unicodeScalars)
        var starts = scalars.indices.filter { scalars[$0] != " " && ($0 == 0 || scalars[$0 - 1] == " ") }
        if starts.isEmpty { starts = [0] }
        var bounds = [0] + starts.dropFirst()
        bounds.append(scalars.count)
        var word = [Int32](), first = [Int]()
        for w in 0..<(bounds.count - 1) {
            for _ in bounds[w]..<bounds[w + 1] {
                word.append(Int32(w))
                first.append(bounds[w])
            }
        }
        return (word, first)
    }

    /// Durations to the exact frame timeline, and the positions the aligner reads.
    static func plan(duration: [Float], wordOfLetter word: [Int32], firstOfWord first: [Int]) -> Plan {
        let wordCount = Int(word.last ?? 0) + 1
        var sums = [Float](repeating: 0, count: wordCount)
        for (i, w) in word.enumerated() { sums[Int(w)] += duration[i] }
        let counts = sums.map { Swift.min(Swift.max(Int($0.rounded(.toNearestOrEven)), 1), maxWordFrames) }

        var wordOfFrame = [Int32](), frameInWord = [Float]()
        outer: for (w, n) in counts.enumerated() {
            for j in 0..<n {
                if wordOfFrame.count == maxFrames { break outer }
                wordOfFrame.append(Int32(w))
                frameInWord.append(Float(Double(j) / Double(n)))
            }
        }

        // Where each letter sits inside its word, by the time it takes.
        let c = duration.map { Swift.max($0, 1e-4) }
        var done = [Float](repeating: 0, count: c.count)
        var running: Float = 0
        for i in c.indices {
            running += c[i]
            done[i] = running
        }
        var totals = [Float](repeating: 0, count: wordCount)
        for (i, w) in word.enumerated() { totals[Int(w)] += c[i] }
        var lettersInWord = [Float](repeating: 0, count: wordCount)
        for w in word { lettersInWord[Int(w)] += 1 }
        var offset = [Float](repeating: 0, count: wordCount)
        var seen: Float = 0
        for w in 0..<wordCount {
            offset[w] = seen
            seen += lettersInWord[w]
        }
        var letterPosition = [Float](repeating: 0, count: c.count)
        for i in c.indices {
            let w = Int(word[i])
            let before = done[first[i]] - c[first[i]]
            let place = Swift.min(Swift.max((done[i] - before - 0.5 * c[i]) / Swift.max(totals[w], 1e-8), 0), 1)
            letterPosition[i] = offset[w] + place * lettersInWord[w]
        }
        var framePosition = [Float](repeating: 0, count: wordOfFrame.count)
        for t in wordOfFrame.indices {
            let w = Int(wordOfFrame[t])
            framePosition[t] = offset[w] + frameInWord[t] * lettersInWord[w]
        }
        return Plan(wordOfFrame: wordOfFrame, framesOfWord: counts, letterPosition: letterPosition, framePosition: framePosition)
    }

    /// frames x letters: 1 where a frame may read a letter.
    static func allowed(wordOfLetter word: [Int32], wordOfFrame: [Int32]) -> [Float] {
        var out = [Float](repeating: 0, count: word.count * wordOfFrame.count)
        for t in wordOfFrame.indices {
            for l in word.indices where abs(Int(word[l]) - Int(wordOfFrame[t])) <= lookaround {
                out[t * word.count + l] = 1
            }
        }
        return out
    }

    // MARK: Core ML

    private func predict(_ model: MLModel, _ inputs: [String: MLMultiArray]) throws -> MLFeatureProvider {
        let provider = try MLDictionaryFeatureProvider(dictionary: inputs.mapValues { MLFeatureValue(multiArray: $0) })
        return try model.prediction(from: provider)
    }

    private func array(_ values: [Float], _ shape: [Int]) throws -> MLMultiArray {
        let out = try MLMultiArray(shape: shape.map { NSNumber(value: $0) }, dataType: .float32)
        out.withUnsafeMutableBytes { raw, _ in
            values.withUnsafeBytes { raw.copyMemory(from: $0) }
        }
        return out
    }

    private func array(_ values: [Int32], _ shape: [Int]) throws -> MLMultiArray {
        let out = try MLMultiArray(shape: shape.map { NSNumber(value: $0) }, dataType: .int32)
        out.withUnsafeMutableBytes { raw, _ in
            values.withUnsafeBytes { raw.copyMemory(from: $0) }
        }
        return out
    }

    /// Every value of an output, in order, whatever its strides.
    private func floats(_ array: MLMultiArray) -> [Float] {
        let count = array.count
        var out = [Float](repeating: 0, count: count)
        array.withUnsafeBytes { raw in
            switch array.dataType {
            case .float32:
                out.withUnsafeMutableBytes { $0.copyMemory(from: UnsafeRawBufferPointer(rebasing: raw[0..<(count * 4)])) }
            case .float16:
                raw.withMemoryRebound(to: Float16.self) { source in
                    for i in 0..<count { out[i] = Float(source[i]) }
                }
            default:
                for i in 0..<count { out[i] = array[i].floatValue }
            }
        }
        return out
    }
}

/// `torch.randn` on the CPU, so a seed gives the same noise here as in PyTorch
/// and the audio matches the published model's for the same seed: mt19937
/// seeded with the low 32 bits, 24-bit uniforms, then ATen's normal fill, where
/// each block of 16 uniforms becomes 16 normals by Box-Muller, pairing value j
/// with j + 8, in float32.
enum TorchNoise {
    /// The first `count` values (a multiple of 16).
    static func normal(seed: UInt64, count: Int) -> [Float] {
        precondition(count % 16 == 0, "whole blocks only")
        var generator = MersenneTwister(seed: UInt32(truncatingIfNeeded: seed))
        var out = [Float](repeating: 0, count: count)
        for i in 0..<count {
            out[i] = Float(generator.next() & 0xffffff) * 5.9604644775390625e-8
        }
        for block in stride(from: 0, to: count, by: 16) {
            for j in 0..<8 {
                let u1 = 1 - out[block + j]
                let u2 = out[block + j + 8]
                let radius = (-2 * log(u1)).squareRoot()
                let theta = Float(2 * Double.pi) * u2
                out[block + j] = radius * cos(theta)
                out[block + j + 8] = radius * sin(theta)
            }
        }
        return out
    }

    /// The seed of a text's piece, as the published engine makes it.
    static func pieceSeed(_ seed: UInt64, _ index: Int) -> UInt64 {
        let (product, _) = seed.multipliedReportingOverflow(by: 1_000_003)
        let (sum, _) = product.addingReportingOverflow(UInt64(index))
        return sum & 0x7fff_ffff_ffff_ffff
    }

    private struct MersenneTwister {
        private var state = [UInt32](repeating: 0, count: 624)
        private var index = 624

        init(seed: UInt32) {
            state[0] = seed
            for j in 1..<624 {
                let previous = state[j - 1] ^ (state[j - 1] >> 30)
                state[j] = 1_812_433_253 &* previous &+ UInt32(j)
            }
        }

        mutating func next() -> UInt32 {
            if index >= 624 { twist() }
            var y = state[index]
            index += 1
            y ^= y >> 11
            y ^= (y << 7) & 0x9d2c_5680
            y ^= (y << 15) & 0xefc6_0000
            y ^= y >> 18
            return y
        }

        private mutating func twist() {
            for i in 0..<624 {
                let y = (state[i] & 0x8000_0000) | (state[(i + 1) % 624] & 0x7fff_ffff)
                var value = state[(i + 397) % 624] ^ (y >> 1)
                if y & 1 != 0 { value ^= 0x9908_b0df }
                state[i] = value
            }
            index = 0
        }
    }
}
