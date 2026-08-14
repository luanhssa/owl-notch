/// The one shared table of terminal apps owl-hook can classify a CLI
/// session as running in, and OwlApp can bring to the front for "jump to
/// session." Previously this lived as two independently hardcoded lists —
/// `ProcessAncestry.terminalProcessNames` (owl-hook) and
/// `SessionFocusService.bundleIdentifier(forTerminalApp:)` (OwlApp) — that
/// had to be hand-synced and had already drifted (GH issue #13). Add a new
/// terminal here once, not in either target.
public enum TerminalAppRegistry {
    public struct App: Sendable {
        /// The process name as it appears in `p_comm` (what `ProcessAncestry`
        /// matches against when walking the parent-PID chain).
        public let processName: String
        public let bundleIdentifier: String
    }

    public static let all: [App] = [
        App(processName: "Terminal", bundleIdentifier: "com.apple.Terminal"),
        App(processName: "iTerm2", bundleIdentifier: "com.googlecode.iterm2"),
        App(processName: "iTerm", bundleIdentifier: "com.googlecode.iterm2"),
    ]

    public static let processNames: Set<String> = Set(all.map(\.processName))

    public static func bundleIdentifier(forProcessName processName: String) -> String? {
        all.first { $0.processName == processName }?.bundleIdentifier
    }
}
