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

    func testShowContextUsageDefaultsToFalseWhenUnset() {
        XCTAssertFalse(Preferences.showContextUsage(defaults: defaults))
    }

    func testShowContextUsageRoundTrips() {
        Preferences.setShowContextUsage(true, defaults: defaults)
        XCTAssertTrue(Preferences.showContextUsage(defaults: defaults))
    }

    func testContextWindowLimitDefaultsToAutomatic() {
        XCTAssertNil(Preferences.contextWindowLimit(defaults: defaults))
    }

    func testContextWindowLimitRoundTripsAndClearsBackToAutomatic() {
        Preferences.setContextWindowLimit(1_000_000, defaults: defaults)
        XCTAssertEqual(Preferences.contextWindowLimit(defaults: defaults), 1_000_000)
        Preferences.setContextWindowLimit(nil, defaults: defaults)
        XCTAssertNil(Preferences.contextWindowLimit(defaults: defaults))
    }

    func testContextWindowLimitIgnoresUnofferedSizes() {
        defaults.set(123, forKey: "owl.contextWindowLimit")
        XCTAssertNil(Preferences.contextWindowLimit(defaults: defaults))
        Preferences.setContextWindowLimit(500_000, defaults: defaults)
        XCTAssertNil(Preferences.contextWindowLimit(defaults: defaults))
    }

    func testCheckForUpdatesDefaultsToFalseWhenUnset() {
        XCTAssertFalse(Preferences.checkForUpdates(defaults: defaults))
    }

    func testCheckForUpdatesRoundTrips() {
        Preferences.setCheckForUpdates(true, defaults: defaults)
        XCTAssertTrue(Preferences.checkForUpdates(defaults: defaults))
    }

    func testLastUpdateCheckRoundTrips() {
        XCTAssertNil(Preferences.lastUpdateCheck(defaults: defaults))
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        Preferences.setLastUpdateCheck(date, defaults: defaults)
        XCTAssertEqual(Preferences.lastUpdateCheck(defaults: defaults), date)
    }

    func testLatestKnownReleaseRoundTrips() {
        XCTAssertNil(Preferences.latestKnownRelease(defaults: defaults))
        let release = UpdateCheckService.Release(
            version: "0.19.0",
            pageURL: URL(string: "https://github.com/luanhssa/owl-notch/releases/tag/v0.19.0")!
        )
        Preferences.setLatestKnownRelease(release, defaults: defaults)
        XCTAssertEqual(Preferences.latestKnownRelease(defaults: defaults), release)
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

    func testWeeklyResetWeekdayDefaultsToNilWhenUnset() {
        XCTAssertNil(Preferences.weeklyResetWeekday(defaults: defaults))
    }

    func testWeeklyResetWeekdayRoundTrips() {
        Preferences.setWeeklyResetWeekday(4, defaults: defaults)
        XCTAssertEqual(Preferences.weeklyResetWeekday(defaults: defaults), 4)
    }

    func testWeeklyResetWeekdayCanBeClearedBackToNil() {
        Preferences.setWeeklyResetWeekday(4, defaults: defaults)
        Preferences.setWeeklyResetWeekday(nil, defaults: defaults)
        XCTAssertNil(Preferences.weeklyResetWeekday(defaults: defaults))
    }

    /// An out-of-range value (1...7 is `Calendar`'s weekday numbering)
    /// written directly, or passed to the setter, is treated as unset
    /// rather than handed to `Calendar` where it would misbehave.
    func testWeeklyResetWeekdayIgnoresOutOfRangeValue() {
        defaults.set(8, forKey: "owl.weeklyResetWeekday")
        XCTAssertNil(Preferences.weeklyResetWeekday(defaults: defaults))

        Preferences.setWeeklyResetWeekday(0, defaults: defaults)
        XCTAssertNil(Preferences.weeklyResetWeekday(defaults: defaults))
    }

    func testWeeklyResetHourDefaultsWhenUnset() {
        XCTAssertEqual(Preferences.weeklyResetHour(defaults: defaults), Preferences.defaultWeeklyResetHour)
    }

    func testWeeklyResetHourRoundTrips() {
        Preferences.setWeeklyResetHour(9, defaults: defaults)
        XCTAssertEqual(Preferences.weeklyResetHour(defaults: defaults), 9)
    }

    func testWeeklyResetHourClampsToValidRange() {
        Preferences.setWeeklyResetHour(-3, defaults: defaults)
        XCTAssertEqual(Preferences.weeklyResetHour(defaults: defaults), 0)

        Preferences.setWeeklyResetHour(99, defaults: defaults)
        XCTAssertEqual(Preferences.weeklyResetHour(defaults: defaults), 23)
    }
}
