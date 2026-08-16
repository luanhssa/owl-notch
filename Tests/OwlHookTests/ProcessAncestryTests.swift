import XCTest
import OwlShared
@testable import owl_hook

/// Tests the pure name-matching half of `ProcessAncestry` extracted for GH
/// issue #38 — `classify(ancestorProcessNames:)` — since the live sysctl-based
/// walk it normally runs on can't be meaningfully mocked in a unit test.
final class ProcessAncestryTests: XCTestCase {
    func testClassifiesKnownTerminalAsCLI() {
        let info = ProcessAncestry.classify(ancestorProcessNames: ["zsh", "Terminal", "login", "launchd"])
        XCTAssertEqual(info.environment, "cli")
        XCTAssertEqual(info.terminalApp, "Terminal")
    }

    func testClassifiesClaudeDesktopAsCode() {
        let info = ProcessAncestry.classify(ancestorProcessNames: ["node", "Claude", "launchd"])
        XCTAssertEqual(info.environment, "code")
        XCTAssertNil(info.terminalApp)
    }

    func testUnknownWhenNoAncestorMatches() {
        let info = ProcessAncestry.classify(ancestorProcessNames: ["bash", "zsh", "launchd"])
        XCTAssertEqual(info.environment, "unknown")
        XCTAssertNil(info.terminalApp)
    }

    func testEmptyAncestryIsUnknown() {
        let info = ProcessAncestry.classify(ancestorProcessNames: [])
        XCTAssertEqual(info.environment, "unknown")
    }

    /// The first match walking outward from owl-hook (closest ancestor
    /// first) wins — order in the input array reflects that walk order.
    func testClosestMatchingAncestorWinsOverAFartherOne() {
        let info = ProcessAncestry.classify(ancestorProcessNames: ["Terminal", "Claude"])
        XCTAssertEqual(info.environment, "cli")
        XCTAssertEqual(info.terminalApp, "Terminal")
    }

    /// Every terminal added to the shared registry (GH issue #28) should be
    /// recognized here too, since ProcessAncestry matches against exactly
    /// that table.
    func testRecognizesEveryTerminalInTheSharedRegistry() {
        for app in TerminalAppRegistry.all {
            let info = ProcessAncestry.classify(ancestorProcessNames: ["some-shell", app.processName])
            XCTAssertEqual(info.environment, "cli", "\(app.processName) should classify as cli")
            XCTAssertEqual(info.terminalApp, app.processName)
        }
    }
}
