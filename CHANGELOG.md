# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).
While the major version stays `0`, patch releases are bug fixes, minor
releases are new capabilities — breaking changes just bump minor too, per
semver's own rule for pre-1.0 releases.

## [Unreleased]

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
