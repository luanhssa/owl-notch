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

    func testPreferredDisplayIDDefaultsToNilWhenUnset() {
        XCTAssertNil(Preferences.preferredDisplayID(defaults: defaults))
    }

    func testPreferredDisplayIDRoundTrips() {
        Preferences.setPreferredDisplayID(42, defaults: defaults)
        XCTAssertEqual(Preferences.preferredDisplayID(defaults: defaults), 42)
    }

    func testPreferredDisplayIDCanBeClearedBackToNil() {
        Preferences.setPreferredDisplayID(42, defaults: defaults)
        Preferences.setPreferredDisplayID(nil, defaults: defaults)
        XCTAssertNil(Preferences.preferredDisplayID(defaults: defaults))
    }

    func testShowLastMessageContentDefaultsToFalseWhenUnset() {
        XCTAssertFalse(Preferences.showLastMessageContent(defaults: defaults))
    }

    func testShowLastMessageContentRoundTrips() {
        Preferences.setShowLastMessageContent(true, defaults: defaults)
        XCTAssertTrue(Preferences.showLastMessageContent(defaults: defaults))
    }

    func testTokenWindowBudgetDefaultsWhenUnset() {
        XCTAssertEqual(Preferences.tokenWindowBudget(defaults: defaults), Preferences.defaultTokenWindowBudget)
    }

    func testTokenWindowBudgetRoundTrips() {
        Preferences.setTokenWindowBudget(80_000_000, defaults: defaults)
        XCTAssertEqual(Preferences.tokenWindowBudget(defaults: defaults), 80_000_000)
    }

    func testTokenWindowBudgetClampsBelowRange() {
        Preferences.setTokenWindowBudget(0, defaults: defaults)
        XCTAssertEqual(Preferences.tokenWindowBudget(defaults: defaults), Preferences.tokenWindowBudgetRange.lowerBound)
    }

    func testTokenWindowBudgetClampsAboveRange() {
        Preferences.setTokenWindowBudget(9_000_000_000, defaults: defaults)
        XCTAssertEqual(Preferences.tokenWindowBudget(defaults: defaults), Preferences.tokenWindowBudgetRange.upperBound)
    }

    /// A value written straight into the defaults domain (an old build, a
    /// hand-edited plist) is clamped on read too — the bar divides by this
    /// number, so a zero or negative one must never reach the view.
    func testTokenWindowBudgetClampsValueStoredOutOfRange() {
        defaults.set(-5, forKey: "owl.tokenWindowBudget")
        XCTAssertEqual(Preferences.tokenWindowBudget(defaults: defaults), Preferences.tokenWindowBudgetRange.lowerBound)
    }

    func testWeeklyTokenBudgetDefaultsWhenUnset() {
        XCTAssertEqual(Preferences.weeklyTokenBudget(defaults: defaults), Preferences.defaultWeeklyTokenBudget)
    }

    func testWeeklyTokenBudgetRoundTrips() {
        Preferences.setWeeklyTokenBudget(600_000_000, defaults: defaults)
        XCTAssertEqual(Preferences.weeklyTokenBudget(defaults: defaults), 600_000_000)
    }

    func testWeeklyTokenBudgetClampsBelowRange() {
        Preferences.setWeeklyTokenBudget(0, defaults: defaults)
        XCTAssertEqual(Preferences.weeklyTokenBudget(defaults: defaults), Preferences.weeklyTokenBudgetRange.lowerBound)
    }

    func testWeeklyTokenBudgetClampsAboveRange() {
        Preferences.setWeeklyTokenBudget(50_000_000_000, defaults: defaults)
        XCTAssertEqual(Preferences.weeklyTokenBudget(defaults: defaults), Preferences.weeklyTokenBudgetRange.upperBound)
    }

    /// Guards the same divide-by-zero the 5h budget does — both bars read
    /// their ceiling straight off this.
    func testWeeklyTokenBudgetClampsValueStoredOutOfRange() {
        defaults.set(0, forKey: "owl.weeklyTokenBudget")
        XCTAssertEqual(Preferences.weeklyTokenBudget(defaults: defaults), Preferences.weeklyTokenBudgetRange.lowerBound)
    }
}
