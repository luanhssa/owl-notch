import XCTest
@testable import OwlApp

final class PreferencesTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "owl-test-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func testStaleSessionCutoffHoursDefaultsWhenUnset() {
        XCTAssertEqual(Preferences.staleSessionCutoffHours(defaults: defaults), Preferences.defaultStaleSessionCutoffHours)
    }

    func testStaleSessionCutoffHoursRoundTrips() {
        Preferences.setStaleSessionCutoffHours(6, defaults: defaults)
        XCTAssertEqual(Preferences.staleSessionCutoffHours(defaults: defaults), 6)
    }

    func testStaleSessionCutoffHoursClampsBelowRange() {
        Preferences.setStaleSessionCutoffHours(0, defaults: defaults)
        XCTAssertEqual(Preferences.staleSessionCutoffHours(defaults: defaults), Preferences.staleSessionCutoffHoursRange.lowerBound)
    }

    func testStaleSessionCutoffHoursClampsAboveRange() {
        Preferences.setStaleSessionCutoffHours(999, defaults: defaults)
        XCTAssertEqual(Preferences.staleSessionCutoffHours(defaults: defaults), Preferences.staleSessionCutoffHoursRange.upperBound)
    }

    func testNotifyOnSessionDoneDefaultsToTrueWhenUnset() {
        XCTAssertTrue(Preferences.notifyOnSessionDone(defaults: defaults))
    }

    func testNotifyOnSessionDoneRoundTrips() {
        Preferences.setNotifyOnSessionDone(false, defaults: defaults)
        XCTAssertFalse(Preferences.notifyOnSessionDone(defaults: defaults))
    }
}
