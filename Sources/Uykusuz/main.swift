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
if let output = ResumeFrozenCommand.run(Array(CommandLine.arguments.dropFirst()), endAfter: ResumeFrozenCommand.endProcess) {
    for line in output.lines { print(line) }
    exit(output.status)
}
UykusuzApp.main()
