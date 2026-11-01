import Foundation

/// Which word on the screen each word of a text being read is. The two lists
/// differ: the screen holds other things around the text, part of the text may
/// be scrolled away, the text read leaves out code blocks and addresses, and
/// the screen's words are recognized from a picture, so some are misread.
enum WordAligner {
    /// A run of words has to be this long to count, with this many of them next
    /// to each other on both sides: common words turn up by chance between any
    /// two texts, but not in a row.
    static let shortestRun = 4
    static let wordsInARow = 3
    /// A run goes on over this many words missing on either side.
    static let longestSkip = 3

    /// A word as both lists can agree on it: recognition mixes up the letters
    /// Turkish adds to the Latin ones, more than it mixes up anything else.
    static func fold(_ word: String) -> String {
        word.lowercased()
            .folding(options: .diacriticInsensitive, locale: nil)
            .replacingOccurrences(of: "ı", with: "i")
    }

    /// Fast recognition knows no ş and reads it as one of these. Left as they
    /// are they would also cut the word in two.
    static func withLetterForMarks(_ recognized: String) -> String {
        String(recognized.map { "*{}$§".contains($0) ? "s" : $0 })
    }

    /// For each word of `reading`, the index of that word in `screen`, or nil
    /// when it is not there. Both are folded already. The longest common
    /// subsequence keeps the two in order over any gap; where a word occurs
    /// more than once the later one wins, since the last reply is at the bottom.
    static func align(reading: [String], screen: [String]) -> [Int?] {
        var out = [Int?](repeating: nil, count: reading.count)
        let pairs = runs(of: commonSubsequence(reading, screen), wordCount: reading.count)
        for (index, pair) in pairs.enumerated() {
            out[pair.reading] = pair.screen
            // Words misread between two good ones are still about there.
            guard index > 0, sameRun(pairs[index - 1], pair) else { continue }
            let before = pairs[index - 1]
            let missing = pair.reading - before.reading
            let onScreen = pair.screen - before.screen
            guard missing > 1, onScreen > 1 else { continue }
            for step in 1..<missing {
                out[before.reading + step] = before.screen + step * onScreen / missing
            }
        }
        return out
    }

    struct Pair: Equatable {
        var reading: Int
        var screen: Int
    }

    private static func sameRun(_ a: Pair, _ b: Pair) -> Bool {
        b.reading - a.reading <= longestSkip + 1 && b.screen - a.screen <= longestSkip + 1
    }

    /// Only the runs that count. A text shorter than a run has to be there whole.
    static func runs(of pairs: [Pair], wordCount: Int) -> [Pair] {
        let long = min(shortestRun, max(wordCount, 1))
        let inARow = min(wordsInARow, max(wordCount, 1))
        func counts(_ run: [Pair]) -> Bool {
            guard run.count >= long else { return false }
            var row = 1, longest = 1
            for (a, b) in zip(run, run.dropFirst()) {
                row = b.reading - a.reading == 1 && b.screen - a.screen == 1 ? row + 1 : 1
                longest = max(longest, row)
            }
            return longest >= inARow
        }
        var kept: [Pair] = []
        var run: [Pair] = []
        for pair in pairs {
            if let last = run.last, !sameRun(last, pair) {
                if counts(run) { kept += run }
                run = []
            }
            run.append(pair)
        }
        if counts(run) { kept += run }
        return kept
    }

    /// In the order of `reading`. Words only one side has are left out first,
    /// which on a screen of other text removes most of the work.
    static func commonSubsequence(_ reading: [String], _ screen: [String]) -> [Pair] {
        let inScreen = Set(screen)
        let inReading = Set(reading)
        let a = reading.indices.filter { inScreen.contains(reading[$0]) }
        let b = screen.indices.filter { inReading.contains(screen[$0]) }
        guard !a.isEmpty, !b.isEmpty else { return [] }

        var table = [UInt16](repeating: 0, count: (a.count + 1) * (b.count + 1))
        let width = b.count + 1
        for i in 1...a.count {
            let word = reading[a[i - 1]]
            for j in 1...b.count {
                table[i * width + j] = word == screen[b[j - 1]]
                    ? table[(i - 1) * width + j - 1] + 1
                    : max(table[(i - 1) * width + j], table[i * width + j - 1])
            }
        }
        var pairs: [Pair] = []
        var i = a.count, j = b.count
        while i > 0, j > 0 {
            if reading[a[i - 1]] == screen[b[j - 1]] {
                pairs.append(Pair(reading: a[i - 1], screen: b[j - 1]))
                i -= 1
                j -= 1
            } else if table[(i - 1) * width + j] >= table[i * width + j - 1] {
                i -= 1
            } else {
                j -= 1
            }
        }
        return pairs.reversed()
    }
}
