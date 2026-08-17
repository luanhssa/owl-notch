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
}
