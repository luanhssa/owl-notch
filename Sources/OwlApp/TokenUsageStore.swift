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
    @Published private(set) var windowBudget: Int = Preferences.tokenWindowBudget()
    @Published private(set) var weeklyBudget: Int = Preferences.weeklyTokenBudget()

    /// Scanning every transcript file on disk isn't free, and token totals
    /// don't need to be second-accurate — 30s keeps the notch's numbers
    /// reasonably fresh without re-walking `~/.claude/projects` constantly.
    private static let refreshInterval: TimeInterval = 30

    private var timer: Timer?
    private var defaultsObserver: NSObjectProtocol?

    init() {
        refresh()
        // Mirrors `SessionStore`'s own `NSWorkspace` observer: `[weak self]`
        // once on the outermost closure is enough — the inner `Task`
        // captures that same (already-optional) `self`, not a fresh strong
        // reference, so re-annotating it `[weak self]` again would be
        // redundant (PATTERNS.md #12).
        timer = Timer.scheduledTimer(withTimeInterval: Self.refreshInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refresh()
            }
        }
        defaultsObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.windowBudget = Preferences.tokenWindowBudget()
                self?.weeklyBudget = Preferences.weeklyTokenBudget()
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
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let result = TokenUsageService.scan()
            Task { @MainActor in
                self?.snapshot = result
            }
        }
    }
}
