# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).
While the major version stays `0`, patch releases are bug fixes, minor
releases are new capabilities — breaking changes just bump minor too, per
semver's own rule for pre-1.0 releases.

## [Unreleased]

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
