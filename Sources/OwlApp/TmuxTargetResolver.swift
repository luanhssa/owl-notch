import Foundation

/// Resolves a tmux pane id (e.g. `%12`, captured by `owl-hook`'s
/// `TmuxInfo.currentPaneID()` and stored as `SessionInfo.tmuxPane`) to the
/// terminal-emulator tab actually showing it — GH issue #41, phase 2.
///
/// A tmux pane has its own pty, allocated by tmux itself — verified live
/// against a real tmux session on this machine, a pane's own tty (e.g.
/// `/dev/ttys001`) is a different device from the tty of the outer
/// Terminal.app/iTerm2 tab running the `tmux attach` client that displays
/// it (e.g. `/dev/ttys024`). `SessionFocusService`'s existing
/// `selectTab(withTTY:inTerminalApp:)` (GH issue #31) searches Terminal.app/
/// iTerm2 tabs by *their own* tty, so it needs the attached client's tty,
/// not the pane's — that's what `activatePane` resolves below, after also
/// switching that client onto the exact target pane so the right
/// window/pane is what's actually visible once the tab comes to the front.
enum TmuxTargetResolver {
    /// Switches whichever tmux client is attached to `paneID`'s session
    /// onto that exact pane — `tmux switch-client -t <paneID>` resolves
    /// the session/window/pane from the pane id alone and selects it as
    /// active, verified live — and returns that client's own tty. `nil` if
    /// the pane no longer exists, tmux isn't installed, or the pane's
    /// session has no attached client (nothing on screen to switch).
    static func activatePane(_ paneID: String) -> String? {
        guard let clientTTY = attachedClientTTY(forPane: paneID) else { return nil }
        _ = run(["switch-client", "-c", clientTTY, "-t", paneID])
        return clientTTY
    }

    private static func attachedClientTTY(forPane paneID: String) -> String? {
        guard
            let paneOutput = run(["list-panes", "-a", "-F", "#{pane_id}\t#{session_name}"]),
            let session = sessionName(forPane: paneID, in: paneOutput),
            let clientOutput = run(["list-clients", "-F", "#{client_session}\t#{client_activity}\t#{client_tty}"])
        else { return nil }
        return mostRecentClientTTY(forSession: session, in: clientOutput)
    }

    /// Pure — parses `tmux list-panes -a -F "#{pane_id}\t#{session_name}"`
    /// output to find which session owns `paneID`. Exposed for testing.
    static func sessionName(forPane paneID: String, in listPanesOutput: String) -> String? {
        for line in listPanesOutput.split(separator: "\n") {
            let fields = line.split(separator: "\t")
            guard fields.count == 2, fields[0] == paneID else { continue }
            return String(fields[1])
        }
        return nil
    }

    /// Pure — parses `tmux list-clients -F "#{client_session}
    /// \t#{client_activity}\t#{client_tty}"` output and picks the tty of
    /// the most recently active client attached to `session` (a session
    /// can have more than one attached client — e.g. two Terminal windows
    /// showing the same tmux session). `client_activity` is a unix
    /// timestamp; larger means more recent. Exposed for testing.
    static func mostRecentClientTTY(forSession session: String, in listClientsOutput: String) -> String? {
        var best: (activity: Int, tty: String)?
        for line in listClientsOutput.split(separator: "\n") {
            let fields = line.split(separator: "\t")
            guard fields.count == 3, fields[0] == session, let activity = Int(fields[1]) else { continue }
            if best == nil || activity > best!.activity {
                best = (activity, String(fields[2]))
            }
        }
        return best?.tty
    }

    /// Runs a real `tmux` subprocess and returns its trimmed stdout, or
    /// `nil` on a nonzero exit or missing binary. Not directly unit
    /// tested — matches this codebase's convention for live-OS-boundary
    /// code (`SessionFocusService`'s AppleScript calls, `LoginItemService`);
    /// verified manually against a real tmux session instead (see the
    /// commit that introduced this file).
    private static func run(_ arguments: [String]) -> String? {
        guard let tmuxPath = tmuxBinaryPath else { return nil }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tmuxPath)
        process.arguments = arguments
        // Verified live: without a UTF-8 locale, tmux silently substitutes
        // "_" for non-printable bytes in `-F` output — including the
        // literal tab used as our field separator above — which silently
        // corrupts every parse below. A login-item-launched `.app` gets
        // exactly this bare environment from launchd (no LANG/LC_ALL), so
        // this can't be left to whatever Owl happens to inherit.
        var environment = ProcessInfo.processInfo.environment
        environment["LC_ALL"] = "en_US.UTF-8"
        environment["LANG"] = "en_US.UTF-8"
        process.environment = environment
        let stdout = Pipe()
        process.standardOutput = stdout
        process.standardError = Pipe()
        do {
            try process.run()
        } catch {
            return nil
        }
        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        return String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// A `.app` bundle launched from Finder/a login item doesn't inherit a
    /// shell's `PATH` the way a terminal-launched process does, so tmux
    /// (commonly at a Homebrew prefix) isn't guaranteed reachable by name
    /// alone — check the real install locations explicitly instead of
    /// relying on `Process`'s own `PATH` lookup.
    private static var tmuxBinaryPath: String? {
        ["/opt/homebrew/bin/tmux", "/usr/local/bin/tmux", "/usr/bin/tmux"]
            .first { FileManager.default.isExecutableFile(atPath: $0) }
    }
}
