import Foundation
import UserNotifications

/// Optional system notification for a session that needs attention while
/// the notch panel itself isn't a reliable signal — locked screen, no
/// notch-equipped display, or simply not looking at the Mac (GH issue
/// #32). Gated behind a Preferences toggle (default off), since enabling
/// it triggers a one-time OS permission prompt.
enum SystemNotificationService {
    /// `UNUserNotificationCenter` needs a proper bundle identifier, so
    /// this is a no-op when Owl is running as the bare SwiftPM binary
    /// during development (or under `swift test`) rather than from a real
    /// `.app` bundle — same guard as `LoginItemService.isAvailable`.
    static var isAvailable: Bool {
        Bundle.main.bundleURL.pathExtension == "app"
    }

    /// Call once when the preference is turned on, not on every
    /// `notify()` — macOS only prompts the user the first time regardless
    /// of how often this is called, but there's no need to ask again.
    static func requestAuthorizationIfNeeded() {
        guard isAvailable else { return }
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            guard settings.authorizationStatus == .notDetermined else { return }
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, error in
                if let error {
                    NSLog("Owl: notification authorization request failed: \(error)")
                } else if !granted {
                    NSLog("Owl: notification authorization denied")
                }
            }
        }
    }

    static func notify(session: SessionInfo) {
        guard isAvailable else { return }
        let content = UNMutableNotificationContent()
        content.title = session.displayTitle
        content.body = session.state.label
        content.sound = .default
        let request = UNNotificationRequest(identifier: session.sessionID, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                NSLog("Owl: failed to deliver system notification: \(error)")
            }
        }
    }
}
