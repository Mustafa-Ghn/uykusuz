import Foundation

/// The LaunchAgent's entry point (fork change). launchd runs the app's own
/// executable as `Uykusuz --backstop-agent <requirement> <bundle>`, so System
/// Settings lists the background item under Uykusuz instead of `sh`. The
/// executable does nothing else: it execs upstream's agent program
/// (`LaunchdBackstop.agentProgram`) with `/bin/sh`, which verifies the
/// bundle against the pinned requirement with codesign and runs the sealed
/// backstop.sh only when that passes, exactly as the upstream LaunchAgent did.
///
/// The one difference from upstream: the first code launchd starts is this
/// executable, not `/bin/sh`, so the check runs after code from the bundle
/// has started. Code that can re-sign the bundle runs as the user and could
/// equally edit the LaunchAgent plist, so this costs no protection a
/// same-user attacker did not already have.
enum BackstopAgentCommand {
    static let flag = "--backstop-agent"

    /// Replaces the process; returns the errno only when that failed.
    typealias Exec = (_ path: String, _ argv: [String]) -> Int32

    /// nil when `arguments` is not this mode. Otherwise the exit status,
    /// reached only when the arguments are wrong or the exec failed.
    static func run(_ arguments: [String], exec: Exec = BackstopAgentCommand.execv) -> Int32? {
        guard arguments.first == flag else { return nil }
        let rest = Array(arguments.dropFirst())
        guard rest.count == 2, !rest[0].isEmpty, !rest[1].isEmpty else {
            FileHandle.standardError.write(Data("usage: Uykusuz \(flag) <requirement> <bundle>\n".utf8))
            return 64
        }
        let err = exec("/bin/sh", Self.shellArguments(requirement: rest[0], bundle: rest[1]))
        FileHandle.standardError.write(Data("backstop agent: could not exec /bin/sh: \(String(cString: strerror(err)))\n".utf8))
        return 1
    }

    /// The argv `/bin/sh` gets: the upstream agent's command line.
    static func shellArguments(requirement: String, bundle: String) -> [String] {
        ["/bin/sh", "-c", LaunchdBackstop.agentProgram, "sh", requirement, bundle]
    }

    static func execv(_ path: String, _ argv: [String]) -> Int32 {
        var cArgs = argv.map { strdup($0) }
        cArgs.append(nil)
        Darwin.execv(path, cArgs)
        let err = errno
        for p in cArgs { free(p) }
        return err
    }
}
