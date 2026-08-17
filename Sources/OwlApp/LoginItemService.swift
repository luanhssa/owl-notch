import Foundation
import ServiceManagement

/// Wraps `SMAppService.mainApp` so the Preferences window (GH issue #34)
/// can show and toggle Owl's "open at login" registration — previously
/// this only ran one-directional and silent, from
/// `AppDelegate.registerLoginItemIfNeeded()` on first launch, with no way
/// to see or undo it from the UI.
enum LoginItemService {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    /// `SMAppService` needs a proper bundle identifier, so this is a no-op
    /// when Owl is running as the bare SwiftPM binary during development
    /// rather than from a real `.app` bundle.
    static var isAvailable: Bool {
        Bundle.main.bundleURL.pathExtension == "app"
    }

    @discardableResult
    static func setEnabled(_ enabled: Bool) -> Bool {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            return true
        } catch {
            NSLog("Owl: login item \(enabled ? "registration" : "unregistration") failed: \(error)")
            return false
        }
    }
}
