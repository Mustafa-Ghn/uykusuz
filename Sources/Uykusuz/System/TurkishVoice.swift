import AVFoundation
import Foundation

/// The best Turkish voice installed on this Mac (fork addition): a premium
/// one, else an enhanced one (the "Gelişmiş" Yelda the user can download in
/// System Settings), else the compact Yelda macOS ships with. `say` takes a
/// voice's identifier as its name.
enum TurkishVoice {
    enum Quality: Int, Comparable, Sendable {
        case basic = 1
        case enhanced = 2
        case premium = 3

        static func < (a: Quality, b: Quality) -> Bool { a.rawValue < b.rawValue }

        var label: String {
            switch self {
            case .basic: "basit"
            case .enhanced: "Gelişmiş"
            case .premium: "Premium"
            }
        }
    }

    struct Choice: Equatable, Sendable {
        let identifier: String
        let name: String
        let quality: Quality

        /// "Yelda (Gelişmiş)".
        var label: String { "\(name) (\(quality.label))" }
    }

    struct Voice: Equatable, Sendable {
        let identifier: String
        let name: String
        let language: String
        let quality: Int
    }

    /// What `say` is given when no Turkish voice can be listed.
    static let fallback = Choice(identifier: "Yelda", name: "Yelda", quality: .basic)
    /// How long a reading of the installed voices is used before it is read
    /// again, so a voice downloaded meanwhile is picked up without a relaunch.
    static let refresh: TimeInterval = 10 * 60

    static func best(among voices: [Voice]) -> Choice? {
        voices
            .filter { $0.language.hasPrefix("tr") }
            .map { Choice(identifier: $0.identifier, name: $0.name, quality: Quality(rawValue: min(max($0.quality, 1), 3)) ?? .basic) }
            .max { ($0.quality, $0.identifier) < ($1.quality, $1.identifier) }
    }

    /// The system's voices. The first read in a process can take seconds,
    /// so it never runs on the main actor (`current`).
    static func installed() -> [Voice] {
        AVSpeechSynthesisVoice.speechVoices().map {
            Voice(identifier: $0.identifier, name: $0.name, language: $0.language, quality: $0.quality.rawValue)
        }
    }

    /// The best installed Turkish voice, read off the main actor and kept for
    /// `refresh`; `fresh` reads it again now (Settings).
    static func current(fresh: Bool = false) async -> Choice {
        await cache.choice(fresh: fresh)
    }

    private static let cache = Cache()

    private actor Cache {
        private var chosen: Choice?
        private var readAt: Date?

        func choice(fresh: Bool) async -> Choice {
            if !fresh, let chosen, let readAt, Date().timeIntervalSince(readAt) < TurkishVoice.refresh {
                return chosen
            }
            let found = await Task.detached(priority: .utility) {
                TurkishVoice.best(among: TurkishVoice.installed())
            }.value ?? TurkishVoice.fallback
            chosen = found
            readAt = Date()
            return found
        }
    }
}
