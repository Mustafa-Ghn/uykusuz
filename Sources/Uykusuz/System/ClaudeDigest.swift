import Foundation

/// What Claude Code did between two moments, read from its session
/// transcripts (fork addition): the "while you were away" summary is
/// written from this (`AwaySummary`).
///
/// Only a little is taken from each transcript: the session's title, how
/// many times each tool ran, the names of the files Claude edited, the
/// descriptions Claude gave its commands, and the end of its last messages.
/// File contents, command lines and tool output are never read into it, so
/// none of them can reach the summary or the API.
struct ClaudeDigest: Equatable, Sendable {
    enum Status: Equatable, Sendable {
        /// Claude finished, or has nothing running.
        case done
        /// Claude is waiting for the user's approval or answer.
        case waiting
        /// Claude is still at work.
        case working
    }

    struct Session: Equatable, Sendable {
        var id: String
        var title: String
        var status: Status = .done
        var toolCounts: [String: Int] = [:]
        var editedFiles: [String] = []
        var commands: [String] = []
        var lastTexts: [String] = []
        /// Prompts the user (or a schedule) sent in the window.
        var prompts = 0
        var lastActivity: Date

        var toolUses: Int { toolCounts.values.reduce(0, +) }
    }

    var from: Date
    var to: Date
    var sessions: [Session]
    /// The span is the lid closed (the summary at a lid open); false for a
    /// span asked for (Settings, `--away-digest`), which is told as the
    /// last minutes instead.
    var away = true

    /// The newest transcript bytes read from each file: enough for any time
    /// away worth a summary, and a bound on a long session's file.
    static let tailBytes = 8 << 20
    static let maxSessions = 4
    static let maxFiles = 12
    static let maxCommands = 8
    static let maxTexts = 2
    static let maxTextLength = 700
    static let editTools: Set<String> = ["Edit", "Write", "MultiEdit", "NotebookEdit"]

    static var defaultProjectsDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/projects", isDirectory: true)
    }

    /// The sessions with something done between `from` and `to`, newest
    /// first; nil when there is none. `status` tells each session's state
    /// now from its id.
    static func build(
        from: Date,
        to: Date,
        projects: URL = defaultProjectsDirectory,
        status: (String) -> Status = { _ in .done }
    ) -> ClaudeDigest? {
        let fm = FileManager.default
        guard let folders = try? fm.contentsOfDirectory(at: projects, includingPropertiesForKeys: nil) else { return nil }
        var sessions: [Session] = []
        for folder in folders {
            guard let files = try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey]) else { continue }
            for file in files where file.pathExtension == "jsonl" {
                let values = try? file.resourceValues(forKeys: [.contentModificationDateKey, .isRegularFileKey])
                guard values?.isRegularFile == true, let modified = values?.contentModificationDate, modified >= from else { continue }
                let id = file.deletingPathExtension().lastPathComponent
                guard var session = read(file, id: id, from: from, to: to) else { continue }
                session.status = status(id)
                sessions.append(session)
            }
        }
        guard !sessions.isEmpty else { return nil }
        sessions.sort { $0.lastActivity > $1.lastActivity }
        return ClaudeDigest(from: from, to: to, sessions: Array(sessions.prefix(maxSessions)))
    }

    /// One session between `from` and `to`, by the name its marker goes by
    /// (`ClaudeHookCommand.markerName`), however many others ran in the span:
    /// `build` keeps only the newest `maxSessions`. Nil when it has no
    /// transcript; one where Claude did nothing in the span still gives its
    /// title, since a message has to say which session it is about.
    static func session(
        _ marker: String,
        from: Date,
        to: Date,
        projects: URL = defaultProjectsDirectory,
        status: (String) -> Status = { _ in .done }
    ) -> Session? {
        let fm = FileManager.default
        guard let folders = try? fm.contentsOfDirectory(at: projects, includingPropertiesForKeys: nil) else { return nil }
        for folder in folders {
            guard let files = try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil) else { continue }
            for file in files where file.pathExtension == "jsonl" {
                let id = file.deletingPathExtension().lastPathComponent
                guard ClaudeHookCommand.markerName(id) == "\(marker).json",
                      var session = read(file, id: id, from: from, to: to, requiringWork: false) else { continue }
                session.status = status(id)
                return session
            }
        }
        return nil
    }

    /// One transcript's entries between `from` and `to`; nil when Claude
    /// did nothing in them, if `requiringWork`.
    static func read(_ file: URL, id: String, from: Date, to: Date, requiringWork: Bool = true) -> Session? {
        guard let data = tail(of: file) else { return nil }
        var session = Session(id: id, title: id, lastActivity: from)
        var assistantEntries = 0
        var title: String?
        var generatedTitle: String?
        var folder: String?
        for line in data.split(separator: UInt8(ascii: "\n")) {
            guard let object = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any] else { continue }
            let type = object["type"] as? String
            if type == "custom-title", let custom = object["customTitle"] as? String, !custom.isEmpty {
                title = custom
                continue
            }
            if type == "ai-title", let generated = object["aiTitle"] as? String, !generated.isEmpty {
                generatedTitle = generated
                continue
            }
            if let cwd = object["cwd"] as? String, !cwd.isEmpty { folder = URL(fileURLWithPath: cwd).lastPathComponent }
            guard type == "assistant" || type == "user",
                  object["isSidechain"] as? Bool != true,
                  let stamp = (object["timestamp"] as? String).flatMap(timestamp),
                  stamp >= from, stamp <= to,
                  let message = object["message"] as? [String: Any] else { continue }
            session.lastActivity = max(session.lastActivity, stamp)
            if type == "user" {
                if object["isMeta"] as? Bool != true, isPrompt(message["content"]) { session.prompts += 1 }
                continue
            }
            assistantEntries += 1
            for block in message["content"] as? [[String: Any]] ?? [] {
                switch block["type"] as? String {
                case "text":
                    if let text = (block["text"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty {
                        session.lastTexts.append(clip(text, to: maxTextLength, keepingEnd: true))
                        if session.lastTexts.count > maxTexts { session.lastTexts.removeFirst() }
                    }
                case "tool_use":
                    guard let name = block["name"] as? String else { continue }
                    session.toolCounts[name, default: 0] += 1
                    let input = block["input"] as? [String: Any] ?? [:]
                    if editTools.contains(name),
                       let path = (input["file_path"] as? String) ?? (input["notebook_path"] as? String) {
                        let fileName = URL(fileURLWithPath: path).lastPathComponent
                        if !session.editedFiles.contains(fileName), session.editedFiles.count < maxFiles {
                            session.editedFiles.append(fileName)
                        }
                    }
                    // The latest ones: how the work ended matters more.
                    if name == "Bash", let description = (input["description"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
                       !description.isEmpty {
                        session.commands.append(clip(description, to: 100, keepingEnd: false))
                        if session.commands.count > maxCommands { session.commands.removeFirst() }
                    }
                default:
                    continue
                }
            }
        }
        guard assistantEntries > 0 || !requiringWork else { return nil }
        session.title = title ?? generatedTitle ?? folder ?? id
        return session
    }

    /// What the API is given: a plain text account of the sessions.
    var promptText: String {
        let span = Self.minutes(to.timeIntervalSince(from))
        var lines = [away ? "Kullanıcı \(span) dakika uzaktaydı (kapak kapalıydı)." : "Özetlenen süre: son \(span) dakika."]
        for (index, s) in sessions.enumerated() {
            lines.append("")
            lines.append("Oturum \(index + 1): \(s.title)")
            lines.append("Şimdiki durum: \(Self.statusText(s.status))")
            if !s.toolCounts.isEmpty {
                let counts = s.toolCounts.sorted { $0.value > $1.value || ($0.value == $1.value && $0.key < $1.key) }
                lines.append("Araç kullanımı: " + counts.map { "\($0.key) \($0.value)" }.joined(separator: ", "))
            }
            if !s.editedFiles.isEmpty { lines.append("Düzenlenen dosyalar: " + s.editedFiles.joined(separator: ", ")) }
            if !s.commands.isEmpty { lines.append("Çalıştırılan komutların açıklamaları: " + s.commands.joined(separator: "; ")) }
            if s.prompts > 0 { lines.append("Bu sürede gelen istek: \(s.prompts)") }
            for text in s.lastTexts { lines.append("Claude'un mesajı: \(text)") }
        }
        return lines.joined(separator: "\n")
    }

    /// The summary without the API: counts, in at most two sentences.
    var localSummary: String {
        let span = Self.minutes(to.timeIntervalSince(from))
        let lead = away ? "Kapak kapalıyken (\(span) dakika)" : "Son \(span) dakikada"
        guard let first = sessions.first else { return "\(lead) Claude bir şey yapmadı." }
        let others = sessions.count - 1
        var sentence = "\(lead) Claude \"\(first.title)\" üzerinde çalıştı"
        var details: [String] = []
        if !first.editedFiles.isEmpty { details.append("\(first.editedFiles.count) dosya düzenledi") }
        let commands = first.toolCounts["Bash"] ?? 0
        if commands > 0 { details.append("\(commands) komut çalıştırdı") }
        if !details.isEmpty { sentence += ": " + details.joined(separator: ", ") }
        sentence += others > 0 ? "; \(others) oturumda daha çalıştı." : "."
        let waiting = sessions.filter { $0.status == .waiting }.count
        let working = sessions.filter { $0.status == .working }.count
        if waiting > 0 {
            sentence += waiting == 1 ? " Bir oturum yanıtınızı bekliyor." : " \(waiting) oturum yanıtınızı bekliyor."
        } else if working > 0 {
            sentence += " Hâlâ çalışıyor."
        } else {
            sentence += " Şu an bitmiş durumda."
        }
        return sentence
    }

    // MARK: Helpers

    static func statusText(_ status: Status) -> String {
        switch status {
        case .done: "bitti, şu an çalışmıyor"
        case .waiting: "kullanıcıdan onay ya da yanıt bekliyor"
        case .working: "hâlâ çalışıyor"
        }
    }

    static func minutes(_ interval: TimeInterval) -> Int {
        max(Int((interval / 60).rounded()), 1)
    }

    /// One line of at most `limit` characters. `keepingEnd`: a message's end
    /// is where Claude says how it went, so a long one keeps that.
    static func clip(_ text: String, to limit: Int, keepingEnd: Bool) -> String {
        let flat = text.split(whereSeparator: \.isNewline).joined(separator: " ")
        guard flat.count > limit else { return flat }
        return keepingEnd
            ? "\u{2026}" + String(flat.suffix(limit)).trimmingCharacters(in: .whitespaces)
            : String(flat.prefix(limit)).trimmingCharacters(in: .whitespaces) + "\u{2026}"
    }

    private static func isPrompt(_ content: Any?) -> Bool {
        if let text = content as? String { return !text.isEmpty }
        guard let blocks = content as? [[String: Any]] else { return false }
        return blocks.contains { $0["type"] as? String == "text" }
    }

    /// Claude Code writes `2026-10-20T19:53:35.476Z`; a stamp without the
    /// fraction is read too.
    static func timestamp(_ text: String) -> Date? {
        (try? Date.ISO8601FormatStyle(includingFractionalSeconds: true).parse(text))
            ?? (try? Date.ISO8601FormatStyle().parse(text))
    }

    /// The last `bytes` of the file, from its first whole line.
    static func tail(of file: URL, bytes: Int = tailBytes) -> Data? {
        guard let handle = try? FileHandle(forReadingFrom: file) else { return nil }
        defer { try? handle.close() }
        guard let size = try? handle.seekToEnd() else { return nil }
        let start = size > UInt64(bytes) ? size - UInt64(bytes) : 0
        try? handle.seek(toOffset: start)
        guard var data = try? handle.readToEnd() else { return nil }
        if start > 0, let newline = data.firstIndex(of: UInt8(ascii: "\n")) {
            data = data.suffix(from: data.index(after: newline))
        }
        return data
    }
}
