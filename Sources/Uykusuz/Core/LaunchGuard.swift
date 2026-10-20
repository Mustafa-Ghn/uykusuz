import Foundation

/// Whether this process starts the menu bar app (fork addition). Two
/// Uykusuz apps would share the session file, the journal and the recovery
/// lock and work against each other, so a second one does not start. Nor
/// does a run with an option this build does not know: an older build that
/// took `--away-digest` for an app launch started that second app.
///
/// The command-line modes (`--claude-hook` and the rest) are answered
/// before this and run beside the app as they always have; another process
/// running one of them does not count as an app.
enum LaunchGuard {
    enum Verdict: Equatable {
        case launch
        case unknownOption(String)
        case alreadyRunning(pid_t)
    }

    static let processName = "Uykusuz"

    static func verdict(
        arguments: [String],
        others: () -> [(pid: pid_t, argv: [String])] = LaunchGuard.otherUykusuzProcesses
    ) -> Verdict {
        if let option = arguments.first(where: { $0.hasPrefix("--") }) {
            return .unknownOption(option)
        }
        if let app = others().first(where: { process in !process.argv.dropFirst().contains { $0.hasPrefix("--") } }) {
            return .alreadyRunning(app.pid)
        }
        return .launch
    }

    /// This user's other processes named Uykusuz, with their arguments.
    /// Another user's cannot be read, and share none of these files.
    static func otherUykusuzProcesses() -> [(pid: pid_t, argv: [String])] {
        let me = getpid()
        return ClaudeActivity.processes()
            .filter { $0.name == processName && $0.pid != me }
            .compactMap { process in argv(process.pid).map { (process.pid, $0) } }
    }

    /// A process's argv through KERN_PROCARGS2: argc, the executable path
    /// and its padding, then argc strings. nil when it cannot be read.
    static func argv(_ pid: pid_t) -> [String]? {
        var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
        var size = 0
        guard sysctl(&mib, 3, nil, &size, nil, 0) == 0, size > 4 else { return nil }
        var buffer = [UInt8](repeating: 0, count: size)
        guard sysctl(&mib, 3, &buffer, &size, nil, 0) == 0, size > 4 else { return nil }
        let argc = Int(buffer.withUnsafeBytes { $0.loadUnaligned(as: Int32.self) })
        var index = 4
        while index < size, buffer[index] != 0 { index += 1 }
        while index < size, buffer[index] == 0 { index += 1 }
        var args: [String] = []
        while args.count < argc, index < size {
            let start = index
            while index < size, buffer[index] != 0 { index += 1 }
            args.append(String(decoding: buffer[start..<index], as: UTF8.self))
            index += 1
        }
        return args
    }
}
