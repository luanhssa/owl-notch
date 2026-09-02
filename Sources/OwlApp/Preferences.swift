import CoreGraphics
import Foundation

/// Owl's user-configurable settings (GH issue #34) — backed by
/// `UserDefaults` so they survive relaunches without a dedicated
/// preferences file. Every accessor takes an injectable `UserDefaults`,
/// defaulting to `.standard` — the same testability seam used throughout
/// the project (see docs/PATTERNS.md) so tests never touch the real
/// defaults domain.
enum Preferences {
    private static let staleSessionCutoffHoursKey = "owl.staleSessionCutoffHours"
    private static let notifyOnSessionDoneKey = "owl.notifyOnSessionDone"
    private static let systemNotificationsEnabledKey = "owl.systemNotificationsEnabled"
    private static let preferredDisplayIDKey = "owl.preferredDisplayID"
    private static let showLastMessageContentKey = "owl.showLastMessageContent"
    private static let tokenWindowBudgetKey = "owl.tokenWindowBudget"
    private static let weeklyTokenBudgetKey = "owl.weeklyTokenBudget"
    private static let weeklyResetWeekdayKey = "owl.weeklyResetWeekday"
    private static let weeklyResetHourKey = "owl.weeklyResetHour"

    /// Posted whenever `setPreferredDisplayID` changes the stored value —
    /// nothing else would otherwise tell `AppDelegate` to reposition the
    /// panel, since changing a preference isn't itself a screen-parameter
    /// change (GH issue #36).
    static let preferredDisplayDidChangeNotification = Notification.Name("owl.preferredDisplayDidChange")

    static let defaultStaleSessionCutoffHours: Double = 12
    static let staleSessionCutoffHoursRange: ClosedRange<Double> = 1...48

    static func staleSessionCutoffHours(defaults: UserDefaults = .standard) -> Double {
        defaults.object(forKey: staleSessionCutoffHoursKey) as? Double ?? defaultStaleSessionCutoffHours
    }

    static func setStaleSessionCutoffHours(_ hours: Double, defaults: UserDefaults = .standard) {
        let clamped = min(max(hours, staleSessionCutoffHoursRange.lowerBound), staleSessionCutoffHoursRange.upperBound)
        defaults.set(clamped, forKey: staleSessionCutoffHoursKey)
    }

    /// The two states meaning "Claude is actually blocked on you"
    /// (`needsAttention`/`needsApproval`) always count as notable — that's
    /// Owl's whole reason to exist. Only "a session finished" (`.done`) is
    /// optional, for anyone who only wants to be pulled back for a live
    /// decision, not just to see something that already completed.
    static func notifyOnSessionDone(defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: notifyOnSessionDoneKey) as? Bool ?? true
    }

    static func setNotifyOnSessionDone(_ value: Bool, defaults: UserDefaults = .standard) {
        defaults.set(value, forKey: notifyOnSessionDoneKey)
    }

    /// Off by default — turning it on triggers a one-time OS permission
    /// prompt (GH issue #32), so this shouldn't be silently opt-in the way
    /// `notifyOnSessionDone` is.
    static func systemNotificationsEnabled(defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: systemNotificationsEnabledKey) as? Bool ?? false
    }

    static func setSystemNotificationsEnabled(_ value: Bool, defaults: UserDefaults = .standard) {
        defaults.set(value, forKey: systemNotificationsEnabledKey)
    }

    /// `nil` means no preference — the panel follows `NSScreen.main` as
    /// before (GH issue #36). Set means "always this display, when it's
    /// connected" — see `PanelDisplay.resolve` for the fallback when it
    /// isn't.
    static func preferredDisplayID(defaults: UserDefaults = .standard) -> CGDirectDisplayID? {
        guard let stored = defaults.object(forKey: preferredDisplayIDKey) as? Int else { return nil }
        return CGDirectDisplayID(stored)
    }

    static func setPreferredDisplayID(_ displayID: CGDirectDisplayID?, defaults: UserDefaults = .standard) {
        if let displayID {
            defaults.set(Int(displayID), forKey: preferredDisplayIDKey)
        } else {
            defaults.removeObject(forKey: preferredDisplayIDKey)
        }
        NotificationCenter.default.post(name: preferredDisplayDidChangeNotification, object: nil)
    }

    /// Off by default (GH issue #45) — a different privacy posture than
    /// `lastToolSummary`'s terse label, since this surfaces real
    /// conversation content in Owl's always-visible notch panel. Turning
    /// it off also clears any already-fetched content rather than just
    /// stopping new fetches — see `SessionStore.handle(envelope:)`.
    static func showLastMessageContent(defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: showLastMessageContentKey) as? Bool ?? false
    }

    static func setShowLastMessageContent(_ value: Bool, defaults: UserDefaults = .standard) {
        defaults.set(value, forKey: showLastMessageContentKey)
    }

    /// The ceiling the notch's usage bar fills against. Claude Code doesn't
    /// publish your plan's per-window token allowance anywhere Owl can read
    /// it — the transcripts only record what was spent — so the ceiling has
    /// to be a number you set. The default is sized from the heaviest
    /// 5-hour windows a Max-plan user actually reaches; adjust it until a
    /// full bar means what a full bar should mean for your plan.
    static let defaultTokenWindowBudget: Int = 120_000_000
    /// Bounds in whole multiples of the Preferences slider's 5M step, so
    /// every reachable slider position is a round number.
    static let tokenWindowBudgetRange: ClosedRange<Int> = 5_000_000...500_000_000

    static func tokenWindowBudget(defaults: UserDefaults = .standard) -> Int {
        clampedInt(key: tokenWindowBudgetKey, default: defaultTokenWindowBudget, range: tokenWindowBudgetRange, defaults: defaults)
    }

    static func setTokenWindowBudget(_ tokens: Int, defaults: UserDefaults = .standard) {
        setClampedInt(tokens, key: tokenWindowBudgetKey, range: tokenWindowBudgetRange, defaults: defaults)
    }

    /// The weekly counterpart of `tokenWindowBudget`, unreadable from
    /// Claude Code for the same reason and so configurable for the same
    /// reason. Bounds are multiples of the Preferences slider's 25M step.
    static let defaultWeeklyTokenBudget: Int = 400_000_000
    static let weeklyTokenBudgetRange: ClosedRange<Int> = 25_000_000...2_000_000_000

    static func weeklyTokenBudget(defaults: UserDefaults = .standard) -> Int {
        clampedInt(key: weeklyTokenBudgetKey, default: defaultWeeklyTokenBudget, range: weeklyTokenBudgetRange, defaults: defaults)
    }

    static func setWeeklyTokenBudget(_ tokens: Int, defaults: UserDefaults = .standard) {
        setClampedInt(tokens, key: weeklyTokenBudgetKey, range: weeklyTokenBudgetRange, defaults: defaults)
    }

    /// When the weekly usage bar rolls over, in the user's own local time.
    /// Claude Code doesn't expose your account's actual weekly-limit reset
    /// schedule anywhere Owl can read it, so this defaults to `nil` —
    /// "not set", meaning `TokenUsageService` falls back to the plain
    /// calendar week (whatever the system Region considers day one), the
    /// same approximation Owl always used. Set it to whatever day
    /// Claude Code's own `/usage` panel shows as your reset day and the
    /// weekly bar rolls over in sync with it instead. `1...7` is
    /// `Calendar`'s own weekday numbering (1 = Sunday … 7 = Saturday).
    static func weeklyResetWeekday(defaults: UserDefaults = .standard) -> Int? {
        guard
            let stored = defaults.object(forKey: weeklyResetWeekdayKey) as? Int,
            (1...7).contains(stored)
        else { return nil }
        return stored
    }

    static func setWeeklyResetWeekday(_ weekday: Int?, defaults: UserDefaults = .standard) {
        if let weekday, (1...7).contains(weekday) {
            defaults.set(weekday, forKey: weeklyResetWeekdayKey)
        } else {
            defaults.removeObject(forKey: weeklyResetWeekdayKey)
        }
    }

    /// The hour (0–23, local time) paired with `weeklyResetWeekday`. Only
    /// meaningful once a reset weekday is actually set; ignored otherwise.
    static let defaultWeeklyResetHour = 0

    static func weeklyResetHour(defaults: UserDefaults = .standard) -> Int {
        guard
            let stored = defaults.object(forKey: weeklyResetHourKey) as? Int,
            (0...23).contains(stored)
        else { return defaultWeeklyResetHour }
        return stored
    }

    static func setWeeklyResetHour(_ hour: Int, defaults: UserDefaults = .standard) {
        defaults.set(min(max(hour, 0), 23), forKey: weeklyResetHourKey)
    }

    /// Shared by `tokenWindowBudget`/`weeklyTokenBudget` — they were
    /// previously two copies of the same get/clamp logic, differing only
    /// in key/default/range (found during #49's review).
    private static func clampedInt(key: String, default defaultValue: Int, range: ClosedRange<Int>, defaults: UserDefaults) -> Int {
        guard let stored = defaults.object(forKey: key) as? Int else { return defaultValue }
        return min(max(stored, range.lowerBound), range.upperBound)
    }

    private static func setClampedInt(_ value: Int, key: String, range: ClosedRange<Int>, defaults: UserDefaults) {
        let clamped = min(max(value, range.lowerBound), range.upperBound)
        defaults.set(clamped, forKey: key)
    }
}
