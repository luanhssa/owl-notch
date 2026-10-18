import Foundation

/// Publishes whether a newer release exists, for the About panel — the
/// `ObservableObject` side of `UpdateCheckService`, the same split as
/// `TokenUsageStore`/`TokenUsageService` (PATTERNS.md #2).
@MainActor
final class UpdateStore: ObservableObject {
    /// Set only when the latest release is newer than the running build.
    @Published private(set) var availableUpdate: UpdateCheckService.Release?

    /// How often to ask "is a check due?" — not how often to hit the
    /// network; that's `UpdateCheckService.checkInterval`. A Mac that
    /// sleeps through a whole week still checks within this long of
    /// waking up.
    private nonisolated static let pollInterval: TimeInterval = 6 * 60 * 60

    private let defaults: UserDefaults
    private let currentVersion: String
    private var timer: Timer?
    private var defaultsObserver: NSObjectProtocol?
    private var isChecking = false

    init(
        defaults: UserDefaults = .standard,
        currentVersion: String = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
    ) {
        self.defaults = defaults
        self.currentVersion = currentVersion

        checkIfDue()
        timer = Timer.scheduledTimer(withTimeInterval: Self.pollInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.checkIfDue()
            }
        }
        // Turning the preference on checks right away (if due) instead of
        // waiting up to `pollInterval`; turning it off hides any notice.
        defaultsObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: defaults,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.checkIfDue()
            }
        }
    }

    deinit {
        timer?.invalidate()
        if let defaultsObserver {
            NotificationCenter.default.removeObserver(defaultsObserver)
        }
    }

    private func checkIfDue() {
        guard Preferences.checkForUpdates(defaults: defaults) else {
            availableUpdate = nil
            return
        }
        guard !isChecking, UpdateCheckService.isCheckDue(lastCheck: Preferences.lastUpdateCheck(defaults: defaults)) else { return }
        isChecking = true
        Task { [weak self] in
            let release = await UpdateCheckService.fetchLatestRelease()
            guard let self else { return }
            isChecking = false
            // Only a successful fetch counts as a check — a failed one
            // retries at the next poll instead of waiting a whole week.
            guard let release else { return }
            Preferences.setLastUpdateCheck(Date(), defaults: defaults)
            guard Preferences.checkForUpdates(defaults: defaults) else { return }
            availableUpdate = UpdateCheckService.isNewer(release.version, than: currentVersion) ? release : nil
        }
    }
}
