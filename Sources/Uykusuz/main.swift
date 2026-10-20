import Foundation

// Entry point. A one-shot command-line mode is answered here, before AppKit
// or SwiftUI start, so backstop.sh can borrow the app's kernel-level
// identity check (see ResumeFrozenCommand), which ends itself when its
// lifetime is up. Anything else starts the menu bar app.
// The LaunchAgent starts the app's executable, which execs the upstream
// agent program (fork change, BackstopAgentCommand).
if let status = BackstopAgentCommand.run(Array(CommandLine.arguments.dropFirst())) {
    exit(status)
}
// What Claude Code's hooks run (fork addition, ClaudeHooks): quick, silent,
// always exit 0.
if let status = ClaudeHookCommand.run(Array(CommandLine.arguments.dropFirst())) {
    exit(status)
}
if let status = ClaudeHooksSetupCommand.run(Array(CommandLine.arguments.dropFirst())) {
    exit(status)
}
// What the away summary would be told for the last minutes (fork addition):
// local, nothing is sent.
if let status = AwayDigestCommand.run(Array(CommandLine.arguments.dropFirst())) {
    exit(status)
}
if let output = ResumeFrozenCommand.run(Array(CommandLine.arguments.dropFirst()), endAfter: ResumeFrozenCommand.endProcess) {
    for line in output.lines { print(line) }
    exit(output.status)
}
// One Uykusuz app at a time, and none for an option this build does not
// know (fork addition, LaunchGuard).
switch LaunchGuard.verdict(arguments: Array(CommandLine.arguments.dropFirst())) {
case let .unknownOption(option):
    FileHandle.standardError.write(Data("Bilinmeyen seçenek: \(option). Uykusuz açılmadı.\n".utf8))
    exit(64)
case let .alreadyRunning(pid):
    Log.info("launch refused: Uykusuz is already running (pid \(pid))")
    FileHandle.standardError.write(Data("Uykusuz zaten çalışıyor (pid \(pid)); ikinci kopya açılmadı.\n".utf8))
    exit(0)
case .launch:
    break
}
UykusuzApp.main()
