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
        /// Claude did nothing in the window: the session is here only for
        /// being at work or waiting now.
        var quiet = false

        var toolUses: Int { toolCounts.values.reduce(0, +) }
    }

    var from: Date
    var to: Date
    /// The sessions told in detail, newest first.
    var sessions: [Session]
    /// The sessions past `maxSessions`: counted and named, nothing more.
    var others: [Session] = []
    /// The span is the user's absence, the lid closed or the screen locked
    /// (the summary on their return), not how long Claude worked; false for
    /// a span asked for (Settings, `--away-digest`), which is told as
    /// "son ..." instead.
    var away = true

    /// The newest transcript bytes read from each file: enough for any time
    /// away worth a summary, and a bound on a long session's file.
    static let tailBytes = 8 << 20
    /// How many sessions are told in detail, not how many are counted.
    static let maxSessions = 8
    static let maxFiles = 12
    static let maxCommands = 8
    static let maxTexts = 2
    static let maxTextLength = 700
    static let editTools: Set<String> = ["Edit", "Write", "MultiEdit", "NotebookEdit"]

    static var defaultProjectsDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/projects", isDirectory: true)
    }

    /// The sessions with something done between `from` and `to`, and those
    /// at work or waiting now even with nothing written in the span (a long
    /// command, a question asked before it); nil when there is none. `status`
    /// tells each session's state now from its id. Every one is counted; the
    /// newest `maxSessions` are told in detail, those waiting on the user
    /// before any other.
    static func build(
        from: Date,
        to: Date,
        projects: URL = defaultProjectsDirectory,
        status: (String) -> Status = { _ in .done }
    ) -> ClaudeDigest? {
        let fm = FileManager.default
        guard let folders = try? fm.contentsOfDirectory(at: projects, includingPropertiesForKeys: nil) else { return nil }
        var found: [Session] = []
        for folder in folders {
            guard let files = try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey]) else { continue }
            for file in files where file.pathExtension == "jsonl" {
                let values = try? file.resourceValues(forKeys: [.contentModificationDateKey, .isRegularFileKey])
                guard values?.isRegularFile == true, let modified = values?.contentModificationDate else { continue }
                let id = file.deletingPathExtension().lastPathComponent
                let state = status(id)
                guard modified >= from || state != .done,
                      var session = read(file, id: id, from: from, to: to, requiringWork: state == .done) else { continue }
                session.status = state
                found.append(session)
            }
        }
        guard !found.isEmpty else { return nil }
        found.sort { $0.lastActivity > $1.lastActivity }
        // A session continued from another folder has a transcript in both.
        var seen = Set<String>()
        let sessions = found.filter { seen.insert($0.id).inserted }
        let ranked = sessions.filter { $0.status == .waiting } + sessions.filter { $0.status != .waiting }
        let detailed = Set(ranked.prefix(maxSessions).map(\.id))
        return ClaudeDigest(
            from: from,
            to: to,
            sessions: sessions.filter { detailed.contains($0.id) },
            others: sessions.filter { !detailed.contains($0.id) }
        )
    }

    /// One session between `from` and `to`, by the name its marker goes by
    /// (`ClaudeHookCommand.markerName`), however many others ran in the span:
    /// `build` tells only `maxSessions` in detail. Nil when it has no
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
        session.quiet = assistantEntries == 0
        session.title = title ?? generatedTitle ?? folder ?? id
        return session
    }

    /// Every session of the span, told in detail or not.
    private var everySession: [Session] { sessions + others }

    private func count(_ status: Status) -> Int {
        everySession.filter { $0.status == status }.count
    }

    /// What the API is given: a plain text account of the sessions. The
    /// counts are spelled out, or the writer counts only those in detail.
    var promptText: String {
        let span = SessionMath.formatSpan(to.timeIntervalSince(from))
        var lines = [away ? "Kullanıcı \(span) uzaktaydı (kapak kapalı ya da ekran kilitli). Bu, Claude'un çalışma süresi değildir." : "Özetlenen süre: son \(span)."]
        if everySession.count > 1 {
            lines.append("Toplam \(everySession.count) oturum var: \(count(.working)) hâlâ çalışıyor, \(count(.waiting)) kullanıcıdan onay ya da yanıt bekliyor, \(count(.done)) bitti.")
        }
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
        if !others.isEmpty {
            lines.append("")
            lines.append("Toplama dahil, ayrıntısı verilmeyen oturumlar:")
            for s in others { lines.append("\(s.title): \(Self.statusText(s.status))") }
        }
        return lines.joined(separator: "\n")
    }

    /// The summary without the API: counts, in a few short sentences. The
    /// absence gets a sentence of its own and the last work its clock, so the
    /// span never reads as how long Claude worked.
    var localSummary: String {
        let span = to.timeIntervalSince(from)
        let lead = away ? "\(SessionMath.formatSpan(span)) uzaktaydınız. Bu sürede" : "Son \(SessionMath.formatSpanLocative(span))"
        guard !everySession.isEmpty else { return "\(lead) Claude bir şey yapmadı." }
        let worked = everySession.filter { !$0.quiet }
        var sentence: String
        if let first = worked.first {
            sentence = "\(lead) Claude \"\(first.title)\" üzerinde çalıştı"
            var details: [String] = []
            if !first.editedFiles.isEmpty { details.append("\(first.editedFiles.count) dosya düzenledi") }
            let commands = first.toolCounts["Bash"] ?? 0
            if commands > 0 { details.append("\(commands) komut çalıştırdı") }
            if !details.isEmpty { sentence += ": " + details.joined(separator: ", ") }
            sentence += worked.count > 1 ? "; \(worked.count - 1) oturumda daha çalıştı." : "."
        } else {
            sentence = "\(lead) Claude'dan yeni bir haber yok."
        }
        let waiting = count(.waiting)
        let working = count(.working)
        if working == 0, let last = worked.map(\.lastActivity).max() {
            sentence += " En son çalıştığı saat: \(SessionMath.formatMoment(last, now: to))."
        }
        if working > 0 {
            sentence += everySession.count == 1 ? " Hâlâ çalışıyor." : working == 1 ? " Bir oturum hâlâ çalışıyor." : " \(working) oturum hâlâ çalışıyor."
        }
        if waiting > 0 {
            sentence += waiting == 1 ? " Bir oturum yanıtınızı bekliyor." : " \(waiting) oturum yanıtınızı bekliyor."
        }
        if working == 0, waiting == 0 { sentence += " Şu an bitmiş durumda." }
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
