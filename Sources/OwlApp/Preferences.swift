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
    private static let tokenWindowBudgetKey = "owl.tokenWindowBudget"
    private static let weeklyTokenBudgetKey = "owl.weeklyTokenBudget"

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
        guard let stored = defaults.object(forKey: tokenWindowBudgetKey) as? Int else {
            return defaultTokenWindowBudget
        }
        return min(max(stored, tokenWindowBudgetRange.lowerBound), tokenWindowBudgetRange.upperBound)
    }

    static func setTokenWindowBudget(_ tokens: Int, defaults: UserDefaults = .standard) {
        let clamped = min(max(tokens, tokenWindowBudgetRange.lowerBound), tokenWindowBudgetRange.upperBound)
        defaults.set(clamped, forKey: tokenWindowBudgetKey)
    }

    /// The weekly counterpart of `tokenWindowBudget`, unreadable from
    /// Claude Code for the same reason and so configurable for the same
    /// reason. Bounds are multiples of the Preferences slider's 25M step.
    static let defaultWeeklyTokenBudget: Int = 400_000_000
    static let weeklyTokenBudgetRange: ClosedRange<Int> = 25_000_000...2_000_000_000

    static func weeklyTokenBudget(defaults: UserDefaults = .standard) -> Int {
        guard let stored = defaults.object(forKey: weeklyTokenBudgetKey) as? Int else {
            return defaultWeeklyTokenBudget
        }
        return min(max(stored, weeklyTokenBudgetRange.lowerBound), weeklyTokenBudgetRange.upperBound)
    }

    static func setWeeklyTokenBudget(_ tokens: Int, defaults: UserDefaults = .standard) {
        let clamped = min(max(tokens, weeklyTokenBudgetRange.lowerBound), weeklyTokenBudgetRange.upperBound)
        defaults.set(clamped, forKey: weeklyTokenBudgetKey)
    }
}
