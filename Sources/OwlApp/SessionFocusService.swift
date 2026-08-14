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
            else { return }
            NSWorkspace.shared.open(url)
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
            _ = workspace.launchApplication(fallbackAppName)
            return
        }

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        workspace.openApplication(at: url, configuration: configuration)
    }

    private static func bundleIdentifier(forTerminalApp appName: String) -> String {
        TerminalAppRegistry.bundleIdentifier(forProcessName: appName) ?? "com.apple.Terminal"
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
