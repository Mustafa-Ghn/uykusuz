import CryptoKit
import Foundation
@testable import Uykusuz

/// Writes the shell scripts tests author: fakes of system tools, stand-in
/// backstops and app binaries, wrappers. A broken fake makes a test fail, or
/// pass, for the wrong reason (a fake gh that used `$10`, which bash reads
/// as `${1}0`, faked 16 failures on #51), so every one goes through here
/// and CI runs ShellCheck over them.
///
/// When UYKUSUZ_TEST_SCRIPT_DUMP names a folder, each script is also copied
/// there, once per distinct text. UUIDs (the per-test temp folders) are
/// replaced with zeros first, so a fake that every fixture writes lands
/// once. A copy is named after the script and a hash of that text, and
/// index.tsv gives the source line that first wrote it. A script with no
/// `#!` line is one a test runs with /bin/bash, so its copy starts with a
/// `# shellcheck shell=bash` line.
///
/// Patched copies of the real scripts in scripts/, and harnesses built
/// from functions cut out of them, do not go through here; the ShellCheck
/// job lints the originals.
enum TestScripts {
    static let dumpKey = "UYKUSUZ_TEST_SCRIPT_DUMP"

    /// Writes `text` to `url`, makes it executable (0755) unless the test
    /// runs it through an interpreter, and copies it to the dump folder.
    static func write(
        _ text: String, to url: URL, executable: Bool = true,
        file: StaticString = #fileID, line: UInt = #line
    ) throws {
        try text.write(to: url, atomically: true, encoding: .utf8)
        if executable {
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        }
        try dump(text, name: url.lastPathComponent, source: "\(file):\(line)")
    }

    /// Writes a fake that a script runs by path, under a time limit or not:
    /// the text goes to `url` + ".fake", and `url` is a symlink to one shared
    /// launcher, which execs the text's #! interpreter on it under the same
    /// pid, so a fake's pid, parent, signals and descriptors are as if it ran
    /// by itself. The text must start with a #! line naming only the
    /// interpreter.
    ///
    /// macOS holds the first exec of every new file until syspolicyd has
    /// scanned it, and on a Mac where other processes run new files too that
    /// wait has no useful bound. The scans take turns across the whole Mac,
    /// about 8 a second whatever the CPU load: alone one takes about 130 ms,
    /// beside 12 other processes doing the same about 2 s (measured on macOS
    /// 26). A fake written for each test then looks hung to the limit it
    /// runs under, though nothing is wrong with the script or the fake. The
    /// real tools are not new files, so the scripts do not meet this outside
    /// the tests. The launcher is scanned once, before any test's limit runs,
    /// and an interpreter reading a fake's text is not an exec of it.
    static func writeLaunched(
        _ text: String, to url: URL,
        file: StaticString = #fileID, line: UInt = #line
    ) throws {
        try write(text, to: url.appendingPathExtension("fake"), executable: false, file: file, line: line)
        let fm = FileManager.default
        let target = try launcher.get()
        // A test may write a fake again, to change what it does.
        if (try? fm.destinationOfSymbolicLink(atPath: url.path)) == target.path { return }
        try fm.createSymbolicLink(at: url, withDestinationURL: target)
    }

    /// Read-only: a test that writes to a fake's path through its symlink
    /// fails, instead of changing every fake in the process.
    private static let launcher = Result<URL, any Error> {
        let fm = FileManager.default
        let dir = ProcessTestHome.root.appendingPathComponent("fake-launcher", isDirectory: true)
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("launcher")
        try write("""
        #!/bin/bash
        read -r shebang < "$0.fake"
        exec "${shebang:2}" "$0.fake" "$@"

        """, to: url)
        try fm.setAttributes([.posixPermissions: 0o555], ofItemAtPath: url.path)
        // The first exec, which waits for the scan.
        try "#!/bin/sh\nexit 0\n".write(to: url.appendingPathExtension("fake"), atomically: true, encoding: .utf8)
        let scanned = Process()
        scanned.executableURL = url
        try runFirstExec(scanned, describedAs: "the fake launcher")
        guard scanned.terminationStatus == 0 else {
            throw NSError(domain: "TestScripts", code: Int(scanned.terminationStatus), userInfo: [NSLocalizedDescriptionKey: "the fake launcher exited \(scanned.terminationStatus)"])
        }
        return url
    }

    /// How long to wait for the first exec of a new file. Running out fails
    /// every test that uses a fake, so this is far above the queue
    /// `writeLaunched` describes, which takes seconds even beside dozens of
    /// other processes. A scan whose answer was lost never ends, so no longer
    /// limit would help.
    static let firstExecLimit: TimeInterval = 120

    /// What a test says when the first exec of a new file has not returned.
    /// The test leaves the process running: the limit cannot tell a long queue
    /// from an answer that will never come.
    static func firstExecIsLate(_ what: String, pid: pid_t, limit: TimeInterval = firstExecLimit) -> String {
        "\(what) (pid \(pid)) did not run within \(limit) s. macOS holds the first exec of a new file until syspolicyd "
            + "has scanned it. If syspolicyd crashed in that time (look for a new /Library/Logs/DiagnosticReports/syspolicyd-*.ips), "
            + "the answer never comes and the process stays at _dyld_start using no CPU; `sample \(pid) 2` shows it. "
            + "It was left running. If it stays stuck, kill it by hand and run the tests again."
    }

    /// Runs `process`, the first exec of a new file, to its end, for at most
    /// `limit` seconds, and past that throws `firstExecIsLate`. The process gets
    /// none of this run's descriptors, because `swift test` reads the run's
    /// output to its end: a process left behind that holds it would still hang
    /// the run.
    static func runFirstExec(_ process: Process, describedAs what: String, limit: TimeInterval = firstExecLimit) throws {
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        let exited = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in exited.signal() }
        try process.run()
        guard exited.wait(timeout: .now() + limit) == .success else {
            throw NSError(domain: "TestScripts", code: Int(ETIMEDOUT), userInfo: [NSLocalizedDescriptionKey: firstExecIsLate(what, pid: process.processIdentifier, limit: limit)])
        }
    }

    private static let lock = NSLock()
    private static let uuid = try! NSRegularExpression(
        pattern: "[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}")

    private static func dump(_ text: String, name: String, source: String) throws {
        guard let raw = ProcessInfo.processInfo.environment[dumpKey], !raw.isEmpty else { return }
        let dir = URL(fileURLWithPath: raw, isDirectory: true)
        let normalized = uuid.stringByReplacingMatches(
            in: text, range: NSRange(text.startIndex..., in: text),
            withTemplate: "00000000-0000-0000-0000-000000000000")
        let lintable = normalized.hasPrefix("#!") ? normalized : "# shellcheck shell=bash\n" + normalized
        let hash = SHA256.hash(data: Data(lintable.utf8)).prefix(6).map { String(format: "%02x", $0) }.joined()
        let copy = dir.appendingPathComponent("\(name)-\(hash)")

        lock.lock()
        defer { lock.unlock() }
        let fm = FileManager.default
        guard !fm.fileExists(atPath: copy.path) else { return }
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        // The index line goes first: a copy the index does not name would
        // never be linted, while an index line with no copy fails the lint.
        let index = dir.appendingPathComponent("index.tsv")
        if !fm.fileExists(atPath: index.path) {
            try Data().write(to: index)
        }
        let handle = try FileHandle(forWritingTo: index)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: Data("\(copy.lastPathComponent)\t\(source)\n".utf8))
        try lintable.write(to: copy, atomically: true, encoding: .utf8)
    }
}
