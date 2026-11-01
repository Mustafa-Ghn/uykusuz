import Foundation

/// The last thing Claude said in a chat (fork addition): the message its turn
/// ended on, none of the steps before it.
struct ClaudeReply: Equatable, Sendable {
    /// The Claude Code session it is from.
    var session: String
    var title: String
    /// Markdown, as Claude wrote it (`ClaudeReplySpeech`).
    var text: String
    var at: Date
}

/// Finds the chat the user is looking at and what Claude last said there
/// (fork addition). Claude's desktop app stamps `lastFocusedAt` in a chat's
/// record when the user goes to it, so the newest stamp is the chat in front
/// of them. Only that stamp and the session's id are taken from a record, and
/// only the session's title, folder and last message from a transcript.
/// Without any record, as with Claude Code in a terminal alone, the transcript
/// written to last stands in.
enum ClaudeChats {
    static var defaultSessionsDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Claude/claude-code-sessions", isDirectory: true)
    }

    static func lastReply(
        sessions: URL = defaultSessionsDirectory,
        projects: URL = ClaudeDigest.defaultProjectsDirectory
    ) -> ClaudeReply? {
        let file = focusedSession(in: sessions).map { transcript(of: $0, in: projects) } ?? newestTranscript(in: projects)
        return file.flatMap(reply(in:))
    }

    /// The session of the chat with the newest focus stamp, from the records
    /// at `<account>/<organization>/local_<id>.json`.
    static func focusedSession(in sessions: URL) -> String? {
        var best: (focus: Double, session: String)?
        for account in children(of: sessions) {
            for organization in children(of: account) {
                for file in children(of: organization) where file.lastPathComponent.hasPrefix("local_") && file.pathExtension == "json" {
                    guard let data = try? Data(contentsOf: file),
                          let record = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                          let focus = record["lastFocusedAt"] as? Double,
                          let session = record["cliSessionId"] as? String else { continue }
                    if focus > best?.focus ?? 0 { best = (focus, session) }
                }
            }
        }
        return best?.session
    }

    static func transcript(of session: String, in projects: URL) -> URL? {
        // It goes into a path.
        guard ClaudeHookCommand.markerName(session) == "\(session).json" else { return nil }
        return children(of: projects)
            .map { $0.appendingPathComponent("\(session).jsonl") }
            .first { FileManager.default.fileExists(atPath: $0.path) }
    }

    static func newestTranscript(in projects: URL) -> URL? {
        func modified(_ file: URL) -> Date {
            (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
        }
        return children(of: projects)
            .flatMap(children(of:))
            .filter { $0.pathExtension == "jsonl" && !$0.lastPathComponent.hasPrefix("agent-") }
            .max { modified($0) < modified($1) }
    }

    /// What Claude last said in a transcript. A message is one line per
    /// block, sharing the message's id, and walking back from the end the
    /// first with text is the last thing on the screen: a message that only
    /// runs tools says nothing. nil when Claude has said nothing.
    static func reply(in file: URL) -> ClaudeReply? {
        guard let data = ClaudeDigest.tail(of: file) else { return nil }
        let titleMark = Data("customTitle".utf8)
        let assistantMark = Data("\"assistant\"".utf8)
        func object(_ line: Data.SubSequence) -> [String: Any]? {
            (try? JSONSerialization.jsonObject(with: Data(line))) as? [String: Any]
        }
        var texts: [String] = []
        var message: String?
        var at: Date?
        var folder: String?
        var title: String?
        var complete = false
        for line in data.split(separator: UInt8(ascii: "\n")).reversed() {
            if title == nil, line.range(of: titleMark) != nil, let found = object(line)?["customTitle"] as? String, !found.isEmpty {
                title = found
            }
            if complete {
                if title != nil { break }
                continue
            }
            guard line.range(of: assistantMark) != nil, let entry = object(line),
                  entry["type"] as? String == "assistant",
                  entry["isSidechain"] as? Bool != true,
                  entry["isApiErrorMessage"] as? Bool != true,
                  let body = entry["message"] as? [String: Any],
                  body["model"] as? String != "<synthetic>" else { continue }
            let id = body["id"] as? String
            if !texts.isEmpty, id == nil || id != message {
                complete = true
                continue
            }
            let blocks = (body["content"] as? [[String: Any]] ?? []).compactMap { block -> String? in
                guard block["type"] as? String == "text",
                      let text = (block["text"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
                return text
            }
            guard !blocks.isEmpty else { continue }
            if texts.isEmpty {
                message = id
                at = (entry["timestamp"] as? String).flatMap(ClaudeDigest.timestamp)
                folder = (entry["cwd"] as? String).flatMap { $0.isEmpty ? nil : URL(fileURLWithPath: $0).lastPathComponent }
            }
            texts.insert(contentsOf: blocks, at: 0)
        }
        guard !texts.isEmpty else { return nil }
        return ClaudeReply(
            session: file.deletingPathExtension().lastPathComponent,
            title: title ?? folder ?? "Claude",
            text: texts.joined(separator: "\n\n"),
            at: at ?? Date()
        )
    }

    private static func children(of folder: URL) -> [URL] {
        (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
    }
}

/// `Uykusuz --last-reply`: prints which chat the shortcut would read and what
/// it would say, to check either in silence.
enum LastReplyCommand {
    static let flag = "--last-reply"

    static func run(_ arguments: [String], find: () -> ClaudeReply? = { ClaudeChats.lastReply() }) -> Int32? {
        guard arguments.first == flag else { return nil }
        guard let reply = find() else {
            print(ClaudeReplyReader.nothingToRead)
            return 0
        }
        print("Sohbet: \(reply.title)")
        print("")
        print(ClaudeReplySpeech.plain(reply.text))
        return 0
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
