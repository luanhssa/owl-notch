import XCTest
@testable import owl_hook

final class ControllingTerminalTests: XCTestCase {
    /// The test runner may or may not have a controlling terminal at all
    /// (CI runners typically don't) — this only asserts it never crashes,
    /// and that whatever it returns looks like a real pty path.
    func testTtyPathNeverCrashesAndLooksLikeARealDeviceWhenPresent() {
        let path = ControllingTerminal.ttyPath()
        if let path {
            XCTAssertTrue(path.hasPrefix("/dev/"), "expected a /dev/... path, got \(path)")
        }
    }
}
