import Foundation

/// Detects whether this process is running inside a tmux pane, using the
/// `TMUX_PANE` environment variable tmux itself sets on every process
/// running inside one (e.g. `%12`) — no need to shell out to the `tmux`
/// binary just to know this much (GH issue #41, phase 1).
///
/// Phase 2 (resolving and targeting the specific pane from `SessionFocusService`
/// when "jump to session" is clicked) is intentionally not implemented yet:
/// it needs to shell out to the `tmux` binary and cross-reference client
/// ttys, and there's no tmux install on the machine this was written on to
/// verify any of that against a real session. Tracked separately.
enum TmuxInfo {
    static func currentPaneID(environment: [String: String] = ProcessInfo.processInfo.environment) -> String? {
        guard let pane = environment["TMUX_PANE"], !pane.isEmpty else { return nil }
        return pane
    }
}
