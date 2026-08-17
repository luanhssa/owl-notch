# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).
While the major version stays `0`, patch releases are bug fixes, minor
releases are new capabilities — breaking changes just bump minor too, per
semver's own rule for pre-1.0 releases.

## [Unreleased]

## [0.18.0] - 2026-08-18

### Added

- Token-usage bars in the expanded notch ([#42](https://github.com/luanhssa/owl-notch/issues/42),
  partial — cost and context-window percentage are still open), laid out
  like Claude Code's own `/usage` panel: one row per limit, each with its
  name, when it resets, the percentage consumed, and a bar underneath.
  Two limits are shown — the current 5-hour window and the calendar week.
  Contributed by [@cristovaoltfarias](https://github.com/cristovaoltfarias)
  in [#49](https://github.com/luanhssa/owl-notch/pull/49), reworked before
  merging to fix the issues below.

  Computed by `TokenUsageService` reading the same transcript JSONL files
  under `~/.claude/projects` that Claude Code itself writes (there's no
  API for this), deduplicated by `message.id`/`requestId` so resumed or
  compacted sessions don't double-count a turn, and grouped into 5-hour
  windows anchored to the top of the hour the way Claude Code's own usage
  reporting does. Refreshed every 30s in the background via
  `TokenUsageStore`, an `ObservableObject` that never blocks the main
  actor while scanning.

  The weekly row is the *calendar* week in your locale: Claude Code's
  weekly limit resets on a per-account schedule that isn't recorded in
  the transcripts, so Owl can't mirror its exact reset instant.
- "Limite da janela de 5h" and "Limite semanal" settings in Preferences,
  the ceilings the bars fill against. Claude Code doesn't expose your
  plan's allowances anywhere Owl can read, so these are numbers you set —
  they default to 120M and 400M tokens.
- An "Encerrar o Owl" button in the About panel. Owl runs as an accessory
  app — no Dock icon, no menu bar item, and no main menu for ⌘Q to hang
  off — so until now Activity Monitor or `pkill` were the only ways to
  stop it.

### Fixed

- The collapsed notch is now clickable across its whole area. A `.plain`
  SwiftUI button only hit-tests where its label actually draws, so the
  toggle's real target was the ~11pt bird glyph rather than the pill it
  looks like — the header now fills the notch's measured height and
  stamps a `contentShape` over it.

### Changed (fixed before merging #49)

- `TokenUsageService`'s scan is now cached per file, keyed by
  path+mtime+size — the original re-read and re-parsed every `.jsonl`
  under `~/.claude/projects` from scratch on every 30-second tick, cost
  growing unboundedly with total lifetime history. Closed files (mtime
  unchanged) are never re-read; only files that actually changed since
  the last scan are.
- `TokenUsageStore.refresh()` now guards against overlapping scans — a
  scan slower than the 30s timer interval could previously let a second,
  concurrent scan start, and whichever finished last (not necessarily the
  newest) won the write to `snapshot`.
- The dedup key now falls back to a (timestamp, model, token counts)
  composite when `message.id`/`requestId` are missing, instead of
  silently skipping dedup entirely for that line.
- `TokenUsageStore` now takes injectable `projectsRoot`/`defaults`/
  `refreshInterval` parameters, matching the testability seam
  `SessionStore` established (`docs/PATTERNS.md` #14) — the original had
  no way to point it at a throwaway root/defaults in a test.
- `Preferences`' two budget accessors and `PreferencesView`'s two slider
  rows were near-identical copies of each other; factored into one
  generic clamped-int accessor and one reusable slider row view.
- `expandedContentHeight()` now accounts for the divider around the
  token-usage row, closing the ~1pt panel-height gap the original PR
  introduced (and the pre-existing gap around the header/session-list
  dividers, per code review during #49).
- All 17 of #49's original tests pass unchanged; new tests added for the
  cache, the concurrency guard, and the dedup fallback.

## [0.17.0] - 2026-08-18

### Added

- A `/owl-setup` slash command ([#47](https://github.com/luanhssa/owl-notch/issues/47)):
  new `.claude/skills/owl-setup/SKILL.md`, a lightweight parallel install
  path for anyone already in a Claude Code session at this repo, running
  the same `Scripts/install.sh` the terminal-based install always has,
  without leaving the session. `disable-model-invocation: true` so this
  only ever runs when explicitly invoked, never something the agent
  decides to run on its own.

## [0.16.0] - 2026-08-18

### Added

- An opt-in "show the real last message" mode
  ([#45](https://github.com/luanhssa/owl-notch/issues/45)), off by
  default — the issue itself flagged this as a different privacy
  posture than `lastToolSummary`'s terse label (real conversation
  content, potentially sensitive, in an always-visible panel) and asked
  for an explicit decision before implementing; decided to ship it
  behind a Preferences toggle rather than as the default or not at all.
  - New `LastMessageService` reads the *last* qualifying line from a
    session's transcript (the "last message" counterpart to
    `SessionTitleService`'s "first message"), rendered with basic
    inline markdown (bold/italic/code/links).
  - Refreshed on every relevant hook event while the toggle is on — not
    cached once-and-done like a session's title/branch, since the
    answer changes on every turn — via the same background-`Task`-then-
    hop-to-`@MainActor` shape `SessionStore` already uses (#24).
  - `SessionInfo.lastMessageContent` is deliberately excluded from
    `Codable`, so it's never written to `sessions.json` — the one field
    on a session that can carry real conversation content shouldn't
    linger on disk between relaunches the way the rest of a session's
    metadata does. Turning the toggle off also clears any
    already-fetched content immediately, not just new fetches.
  - 14 new tests; all 109 pass.

## [0.15.0] - 2026-08-18

### Added

- Multi-display support ([#36](https://github.com/luanhssa/owl-notch/issues/36)):
  a "Tela" section in Preferences lets you pin the notch panel to a fixed
  display instead of always `NSScreen.main`. New `PanelDisplay.resolve`
  falls back to the main screen when no preference is set, or when the
  chosen display isn't currently connected. The panel repositions on
  `NSApplication.didChangeScreenParametersNotification` (monitor
  connected/disconnected/rearranged) and on the preference changing,
  neither of which is a `SessionStore` change `observeStore()`'s existing
  triggers would have caught.
  - Deliberately doesn't try to track "the display the relevant terminal
    window is currently on" dynamically — real per-window tracking
    machinery for a multi-monitor-only need the issue itself says a fixed
    preference already covers.
  - 7 new tests; all 95 pass.

## [0.14.0] - 2026-08-18

### Added

- Phase 2 of tmux-aware session targeting
  ([#41](https://github.com/luanhssa/owl-notch/issues/41)): "Abrir sessão"
  on a tmux-hosted session now resolves and switches to the *exact* pane,
  not just the terminal application. New `TmuxTargetResolver` shells out
  to the real `tmux` binary — a pane's own pty (captured as `tmuxPane` by
  phase 1) is a different device from the tty of the Terminal.app/iTerm2
  tab actually showing it, so this resolves the attached client's tty via
  `tmux list-panes`/`list-clients`, switches that client onto the target
  pane (`tmux switch-client -t <paneID>`), and hands the resolved tty to
  `SessionFocusService`'s existing tab-targeting (#31).
  - Verified against a real tmux 3.7c session on this machine (installed
    specifically to verify this, rather than shipping it unconfirmed the
    way phase 1 was deferred). That live verification caught a real bug
    before shipping: tmux silently substitutes `_` for non-printable
    bytes — including the literal tab used as `-F` output's field
    separator — when it can't confirm a UTF-8 locale, which is exactly
    the bare environment a login-item-launched `.app` gets from
    `launchd` (no `LANG`/`LC_ALL`). `TmuxTargetResolver` now forces
    `LC_ALL`/`LANG` explicitly rather than depending on whatever locale
    Owl happens to inherit.
  - 9 new tests for the pure pane/client parsing logic, with fixtures
    captured from real `tmux` output; all 88 pass.

## [0.13.1] - 2026-08-17

### Changed

- Moved `GitInfoService`'s directory walk and `SessionTitleService`'s
  transcript read off the main actor
  ([#24](https://github.com/luanhssa/owl-notch/issues/24)) — both used to
  run inline inside `SessionStore.handle(envelope:)`, blocking every hook
  event on disk I/O for however long a cache miss took. `SidebarTitleService`'s
  tree scan (the issue's first phase) was already off the main actor from
  the [#1](https://github.com/luanhssa/owl-notch/issues/1) fix.
  `handle(envelope:)` itself stays fully synchronous — no inline `await` —
  since an actor method is reentrant across suspension points; an `await`
  sitting mid-mutation would let another call for the same session
  interleave and get silently overwritten. Instead, each lookup spawns a
  detached `Task` and hops back to `@MainActor` only to assign the
  resolved value, re-reading the session fresh at that point rather than
  a copy captured before the hop. Documented as pattern #16 in
  `docs/PATTERNS.md`. 2 new async convergence tests; all 79 pass. Purely
  an internal refactor — no observable behavior change beyond the title/
  branch appearing a beat later on a cold cache instead of blocking for it.

## [0.13.0] - 2026-08-17

### Added

- An optional system notification for a session that needs attention
  ([#32](https://github.com/luanhssa/owl-notch/issues/32)), off by
  default since enabling it triggers a one-time OS permission prompt.
  New `SystemNotificationService` wraps `UNUserNotificationCenter`; fires
  from the same "just became newly notable" transition in
  `handle(envelope:)` that un-acknowledges a session, gated through a new
  pure `SessionStore.shouldSendSystemNotification(...)` that mirrors
  `isUrgent`'s foreground/snooze checks exactly — a system notification
  only fires for a transition that would also flag the notch itself.
  Deliberately doesn't try to auto-detect "the notch isn't visible"
  (locked screen, no notch display) — that's real complexity for
  dubious reliability; the toggle in Preferences covers the same need
  more simply, in line with the "don't let the notch grow needless
  configurability" reasoning behind [#34](https://github.com/luanhssa/owl-notch/issues/34)
  and [#48](https://github.com/luanhssa/owl-notch/issues/48).
  5 new tests; all 77 pass.

## [0.12.0] - 2026-08-17

### Added

- A focus-time snooze ([#33](https://github.com/luanhssa/owl-notch/issues/33)),
  global and per-session, both fixed at 30 minutes rather than
  configurable — same "don't let the notch grow needless configurability"
  reasoning as [#34](https://github.com/luanhssa/owl-notch/issues/34)'s
  `notifyOnSessionDone` and the [#48](https://github.com/luanhssa/owl-notch/issues/48)
  decision:
  - **Global** — a new moon button next to the About button in the
    expanded header suppresses the urgent badge/auto-expand for every
    session at once. Deliberately not persisted across relaunches (it's a
    short-lived "leave me alone" state, not a standing preference).
  - **Per-session** — a new bell-slash button in each session's expanded
    row snoozes just that one. Persisted as part of the session (like
    `acknowledged`), so it survives a relaunch, with a live "silenciado
    por mais Xm" caption.
  - A snooze can expire with no new hook event to trigger a natural
    re-render (the same problem [#17](https://github.com/luanhssa/owl-notch/issues/17)
    solved for the elapsed-time label) — `SessionStore` now runs a
    15-second tick, active only while a snooze is outstanding, that
    forces `needsAttentionCount`/`sortedSessions` to re-evaluate against
    the current time.
  - 5 new tests covering the pure `isSnoozeActive` comparison and both
    toggle paths; all 72 pass.

## [0.11.0] - 2026-08-17

### Added

- A Preferences window ([#34](https://github.com/luanhssa/owl-notch/issues/34)),
  opened from a new button in the About panel, exposing three settings
  that were previously either hardcoded or invisible:
  - **Stale-session cutoff** — how long a session with no new hook event
    stays tracked before being dropped (`SessionStore.staleAfter` was a
    fixed 12h; now a 1–48h slider, backed by `UserDefaults`).
  - **Notify on session finish** — whether a `.done` session counts
    toward the urgent badge/auto-expand. The two states meaning "Claude
    is actually blocked on you" (`needsAttention`/`needsApproval`) stay
    always-notable and non-optional by design — same "don't let the
    notch grow needless configurability" reasoning as the
    [#48](https://github.com/luanhssa/owl-notch/issues/48) decision;
    only "it finished" is a matter of taste.
  - **Open at login** — a real toggle over Owl's existing silent/automatic
    `SMAppService` registration (new `LoginItemService` wrapper), instead
    of a one-way action with no way to see or undo it from the UI.
  - 10 new tests (`PreferencesTests`, plus `SessionStoreTests` additions)
    covering defaults, round-tripping, range clamping, and that the
    notify-on-finish toggle only gates `.done`.

## [0.10.1] - 2026-08-17

### Changed

- Extracted `NotchContentView`'s styling literals (font sizes, opacities,
  corner radii, sizes, spacing/padding) into a new `NotchStyle` enum
  ([#39](https://github.com/luanhssa/owl-notch/issues/39)), mirroring
  `NotchLayout`'s existing centralization of shared geometry constants.
  Tokens are grouped by semantic role rather than by call site, so values
  that mean the same thing in different places (e.g. "muted text opacity")
  share one token instead of being coincidentally-equal inline literals.
  Purely mechanical — no visual or behavioral change.

## [0.10.0] - 2026-08-17

### Added

- Phase 1 of tmux-aware session targeting
  ([#41](https://github.com/luanhssa/owl-notch/issues/41)): `owl-hook`
  reads `TMUX_PANE` from its own environment (which tmux sets on every
  process running inside a pane — no need to shell out to the `tmux`
  binary for this much) and forwards it in the envelope. A session running
  inside tmux now shows a `·tmux` suffix on its environment tag instead of
  looking identical to a plain terminal session. 4 new tests for the
  (fully mockable) pane-id detection.

### Not done yet

- Phase 2 — resolving and targeting the *specific* tmux pane from
  `SessionFocusService` when "jump to session" is clicked — is **not**
  implemented. It needs to shell out to the `tmux` binary and
  cross-reference client ttys against #31's tab-targeting, and there's no
  tmux install on the machine this was written on to verify any of that
  against a real session. Left as a tracked follow-up on #41 rather than
  shipped unverified.

## [0.9.0] - 2026-08-17

### Added

- A global keyboard shortcut, **⌥⌘O**, toggles the notch panel open/closed
  from anywhere — even when Owl isn't the frontmost app
  ([#44](https://github.com/luanhssa/owl-notch/issues/44)). Implemented via
  the Carbon Hot Key API (`GlobalHotKey`) rather than an `NSEvent` global
  monitor, so it doesn't require Input Monitoring/Accessibility permission.
  Fixed rather than configurable for now — there's nowhere to configure it
  until the Preferences window (#34) exists; worth revisiting then.
  Mentioned in the README.

### Verification notes

- No automated test covers the actual hotkey registration/firing — like
  the AppleScript execution added for #31, this is a live system
  integration (a real global hotkey registration) that shouldn't be
  exercised from a test process. Verified via a clean debug and release
  build only.

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
