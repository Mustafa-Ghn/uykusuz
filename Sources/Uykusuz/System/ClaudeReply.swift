import Foundation

/// The last thing Claude said in a chat (fork addition): the message its turn
/// ended on, none of the steps before it. While Claude waits on the user to
/// approve a plan, that plan.
struct ClaudeReply: Equatable, Sendable {
    /// The Claude Code session it is from.
    var session: String
    var title: String
    /// Markdown, as Claude wrote it (`ClaudeReplySpeech`).
    var text: String
    var at: Date
    /// The plan the chat waits on the user to approve, read instead of the
    /// last message.
    var isPlan = false
}

/// Finds the chat the user is looking at and what Claude last said there
/// (fork addition). Claude's desktop app stamps `lastFocusedAt` in a chat's
/// record when the user goes to it, so the newest stamp is the chat in front
/// of them. Only that stamp and the session's id are taken from a record, and
/// only the session's title, folder and last message from a transcript, or
/// the plan waiting on the user and that plan's file. Without any record, as
/// with Claude Code in a terminal alone, the transcript written to last
/// stands in.
enum ClaudeChats {
    static var defaultSessionsDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Claude/claude-code-sessions", isDirectory: true)
    }

    /// Where Claude Code writes the plans it makes in plan mode.
    static var defaultPlansDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/plans", isDirectory: true)
    }

    /// The tool Claude hands a plan in with, to wait there for the user's approval.
    static let planTool = "ExitPlanMode"
    /// A plan file bigger than this is not read; the plan Claude handed in is.
    static let planFileBytes = 1 << 20

    static func lastReply(
        sessions: URL = defaultSessionsDirectory,
        projects: URL = ClaudeDigest.defaultProjectsDirectory,
        plans: URL = defaultPlansDirectory
    ) -> ClaudeReply? {
        let file = focusedSession(in: sessions).map { transcript(of: $0, in: projects) } ?? newestTranscript(in: projects)
        return file.flatMap { reply(in: $0, plans: plans) }
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

    /// What the shortcut reads in a transcript: the plan Claude waits on the
    /// user to approve, or else what Claude last said. nil when Claude has
    /// said nothing.
    static func reply(in file: URL, plans: URL = defaultPlansDirectory) -> ClaudeReply? {
        guard let data = ClaudeDigest.tail(of: file) else { return nil }
        let lines = data.split(separator: UInt8(ascii: "\n"))
        guard let said = pendingPlan(in: lines, plans: plans) ?? lastMessage(in: lines) else { return nil }
        return ClaudeReply(
            session: file.deletingPathExtension().lastPathComponent,
            title: title(in: lines) ?? said.folder ?? "Claude",
            text: said.text,
            at: said.at ?? Date(),
            isPlan: said.isPlan
        )
    }

    private struct Said {
        var text: String
        var at: Date?
        var folder: String?
        var isPlan = false
    }

    /// What Claude last said. A message is one line per block, sharing the
    /// message's id, and walking back from the end the first with text is the
    /// last thing on the screen: a message that only runs tools says nothing.
    private static func lastMessage(in lines: [Data.SubSequence]) -> Said? {
        var texts: [String] = []
        var message: String?
        var at: Date?
        var folder: String?
        for line in lines.reversed() where line.range(of: assistantMark) != nil {
            guard let entry = object(line), isClaude(entry), let body = entry["message"] as? [String: Any] else { continue }
            let id = body["id"] as? String
            if !texts.isEmpty, id == nil || id != message { break }
            let blocks = (body["content"] as? [[String: Any]] ?? []).compactMap { block -> String? in
                guard block["type"] as? String == "text",
                      let text = (block["text"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
                return text
            }
            guard !blocks.isEmpty else { continue }
            if texts.isEmpty {
                message = id
                at = timestamp(of: entry)
                folder = Self.folder(of: entry)
            }
            texts.insert(contentsOf: blocks, at: 0)
        }
        guard !texts.isEmpty else { return nil }
        return Said(text: texts.joined(separator: "\n\n"), at: at, folder: folder)
    }

    /// The plan the chat waits on the user to approve: Claude's last message
    /// hands one in (`planTool`) and nothing has answered that call yet.
    /// Approving or turning the plan down answers it, so a plan being worked
    /// on is not read again. A plan is read from its file, which the user may
    /// have changed since, when that is one of Claude Code's plans; otherwise
    /// it is the text Claude handed in.
    private static func pendingPlan(in lines: [Data.SubSequence], plans: URL) -> Said? {
        var answered: Set<String> = []
        var seen = false
        var message: String?
        for line in lines.reversed() where line.range(of: assistantMark) != nil || line.range(of: userMark) != nil {
            guard let entry = object(line), entry["isSidechain"] as? Bool != true else { continue }
            if entry["type"] as? String == "user" {
                // The answers to the tools of Claude's last message come after
                // it; anything else from the user means the chat went on.
                let blocks = (entry["message"] as? [String: Any])?["content"] as? [[String: Any]] ?? []
                let results = blocks.filter { $0["type"] as? String == "tool_result" }
                guard !results.isEmpty, results.count == blocks.count else { return nil }
                answered.formUnion(results.compactMap { $0["tool_use_id"] as? String })
                continue
            }
            guard isClaude(entry), let body = entry["message"] as? [String: Any] else { continue }
            let id = body["id"] as? String
            if seen, id == nil || id != message { return nil }
            seen = true
            message = id
            for block in body["content"] as? [[String: Any]] ?? []
            where block["type"] as? String == "tool_use" && block["name"] as? String == planTool {
                guard let call = block["id"] as? String, !answered.contains(call) else { continue }
                let input = block["input"] as? [String: Any] ?? [:]
                guard let plan = planFile(input["planFilePath"] as? String, plans: plans) ?? nonEmpty(input["plan"] as? String) else { continue }
                return Said(text: plan, at: timestamp(of: entry), folder: folder(of: entry), isPlan: true)
            }
        }
        return nil
    }

    /// A plan's own file, when it is one of Claude Code's: a markdown file in
    /// its plans folder and not too big for a plan. No other file is read.
    private static func planFile(_ path: String?, plans: URL) -> String? {
        guard let path, path.hasPrefix("/") else { return nil }
        let file = URL(fileURLWithPath: path).standardizedFileURL
        guard file.pathExtension == "md",
              file.deletingLastPathComponent().path == plans.standardizedFileURL.path,
              let values = try? file.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
              values.isRegularFile == true, let size = values.fileSize, size <= planFileBytes,
              let data = try? Data(contentsOf: file) else { return nil }
        return nonEmpty(String(data: data, encoding: .utf8))
    }

    /// The chat's newest title in the transcript.
    private static func title(in lines: [Data.SubSequence]) -> String? {
        for line in lines.reversed() where line.range(of: titleMark) != nil {
            if let found = object(line)?["customTitle"] as? String, !found.isEmpty { return found }
        }
        return nil
    }

    private static let titleMark = Data("customTitle".utf8)
    private static let assistantMark = Data("\"assistant\"".utf8)
    private static let userMark = Data("\"user\"".utf8)

    private static func object(_ line: Data.SubSequence) -> [String: Any]? {
        (try? JSONSerialization.jsonObject(with: Data(line))) as? [String: Any]
    }

    /// What Claude wrote in the chat itself: not a subagent's line, an API
    /// error or one Claude Code made up.
    private static func isClaude(_ entry: [String: Any]) -> Bool {
        entry["type"] as? String == "assistant"
            && entry["isSidechain"] as? Bool != true
            && entry["isApiErrorMessage"] as? Bool != true
            && (entry["message"] as? [String: Any])?["model"] as? String != "<synthetic>"
    }

    private static func timestamp(of entry: [String: Any]) -> Date? {
        (entry["timestamp"] as? String).flatMap(ClaudeDigest.timestamp)
    }

    private static func folder(of entry: [String: Any]) -> String? {
        (entry["cwd"] as? String).flatMap { $0.isEmpty ? nil : URL(fileURLWithPath: $0).lastPathComponent }
    }

    private static func nonEmpty(_ text: String?) -> String? {
        guard let text = text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
        return text
    }

    private static func children(of folder: URL) -> [URL] {
        (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
    }
}

/// `Uykusuz --last-reply`: prints which chat the shortcut would read and what
/// it would say, to check either in silence.
enum LastReplyCommand {
    static let flag = "--last-reply"
    static let planLine = "Onayınızı bekleyen plan okunur."

    static func run(_ arguments: [String], find: () -> ClaudeReply? = { ClaudeChats.lastReply() }) -> Int32? {
        guard arguments.first == flag else { return nil }
        guard let reply = find() else {
            print(ClaudeReplyReader.nothingToRead)
            return 0
        }
        print("Sohbet: \(reply.title)")
        if reply.isPlan { print(planLine) }
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
