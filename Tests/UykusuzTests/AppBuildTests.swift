import XCTest
@testable import Uykusuz

/// The version Settings and the launch log show.
final class AppBuildTests: XCTestCase {
    func testVersionAndBuildComeFromInfoPlist() {
        let build = AppBuild(info: ["CFBundleShortVersionString": "0.1.0", "CFBundleVersion": "1"])
        XCTAssertEqual(build, AppBuild(version: "0.1.0", build: "1"))
        XCTAssertEqual(build.label, "0.1.0 (1)")
    }

    func testABinaryWithoutAnInfoPlistSaysSo() {
        let build = AppBuild(info: [:])
        XCTAssertNil(build.version)
        XCTAssertEqual(build.label, "sürüm yok: bu derlemede Info.plist yok")
        XCTAssertEqual(AppBuild(info: ["CFBundleShortVersionString": "", "CFBundleVersion": 7]).label, "sürüm yok: bu derlemede Info.plist yok",
                       "an empty version and a build of the wrong type read as missing")
        XCTAssertEqual(AppBuild(info: ["CFBundleShortVersionString": "0.2.0"]).label, "0.2.0")
    }
}
