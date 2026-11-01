import Foundation

/// How loud the natural voice is heard. The model speaks at about -25 LUFS:
/// 11 dB under what music and video play at and 7 under the system's voice,
/// with peaks so close to full scale that plain gain would clip. So the loud
/// parts come down, all of it goes up and what still sticks out is held under
/// `ceiling`. The quiet parts gain the most, and they are what a noisy room
/// takes first: consonants and the ends of words.
///
/// A piece is whole by the time it gets here, so a gain can fall ahead of what
/// it lowers without delaying anything. Every sample stays in its place, which
/// is what the word marks count on.
enum SpeechLevel {
    /// The level above which the voice is brought down (dBFS).
    private static let threshold = -30.0
    /// Above `threshold`, 2.5 dB in make 1 dB out.
    private static let ratio = 2.5
    /// What all of it gets afterwards: 16 dB.
    private static let makeup = Float(pow(10.0, 16.0 / 20))
    /// -2 dBFS. Between samples the sound reaches about 1 dB higher, and a
    /// Bluetooth encoder needs that last decibel.
    static let ceiling: Float = 0.794
    /// How much sound the level is read over: two periods of a low voice, so it
    /// follows the syllables and not the waves.
    private static let window = Int(0.02 * SpeechModel.sampleRate)
    /// How long before a loud part a gain starts falling.
    private static let lookahead = Int(0.005 * SpeechModel.sampleRate)
    /// How fast a gain comes back: soon enough for the consonant after a vowel.
    private static let release = 0.05 * SpeechModel.sampleRate

    static func raised(_ samples: [Float]) -> [Float] {
        let compression = smoothed(wantedByLevel(samples))
        var out = samples
        for i in out.indices { out[i] *= compression[i] * makeup }
        let limit = smoothed(out.map { min(1, ceiling / max(abs($0), .leastNormalMagnitude)) })
        for i in out.indices { out[i] *= limit[i] }
        return out
    }

    /// The gain each sample asks for from the level around it.
    private static func wantedByLevel(_ samples: [Float]) -> [Float] {
        var wanted = [Float](repeating: 1, count: samples.count)
        var energy = 0.0
        var from = 0, to = 0
        for i in samples.indices {
            while to < min(i + window / 2 + 1, samples.count) {
                energy += Double(samples[to]) * Double(samples[to])
                to += 1
            }
            while from < i - window / 2 {
                energy -= Double(samples[from]) * Double(samples[from])
                from += 1
            }
            let level = 10 * log10(max(energy, 0) / Double(to - from) + 1e-12)
            if level > threshold {
                wanted[i] = Float(pow(10, (threshold - level) * (1 - 1 / ratio) / 20))
            }
        }
        return wanted
    }

    /// A gain that moves without being heard and is never above `wanted`: the
    /// lowest asked for in the next `lookahead` samples, back up over `release`,
    /// and over the last `lookahead` samples the average, every one of which
    /// was already that low for the sample it arrives at.
    private static func smoothed(_ wanted: [Float]) -> [Float] {
        // The lowest ahead, from the end: `queue` holds the samples that can
        // still be the lowest, with the lowest at `head`.
        var lowest = wanted
        var queue = [Int](repeating: 0, count: wanted.count)
        var head = 0, tail = 0
        for i in wanted.indices.reversed() {
            while tail > head, wanted[queue[tail - 1]] >= wanted[i] { tail -= 1 }
            queue[tail] = i
            tail += 1
            while queue[head] > i + lookahead { head += 1 }
            lowest[i] = wanted[queue[head]]
        }
        let back = Float(exp(-1 / release))
        var current: Float = 1
        for i in lowest.indices {
            current = min(lowest[i], 1 - back * (1 - current))
            lowest[i] = current
        }
        var out = lowest
        var sum = 0.0
        for i in lowest.indices {
            sum += Double(lowest[i])
            if i > lookahead { sum -= Double(lowest[i - lookahead - 1]) }
            out[i] = Float(sum / Double(min(i + 1, lookahead + 1)))
        }
        return out
    }
}
