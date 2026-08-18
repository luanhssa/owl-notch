import XCTest
@testable import OwlApp

final class PanelDisplayTests: XCTestCase {
    func testFallsBackWhenNoPreferenceIsSet() {
        let screens = [(id: CGDirectDisplayID(1), screen: "main"), (id: CGDirectDisplayID(2), screen: "external")]
        XCTAssertEqual(PanelDisplay.pickPreferred(preferredDisplayID: nil, from: screens, fallback: "main"), "main")
    }

    func testPicksThePreferredDisplayWhenConnected() {
        let screens = [(id: CGDirectDisplayID(1), screen: "main"), (id: CGDirectDisplayID(2), screen: "external")]
        XCTAssertEqual(PanelDisplay.pickPreferred(preferredDisplayID: 2, from: screens, fallback: "main"), "external")
    }

    func testFallsBackWhenThePreferredDisplayIsNotConnected() {
        let screens = [(id: CGDirectDisplayID(1), screen: "main")]
        XCTAssertEqual(PanelDisplay.pickPreferred(preferredDisplayID: 99, from: screens, fallback: "main"), "main")
    }

    func testReturnsNilFallbackWhenNothingMatchesAndNoFallbackExists() {
        let screens = [(id: CGDirectDisplayID(1), screen: "main")]
        XCTAssertNil(PanelDisplay.pickPreferred(preferredDisplayID: 99, from: screens, fallback: Optional<String>.none))
    }
}
