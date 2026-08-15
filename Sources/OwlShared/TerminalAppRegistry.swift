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
        // Verified directly against a real local install of this app
        // (`Contents/Info.plist`'s CFBundleExecutable/CFBundleIdentifier) —
        // highest-confidence entries.
        App(processName: "Code", bundleIdentifier: "com.microsoft.VSCode"),
        // Verified against the project's own Info.plist/build config in its
        // public source repo.
        App(processName: "alacritty", bundleIdentifier: "org.alacritty"),
        App(processName: "kitty", bundleIdentifier: "net.kovidgoyal.kitty"),
        App(processName: "wezterm-gui", bundleIdentifier: "com.github.wez.wezterm"),
        // Bundle identifier verified against the project's own Xcode build
        // settings; the process name is inferred from PRODUCT_NAME =
        // $(TARGET_NAME) and the app's own product name, not independently
        // confirmed against a running instance.
        App(processName: "Ghostty", bundleIdentifier: "com.mitchellh.ghostty"),
        // Bundle identifier corroborated across multiple sources; the
        // process name is a good-faith guess following the same
        // executable-matches-product-name convention every other verified
        // entry above happens to follow — not confirmed against a running
        // Warp instance. Worst case if wrong: unchanged from today (falls
        // back to "unknown"/Terminal.app, same as before this entry existed).
        App(processName: "Warp", bundleIdentifier: "dev.warp.Warp-Stable"),
    ]

    public static let processNames: Set<String> = Set(all.map(\.processName))

    public static func bundleIdentifier(forProcessName processName: String) -> String? {
        all.first { $0.processName == processName }?.bundleIdentifier
    }
}
