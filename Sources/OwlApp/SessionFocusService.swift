import AppKit
import OwlShared

/// "Jump to session" (the deep-link arrow).
///
/// `.code` uses Claude Desktop's own `claude://resume?session=<id>` deep
/// link (confirmed present in Claude.app's bundled source: it validates the
/// UUID and calls `importCliSession`, which resolves a session and navigates
/// straight to it). `importCliSession`'s own dedup only reuses a session if
/// its computed key (`local_<id>`) already matches one *it* is tracking in
/// memory — passing the raw CLI session id there always misses (Desktop's
/// own key for an already-open conversation is unrelated to the CLI id) and
/// creates a fresh duplicate sidebar entry ("general coding session"),
/// confirmed happening in practice. So instead we look up Desktop's own
/// internal id for this CLI session (SidebarTitleService, read from the same
/// on-disk records Desktop itself keeps) and pass *that* — its dedup key
/// then collides with the session Desktop already has open, so it reuses it
/// instead of importing a new one. Best-effort: if Desktop isn't tracking
/// this CLI session at all yet (no on-disk record found), there's nothing to
/// collide with, so we fall back to the plain CLI session id — that always
/// goes through the normal import path.
/// `.cowork`/`.cli` still just bring the right app to the front — precise
/// Cowork targeting and terminal tab/window targeting are stretch goals.
enum SessionFocusService {
    private static let claudeDesktopBundleID = "com.anthropic.claudefordesktop"

    static func activate(for session: SessionInfo) {
        switch session.environment {
        case .code:
            let target = SidebarTitleService.internalSessionID(forCliSessionID: session.sessionID) ?? session.sessionID
            // Both id sources are UUID-shaped today, but percent-encode
            // defensively rather than relying on that — an unescaped
            // reserved character here would make URL(string:) return nil
            // and silently no-op (GH issue #20).
            guard
                let encodedTarget = target.addingPercentEncoding(withAllowedCharacters: Self.queryValueAllowedCharacters),
                let url = URL(string: "claude://resume?session=\(encodedTarget)")
            else {
                reportFailure("couldn't build a claude:// URL for session \(session.sessionID)")
                return
            }
            if !NSWorkspace.shared.open(url) {
                reportFailure("NSWorkspace couldn't open \(url.absoluteString) — is Claude Desktop installed?")
            }
        case .cowork:
            activate(bundleIdentifier: claudeDesktopBundleID, fallbackAppName: "Claude")
        case .cli, .unknown:
            let appName = session.terminalApp ?? "Terminal"
            activate(bundleIdentifier: bundleIdentifier(forTerminalApp: appName), fallbackAppName: appName)
        }
    }

    private static func activate(bundleIdentifier: String, fallbackAppName: String) {
        let workspace = NSWorkspace.shared

        guard let url = workspace.urlForApplication(withBundleIdentifier: bundleIdentifier) else {
            if !workspace.launchApplication(fallbackAppName) {
                reportFailure("couldn't find or launch \(fallbackAppName)")
            }
            return
        }

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        workspace.openApplication(at: url, configuration: configuration) { _, error in
            if let error {
                reportFailure("couldn't open \(fallbackAppName): \(error.localizedDescription)")
            }
        }
    }

    private static func bundleIdentifier(forTerminalApp appName: String) -> String {
        TerminalAppRegistry.bundleIdentifier(forProcessName: appName) ?? "com.apple.Terminal"
    }

    /// Every "jump to session" failure path used to be a completely silent
    /// no-op — a system beep plus a log line is a minimal, honest signal
    /// that something didn't work, short of building a full in-panel
    /// message (GH issue #21).
    private static func reportFailure(_ message: String) {
        NSLog("Owl: \"jump to session\" failed — \(message)")
        NSSound.beep()
    }

    /// `.urlQueryAllowed` alone permits `&`/`=`/`+`, which are fine in a
    /// full query string but would let a single query *value* inject an
    /// extra parameter or corrupt the one it's part of — remove them here
    /// since `target` is a value, not a query string of its own.
    private static var queryValueAllowedCharacters: CharacterSet {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "&=+")
        return allowed
    }
}
