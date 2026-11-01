import Darwin
import Foundation
import XCTest
@testable import Uykusuz

/// What a fake written by `TestScripts.writeLaunched` must keep through its
/// launcher: the tests about pids, signals and the lock on fd 9 rely on it.
final class LaunchedFakeTests: XCTestCase {
    private var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("uykusuz-launched-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let dir { try FileManager.default.removeItem(at: dir) }
    }

    /// The shell execs the fake, so the fake has this Process's pid and its
    /// parent is this test, as for a fake that is a file of its own. Its
    /// arguments arrive unchanged, fd 9 stays open, and SIGTERM stays ignored.
    func testAFakeKeepsItsPidArgumentsDescriptorsAndIgnoredSignals() throws {
        let fake = dir.appendingPathComponent("tool")
        let out = dir.appendingPathComponent("out")
        try TestScripts.writeLaunched("""
        #!/bin/bash
        {
          echo "pid $$ parent $PPID"
          for a in "$@"; do echo "arg [$a]"; done
          if { : >&9; } 2>/dev/null; then echo "fd9 open"; fi
          kill -TERM $$
          echo "survived SIGTERM"
        } > "\(out.path)"

        """, to: fake)
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/bash")
        p.arguments = ["-c", #"trap '' TERM; exec 9<>/dev/null; exec "$0" "a b" '*'"#, fake.path]
        let exit = ProcessExit(p)
        try p.run()
        exit.wait()

        XCTAssertEqual(p.terminationStatus, 0)
        XCTAssertEqual(try String(contentsOf: out, encoding: .utf8), """
        pid \(p.processIdentifier) parent \(getpid())
        arg [a b]
        arg [*]
        fd9 open
        survived SIGTERM

        """)
    }

    /// The text runs in the interpreter its #! line names. /bin/cat shows it:
    /// it prints the file it is given.
    func testAFakeRunsInItsOwnInterpreter() throws {
        let fake = dir.appendingPathComponent("tool")
        let text = "#!/bin/cat\nnot a shell script\n"
        try TestScripts.writeLaunched(text, to: fake)
        let p = Process()
        p.executableURL = fake
        let pipe = Pipe()
        p.standardOutput = pipe
        let exit = ProcessExit(p)
        try p.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        exit.wait()

        XCTAssertEqual(p.terminationStatus, 0)
        XCTAssertEqual(String(decoding: data, as: UTF8.self), text)
    }

    /// Every fake is a link to one file, so macOS scans one file however many
    /// fakes there are, and no test can change that file for the others.
    func testFakesShareOneReadOnlyLauncher() throws {
        let fm = FileManager.default
        let a = dir.appendingPathComponent("a")
        let b = dir.appendingPathComponent("b")
        try TestScripts.writeLaunched("#!/bin/sh\n", to: a)
        try TestScripts.writeLaunched("#!/bin/sh\n", to: b)

        let launcher = try fm.destinationOfSymbolicLink(atPath: a.path)
        XCTAssertEqual(try fm.destinationOfSymbolicLink(atPath: b.path), launcher)
        XCTAssertFalse(fm.isWritableFile(atPath: launcher))
    }

    /// A first exec that does not return ends in an error that says why, and
    /// the process is left alone. /bin/sleep stands in for it: it is no new
    /// file, so stopping it afterwards interrupts no scan.
    func testAFirstExecPastItsLimitFailsAndSaysWhy() throws {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sleep")
        p.arguments = ["30"]
        defer { if p.isRunning { p.terminate() } }

        XCTAssertThrowsError(try TestScripts.runFirstExec(p, describedAs: "the stand-in", limit: 0.1)) { error in
            let text = error.localizedDescription
            XCTAssertTrue(text.contains("the stand-in (pid \(p.processIdentifier))"), text)
            XCTAssertTrue(text.contains("syspolicyd"), text)
        }
        XCTAssertTrue(p.isRunning)
    }

    /// A first exec that ends in time returns, with its status final.
    func testAFirstExecWithinItsLimitReturnsAfterTheExit() throws {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = ["-c", "exit 3"]

        try TestScripts.runFirstExec(p, describedAs: "the stand-in", limit: 30)

        XCTAssertEqual(p.terminationStatus, 3)
    }
}
