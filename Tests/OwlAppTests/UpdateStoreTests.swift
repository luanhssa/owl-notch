import XCTest
@testable import OwlApp

@MainActor
final class UpdateStoreTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!
    private let release = UpdateCheckService.Release(
        version: "0.19.0",
        pageURL: URL(string: "https://github.com/luanhssa/owl-notch/releases/tag/v0.19.0")!
    )

    override func setUp() {
        super.setUp()
        suiteName = "owl-test-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        // A check that just ran keeps every test here off the network.
        Preferences.setLastUpdateCheck(Date(), defaults: defaults)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func testRestoresNoticeFromLastCheckAfterRelaunch() {
        Preferences.setCheckForUpdates(true, defaults: defaults)
        Preferences.setLatestKnownRelease(release, defaults: defaults)
        let store = UpdateStore(defaults: defaults, currentVersion: "0.18.0")
        XCTAssertEqual(store.availableUpdate, release)
    }

    func testNoNoticeOnceRunningTheKnownReleaseOrNewer() {
        Preferences.setCheckForUpdates(true, defaults: defaults)
        Preferences.setLatestKnownRelease(release, defaults: defaults)
        let store = UpdateStore(defaults: defaults, currentVersion: "0.19.0")
        XCTAssertNil(store.availableUpdate)
    }

    func testNoNoticeWhileTheCheckIsOff() {
        Preferences.setLatestKnownRelease(release, defaults: defaults)
        let store = UpdateStore(defaults: defaults, currentVersion: "0.18.0")
        XCTAssertNil(store.availableUpdate)
    }
}
