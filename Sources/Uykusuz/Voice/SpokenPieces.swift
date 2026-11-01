import Foundation

/// From spoken Turkish to what the speech model reads: its alphabet, then
/// pieces short enough for one pass. Text that fits in about ten seconds stays
/// one piece and the model reads its punctuation itself. Longer text is cut at
/// the last good spot inside each ten seconds: a sentence end, then a clause
/// mark, then a space. The model was trained on sentences, so every piece ends
/// like one.
enum SpokenPieces {
    static let sentencePause = 0.25
    static let clausePause = 0.12
    private static let lettersPerSecond = 18.0
    private static let maxSeconds = 10.0
    private static let maxLetters = 250.0

    /// Turkish lowercase in the model's letters. Accents go, and whatever it cannot read becomes a space.
    static func alphabet(_ text: String) -> String {
        var typed = ""
        typed.reserveCapacity(text.count)
        for scalar in text.unicodeScalars {
            switch scalar {
            case "\u{2019}", "\u{2018}", "\u{02BC}", "\u{00B4}", "`": typed.append("'")
            case "\u{201C}", "\u{201D}", "\u{201E}", "\u{00AB}", "\u{00BB}": typed.append("\"")
            case "\u{2013}", "\u{2014}", "\u{2212}": typed.append("-")
            case "\u{2026}": typed.append("...")
            case "\u{0130}": typed.append("i")
            case "I": typed.append("\u{0131}")
            default: typed.unicodeScalars.append(scalar)
            }
        }
        var out = String.UnicodeScalarView()
        var pendingSpace = false
        func add(_ scalar: Unicode.Scalar) {
            if SpeechModel.letterIDs[scalar] != nil, scalar != " " {
                if pendingSpace, !out.isEmpty { out.append(" ") }
                pendingSpace = false
                out.append(scalar)
            } else {
                pendingSpace = true
            }
        }
        for scalar in typed.lowercased().unicodeScalars {
            if "çğıöşü".unicodeScalars.contains(scalar) {
                add(scalar)
                continue
            }
            let plain = String(scalar).decomposedStringWithCompatibilityMapping.unicodeScalars
                .filter { $0.properties.canonicalCombiningClass == .notReordered }
            if plain.isEmpty || !plain.allSatisfy({ SpeechModel.letterIDs[$0] != nil }) {
                pendingSpace = true
            } else {
                plain.forEach(add)
            }
        }
        return String(out)
    }

    /// The pieces of spoken text in the model's alphabet, each with the silence after it.
    static func chunk(_ text: String, speed: Double = 1) -> [SpokenPiece] {
        let limit = Int(min(maxLetters, lettersPerSecond * maxSeconds * speed))
        var pieces: [SpokenPiece] = []
        var rest = Array(trim(Array(text.unicodeScalars)))
        while !rest.isEmpty {
            var cut = rest.count
            var pause = 0.0
            if rest.count > limit {
                (cut, pause) = goodCut(rest, limit: limit)
            }
            let piece = trim(Array(rest[..<cut]))
            rest = trim(Array(rest[cut...]))
            if piece.contains(where: { $0.properties.isAlphabetic }) {
                pieces.append(SpokenPiece(text: finish(piece), pause: pause))
            }
        }
        if !pieces.isEmpty { pieces[pieces.count - 1].pause = 0 }
        return pieces
    }

    /// Where to end a piece: the last sentence end, else clause mark, else
    /// space that the limit can see, and only then the limit itself.
    private static func goodCut(_ text: [Unicode.Scalar], limit: Int) -> (Int, Double) {
        let closers: Set<Unicode.Scalar> = ["\"", "'", ")"]
        let enders: Set<Unicode.Scalar> = [".", "!", "?"]
        let spaces = stride(from: limit, to: 0, by: -1).filter { $0 < text.count && text[$0] == " " }
        for p in spaces {
            var i = p - 1
            while i >= 0, closers.contains(text[i]) { i -= 1 }
            if i >= 0, enders.contains(text[i]) { return (p, sentencePause) }
        }
        let marks: Set<Unicode.Scalar> = [",", ";", ":"]
        for p in spaces where marks.contains(text[p - 1]) { return (p, clausePause) }
        for p in spaces where text[p - 1] != " " { return (p, clausePause) }
        return (limit, 0)
    }

    private static func finish(_ piece: [Unicode.Scalar]) -> String {
        var end = piece.count
        let closers: Set<Unicode.Scalar> = ["\"", "'", ")"]
        while end > 0, closers.contains(piece[end - 1]) { end -= 1 }
        if end > 0, [".", "!", "?"].contains(piece[end - 1]) { return string(piece) }
        var keep = piece.count
        let dropped: Set<Unicode.Scalar> = [",", ";", ":", "-", " "]
        while keep > 0, dropped.contains(piece[keep - 1]) { keep -= 1 }
        return string(Array(piece[..<keep])) + "."
    }

    private static func trim(_ scalars: [Unicode.Scalar]) -> [Unicode.Scalar] {
        var a = 0, b = scalars.count
        while a < b, scalars[a] == " " { a += 1 }
        while b > a, scalars[b - 1] == " " { b -= 1 }
        return Array(scalars[a..<b])
    }

    private static func string(_ scalars: [Unicode.Scalar]) -> String {
        var view = String.UnicodeScalarView()
        view.append(contentsOf: scalars)
        return String(view)
    }
}
