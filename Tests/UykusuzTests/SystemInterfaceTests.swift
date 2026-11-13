import XCTest
@testable import Uykusuz

/// The undocumented macOS interfaces the app calls, looked up on the macOS
/// the tests run on. Nothing is called and no device is reached: a class,
/// a selector or a symbol is only asked for. After a macOS update, a
/// failure here names what the update took away (AGENTS.md, "macOS, iOS ve
/// Claude Code güncellemeleri"). The names are the ones the sources use; a
/// name changed there is changed here.
final class SystemInterfaceTests: XCTestCase {
    private let major = ProcessInfo.processInfo.operatingSystemVersion.majorVersion

    private func open(_ path: String, file: StaticString = #filePath, line: UInt = #line) throws -> UnsafeMutableRawPointer {
        try XCTUnwrap(dlopen(path, RTLD_LAZY), "\(path) does not load on macOS \(major)", file: file, line: line)
    }

    private func assertClass(_ name: String, has selectors: [String], file: StaticString = #filePath, line: UInt = #line) throws {
        let type = try XCTUnwrap(NSClassFromString(name) as? NSObject.Type, "\(name) is gone on macOS \(major)", file: file, line: line)
        for selector in selectors {
            XCTAssertTrue(type.instancesRespond(to: NSSelectorFromString(selector)), "\(name) no longer has \(selector)", file: file, line: line)
        }
    }

    /// `SharingHotspotWaker`: asking a phone to turn its hotspot on.
    func testTheHotspotBrowserIsWhereItWasMeasured() throws {
        try XCTSkipUnless(SharingHotspotWaker.measuredMajorVersions.contains(major), "not measured on macOS \(major): the app asks no device there")
        _ = try open(SharingHotspotWaker.framework)
        try assertClass("SFRemoteHotspotSession", has: ["setDelegate:", "startBrowsing", "stopBrowsing", "enableRemoteHotspotForDevice:withCompletionHandler:"])
        try assertClass("SFRemoteHotspotDevice", has: ["deviceName"])
        try assertClass("SFRemoteHotspotInfo", has: ["name", "password"])
    }

    /// `HotspotJoinMode`: reading "Ask to join hotspots".
    func testTheHotspotJoinSettingIsWhereItWasMeasured() throws {
        try XCTSkipUnless(HotspotJoinMode.measuredMajorVersions.contains(major), "not measured on macOS \(major): Settings shows nothing there")
        _ = try open("/System/Library/PrivateFrameworks/CoreWiFi.framework/CoreWiFi")
        try assertClass("CWFInterface", has: ["autoHotspotMode", "activate", "invalidate"])
    }

    /// `DisplayServicesBrightness`: the display's brightness.
    func testTheDisplayBrightnessCallsAreWhereTheyWereMeasured() throws {
        try XCTSkipUnless(DisplayPower.measuredDisplayServicesMajors.contains(major), "not measured on macOS \(major): the display is not darkened there")
        let handle = try open("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices")
        for symbol in ["DisplayServicesGetBrightness", "DisplayServicesSetBrightness", "DisplayServicesCanChangeBrightness"] {
            XCTAssertNotNil(dlsym(handle, symbol), "DisplayServices no longer has \(symbol)")
        }
    }

    /// `CoreBrightnessKeyboardBacklight`: the keyboard backlight. The shape
    /// of its methods is checked by the app itself (`PrivateDisplayGuardTests`).
    func testTheKeyboardBacklightClientIsThere() throws {
        _ = try open("/System/Library/PrivateFrameworks/CoreBrightness.framework/CoreBrightness")
        XCTAssertNotNil(NSClassFromString("KeyboardBrightnessClient"), "KeyboardBrightnessClient is gone on macOS \(major)")
    }

    /// `LoginScreenLock`: locking the darkened screen.
    func testTheScreenLockCallIsThere() throws {
        let handle = try open(LoginScreenLock.frameworkPath)
        XCTAssertNotNil(dlsym(handle, "SACLockScreenImmediate"), "login.framework no longer has SACLockScreenImmediate")
    }
}
