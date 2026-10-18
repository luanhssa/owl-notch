import XCTest
@testable import OwlApp

final class UpdateCheckServiceTests: XCTestCase {
    func testNewerVersionsCompareNumericallyNotAsStrings() {
        XCTAssertTrue(UpdateCheckService.isNewer("0.10.0", than: "0.9.0"))
        XCTAssertTrue(UpdateCheckService.isNewer("v0.19.0", than: "0.18.0"))
        XCTAssertTrue(UpdateCheckService.isNewer("1.0", than: "0.99.99"))
    }

    func testSameOrOlderVersionIsNotNewer() {
        XCTAssertFalse(UpdateCheckService.isNewer("0.18.0", than: "0.18.0"))
        XCTAssertFalse(UpdateCheckService.isNewer("0.18", than: "0.18.0"))
        XCTAssertFalse(UpdateCheckService.isNewer("0.17.9", than: "0.18.0"))
    }

    func testNonNumericVersionFailsClosed() {
        XCTAssertFalse(UpdateCheckService.isNewer("0.19.0-beta", than: "0.18.0"))
        XCTAssertFalse(UpdateCheckService.isNewer("", than: "0.18.0"))
    }

    func testParsesTagAndPageFromTheReleasesAPIResponse() throws {
        let json: [String: Any] = [
            "tag_name": "v0.19.0",
            "html_url": "https://github.com/luanhssa/owl-notch/releases/tag/v0.19.0",
            "draft": false,
        ]
        let release = UpdateCheckService.parseRelease(data: try JSONSerialization.data(withJSONObject: json))
        XCTAssertEqual(release?.version, "0.19.0")
        XCTAssertEqual(release?.pageURL.absoluteString, "https://github.com/luanhssa/owl-notch/releases/tag/v0.19.0")
    }

    func testMalformedResponseParsesToNil() {
        XCTAssertNil(UpdateCheckService.parseRelease(data: Data("{\"message\":\"Not Found\"}".utf8)))
        XCTAssertNil(UpdateCheckService.parseRelease(data: Data("not json".utf8)))
    }

    func testCheckIsDueWhenNeverCheckedOrAWeekHasPassed() {
        let now = Date()
        XCTAssertTrue(UpdateCheckService.isCheckDue(lastCheck: nil, now: now))
        XCTAssertTrue(UpdateCheckService.isCheckDue(lastCheck: now.addingTimeInterval(-UpdateCheckService.checkInterval), now: now))
        XCTAssertFalse(UpdateCheckService.isCheckDue(lastCheck: now.addingTimeInterval(-60), now: now))
    }
}
