import Foundation

/// Whether this process is a test run. Keyboard focus and the menu bar belong
/// to the whole login session, not to the process: a test that takes them gets
/// in the way of whoever is at the Mac, whose typing goes missing and whose
/// menu bar shows an eye that comes and goes with each test.
enum TestProcess {
    static let isRunning = NSClassFromString("XCTestCase") != nil
}
