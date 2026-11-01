import Foundation
import JavaScriptCore

/// Claude's Turkish, written for the eye, made ready for the ear. The speech
/// model reads Turkish spelling: an English word spelled the English way comes
/// out letter by letter, the same word in Turkish letters comes out right. So
/// symbols, code names and developer words here become what a Turkish developer
/// would say, and `TurkishNumbers` then reads numbers and dates.
///
/// Nothing converts unless it is listed here or is a camelCase name. A large
/// Turkish text corpus showed why: "pedal", "zebra", "yokum" and "pille" are all
/// in the English dictionary and rare in Turkish.
struct SpokenTurkish: Sendable {
    /// `word -> how a Turkish speaker says it`, for the parts of camelCase names (english.tsv).
    private let english: @Sendable (String) -> String?
    /// ALLCAPS words of 4 to 6 letters read as words, not letter by letter (caps.txt).
    private let capsWords: Set<String>

    init(english: @escaping @Sendable (String) -> String? = { _ in nil }, capsWords: Set<String> = []) {
        self.english = english
        self.capsWords = capsWords
    }

    /// The text for `TurkishNumbers`.
    func spoken(_ text: String) -> String {
        var t = Self.unescape(text.precomposedStringWithCanonicalMapping)
        t = Self.chord.replace(in: t) { match in
            let whole = match[0]
            return String(whole[..<(whole.firstIndex(of: "(") ?? whole.endIndex)]).trimmingCharacters(in: .whitespaces)
        }
        for (key, say) in Self.keys { t = t.replacingOccurrences(of: key, with: say) }
        t = Self.plusAfterKey.replace(in: t) { "\($0[1]) " }
        t = Self.brackets.replace(in: t) { match in
            let inner = match[1].trimmingCharacters(in: .whitespaces)
            if inner.isEmpty { return " " }
            let isCode = Self.codeOnly.matches(inner) && (inner.contains(".") || inner.contains("_") || Self.innerCapital.matches(inner))
            return isCode ? " " : ", \(inner),"
        }
        for (pattern, say) in Self.symbols { t = pattern.replace(in: t) { _ in say } }
        t = outsideAddresses(t, words)
        t = Self.lastKey.replace(in: t) { "\($0[1]) \(Self.letterNames[$0[2]] ?? $0[2])" }
        t = Self.spaceBeforeMark.replace(in: t) { $0[1] }
        t = Self.repeatedMarks.replace(in: t) { $0[1] }
        t = Self.commaBeforeEnd.replace(in: t) { $0[1] }
        return Self.spaces.replace(in: t) { _ in " " }.trimmingCharacters(in: CharacterSet(charactersIn: " ,"))
    }

    // MARK: Words

    private func outsideAddresses(_ text: String, _ convert: (String) -> String) -> String {
        var out = ""
        var last = text.startIndex
        for match in Self.address.ranges(in: text) {
            out += convert(String(text[last..<match.lowerBound]))
            out += text[match]
            last = match.upperBound
        }
        out += convert(String(text[last...]))
        return out
    }

    private func words(_ text: String) -> String {
        var t = Self.flag.replace(in: text) { $0[1] }
        t = Self.version.replace(in: t) { $0[1] }
        t = Self.verb.replace(in: t) { match in
            let stem = wordForm(match[1]) ?? match[1]
            return stem + Self.harmonize(stem, match[2])
        }
        t = Self.identifier.replace(in: t) { identifier($0[0]) }
        return Self.token.replace(in: t) { token($0[0], word: $0[1], suffix: $0[2]) }
    }

    private func token(_ whole: String, word: String, suffix: String) -> String {
        guard let spoken = wordForm(word) else { return whole }
        return suffix.isEmpty ? spoken : spoken + Self.harmonize(spoken, suffix)
    }

    /// foo_bar, Foo.bar, README.md, claude-replies: part by part, an extension by its letters.
    private func identifier(_ text: String) -> String {
        if let exact = Self.exact[text] { return exact }
        if Self.initialAndName.matches(text) { return text }
        if let dot = text.lastIndex(of: ".") {
            let ext = String(text[text.index(after: dot)...]).lowercased()
            if let spoken = Self.extensions[ext] {
                return "\(identifierParts(String(text[..<dot]))) nokta \(spoken)"
            }
        }
        return identifierParts(text)
    }

    private func identifierParts(_ text: String) -> String {
        var out: [String] = []
        for piece in Self.separated(text) {
            if piece.isSeparator {
                if piece.text == "." { out.append("nokta") }
            } else {
                out.append(Self.token.replace(in: piece.text) { token($0[0], word: $0[1], suffix: $0[2]) })
            }
        }
        return out.filter { !$0.isEmpty }.joined(separator: " ")
    }

    /// The spoken form of one written word, or nil when it stays as written.
    func wordForm(_ word: String) -> String? {
        if let exact = Self.exact[word] { return exact }
        if let any = Self.anyCase[word.lowercased()] { return any }
        if word.count == 2, word.first == "M", let digit = word.last, ("1"..."9").contains(digit) {
            return "Em \(digit)"
        }
        let isASCIILetters = word.unicodeScalars.allSatisfy { $0.isASCII && $0.properties.isAlphabetic }
        if word.count >= 4, Self.isAllCaps(word), capsWords.contains(word) || word.count >= 7 {
            return Self.turkishLower(word)
        }
        if isASCIILetters, word.dropFirst().contains(where: \.isUppercase), word.contains(where: \.isLowercase) {
            let parts = Self.camelParts.strings(in: word).map { part in
                wordForm(part) ?? respell(part) ?? part
            }
            return parts.filter { !$0.isEmpty }.joined(separator: " ")
        }
        return nil
    }

    /// A camelCase part: an acronym letter by letter, a word from the dictionary.
    private func respell(_ part: String) -> String? {
        if part.allSatisfy(\.isNumber) { return part }
        if part.count == 1 { return Self.englishLetters[part.uppercased()] }
        if Self.isAllCaps(part), part.count <= 5 {
            return part.map { Self.englishLetters[String($0)]?.capitalized ?? String($0) }.joined(separator: " ")
        }
        return english(part.lowercased())
    }

    // MARK: Suffixes

    /// A Turkish suffix re-fitted to how the word now sounds: Ay + leri is Ayları, Key + yi is Keyi.
    static func harmonize(_ stem: String, _ written: String) -> String {
        if ["yor", "ken", "ki", "gil"].contains(written) { return written }
        let low = turkishLower(stem)
        var last = low.last(where: { vowels.contains($0) }) ?? "e"
        let endsInVowel = low.last.map { vowels.contains($0) } ?? false
        var suffix = written
        if !endsInVowel, suffix.count >= 2, suffix.hasPrefix("y"), "aeıiuü".contains(suffix[suffix.index(after: suffix.startIndex)]) {
            suffix.removeFirst()
        } else if !endsInVowel, suffix.count == 3, suffix.hasPrefix("n"), suffix.hasSuffix("n"), "ıiuü".contains(suffix[suffix.index(after: suffix.startIndex)]) {
            suffix.removeFirst()
        } else if endsInVowel, let first = suffix.first, vowels.contains(first) {
            suffix = (suffix.count == 2 && "ıiuü".contains(first) && suffix.hasSuffix("n") ? "n" : "y") + suffix
        }
        var out = ""
        for c in suffix {
            switch c {
            case "a", "e":
                let new: Character = backVowels.contains(last) ? "a" : "e"
                out.append(new)
                last = new
            case "ı", "i", "u", "ü":
                let new: Character = switch (backVowels.contains(last), roundedVowels.contains(last)) {
                case (true, false): "ı"
                case (true, true): "u"
                case (false, false): "i"
                case (false, true): "ü"
                }
                out.append(new)
                last = new
            case "o", "ö":
                out.append(c)
                last = c
            default:
                out.append(c)
            }
        }
        return out
    }

    private static let vowels: Set<Character> = ["a", "e", "ı", "i", "o", "ö", "u", "ü"]
    private static let backVowels: Set<Character> = ["a", "ı", "o", "u"]
    private static let roundedVowels: Set<Character> = ["o", "u", "ö", "ü"]

    static func turkishLower(_ text: String) -> String {
        text.replacingOccurrences(of: "I", with: "ı").replacingOccurrences(of: "\u{0130}", with: "i").lowercased()
    }

    private static func isAllCaps(_ word: String) -> Bool {
        word.contains(where: \.isLetter) && word.allSatisfy { $0.isUppercase || !$0.isLetter } && word.allSatisfy { $0.isLetter }
    }

    private static func unescape(_ text: String) -> String {
        guard text.contains("&") else { return text }
        return [("&amp;", "&"), ("&lt;", "<"), ("&gt;", ">"), ("&quot;", "\""), ("&#39;", "'")].reduce(text) {
            $0.replacingOccurrences(of: $1.0, with: $1.1)
        }
    }

    private struct Separated {
        var text: String
        var isSeparator: Bool
    }

    private static func separated(_ text: String) -> [Separated] {
        var out: [Separated] = []
        var current = ""
        var inSeparator = false
        for c in text {
            let isSeparator = "._:-".contains(c)
            if isSeparator != inSeparator, !current.isEmpty {
                out.append(Separated(text: current, isSeparator: inSeparator))
                current = ""
            }
            inSeparator = isSeparator
            current.append(c)
        }
        if !current.isEmpty { out.append(Separated(text: current, isSeparator: inSeparator)) }
        return out
    }

    // MARK: Patterns

    private static let keys: [(String, String)] = [
        ("\u{2303}", "Kontrol "), ("\u{2325}", "Opşın "), ("\u{2318}", "Komut "), ("\u{21E7}", "Şift "),
        ("\u{21A9}", "Enter "), ("\u{238B}", "Esc "),
    ]
    private static let chord = SpeechPattern(#"\b(?:Control|Command|Option|Shift|Alt|Cmd|Ctrl)(?:\s*\+\s*\w+)+\s*\(\s*[\x{2303}\x{2325}\x{2318}\x{21E7}][^)]*\)"#)
    private static let plusAfterKey = SpeechPattern(#"\b(Cmd|Ctrl|Shift|Option|Alt|Control|Command)\s*\+\s*"#)
    private static let brackets = SpeechPattern(#"\(([^()]*)\)"#)
    private static let codeOnly = SpeechPattern(#"^[A-Za-z_][\w.:-]*(?:\(\))?$"#)
    private static let innerCapital = SpeechPattern(#"[a-z][A-Z]"#)
    private static let symbols: [(SpeechPattern, String)] = [
        (SpeechPattern(#"\s*(?:\x{2192}|\x{21D2}|->|=>)\s*"#), ", "),
        (SpeechPattern(#"\s+>\s+"#), ", "),
        (SpeechPattern(#"(?<=\s)[-\x{2013}\x{2014}](?=\s)"#), ","),
        (SpeechPattern(#"\s*&\s*"#), " ve "),
        (SpeechPattern(#"[~\x{2248}]\s*(?=\d)"#), "yaklaşık "),
        (SpeechPattern(#"(?<=\d)\s*[\x{00D7}x](?=\s|$)"#), " kat"),
        (SpeechPattern(#"#(?=\d)"#), "numara "),
        (SpeechPattern(#"["\x{201C}\x{201D}\x{201E}\x{00AB}\x{00BB}]"#), ""),
        (SpeechPattern(#"[\x{2713}\x{2714}\x{2705}\x{274C}\x{26A0}\x{FE0F}\x{1F389}\x{1F680}\x{2022}\x{00B7}]"#), " "),
    ]
    private static let address = SpeechPattern(#"(?i)[\w.+-]+@[\w-]+(?:\.[\w-]+)+|(?:https?://|www\.)\S+|\b[\w-]+(?:\.[\w-]+)*\.(?:com|net|org|ai|io|co|app|dev|gov|edu|tr|me|info)(?:\.[a-z]{2})?\b"#)
    private static let flag = SpeechPattern(#"(?<!\S)--?([A-Za-z][\w-]*)"#)
    private static let version = SpeechPattern(#"\bv(\d+(?:\.\d+)+)"#)
    private static let verb = SpeechPattern(#"(?i)(?<![\w'\x{2019}])(push|pull|commit|merge|rebase|deploy|build|fix|debug|cache|hook|tag)(l[ae][a-zçğıöşü]*)(?!\w)"#)
    private static let identifier = SpeechPattern(#"(?<![\w@'\x{2019}])[A-Za-z_][A-Za-z0-9_]*(?:[._:-]+[A-Za-z0-9_]+)+(?![\w@])"#)
    private static let token = SpeechPattern(#"(?<![\w@./-])([A-Za-z][A-Za-z0-9+-]*)(?:['\x{2019}]([a-zçğıöşü]+))?(?![\w@])"#)
    private static let camelParts = SpeechPattern(#"[A-Z]{2,}(?=[A-Z][a-z]|\b|[0-9]|$)|[A-Z]?[a-z]+|[A-Z]+|[0-9]+"#)
    private static let initialAndName = SpeechPattern(#"^[A-Za-z]\.[A-ZÇĞİÖŞÜ]\w*$"#)
    private static let lastKey = SpeechPattern(#"\b(Kontrol|Opşın|Komut|Şift) ([A-Z])\b"#)
    private static let spaceBeforeMark = SpeechPattern(#"\s+([,.;:!?])"#)
    private static let repeatedMarks = SpeechPattern(#"([,;:])(?:\s*[,;:])+"#)
    private static let commaBeforeEnd = SpeechPattern(#",\s*([.!?])"#)
    private static let spaces = SpeechPattern(#"\s+"#)

    // MARK: How these are said

    private static let letterNames: [String: String] = [
        "A": "a", "B": "be", "C": "ce", "D": "de", "E": "e", "F": "fe", "G": "ge", "H": "he", "I": "ı", "J": "je", "K": "ke", "L": "le", "M": "me",
        "N": "ne", "O": "o", "P": "pe", "Q": "ku", "R": "re", "S": "se", "T": "te", "U": "u", "V": "ve", "W": "ve", "X": "iks", "Y": "ye", "Z": "ze",
    ]
    private static let englishLetters: [String: String] = [
        "A": "ey", "B": "bi", "C": "si", "D": "di", "E": "i", "F": "ef", "G": "ci", "H": "eyç", "I": "ay", "J": "cey", "K": "key", "L": "el", "M": "em",
        "N": "en", "O": "o", "P": "pi", "Q": "kyu", "R": "ar", "S": "es", "T": "ti", "U": "yu", "V": "vi", "W": "dabılyu", "X": "eks", "Y": "vay", "Z": "zi",
    ]
    private static let extensions: [String: String] = [
        "md": "em di", "swift": "svift", "json": "ceyson", "yaml": "yemıl", "yml": "yemıl", "py": "pi vay", "sh": "es eyç", "js": "ce es",
        "ts": "ti es", "html": "aç te me le", "css": "si es es", "txt": "te ikste", "plist": "pi list", "app": "ep", "zip": "zip", "wav": "vav",
        "png": "pi en ci", "jpg": "jipeg", "pdf": "pe de ef", "log": "log", "dmg": "di em ci", "toml": "tomıl", "onnx": "oniks", "pt": "pi ti",
    ]
    /// Exact case: an acronym or a brand.
    private static let exact: [String: String] = [
        "API": "Ey Pi Ay", "APIs": "Ey Pi Aylar", "SDK": "Es Di Key", "CLI": "Si El Ay", "URL": "Yu Ar El", "HTTP": "Eyç Ti Ti Pi",
        "HTTPS": "Eyç Ti Ti Pi Es", "SSH": "Es Es Eyç", "UI": "Yu Ay", "UX": "Yu Eks", "PR": "Pi Ar", "CI": "Si Ay", "CD": "Si Di",
        "HTML": "Aç Te Me Le", "CSS": "Si Es Es", "JSON": "Ceyson", "YAML": "Yemıl", "SQL": "Es Ku El", "XML": "Eks Em El",
        "GPU": "Ci Pi Yu", "CPU": "Si Pi Yu", "SSD": "Es Es Di", "USB": "Yu Es Bi", "ID": "Ay Di", "AI": "Ey Ay", "LLM": "El El Em",
        "TTS": "Ti Ti Es", "MLX": "Em El Eks", "ONNX": "Oniks", "MCP": "Em Si Pi", "PID": "Pi Ay Di", "OS": "O Es", "VM": "Vi Em",
        "README": "ridmi", "SECURITY": "sekyuriti", "CHANGELOG": "çeync log", "LICENSE": "laysıns", "TODO": "tu du", "NOTICE": "notis",
        "CLAUDE": "klod", "AGENTS": "eycınts", "SSID": "Es Es Ay Di", "SIGSTOP": "Sig Stop", "SIGCONT": "Sig Kont", "CRISPR": "Krispır", "MP3": "Em Pe Üç",
        "Mac": "Mek", "Macs": "Mekler", "macOS": "mek o es", "iOS": "ay o es", "iPadOS": "aypet o es", "iMessage": "Aymesaj",
        "iCloud": "Aykılaud", "iPad": "Aypet", "iPhone": "Ayfon", "MacBook": "Mekbuk", "AirDrop": "Er Drop", "Xcode": "Eks Kod",
        "SwiftUI": "Svift Yu Ay", "AppKit": "Ep Kit", "Swift": "Svift", "GitHub": "Githab", "GitLab": "Gitlab", "Git": "Git",
        "Claude": "Klod", "Code": "Kod", "Anthropic": "Entropik", "OpenAI": "Opın Ey Ay", "ChatGPT": "Çet Ci Pi Ti", "Gemini": "Cemini",
        "Sonnet": "Sonıt", "Haiku": "Hayku", "Opus": "Opus", "Fable": "Feybıl", "Python": "Paytın", "JavaScript": "Cavaskript",
        "TypeScript": "Taypskript", "React": "Riekt", "Node": "Nod", "Keychain": "Kiçeyn", "Finder": "Faynder", "Dock": "Dok",
        "LaunchAgent": "Lonç Eycınt", "LaunchDaemon": "Lonç Dimın", "Spotlight": "Spotlayt", "Chromium": "Kromiyum", "Chrome": "Krom",
        "Safari": "Safari", "Slack": "Slek", "Docker": "Dokır", "Tailscale": "Teylskeyl", "Remote": "Rimot", "Bluetooth": "Blutut",
        "Wi-Fi": "Vayfay", "WiFi": "Vayfay", "YouTube": "Yutub", "WhatsApp": "Vatsap", "LinkedIn": "Linkedin", "PowerPoint": "Pavır Poynt",
        "iPod": "Aypod", "iTunes": "Aytuns", "eBay": "İbey", "SpaceX": "Speys Eks", "FedEx": "Fedeks", "ArGe": "Ar Ge", "mRNA": "Em Ar En Ey",
        "pH": "Pe He", "fMRI": "Ef Em Ar Ay", "Control": "Kontrol", "Option": "Opşın", "Command": "Komut", "Shift": "Şift", "Cmd": "Komut", "Ctrl": "Kontrol",
    ]
    /// Any case: words Claude writes in lowercase in the middle of a Turkish sentence.
    private static let anyCase: [String: String] = [
        "commit": "komit", "commits": "komitler", "push": "puş", "pull": "pul", "merge": "mörç", "rebase": "ribeys", "branch": "branç",
        "main": "meyn", "master": "master", "tag": "teg", "release": "riliz", "deploy": "diploy", "build": "bild", "hook": "huk", "hooks": "huklar",
        "bug": "bag", "bugs": "baglar", "fix": "fiks", "debug": "dibag", "cache": "keş", "server": "sörvır", "client": "klayınt",
        "frontend": "front end", "backend": "bek end", "framework": "freymvörk", "script": "skript", "shell": "şel", "worktree": "vörk tri",
        "sandbox": "sendboks", "plist": "pi list", "filter": "filtır", "timeout": "taym aut", "default": "difolt", "config": "konfig",
        "prompt": "prompt", "session": "seşın", "agent": "eycınt", "agents": "eycıntlar", "shortcut": "şortkat", "npm": "en pi em",
        "pip": "pip", "uv": "yu vi", "sudo": "sudo", "stash": "steş", "diff": "dif", "repo": "repo", "workflow": "vörkflov", "token": "token",
        "tokens": "tokenler", "hotspot": "hotspot", "launchctl": "lonç kontrol", "pmset": "pi em set", "codesign": "kod sayn", "true": "tru", "false": "fols",
        "nil": "nil", "null": "nal", "string": "string", "struct": "strakt", "enum": "inam", "async": "asenk", "await": "avet", "actor": "aktör",
        "wrapper": "repır", "parser": "parsır", "array": "erey", "render": "render", "runtime": "rantaym", "update": "apdeyt", "upstream": "apstrim",
        "signing": "sayning", "bundle": "bandıl", "installer": "instalır", "install": "instol", "swift": "svift", "git": "git", "scan": "sken",
        "text": "tekst", "router": "rutır", "wiki": "viki", "bypass": "baypas", "offshore": "ofşor", "joystick": "coystik",
        "docker": "dokır", "backstop": "bekstop", "app": "ep", "claude": "klod", "library": "laybreri", "compose": "kompoz", "scripts": "skriptler",
        "hoc": "hok", "sudoers": "sudoırz", "docs": "doks", "tmux": "ti maks", "api": "ey pi ay", "anthropic": "entropik", "settings": "setings",
        "pid": "pi ay di", "applications": "eplikeyşıns", "application": "eplikeyşın", "support": "sapport", "ps": "pi es", "up": "ap", "run": "ran",
        "continue": "kontinyu", "issue": "işu", "cdhash": "si di heş", "verify": "verifay", "uninstall": "anistol", "buildx": "bild eks",
        "resources": "risorsız", "deny": "dinay", "word": "vörd", "excel": "eksel", "view": "vyu", "github": "githab", "logs": "logs", "attestation": "ettesteyşın",
        "inspect": "inspekt", "artifact": "artifekt", "signature": "signeçır", "nightly": "naytli", "occluded": "okluded", "desktop": "desktop", "info": "info",
        "gh": "ci eyç", "cd": "si di",
    ]
}

/// One fixed regular expression, with a replacement that sees its groups.
struct SpeechPattern: @unchecked Sendable {
    private let regex: NSRegularExpression

    init(_ pattern: String) {
        // Fixed strings, covered by the tests.
        regex = try! NSRegularExpression(pattern: pattern)
    }

    func matches(_ text: String) -> Bool {
        regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
    }

    func strings(in text: String) -> [String] {
        ranges(in: text).map { String(text[$0]) }
    }

    func ranges(in text: String) -> [Range<String.Index>] {
        regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap { Range($0.range, in: text) }
    }

    /// `build` gets the match, then each group ("" for one that took no part).
    func replace(in text: String, _ build: ([String]) -> String) -> String {
        var out = ""
        var last = text.startIndex
        for match in regex.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
            guard let whole = Range(match.range, in: text) else { continue }
            out += text[last..<whole.lowerBound]
            let groups = (0..<match.numberOfRanges).map { i -> String in
                Range(match.range(at: i), in: text).map { String(text[$0]) } ?? ""
            }
            out += build(groups)
            last = whole.upperBound
        }
        out += text[last...]
        return out
    }
}

/// Numbers, dates, times, money and abbreviations in written Turkish, read out
/// with the right suffixes: 14:30'da is "on dört otuzda". The rules are a
/// third-party library in JavaScript (Resources/Voice/NOTICE.md), run in the
/// system's JavaScriptCore with no way out of its context: no network, no files.
/// Not thread-safe; `SpeechSession` calls it from one task at a time.
final class TurkishNumbers: @unchecked Sendable {
    private let context: JSContext
    private let function: JSValue

    init(script url: URL) throws {
        let source = try String(contentsOf: url, encoding: .utf8)
        guard let context = JSContext() else { throw SpeechModelError.missing("a script context") }
        context.evaluateScript(source, withSourceURL: url)
        guard context.exception == nil,
              let function = context.objectForKeyedSubscript("trnorm")?.objectForKeyedSubscript("normalize"), function.isObject else {
            throw SpeechModelError.missing("the number rules")
        }
        self.context = context
        self.function = function
    }

    /// The spoken form, or the text as it came if the rules could not read it.
    func normalize(_ text: String) -> String {
        context.exception = nil
        let result = function.call(withArguments: [text])
        guard context.exception == nil, let result, result.isString, let out = result.toString() else {
            context.exception = nil
            return text
        }
        return out
    }
}
