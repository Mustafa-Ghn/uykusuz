import XCTest
@testable import Uykusuz

@MainActor
final class UserPresenceTests: XCTestCase {
    func testAwayWhenTheLidIsClosedTheScreenIsLockedOrNothingWasTouched() {
        XCTAssertFalse(UserPresence.isAway(lidClosed: false, screenLocked: false, idle: 10))
        XCTAssertTrue(UserPresence.isAway(lidClosed: true, screenLocked: false, idle: 0))
        XCTAssertTrue(UserPresence.isAway(lidClosed: false, screenLocked: true, idle: 0))
        XCTAssertTrue(UserPresence.isAway(lidClosed: false, screenLocked: false, idle: UserPresence.idleLimit))
        XCTAssertFalse(UserPresence.isAway(lidClosed: false, screenLocked: false, idle: UserPresence.idleLimit - 1))
        XCTAssertEqual(WaitingAlerts.awayIdle, UserPresence.idleLimit, "the iMessage and the pushes agree on away")
    }
}

final class ClaudePresenceSettingTests: XCTestCase {
    private var dir: URL!
    private var settings: URL { dir.appendingPathComponent("settings.json") }
    private var file: URL { dir.appendingPathComponent(ClaudePushGate.fileName) }

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("uykusuz-presence-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    private func read() throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: settings)) as? [String: Any])
    }

    func testInstallKeepsTheRestAndRemoveTakesOnlyOurs() throws {
        try Data(#"{"theme":"dark","env":{"FOO":"bar"},"hooks":{}}"#.utf8).write(to: settings)
        XCTAssertEqual(try ClaudeHooks.installPresence(file: file, settingsURL: settings), .installed)
        XCTAssertEqual(try ClaudeHooks.installPresence(file: file, settingsURL: settings), .unchanged)
        var root = try read()
        XCTAssertEqual(root["theme"] as? String, "dark")
        XCTAssertEqual(root["env"] as? [String: String], ["FOO": "bar", ClaudeHooks.presenceVariable: file.path])
        XCTAssertEqual(ClaudeHooks.presenceFile(settingsURL: settings), file.path)
        XCTAssertTrue(FileManager.default.fileExists(atPath: settings.path + ClaudeHooks.backupSuffix), "the first change keeps the old file")

        XCTAssertEqual(try ClaudeHooks.removePresence(file: file, settingsURL: settings), .removed)
        root = try read()
        XCTAssertEqual(root["env"] as? [String: String], ["FOO": "bar"])
        XCTAssertEqual(root["theme"] as? String, "dark")
        XCTAssertEqual(try ClaudeHooks.removePresence(file: file, settingsURL: settings), .unchanged)
    }

    func testAnEnvOfOurOwnGoesAndAFileTheUserNamedStays() throws {
        XCTAssertEqual(try ClaudeHooks.installPresence(file: file, settingsURL: settings), .installed, "no settings file yet")
        XCTAssertEqual(try ClaudeHooks.removePresence(file: file, settingsURL: settings), .removed)
        XCTAssertNil(try read()["env"], "an env left empty goes")

        try Data(#"{"env":{"CLAUDE_CLIENT_PRESENCE_FILE":"/Users/x/present"}}"#.utf8).write(to: settings)
        XCTAssertThrowsError(try ClaudeHooks.installPresence(file: file, settingsURL: settings))
        XCTAssertEqual(try ClaudeHooks.removePresence(file: file, settingsURL: settings), .unchanged)
        XCTAssertEqual(ClaudeHooks.presenceFile(settingsURL: settings), "/Users/x/present")
    }
}

@MainActor
final class ClaudePushGateTests: XCTestCase {
    @MainActor final class Flags {
        var on = false
        var away = false
    }

    func testTheFileIsThereOnlyWhileOnAndTheUserIsAtTheMac() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("uykusuz-gate-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent(ClaudePushGate.fileName)
        let flags = Flags()
        let gate = ClaudePushGate(file: file, enabled: { flags.on }, away: { flags.away })
        func exists() -> Bool { FileManager.default.fileExists(atPath: file.path) }

        gate.tick()
        XCTAssertFalse(exists(), "off: Claude's pushes as usual")
        flags.on = true
        gate.tick()
        XCTAssertTrue(exists(), "at the Mac: the pushes are held")
        XCTAssertEqual(try FileManager.default.attributesOfItem(atPath: file.path)[.posixPermissions] as? Int, 0o600)
        flags.away = true
        gate.tick()
        XCTAssertFalse(exists(), "away: the pushes go")
        flags.away = false
        gate.tick()
        XCTAssertTrue(exists())
        gate.userLeft()
        XCTAssertFalse(exists(), "a lock or a lid close takes it away at once, before the idle time says so")
        gate.tick()
        XCTAssertTrue(exists())
        gate.stop()
        XCTAssertFalse(exists(), "quitting leaves nothing that would hold the pushes")
    }
}

final class PhoneReplyGraceTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 2_000_000_000)

    func testRepliesFromThePhoneKeepTheSessionOnForOne() {
        var config = Config()
        XCTAssertEqual(config.autoIdleGrace, AutoSessionPolicy.idleGrace)
        XCTAssertEqual(config.autoWaitGrace, config.approvalWaitGrace)
        config.phoneReplies = true
        XCTAssertEqual(config.autoIdleGrace, config.phoneReplyWindow)
        XCTAssertEqual(config.autoWaitGrace, config.phoneReplyWindow)
        config.approvalWaitGrace = 2 * 3600
        XCTAssertEqual(config.autoWaitGrace, 2 * 3600, "a longer wait the user chose stays")

        var p = AutoSessionPolicy()
        func step(_ offset: TimeInterval, active: Bool) -> AutoSessionPolicy.Action? {
            let session = offset == 0 ? nil : t0
            return p.step(.init(
                now: t0.addingTimeInterval(offset),
                agentActive: active,
                sessionStartedAt: session,
                sessionEndsAt: session?.addingTimeInterval(AutoSessionPolicy.chunk),
                batteryPercent: 80,
                isCharging: false,
                thermal: .nominal,
                endFloor: 20,
                idleGrace: 30 * 60
            ))
        }
        XCTAssertEqual(step(0, active: true), .start(AutoSessionPolicy.chunk))
        p.started(at: t0)
        XCTAssertNil(step(AutoSessionPolicy.idleGrace + 60, active: false), "past the usual end, still on for a reply")
        XCTAssertEqual(step(30 * 60, active: false), .end)
    }
}
