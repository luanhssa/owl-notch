# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).
While the major version stays `0`, patch releases are bug fixes, minor
releases are new capabilities — breaking changes just bump minor too, per
semver's own rule for pre-1.0 releases.

## [Unreleased]

## [0.8.0] - 2026-08-17

### Added

- Precise "jump to session" tab/window targeting for Terminal.app and
  iTerm2 ([#31](https://github.com/luanhssa/owl-notch/issues/31)):
  `owl-hook` now detects its controlling terminal's pty path
  (`ControllingTerminal.ttyPath()`, opening `/dev/tty` directly rather than
  checking stdin/stdout/stderr, since Claude Code pipes the hook JSON into
  this process's stdin) and forwards it in the envelope. `SessionFocusService`
  uses it to find and select the exact matching tab via AppleScript
  (`tty of tab`/`tty of session`), falling back to the existing app-level
  focus for every other registered terminal (Warp, Alacritty, kitty,
  WezTerm, Ghostty, VS Code) — none of which expose an equivalent
  scripting API, a real and disclosed gap rather than something papered
  over.
- 4 new tests covering the pure "does this terminal support precise
  targeting" decision and the tty-detection helper; the AppleScript
  execution itself is deliberately never invoked from a test (see below).

### Verification notes

- Terminal.app's `tty`/`index`/`selected`/`frontmost` properties were
  verified read-only against this machine's real, currently-open Terminal
  windows before writing the script (`osascript -e 'tell application
  "Terminal" to get tty of every tab of every window'` and similar) —
  confirmed working, real tty paths returned.
- iTerm2 isn't installed on this machine, so its script is implemented per
  iTerm2's own official documentation rather than empirically verified.
- The actual window-raising/tab-selecting commands were **not** live-executed
  during this session, to avoid visibly disrupting this machine's real, open
  terminal windows mid-conversation — worth one manual smoke test.

## [0.7.0] - 2026-08-17

### Added

- A small pulsing dot next to the last-tool summary in a session's
  expanded detail, shown only while that session is `.running`
  ([#35](https://github.com/luanhssa/owl-notch/issues/35)) — a static row
  otherwise looks identical whether Claude is actively working or has
  silently stalled. Uses its own self-contained looping SwiftUI animation
  rather than a manual timer, and respects "reduce motion"
  (`NSWorkspace.accessibilityDisplayShouldReduceMotion`) by staying a
  plain solid dot instead of animating.

## [0.6.0] - 2026-08-17

### Added

- Owl can now offer to wire its own hooks into `~/.claude/settings.json`
  automatically ([#43](https://github.com/luanhssa/owl-notch/issues/43)):
  on first launch, if `owl-hook` is already at its stable installed path
  and the hooks aren't already set up, a native alert offers to install
  them, show the manual README instructions instead, or dismiss (which is
  remembered — it won't ask again). Never writes anything without that
  explicit, in-the-moment choice. `HookInstaller` merges non-destructively:
  existing hooks for the same event are kept, Owl's are added alongside
  them, and re-running it is idempotent (verified with 8 new tests,
  including one specifically for "an existing hook must survive, not get
  replaced").
- `Scripts/install.sh`'s comment referenced a `Scripts/print-hooks-diff.sh`
  that never existed in the repo — fixed to point at this feature and the
  README instead.

### Changed

- README's "Wiring up the hooks" section now leads with the automatic
  option, keeping the manual JSON as the fallback.

## [0.5.0] - 2026-08-17

### Added

- A minimal About/Troubleshooting window (GH issue #37): app version, an
  "Abrir Console" button, and a confirmed "reset all sessions" action.
  Reachable from a small info-circle button in the notch's expanded
  header — Owl has no Dock icon or menu bar item, so this is its only
  other UI surface.
- `SessionStore.resetAllSessions()` — clears every tracked session at once,
  for when state gets stuck and a full app restart isn't convenient.

### Changed

- The panel opens Console.app rather than a specific log file: Owl's
  production code logs via `NSLog` into the unified system log, not a
  plain text file — `owl.log` is written only by the standalone
  `OwlServer` reference target (kept for historical/reference purposes),
  never by the real app. The original issue assumed a log file existed;
  it doesn't, so pointing at Console.app is the honest version of "view
  logs" rather than a button that opens nothing.

## [0.4.0] - 2026-08-16

### Added

- Foreground-session suppression, phase 1 (user-requested): a session whose
  own app (terminal, or Claude Desktop) is already the frontmost
  application no longer counts toward `needsAttentionCount` or floats to
  the top of `sortedSessions` — the user is already looking at it. Reverses
  immediately if the user switches away, since it's a live comparison
  against `NSWorkspace.frontmostApplication`, not a sticky flag like
  `acknowledged` ([#30](https://github.com/luanhssa/owl-notch/issues/30)).
  Phase 2 (window/tab-level precision via the Accessibility API) stays a
  separate, deferred stretch goal — `NSWorkspace` only reports the
  frontmost application, not which tab is visible.
- 5 new tests covering the pure `SessionStore.isForeground(frontmostBundleIdentifier:session:)`
  comparison across all session environments.

### Changed

- `SessionFocusService` now exposes `bundleIdentifier(for:)` — the same
  app-identity mapping `activate(for:)` uses to focus a session, reused by
  the foreground check instead of a third hardcoded copy of it.

## [0.3.0] - 2026-08-16

### Added

- A real test suite: 36 tests across two new targets (`OwlAppTests`,
  `OwlHookTests`), covering `SessionStore.handle(envelope:)`'s state
  machine (including the #5 and #23 regressions), `GitInfoService`'s HEAD/
  worktree parsing (including the #9 and #10 regressions), `SessionTitleService`'s
  title derivation (including the #19 regression), and `ProcessAncestry`'s
  name-matching classification ([#38](https://github.com/luanhssa/owl-notch/issues/38)).
  CI now runs `swift test` on every push/PR instead of just `swift build`.

### Changed

- `SessionStore.init` now takes an injectable `persistenceURL` (defaulting
  to the real path, unchanged for production) so tests never touch a real
  user's Owl data — see `docs/PATTERNS.md` #14.
- `ProcessAncestry.classify()` is now split into a live sysctl-based walk
  and a separate, pure `classify(ancestorProcessNames:)` matching function,
  so the matching logic can be unit tested without mocking process
  introspection — see `docs/PATTERNS.md` #15.

### Fixed

- While verifying this work, discovered that manually invoking `owl-hook`
  against the real unix socket during development reaches the developer's
  actual running Owl.app and pollutes its real session state — this
  happened during this session and required quitting/cleaning/relaunching
  the live app. Documented as a standing caution; the new test suite
  exercises this logic without ever touching a real socket.

## [0.2.1] - 2026-08-13

### Added

- CI via GitHub Actions (`.github/workflows/ci.yml`): runs `swift build` in
  both debug and release on every push to `main` and every PR, on
  `macos-15`. No test target exists yet (see #38) — a `swift test` step
  will follow once one does ([#40](https://github.com/luanhssa/owl-notch/issues/40)).

## [0.2.0] - 2026-08-13

### Added

- `TerminalAppRegistry` now covers VS Code, Alacritty, kitty, WezTerm,
  Ghostty, and Warp in addition to Terminal/iTerm2/iTerm — CLI sessions
  running in any of these now classify correctly instead of falling back to
  `"unknown"`, and "jump to session" focuses the right app instead of
  defaulting to Terminal.app ([#28](https://github.com/luanhssa/owl-notch/issues/28)).
  Process names/bundle identifiers were verified against each project's own
  source/build files where possible (VS Code was checked directly against a
  local install); Ghostty's and Warp's process names are good-faith
  inferences, not independently confirmed against a running instance —
  noted inline in the registry.

## [0.1.21] - 2026-08-13

### Fixed

- `sessions` (and its persisted mirror) was only bounded by the 12-hour
  `staleAfter` time window, which by definition can't catch a burst of many
  distinct session ids within that window. Added an independent
  `maxTrackedSessions` (200) hard cap, evicting the least-recently-active
  sessions first when exceeded, enforced both at startup (loading a
  persisted file) and in `handle(envelope:)`
  ([#23](https://github.com/luanhssa/owl-notch/issues/23)).

## [0.1.20] - 2026-08-13

### Fixed

- Every "jump to session" failure path (bad URL, Claude Desktop not
  installed, app-open failure) was a silent no-op — none of
  `NSWorkspace`'s return values or completion handlers were inspected. Now
  logs via `NSLog` and plays a system beep on failure, a minimal but honest
  signal instead of doing nothing ([#21](https://github.com/luanhssa/owl-notch/issues/21)).

## [0.1.19] - 2026-08-13

### Fixed

- `SessionFocusService` interpolated the session id into the `claude://`
  deep link with no percent-encoding — a value containing a reserved
  character (space, `&`, `=`, `#`, `+`) would make `URL(string:)` return
  `nil` and silently no-op. Now percent-encodes it first, with `&`/`=`/`+`
  also excluded from the allowed set since the id is a single query value,
  not a query string of its own ([#20](https://github.com/luanhssa/owl-notch/issues/20)).

## [0.1.18] - 2026-08-13

### Fixed

- `SessionTitleService` filtered harness-injected noise via a small,
  hand-maintained exact-string list (`<task-notification>`,
  `<system-reminder>`, `<user-prompt-submit-hook>`) that would drift out of
  date as Claude Code adds more of these. Replaced it with a shape-based
  heuristic — a bare, attribute-less kebab-case tag at the start of the
  text — that generalizes to future tags following the same convention,
  verified against both the known tags and plausible real text that starts
  with `<` (`<3`, `<html>`, pasted HTML) to confirm it doesn't misfire
  ([#19](https://github.com/luanhssa/owl-notch/issues/19)).

## [0.1.17] - 2026-08-13

### Fixed

- `NotchContentView.body` accessed `store.sortedSessions` three separate
  times per render (empty check, `ForEach`, and a last-element divider
  check re-sorting once per iteration) — `sortedSessions` re-sorts on every
  access. Captured it once into a local `let` and reused it
  ([#18](https://github.com/luanhssa/owl-notch/issues/18)).

## [0.1.16] - 2026-08-13

### Fixed

- The "há Xm nesse estado" elapsed-time label in a session's expanded detail
  only recomputed when an unrelated `@Published` change happened to
  re-render the view, so it could go stale indefinitely while nothing else
  changed. Wrapped it in a `TimelineView(.periodic(from: .now, by: 1))` so
  it now ticks on its own every second while visible
  ([#17](https://github.com/luanhssa/owl-notch/issues/17)).

## [0.1.15] - 2026-08-13

### Fixed

- `IPCServer` silently truncated the socket path via `strncpy` if it ever
  exceeded `sockaddr_un.sun_path`'s 104-byte buffer (an unusually long home
  directory path), which would bind to a different, wrong path with zero
  indication. Now checks the length first and logs via `NSLog` instead of
  proceeding ([#16](https://github.com/luanhssa/owl-notch/issues/16)).

## [0.1.14] - 2026-08-13

### Fixed

- `fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]` was
  copy-pasted in five places across all three targets, with no shared
  helper documenting why the force-index is safe. Added
  `OwlPaths.applicationSupportDirectory` to `OwlShared` and pointed every
  call site at it instead ([#15](https://github.com/luanhssa/owl-notch/issues/15)).
  Verified both debug and release builds, and `owl-hook`, still work
  end-to-end.

## [0.1.13] - 2026-08-13

### Fixed

- `owl-hook` called `ProcessAncestry.classify()` only after its socket
  connect/poll dance, which alone can take up to `connectTimeoutMs` (250ms).
  If the hook-invoking parent process exited during that window, owl-hook
  would already be reparented to `launchd` by the time `classify()` ran,
  misclassifying a real `"cli"`/`"code"` session as `"unknown"`. Moved the
  call to the very start of the process, before reading stdin or touching
  the socket at all ([#14](https://github.com/luanhssa/owl-notch/issues/14)).

## [0.1.12] - 2026-08-13

### Fixed

- `ProcessAncestry` (owl-hook) and `SessionFocusService` (OwlApp) each had
  their own hardcoded, hand-synced list of terminal apps, which had already
  drifted from each other. Extracted a new `OwlShared` target with a single
  `TerminalAppRegistry` both now depend on and import
  ([#13](https://github.com/luanhssa/owl-notch/issues/13)). Terminal
  coverage is unchanged (Terminal/iTerm2/iTerm) — expanding it further is
  tracked separately.

### Added

- A new `OwlShared` library target for data more than one target needs, so
  it doesn't get copy-pasted per target again.

## [0.1.11] - 2026-08-13

### Fixed

- `SidebarTitleService` silently swallowed any schema mismatch in Claude
  Desktop's on-disk session records (renamed/missing `cliSessionId`, a
  non-numeric `lastActivityAt`) with zero logging. Genuine parsing/schema
  failures now log via `NSLog`, kept separate from the deliberate, silent
  `isArchived` skip so that expected filtering doesn't get logged as a
  problem ([#12](https://github.com/luanhssa/owl-notch/issues/12)).

## [0.1.10] - 2026-08-13

### Fixed

- `GitInfoService` resolved a worktree's relative `gitdir:` pointer against
  Owl's own process cwd instead of the `.git` file's directory. Now resolves
  relative to the `.git` file itself, matching git's own semantics — the
  common absolute-path case is unaffected
  ([#10](https://github.com/luanhssa/owl-notch/issues/10)).

## [0.1.9] - 2026-08-13

### Fixed

- `GitInfoService` never resolved symlinks when walking up for `.git` —
  only `.standardizedFileURL`'s lexical `.`/`..` normalization was applied,
  so a symlinked working directory could never find the real repo. Now
  uses `.resolvingSymlinksInPath()`
  ([#9](https://github.com/luanhssa/owl-notch/issues/9)).

## [0.1.8] - 2026-08-13

### Fixed

- `IPCServer` assumed a hook envelope always arrived in a single `read()`
  call — a payload fragmented across multiple reads was silently dropped.
  Connections are now read in a loop until the peer closes its side (EOF),
  which is how owl-hook always terminates a write, bounded by a 1MB ceiling
  and the existing read timeout ([#8](https://github.com/luanhssa/owl-notch/issues/8)).

## [0.1.7] - 2026-08-13

### Fixed

- `IPCServer`'s per-connection `read()` had no timeout — a client that
  connected and never wrote could park a `DispatchQueue.global()` worker
  thread indefinitely, and enough stalled connections could exhaust the
  pool. Accepted connections now set a 2s `SO_RCVTIMEO`
  ([#7](https://github.com/luanhssa/owl-notch/issues/7)).

## [0.1.6] - 2026-08-13

### Fixed

- `IPCServer`'s accept loop had no error handling, so a repeatedly-failing
  `accept()` (e.g. hitting the process's file descriptor limit) would
  busy-spin a CPU core forever with no logging. Failures now log via
  `NSLog` and back off exponentially (capped at 1s)
  ([#6](https://github.com/luanhssa/owl-notch/issues/6)).
- Added `IPCServer.stop()` — there was previously no way to shut the socket
  server down cleanly; it's now called from `applicationWillTerminate`
  ([#6](https://github.com/luanhssa/owl-notch/issues/6)).

## [0.1.5] - 2026-08-13

### Fixed

- A session's `acknowledged` flag could permanently suppress a still-pending
  notification: it only reset on an actual `SessionState` transition, so a
  repeat `"notification"` hook for an already-acknowledged session (e.g. two
  permission prompts in a row with no intervening `userpromptsubmit`) never
  re-flagged it. A fresh `"notification"` event now un-acknowledges the
  session even when it maps to the same state as before
  ([#5](https://github.com/luanhssa/owl-notch/issues/5)).

## [0.1.4] - 2026-08-13

### Fixed

- `SessionTitleService` re-read and re-parsed up to 4MB of transcript on
  every hook event for any session whose title never resolved (noise-only
  first prompt, or one that fell past the scan window) — results (including
  "no title found") are now cached per `transcriptPath`, which is exact
  rather than a trade-off: a transcript's first message never changes as
  the conversation grows ([#4](https://github.com/luanhssa/owl-notch/issues/4)).

## [0.1.3] - 2026-08-13

### Fixed

- `GitInfoService` re-walked the filesystem for branch info on every hook
  event for any session outside a git repo — results (including "no repo
  found") are now cached per `cwd` instead of recomputed every time
  ([#3](https://github.com/luanhssa/owl-notch/issues/3)). The main-actor
  blocking / no-timeout half of that issue is tracked separately under the
  "Move filesystem-heavy lookups off the main actor" enhancement.

## [0.1.2] - 2026-08-13

### Fixed

- `SessionStore` wrote the full session state to disk synchronously on
  every single hook event — writes are now debounced (1.5s) so a burst of
  events coalesces into one write once things settle, and encode/write
  failures now log via `NSLog` instead of failing silently
  ([#2](https://github.com/luanhssa/owl-notch/issues/2)).
- `SessionStore`'s prune timer was never invalidated on deallocation — added
  a `deinit` that invalidates both the prune and persist timers
  ([#22](https://github.com/luanhssa/owl-notch/issues/22)).

## [0.1.1] - 2026-08-13

### Fixed

- `SidebarTitleService` rescanned Claude Desktop's entire session tree on
  every hook event, blocking the main actor — the disk scan now runs on a
  background queue, serving the existing cache immediately and refreshing it
  asynchronously ([#1](https://github.com/luanhssa/owl-notch/issues/1)).
- `SidebarTitleService`'s shared cache had no synchronization, relying on
  every caller happening to already be on the main actor — access is now
  guarded by a lock ([#11](https://github.com/luanhssa/owl-notch/issues/11)).

## [0.1.0] - 2026-08-13

### Added

- Initial public release: the notch panel (`OwlApp`), the hook forwarder
  (`owl-hook`), the embedded IPC server, and per-session state tracking
  (running / needs attention / needs approval / done).
- `docs/PATTERNS.md` documenting the project's conventions.
- An issue template and a public backlog of 48 tracked bugs and
  improvements (see [Issues](https://github.com/luanhssa/owl-notch/issues)).
