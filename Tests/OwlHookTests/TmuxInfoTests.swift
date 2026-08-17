import XCTest
@testable import owl_hook

final class TmuxInfoTests: XCTestCase {
    func testReturnsPaneIDWhenPresent() {
        XCTAssertEqual(TmuxInfo.currentPaneID(environment: ["TMUX_PANE": "%12"]), "%12")
    }

    func testReturnsNilWhenAbsent() {
        XCTAssertNil(TmuxInfo.currentPaneID(environment: [:]))
    }

    func testReturnsNilWhenEmptyString() {
        XCTAssertNil(TmuxInfo.currentPaneID(environment: ["TMUX_PANE": ""]))
    }

    func testIgnoresUnrelatedEnvironmentVariables() {
        XCTAssertNil(TmuxInfo.currentPaneID(environment: ["PATH": "/usr/bin", "TMUX": "/tmp/tmux-501/default,1234,0"]))
    }
}
