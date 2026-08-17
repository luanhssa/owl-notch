import XCTest
import OwlShared
@testable import OwlApp

/// Only tests the pure `supportsPreciseTargeting` decision — never calls
/// the private `selectTab(withTTY:inTerminalApp:)`, which executes real
/// AppleScript against whatever Terminal.app/iTerm2 windows happen to be
/// open on the machine running the test. That's exactly the kind of live,
/// unintended side effect already learned the hard way once this session
/// (see docs/PATTERNS.md #14) — a test must never risk actually raising a
/// real window.
final class SessionFocusServiceTests: XCTestCase {
    func testSupportsPreciseTargetingForTerminalAndITerm() {
        XCTAssertTrue(SessionFocusService.supportsPreciseTargeting(terminalAppName: "Terminal"))
        XCTAssertTrue(SessionFocusService.supportsPreciseTargeting(terminalAppName: "iTerm2"))
        XCTAssertTrue(SessionFocusService.supportsPreciseTargeting(terminalAppName: "iTerm"))
    }

    func testDoesNotSupportPreciseTargetingForOtherRegisteredTerminals() {
        for app in TerminalAppRegistry.all where !["Terminal", "iTerm2", "iTerm"].contains(app.processName) {
            XCTAssertFalse(
                SessionFocusService.supportsPreciseTargeting(terminalAppName: app.processName),
                "\(app.processName) has no AppleScript tty-matching API and must fall back to app-level focus"
            )
        }
    }

    func testDoesNotSupportPreciseTargetingForUnknownApp() {
        XCTAssertFalse(SessionFocusService.supportsPreciseTargeting(terminalAppName: "SomeFutureTerminal"))
    }
}
