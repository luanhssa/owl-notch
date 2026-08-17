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
/// `.cli`/`.unknown` first try precise tab targeting (below) when the
/// terminal app and pty are both known and supported; otherwise, and always
/// for `.cowork`, this just brings the app to the front. Cowork targeting
/// stays a stretch goal (GH issue #31 covers terminal tab/window targeting
/// specifically, not Cowork).
enum SessionFocusService {
    static let claudeDesktopBundleID = "com.anthropic.claudefordesktop"

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
            if
                let tty = session.terminalTTY,
                supportsPreciseTargeting(terminalAppName: appName),
                selectTab(withTTY: tty, inTerminalApp: appName)
            {
                return
            }
            activate(bundleIdentifier: bundleIdentifier(forTerminalApp: appName), fallbackAppName: appName)
        }
    }

    /// Whether `selectTab(withTTY:inTerminalApp:)` below can target this
    /// terminal app precisely — Terminal.app and iTerm2 both have a mature,
    /// documented AppleScript dictionary exposing a tab/session's `tty`.
    /// Every other registered terminal (Warp, Alacritty, kitty, WezTerm,
    /// Ghostty, VS Code) has no equivalent scripting API, so those fall
    /// through to the existing app-level `activate(bundleIdentifier:
    /// fallbackAppName:)` — a real, disclosed gap, not silently pretended
    /// away (GH issue #31).
    static func supportsPreciseTargeting(terminalAppName: String) -> Bool {
        ["Terminal", "iTerm2", "iTerm"].contains(terminalAppName)
    }

    /// Finds the tab/session whose tty matches, selects it, and brings its
    /// window to the front — verified against a real local Terminal.app
    /// (`tty`/`index`/`selected`/`frontmost` are all real, readable
    /// properties on this machine); iTerm2's dictionary is documented
    /// identically (session tty, `select` on tab and window) but wasn't
    /// live-tested since iTerm2 isn't installed here. The actual
    /// window-raising commands were deliberately not live-tested against
    /// this machine's real, currently-open terminal windows, to avoid
    /// visibly disrupting them mid-session — worth one manual smoke test.
    /// Returns false (falls through to app-level focus) on any mismatch,
    /// script error, or unsupported app.
    private static func selectTab(withTTY tty: String, inTerminalApp appName: String) -> Bool {
        guard tty.hasPrefix("/dev/tty") else { return false }

        let script: String
        switch appName {
        case "Terminal":
            script = """
            tell application "Terminal"
                repeat with w in windows
                    repeat with t in tabs of w
                        if tty of t is "\(tty)" then
                            set frontmost to true
                            set index of w to 1
                            set selected of t to true
                            return true
                        end if
                    end repeat
                end repeat
                return false
            end tell
            """
        case "iTerm2", "iTerm":
            script = """
            tell application "iTerm2"
                repeat with w in windows
                    repeat with t in tabs of w
                        repeat with s in sessions of t
                            if tty of s is "\(tty)" then
                                select w
                                select t
                                return true
                            end if
                        end repeat
                    end repeat
                end repeat
                return false
            end tell
            """
        default:
            return false
        }

        guard let appleScript = NSAppleScript(source: script) else { return false }
        var errorInfo: NSDictionary?
        let result = appleScript.executeAndReturnError(&errorInfo)
        if let errorInfo {
            NSLog("Owl: precise tab targeting for \(appName) failed: \(errorInfo)")
            return false
        }
        return result.booleanValue
    }

    /// The bundle identifier `activate(for:)` would bring to the front for
    /// this session — factored out so `SessionStore`'s foreground-session
    /// suppression (GH issue #30) checks the exact same mapping "jump to
    /// session" uses, instead of a third hardcoded copy of it.
    static func bundleIdentifier(for session: SessionInfo) -> String {
        switch session.environment {
        case .code, .cowork:
            return claudeDesktopBundleID
        case .cli, .unknown:
            return bundleIdentifier(forTerminalApp: session.terminalApp ?? "Terminal")
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
