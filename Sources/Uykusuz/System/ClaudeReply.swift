import Foundation

/// The message Claude ended a turn with (fork addition). The `Stop` hook's
/// `last_assistant_message` is that message alone, none of the steps before
/// it, so nothing has to be picked out of the chat or the transcript.
struct ClaudeReply: Codable, Equatable, Sendable {
    /// The session id as `ClaudeHookCommand.markerName` makes it safe.
    var session: String
    var title: String
    /// Markdown, as Claude wrote it (`ClaudeReplySpeech`).
    var text: String
    var at: Date
}

/// Hands a reply from `Uykusuz --claude-hook`, which runs and exits, to the
/// app: one owner-only file per session, renamed into place so the app never
/// reads half of one, and removed as soon as the app has read it.
enum ClaudeReplyInbox {
    /// A reply older than this is not read aloud: the app was not running
    /// when Claude finished.
    static let maxAge: TimeInterval = 2 * 60

    static func directory(_ paths: Paths) -> URL {
        paths.appSupport.appendingPathComponent("claude-replies", isDirectory: true)
    }

    static func put(_ reply: ClaudeReply, paths: Paths, now: Date = Date()) throws {
        let dir = directory(paths)
        _ = try OwnerOnly.createDirectory(dir)
        sweep(dir, now: now)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let temp = dir.appendingPathComponent(".\(UUID().uuidString).tmp")
        try OwnerOnly.createFile(at: temp, contents: encoder.encode(reply))
        guard rename(temp.path, dir.appendingPathComponent("\(reply.session).json").path) == 0 else {
            let failure = errno
            try? FileManager.default.removeItem(at: temp)
            throw OwnerOnlyError.write(path: temp.path, errno: failure)
        }
    }

    /// The replies waiting, oldest first; their files are gone afterwards.
    static func take(paths: Paths) -> [ClaudeReply] {
        let dir = directory(paths)
        let names = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        var replies: [ClaudeReply] = []
        for name in names where name.hasSuffix(".json") {
            let file = dir.appendingPathComponent(name)
            if let data = try? Data(contentsOf: file), let reply = try? decoder.decode(ClaudeReply.self, from: data) {
                replies.append(reply)
            }
            try? FileManager.default.removeItem(at: file)
        }
        return replies.sorted { $0.at < $1.at }
    }

    /// With the app not running nothing takes the files, so a conversation's
    /// text does not pile up: each new reply removes the ones past `maxAge`.
    private static func sweep(_ dir: URL, now: Date) {
        let fm = FileManager.default
        let files = (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        for file in files {
            let modified = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
            if let modified, now.timeIntervalSince(modified) > maxAge { try? fm.removeItem(at: file) }
        }
    }

    /// What the window is headed with: the session's title as Claude's own
    /// sidebar shows it, else the folder it runs in. Claude Code repeats the
    /// title through the transcript, so the end of the file has it.
    static func title(transcript: String?, cwd: String?) -> String {
        if let transcript, let data = ClaudeDigest.tail(of: URL(fileURLWithPath: transcript), bytes: 256 << 10) {
            for line in data.split(separator: UInt8(ascii: "\n")).reversed() where line.range(of: Data("custom-title".utf8)) != nil {
                let object = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any]
                if let title = object?["customTitle"] as? String, !title.isEmpty { return title }
            }
        }
        if let cwd, !cwd.isEmpty { return URL(fileURLWithPath: cwd).lastPathComponent }
        return "Claude"
    }
}

/// Claude's markdown as something to listen to (fork addition): the marks
/// are dropped, a code block is named instead of spelled out, a link is its
/// text and a path its file name. Each paragraph, heading and list item is
/// one line, and one that does not end a sentence gets a period so the voice
/// pauses there.
enum ClaudeReplySpeech {
    static let codeBlock = "Kod bloğu atlandı."
    static let link = "bağlantı"

    static func plain(_ markdown: String) -> String {
        var lines: [String] = []
        var paragraph: [String] = []
        var inFence = false

        func endParagraph() {
            guard !paragraph.isEmpty else { return }
            lines.append(paragraph.joined(separator: " "))
            paragraph.removeAll()
        }
        func addOwnLine(_ text: String) {
            endParagraph()
            let spoken = inline(text)
            if !spoken.isEmpty { lines.append(endingASentence(spoken)) }
        }

        for raw in markdown.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("```") || line.hasPrefix("~~~") {
                if !inFence { addOwnLine(codeBlock) }
                inFence.toggle()
            } else if inFence {
                continue
            } else if line.isEmpty {
                endParagraph()
            } else if isRule(line) || isTableDivider(line) {
                endParagraph()
            } else if let rest = withoutPrefix(headingPrefix, line) ?? withoutPrefix(bulletPrefix, line) {
                addOwnLine(rest)
            } else if numberedPrefix.firstMatch(in: line) {
                addOwnLine(line)
            } else if line.hasPrefix("|") {
                addOwnLine(tableCells(line).joined(separator: ", "))
            } else {
                let spoken = inline(withoutPrefix(quotePrefix, line) ?? line)
                if !spoken.isEmpty { paragraph.append(spoken) }
            }
        }
        endParagraph()
        return lines.joined(separator: "\n")
    }

    // MARK: Lines

    private static let headingPrefix = Pattern(#"^#{1,6}\s+"#)
    private static let bulletPrefix = Pattern(#"^[-*+]\s+(\[[ xX]\]\s+)?"#)
    private static let numberedPrefix = Pattern(#"^\d+[.)]\s+"#)
    private static let quotePrefix = Pattern(#"^>+\s?"#)
    private static let rule = Pattern(#"^([-*_])\s*(\1\s*){2,}$"#)
    private static let tableDivider = Pattern(#"^\|?\s*:?-+:?\s*(\|\s*:?-+:?\s*)*\|?$"#)

    private static func withoutPrefix(_ prefix: Pattern, _ line: String) -> String? {
        prefix.firstMatch(in: line) ? prefix.replacing(in: line, with: "") : nil
    }

    private static func isRule(_ line: String) -> Bool { rule.firstMatch(in: line) }

    private static func isTableDivider(_ line: String) -> Bool {
        line.contains("-") && tableDivider.firstMatch(in: line)
    }

    private static func tableCells(_ line: String) -> [String] {
        line.split(separator: "|").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    private static func endingASentence(_ text: String) -> String {
        guard let last = text.last, !".!?:;\u{2026}".contains(last) else { return text }
        return text + "."
    }

    // MARK: Within a line

    /// In this order: a link's address and a code span's marks go before a
    /// path is shortened, and a bare address after the links are done.
    private static let replacements: [(Pattern, String)] = [
        (Pattern(#"!?\[([^\]]*)\]\([^)]*\)"#), "$1"),
        (Pattern(#"`+([^`]+)`+"#), "$1"),
        (Pattern(#"https?://[^\s)]+"#), link),
        (Pattern(#"(?:[\w.~-]*/)+([\w-]+\.[A-Za-z]\w*)"#), "$1"),
        (Pattern(#"(?=[\w.~/-]*\p{L})(?:[\w.~-]*/){2,}([\w.-]+)/?"#), "$1"),
        (Pattern(#"([\w-]+\.[A-Za-z]\w*):\d+(?:-\d+)?"#), "$1"),
        (Pattern(#"\*\*(.+?)\*\*"#), "$1"),
        (Pattern(#"(?<!\w)__(?=\S)(.+?)(?<=\S)__(?!\w)"#), "$1"),
        (Pattern(#"(?<![\w*])\*(?=\S)(.+?)(?<=\S)\*(?![\w*])"#), "$1"),
        (Pattern(#"(?<!\w)_(?=\S)(.+?)(?<=\S)_(?!\w)"#), "$1"),
        (Pattern(#"~~(.+?)~~"#), "$1"),
    ]

    private static func inline(_ text: String) -> String {
        replacements.reduce(text) { $1.0.replacing(in: $0, with: $1.1) }
            .trimmingCharacters(in: .whitespaces)
    }

    private struct Pattern: @unchecked Sendable {
        let regex: NSRegularExpression

        init(_ pattern: String) {
            // Fixed strings, covered by the tests.
            regex = try! NSRegularExpression(pattern: pattern)
        }

        func firstMatch(in text: String) -> Bool {
            regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
        }

        func replacing(in text: String, with template: String) -> String {
            regex.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: template)
        }
    }
}
