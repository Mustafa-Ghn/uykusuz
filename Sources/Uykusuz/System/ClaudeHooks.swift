import Foundation

/// Claude Code hooks that tell Uykusuz when Claude is running a task, not
/// merely open (fork addition).
///
/// Claude Code runs `command` on these events: a task starts
/// (`UserPromptSubmit`) and goes on (`PostToolUse`, `PostToolUseFailure` for
/// a tool that failed, and `PermissionDenied`: Claude carries on after a
/// refusal); Claude stops for the user
/// (`PermissionRequest` when a permission dialog comes up, `Notification`
/// for a permission prompt or an MCP question, `PreToolUse` for a question
/// or a plan to approve); the task is over (`Stop`, `StopFailure` for a turn
/// an API error ended, `SessionEnd`). The command runs this app's executable
/// in `--claude-hook` mode (`ClaudeHookCommand`), which keeps one marker
/// file per Claude Code session under the app support folder while a task
/// runs. `ClaudeActivity` reads them.
enum ClaudeHooks {
    static let flag = "--claude-hook"
    static let events = [
        "UserPromptSubmit", "PostToolUse", "Stop", "SessionEnd",
        "StopFailure", "PermissionRequest", "PermissionDenied", "Notification", "PreToolUse", "PostToolUseFailure",
    ]
    /// Events whose hook only runs for some tools.
    static let matchers = [
        "PostToolUse": "*",
        "PostToolUseFailure": "*",
        "PreToolUse": ClaudeHookCommand.waitingTools.sorted().joined(separator: "|"),
    ]
    /// Prints nothing (a UserPromptSubmit hook's output becomes part of the
    /// prompt) and always succeeds, so a missing or broken Uykusuz never
    /// blocks or changes what Claude Code does.
    static let command = #""$HOME/Applications/Uykusuz.app/Contents/MacOS/Uykusuz" --claude-hook >/dev/null 2>&1 || true"#
    static let timeout = 10
    /// Where the first install keeps the file as it was.
    static let backupSuffix = ".uykusuz-yedek"

    static var defaultSettingsURL: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/settings.json")
    }

    enum Change: Equatable, Sendable {
        case installed, removed, unchanged
    }

    struct SettingsError: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    /// True when the user's Claude Code settings run this app's hook.
    static func isInstalled(settingsURL: URL = defaultSettingsURL) -> Bool {
        guard let data = try? Data(contentsOf: settingsURL) else { return false }
        return String(decoding: data, as: UTF8.self).contains(flag)
    }

    /// Adds the hook to each of `events`, keeping everything else in the
    /// file. Before the first change the file is copied, as it was, to
    /// `settings.json.uykusuz-yedek`.
    @discardableResult
    static func install(settingsURL: URL = defaultSettingsURL) throws -> Change {
        var root = try readSettings(settingsURL)
        var hooks = root["hooks"] as? [String: Any] ?? [:]
        var changed = false
        for event in events {
            var groups = hooks[event] as? [[String: Any]] ?? []
            guard !groups.contains(where: containsOurHook) else { continue }
            var group: [String: Any] = ["hooks": [["type": "command", "command": command, "timeout": timeout]]]
            if let matcher = matchers[event] { group["matcher"] = matcher }
            groups.append(group)
            hooks[event] = groups
            changed = true
        }
        guard changed else { return .unchanged }
        root["hooks"] = hooks
        try writeSettings(root, to: settingsURL)
        return .installed
    }

    /// Events in `events` that do not run this app's hook.
    static func missingEvents(settingsURL: URL = defaultSettingsURL) -> [String] {
        let hooks = (try? readSettings(settingsURL))?["hooks"] as? [String: Any] ?? [:]
        return events.filter { !((hooks[$0] as? [[String: Any]])?.contains(where: containsOurHook) ?? false) }
    }

    /// With this app's hooks installed, adds the events an earlier build did
    /// not install. Run at launch; returns what it added.
    @discardableResult
    static func upgradeIfInstalled(settingsURL: URL = defaultSettingsURL) throws -> [String] {
        guard isInstalled(settingsURL: settingsURL) else { return [] }
        let missing = missingEvents(settingsURL: settingsURL)
        guard !missing.isEmpty else { return [] }
        try install(settingsURL: settingsURL)
        return missing
    }

    /// Takes this app's hook out of every event and leaves the rest as is.
    @discardableResult
    static func remove(settingsURL: URL = defaultSettingsURL) throws -> Change {
        guard FileManager.default.fileExists(atPath: settingsURL.path) else { return .unchanged }
        var root = try readSettings(settingsURL)
        guard var hooks = root["hooks"] as? [String: Any] else { return .unchanged }
        var changed = false
        for (event, value) in hooks {
            guard var groups = value as? [[String: Any]] else { continue }
            let before = groups.count
            groups = groups.compactMap { group in
                guard var entries = group["hooks"] as? [[String: Any]] else { return group }
                let kept = entries.filter { !isOurHook($0) }
                guard kept.count != entries.count else { return group }
                changed = true
                entries = kept
                if entries.isEmpty { return nil }
                var g = group
                g["hooks"] = entries
                return g
            }
            if groups.count != before { changed = true }
            hooks[event] = groups.isEmpty ? nil : groups
        }
        guard changed else { return .unchanged }
        root["hooks"] = hooks.isEmpty ? nil : hooks
        try writeSettings(root, to: settingsURL)
        return .removed
    }

    // MARK: Private

    private static func isOurHook(_ entry: [String: Any]) -> Bool {
        (entry["command"] as? String)?.contains(flag) ?? false
    }

    private static func containsOurHook(_ group: [String: Any]) -> Bool {
        (group["hooks"] as? [[String: Any]])?.contains(where: isOurHook) ?? false
    }

    private static func readSettings(_ url: URL) throws -> [String: Any] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [:] }
        let data = try Data(contentsOf: url)
        guard !data.isEmpty else { return [:] }
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw SettingsError(message: "\(url.path) bir JSON nesnesi değil; dokunulmadı")
        }
        return root
    }

    private static func writeSettings(_ root: [String: Any], to url: URL) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let backup = URL(fileURLWithPath: url.path + backupSuffix)
        if fm.fileExists(atPath: url.path), !fm.fileExists(atPath: backup.path) {
            try fm.copyItem(at: url, to: backup)
        }
        let data = try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .withoutEscapingSlashes])
        try data.write(to: url, options: .atomic)
        chmod(url.path, 0o600)
    }
}

/// One Claude Code session's running task, as the hook last saw it.
struct ClaudeTaskMarker: Codable, Equatable, Sendable {
    /// The `claude` process the hook ran under; 0 when it was not found.
    var pid: Int32
    var identity: ProcessIdentity?
    var event: String
    var updatedAt: Date
    /// Since when Claude has been stopped for the user (a permission prompt,
    /// a question, a plan to approve); nil while it works.
    var waitingSince: Date? = nil
}

/// `Uykusuz --claude-hook`: what Claude Code runs on each hook event, with
/// the event as JSON on stdin. A task start or a tool use writes the
/// session's marker; Claude stopping for the user marks it waiting, and the
/// next sign of work clears that; Claude finishing or the session ending
/// removes it. Always exits 0 and prints nothing, so it never answers a
/// permission request or changes a tool call.
enum ClaudeHookCommand {
    struct Input: Decodable {
        let session_id: String?
        let hook_event_name: String?
        let notification_type: String?
        let tool_name: String?
    }

    enum Kind: Equatable, Sendable {
        case busy, waiting, idle
    }

    static let busyEvents: Set<String> = ["UserPromptSubmit", "PostToolUse", "PostToolUseFailure", "PermissionDenied"]
    static let idleEvents: Set<String> = ["Stop", "StopFailure", "SessionEnd"]
    /// Notifications for Claude stopped on the user: a tool permission, an
    /// MCP server's question.
    static let waitingNotifications: Set<String> = ["permission_prompt", "elicitation_dialog"]
    /// Tools that wait for the user from `PreToolUse` until their
    /// `PostToolUse`: a question, a plan to approve.
    static let waitingTools: Set<String> = ["AskUserQuestion", "ExitPlanMode"]

    /// What an event says about the session; nil for one that says nothing
    /// (another notification, a tool that does not wait).
    static func kind(of input: Input) -> Kind? {
        guard let event = input.hook_event_name else { return nil }
        if busyEvents.contains(event) { return .busy }
        if idleEvents.contains(event) { return .idle }
        switch event {
        case "PermissionRequest": return .waiting
        case "PreToolUse": return input.tool_name.map(waitingTools.contains) == true ? .waiting : nil
        case "Notification": return input.notification_type.map(waitingNotifications.contains) == true ? .waiting : nil
        default: return nil
        }
    }

    static func markerDirectory(_ paths: Paths) -> URL {
        paths.appSupport.appendingPathComponent("claude-sessions", isDirectory: true)
    }

    /// nil when `arguments` is not this mode; otherwise 0.
    static func run(
        _ arguments: [String],
        readInput: () -> Data = { FileHandle.standardInput.readDataToEndOfFile() },
        paths: Paths = .fromEnvironment(),
        now: Date = Date(),
        claudeProcess: () -> (pid: Int32, identity: ProcessIdentity?)? = ClaudeHookCommand.findClaudeProcess
    ) -> Int32? {
        guard arguments.first == ClaudeHooks.flag else { return nil }
        guard let input = try? JSONDecoder().decode(Input.self, from: readInput()),
              let event = input.hook_event_name,
              let name = markerName(input.session_id) else { return 0 }
        let dir = markerDirectory(paths)
        let file = dir.appendingPathComponent(name)
        switch kind(of: input) {
        case let kind? where kind != .idle:
            // A wait keeps the moment it began across the events that
            // repeat it (a dialog's request, then its notification).
            let since = kind == .waiting ? (readMarker(file)?.waitingSince ?? now) : nil
            let process = claudeProcess()
            let marker = ClaudeTaskMarker(pid: process?.pid ?? 0, identity: process?.identity, event: event, updatedAt: now, waitingSince: since)
            do {
                _ = try OwnerOnly.createDirectory(dir)
                let encoder = JSONEncoder()
                encoder.dateEncodingStrategy = .iso8601
                try encoder.encode(marker).write(to: file, options: .atomic)
                chmod(file.path, 0o600)
            } catch {
                Log.error("claude hook: could not write \(file.path): \(error.localizedDescription)")
            }
        case .idle?:
            try? FileManager.default.removeItem(at: file)
        default:
            break
        }
        return 0
    }

    static func readMarker(_ file: URL) -> ClaudeTaskMarker? {
        guard let data = try? Data(contentsOf: file) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(ClaudeTaskMarker.self, from: data)
    }

    /// The session id as a file name: letters, digits, `-` and `_` only.
    static func markerName(_ sessionID: String?) -> String? {
        guard let sessionID else { return nil }
        let allowed = Set("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_")
        let cleaned = String(sessionID.prefix(128).map { allowed.contains($0) ? $0 : "_" })
        guard cleaned.contains(where: { $0 != "_" }) else { return nil }
        return cleaned + ".json"
    }

    /// The nearest ancestor named `claude`: the Claude Code process that ran
    /// this hook, through the shell it used. Looks a few levels up.
    static func findClaudeProcess() -> (pid: Int32, identity: ProcessIdentity?)? {
        var pid = getppid()
        for _ in 0..<6 where pid > 1 {
            guard case let .present(state) = SignalProcessControl.processTableState(pid: pid) else { return nil }
            if ClaudeActivity.processName(pid) == "claude" { return (pid, state.identity) }
            pid = state.ppid
        }
        return nil
    }
}

/// Whether Claude is running a task (fork addition): a session marker
/// from the hooks, or a command Claude Code's Bash tool started doing work
/// (`BashToolWatcher`), in the foreground or the background, so a long
/// build Claude is waiting for counts too, and a server it left running
/// does not.
enum ClaudeActivity {
    /// A marker no hook has refreshed for this long is stale: Claude may
    /// have been interrupted, which skips the Stop hook.
    static let markerMaxAge: TimeInterval = 2 * 3600
    /// Claude Code runs every Bash tool command through a shell that sources
    /// a snapshot from this folder.
    static let bashToolMarker = "/.claude/shell-snapshots/"

    enum State: Equatable, Sendable {
        case idle
        case working
        /// Every session with a task waits on the user, the longest since
        /// this moment, and no Bash tool command is running.
        case waiting(since: Date)

        var waitingSince: Date? {
            if case let .waiting(since) = self { return since }
            return nil
        }
    }

    /// `commandWorking`: a command Claude started is doing work
    /// (`BashToolWatcher`, which keeps readings between calls).
    static func state(
        paths: Paths,
        now: Date = Date(),
        lookup: (Int32) -> ProcessLookup = SignalProcessControl.processTableState,
        commandWorking: () -> Bool
    ) -> State {
        let markers = liveMarkers(paths: paths, now: now, lookup: lookup)
        if markers.contains(where: { $0.waitingSince == nil }) || commandWorking() { return .working }
        if let since = markers.compactMap(\.waitingSince).min() { return .waiting(since: since) }
        return .idle
    }

    /// A session's marker that is fresh and whose `claude` process is still
    /// the one that wrote it, working or waiting. Stale and orphaned markers
    /// are removed.
    static func markerBusy(
        paths: Paths,
        now: Date,
        maxAge: TimeInterval = markerMaxAge,
        lookup: (Int32) -> ProcessLookup = SignalProcessControl.processTableState
    ) -> Bool {
        !liveMarkers(paths: paths, now: now, maxAge: maxAge, lookup: lookup).isEmpty
    }

    static func liveMarkers(
        paths: Paths,
        now: Date,
        maxAge: TimeInterval = markerMaxAge,
        lookup: (Int32) -> ProcessLookup = SignalProcessControl.processTableState
    ) -> [ClaudeTaskMarker] {
        let dir = ClaudeHookCommand.markerDirectory(paths)
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: dir.path) else { return [] }
        var markers: [ClaudeTaskMarker] = []
        for name in names where name.hasSuffix(".json") {
            let file = dir.appendingPathComponent(name)
            guard let marker = ClaudeHookCommand.readMarker(file) else { continue }
            var live = now.timeIntervalSince(marker.updatedAt) < maxAge
            if live, marker.pid > 0 {
                if case let .present(state) = lookup(marker.pid) {
                    live = marker.identity == nil || state.identity == marker.identity
                } else {
                    live = false
                }
            }
            if live {
                markers.append(marker)
            } else {
                try? FileManager.default.removeItem(at: file)
            }
        }
        return markers
    }

    static func processName(_ pid: Int32) -> String? {
        var buffer = [CChar](repeating: 0, count: 256)
        guard proc_name(pid, &buffer, UInt32(buffer.count)) > 0 else { return nil }
        return String(decoding: buffer.prefix(while: { $0 != 0 }).map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }

    /// Every process with its short name, via sysctl KERN_PROC_ALL.
    static func processes() -> [(pid: Int32, name: String)] {
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_ALL, 0]
        var size = 0
        guard sysctl(&mib, UInt32(mib.count), nil, &size, nil, 0) == 0, size > 0 else { return [] }
        size += size / 4
        let stride = MemoryLayout<kinfo_proc>.stride
        let capacity = size / stride + 1
        let buffer = UnsafeMutablePointer<kinfo_proc>.allocate(capacity: capacity)
        defer { buffer.deallocate() }
        size = capacity * stride
        guard sysctl(&mib, UInt32(mib.count), buffer, &size, nil, 0) == 0 else { return [] }
        return (0..<(size / stride)).map { i in
            let p = buffer[i]
            let name = withUnsafeBytes(of: p.kp_proc.p_comm) { raw in
                String(decoding: raw.prefix(while: { $0 != 0 }), as: UTF8.self)
            }
            return (p.kp_proc.p_pid, name)
        }
    }

    /// A process's arguments and environment as one string, via sysctl
    /// KERN_PROCARGS2 (the caller's own processes only).
    static func arguments(_ pid: Int32) -> String? {
        var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
        var size = 0
        guard sysctl(&mib, 3, nil, &size, nil, 0) == 0, size > 4 else { return nil }
        var buffer = [UInt8](repeating: 0, count: size)
        guard sysctl(&mib, 3, &buffer, &size, nil, 0) == 0, size > 4 else { return nil }
        return String(decoding: buffer[4..<size].map { $0 == 0 ? 0x20 : $0 }, as: UTF8.self)
    }
}

/// `Uykusuz --install-claude-hooks` / `--remove-claude-hooks`: the same as
/// the button in Settings, for setting up another Mac from a terminal.
enum ClaudeHooksSetupCommand {
    static func run(_ arguments: [String], settingsURL: URL = ClaudeHooks.defaultSettingsURL) -> Int32? {
        do {
            switch arguments.first {
            case "--install-claude-hooks":
                let change = try ClaudeHooks.install(settingsURL: settingsURL)
                print(change == .unchanged ? "Claude Code hook'ları zaten kurulu: \(settingsURL.path)" : "Claude Code hook'ları kuruldu: \(settingsURL.path)")
            case "--remove-claude-hooks":
                let change = try ClaudeHooks.remove(settingsURL: settingsURL)
                print(change == .unchanged ? "Kaldırılacak Claude Code hook'u yok: \(settingsURL.path)" : "Claude Code hook'ları kaldırıldı: \(settingsURL.path)")
            default:
                return nil
            }
            return 0
        } catch {
            FileHandle.standardError.write(Data("Claude Code ayarları değiştirilemedi: \(error.localizedDescription)\n".utf8))
            return 1
        }
    }
}
