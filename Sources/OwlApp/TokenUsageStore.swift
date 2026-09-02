import Foundation

/// Thin, timer-driven `ObservableObject` wrapper around `TokenUsageService`.
/// SwiftUI needs a `@Published` value to observe, but the actual token
/// count stays a pure, independently-testable function per
/// docs/PATTERNS.md #2/#14 — this class's only job is re-running it
/// periodically on a background queue and publishing whatever comes back,
/// the same background-thread-then-hop-to-main-actor shape `IPCServer`
/// uses (PATTERNS.md #1).
@MainActor
final class TokenUsageStore: ObservableObject {
    @Published private(set) var snapshot: TokenUsageService.Snapshot = .zero
    /// Published alongside the snapshot rather than read directly by the
    /// view, so editing a budget in Preferences redraws the bars
    /// immediately instead of at the next 30s tick.
    @Published private(set) var windowBudget: Int
    @Published private(set) var weeklyBudget: Int

    /// Scanning every transcript file on disk isn't free, and token totals
    /// don't need to be second-accurate — 30s keeps the notch's numbers
    /// reasonably fresh without re-walking `~/.claude/projects` constantly.
    private nonisolated static let defaultRefreshInterval: TimeInterval = 30

    private let projectsRoot: URL
    private let defaults: UserDefaults
    private let refreshInterval: TimeInterval
    private var timer: Timer?
    private var defaultsObserver: NSObjectProtocol?
    /// Guards against a scan slower than `refreshInterval` overlapping
    /// with the next timer tick — without this, two concurrent scans
    /// could race to assign `snapshot`, and the slower (and by then
    /// stale) one could finish last and silently revert to old numbers
    /// (found during #49's review).
    private var isScanning = false

    /// `projectsRoot`/`defaults`/`refreshInterval` are injectable so tests
    /// never scan a developer's real `~/.claude/projects` or touch real
    /// `UserDefaults` — the same testability seam `SessionStore`
    /// established (docs/PATTERNS.md #14); the original had neither.
    init(
        projectsRoot: URL = TokenUsageService.defaultProjectsRoot,
        defaults: UserDefaults = .standard,
        refreshInterval: TimeInterval = defaultRefreshInterval
    ) {
        self.projectsRoot = projectsRoot
        self.defaults = defaults
        self.refreshInterval = refreshInterval
        windowBudget = Preferences.tokenWindowBudget(defaults: defaults)
        weeklyBudget = Preferences.weeklyTokenBudget(defaults: defaults)

        refresh()
        // Mirrors `SessionStore`'s own `NSWorkspace` observer: `[weak self]`
        // once on the outermost closure is enough — the inner `Task`
        // captures that same (already-optional) `self`, not a fresh strong
        // reference, so re-annotating it `[weak self]` again would be
        // redundant (PATTERNS.md #12).
        timer = Timer.scheduledTimer(withTimeInterval: refreshInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refresh()
            }
        }
        // `object: defaults` (not `nil`) so this only reacts to *this*
        // instance's defaults changing — with `nil`, a test using a
        // throwaway suite would still react to unrelated UserDefaults
        // activity anywhere else in the same process.
        defaultsObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: defaults,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.windowBudget = Preferences.tokenWindowBudget(defaults: self.defaults)
                self.weeklyBudget = Preferences.weeklyTokenBudget(defaults: self.defaults)
                // Budgets alone don't need a rescan — they're just the bar's
                // denominator. The weekly reset day/hour changes the actual
                // `weekTokens`/`weekEnd` computation, so it needs one to show
                // up before the next scheduled tick.
                self.refresh()
            }
        }
    }

    deinit {
        timer?.invalidate()
        if let defaultsObserver {
            NotificationCenter.default.removeObserver(defaultsObserver)
        }
    }

    private func refresh() {
        guard !isScanning else { return }
        isScanning = true
        let root = projectsRoot
        let weekResetWeekday = Preferences.weeklyResetWeekday(defaults: defaults)
        let weekResetHour = Preferences.weeklyResetHour(defaults: defaults)
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let result = TokenUsageService.scan(
                projectsRoot: root,
                weekResetWeekday: weekResetWeekday,
                weekResetHour: weekResetHour
            )
            Task { @MainActor in
                self?.isScanning = false
                self?.snapshot = result
            }
        }
    }
}
