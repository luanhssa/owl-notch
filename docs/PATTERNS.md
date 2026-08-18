# Patterns

Conventions this codebase already follows, written down so new code — from
me or anyone else — stays consistent with them instead of drifting.

Bugs found while reviewing the code that follows these patterns are tracked
as [issues labeled `bug`](https://github.com/luanhssa/owl-notch/issues?q=is%3Aissue+label%3Abug),
not here. Improvement ideas are tracked as
[issues labeled `enhancement`](https://github.com/luanhssa/owl-notch/issues?q=is%3Aissue+label%3Aenhancement).
This file is for conventions, which don't go stale the way a bug list does.

## 1. Concurrency model: one main actor, one place for the unsafe stuff

`SessionStore` is `@MainActor`-isolated — its own doc comment states this
explicitly, since SwiftUI observation needs to run there. `IPCServer` runs
its accept/read loop on a background thread (blocking socket calls are fine
there) and hops to the main actor with `Task { @MainActor in ... }` — not
`DispatchQueue.main.async` — before ever touching `store`.

Low-level, unsafe C interop (`sockaddr_un`, `sysctl`/`kinfo_proc`,
`withUnsafeMutablePointer`) stays isolated to exactly two files —
`IPCServer.swift` and `owl-hook`'s `ProcessAncestry.swift` — and never leaks
into SwiftUI or model code.

## 2. Stateless "Service" enums, not classes

Every piece of standalone behavior — `GitInfoService`, `SessionTitleService`,
`SidebarTitleService`, `SessionFocusService`, `ProcessAncestry` — is an
`enum` with only `static` members. No instances, no protocols, no DI
container. `SidebarTitleService`, `GitInfoService`, and `SessionTitleService` are the
exceptions, each with a lock-guarded static cache (keyed by session id, by
`cwd`, and by `transcriptPath` respectively) to avoid re-scanning the
filesystem on every hook event. If you add another cached service, guard
its state with a lock too — don't rely on "every caller happens to already
be on the main actor," which is how issue #11 happened.

## 3. Doc comments explain WHY, and say what's confirmed vs. assumed

Comments across the codebase justify a decision, not restate the code next
to it. When a comment describes reverse-engineered behavior of another app —
`SessionFocusService`'s `claude://resume` dedup workaround is the clearest
example — it explicitly says what was *"confirmed happening in practice"*
versus inferred. New code that depends on another app's private format
should follow the same discipline: verify, then say so.

## 4. Fail-soft / fail-open, everywhere

`guard let ... else { return nil }` and `try?` are the default; no thrown
errors are surfaced to callers anywhere in `OwlApp`. This mirrors
`owl-hook`'s own top-level design principle — always exit `0`, never
influence a permission decision, a 250ms connect timeout so a missing Owl
never slows down Claude Code — extended into the app itself.

## 5. Every magic number is a named, commented constant

`SessionTitleService.maxBytesRead`/`maxLinesScanned`,
`SessionStore.staleAfter`/`pruneInterval`, `GitInfoService`'s `0..<20`
directory walk, `ProcessAncestry`'s `hops < 40`, `SidebarTitleService
.scanInterval` — every bound in the codebase is a named constant with an
inline comment justifying the value. Two files don't yet follow this and
shouldn't be used as a template: `IPCServer`'s buffer size (`65536`) and
listen backlog (`32`), and `NotchContentView`'s inline styling literals
(fonts, spacing, opacity, corner radius).

## 6. Trust boundary decides JSON strictness

Owl's own wire/model types — `SessionInfo`, `HookEnvelope`, `HookInput` — are
`Codable` structs. Anything read from another app's private storage —
Claude Desktop's sidebar records in `SidebarTitleService`, transcript JSONL
in `SessionTitleService` — is parsed as a loose `[String: Any]` with `as?`
casts instead. The rule: **own data gets a `Codable` struct, foreign data
gets a loose dictionary** — because a foreign format can change without
notice and a `Codable` decode failure there would be a crash risk, not a
`nil`.

## 7. Value-type state, copy-modify-reassign

`SessionInfo` is a `struct`. `SessionStore.handle(envelope:)` always does
`var info = previous ?? SessionInfo(...); info.x = ...; sessions[id] = info`
rather than mutating a class instance or a dictionary entry in place.

## 8. Encapsulation via `@Published private(set)`

External code only changes `SessionStore` state through its named methods —
`handle`, `acknowledge`, `dismissAll`, `toggleAccordion`, `toggleExpanded` —
never by reaching into `sessions` directly.

## 9. Explicit dependency injection in SwiftUI

Views take `@ObservedObject var store: SessionStore` passed down explicitly
through the view hierarchy, never `@EnvironmentObject`.

## 10. Shared geometry constants, centralized once

`NotchLayout` exists specifically so AppKit panel sizing (`App.swift`) and
SwiftUI content (`NotchContentView.swift`) can't drift apart — its own doc
comment says so. That principle isn't yet extended to `NotchContentView`'s
own styling constants; see the [design-tokens
enhancement](https://github.com/luanhssa/owl-notch/issues?q=is%3Aissue+label%3Aenhancement)
for closing that gap.

## 11. UI text in PT-BR, code in English

`SessionState.label` and other user-facing strings ("rodando", "sua vez no
terminal", "aguardando decisão") are in Portuguese; every identifier,
comment, and commit message is in English. Keep that split — don't
translate identifiers, don't leave user-facing strings in English.

## 12. `[weak self]` by habit, not because of a real cycle

Escaping closures capture `[weak self]` defensively even where the owning
object is expected to live for the whole process — `IPCServer`'s
accept-loop thread, `SessionStore`'s prune `Timer`. This is a conservative
style choice, not a signal that a retain cycle was ever found; keep doing it
in new escaping closures rather than reasoning case-by-case about whether
it's "really" needed.

## 13. Shared cross-target data lives in `OwlShared`, not in a hardcoded copy per target

`ProcessAncestry` (in the `owl-hook` target) and `SessionFocusService` (in
the `OwlApp` target) both need the same terminal-app table — which app's
process name maps to which bundle identifier. It used to be two
independently hardcoded, hand-synced lists that had already drifted (GH
issue #13); it's now `TerminalAppRegistry` in the `OwlShared` target, which
both targets depend on and import. If another piece of data ever needs to
be known by more than one target, add it to `OwlShared` rather than copying
it — that's the whole reason the target exists.

## 14. Testability seam: inject real-world paths via a defaulted init parameter

`SessionStore` reads/writes a real file
(`~/Library/Application Support/Owl/sessions.json`) from its `init()`. Tests
can't safely call `SessionStore()` as-is — it would touch the developer's
actual Owl data (this bit us once: see `Tests/OwlAppTests/SessionStoreTests.swift`'s
history and the `feedback_owl_hook_live_socket` note about invoking
`owl-hook` against a real running Owl.app during manual verification).
The fix is `init(persistenceURL: URL = OwlPaths.applicationSupportDirectory...)`
— production code gets the exact same default it always had, and tests pass
a throwaway temp file instead. Follow the same pattern for any future state
that touches a real, shared, or user-specific path: default parameter for
production, explicit override for tests — not a global/static path baked
into the type.

## 15. Tests use fixtures, not mocks, for filesystem-backed services

`GitInfoServiceTests` and `SessionTitleServiceTests` don't mock
`FileManager` — they write real temporary files/directories (a fresh,
UUID-named path per test, cleaned up in `tearDown`) and call the real
service against them. Both services cache by path (see #2, #3), so reusing
a fixed path across tests would leak a cached result from one test into
another; a unique path per test sidesteps that entirely rather than
resetting internal cache state from outside. `ProcessAncestry` is the
exception — its live `sysctl`-based walk genuinely can't be exercised this
way, so its name-matching logic was extracted into a pure, plain-array-in
function (`classify(ancestorProcessNames:)`) instead.

## 16. Deferred lookups hop off `@MainActor`, then back only to assign — never `await` inline mid-mutation

`SessionStore.handle(envelope:)` builds and commits a `SessionInfo` update
synchronously, in one uninterrupted pass — it never contains an `await`.
That's deliberate: `handle(envelope:)` runs on `@MainActor`, and an actor
method is *reentrant* across its own suspension points, so a plain
`await GitInfoService.branch(...)` sitting inline, midway through building
`info`, would let another `handle(envelope:)` call for the very same
session run to completion during that suspension — and then this call's
eventual `sessions[sessionID] = info` would silently overwrite that newer
state with the stale copy it captured before the `await` (GH issue #24).

The fix — see `kickOffGitBranchLookupIfNeeded`/`kickOffTitleLookupIfNeeded`
— is to keep the triggering method fully synchronous, and instead spawn a
detached `Task` for the actual filesystem work, hopping back to
`@MainActor` only in its completion handler, where it re-reads
`sessions[sessionID]` fresh (not the `info` from the original call) before
writing the resolved field. A `Set<String>` of in-flight session IDs per
lookup kind guards against a burst of hook events for one session (e.g.
several `PreToolUse` calls in a row) each kicking off a redundant lookup
before the first resolves. Follow this shape for any future lookup that
needs to move off the main actor: never `await` inside a method that also
mutates shared actor state before and after the suspension point.

## 17. Subprocesses that emit structured output need an explicit UTF-8 locale — don't trust the inherited one

`TmuxTargetResolver` shells out to `tmux` and parses tab-delimited `-F`
output. Verified live (GH issue #41, phase 2): without a UTF-8 locale in
its environment, `tmux` silently substitutes `_` for non-printable bytes
in that output — including the literal tab used as the field separator —
corrupting every parse with no error, no crash, just wrong data. A
login-item-launched `.app` gets exactly this bare environment from
`launchd` (no `LANG`/`LC_ALL` set), unlike a shell-launched process, which
is why this wasn't caught by the pure-parsing unit tests (they never touch
a real subprocess) and would only have shown up as a silent, hard-to-
diagnose failure in production. The fix: explicitly set `LC_ALL`/`LANG` on
`Process.environment` before invoking any subprocess whose output gets
parsed by field/delimiter, rather than depending on whatever locale Owl
happens to inherit. If a future subprocess integration skips this, it's
worth a live test against the real binary before shipping — a fixture-only
test can't catch a bug that only exists in how the *real* tool behaves
under the *real* environment Owl actually runs with.

## 18. A field carrying real conversation content needs its own privacy decision, and its own `CodingKeys` exclusion

`SessionInfo.lastMessageContent` (GH issue #45) is the one field on a
session that can hold genuinely sensitive content — the actual text of a
message, not just a tool name or file path. Two things follow from that,
both worth repeating for any future field in the same category:

1. Whether to surface it at all needs an explicit, separate decision from
   "should we implement this issue" — see the issue's own note asking for
   one, and #48's decision on in-panel approve/deny as the precedent for
   treating "does this change what Owl exposes" as its own question.
2. It's excluded from `SessionInfo`'s `CodingKeys` on purpose, so it's
   simply never written to `sessions.json` — every other field syncs to
   disk for the next relaunch; this one is refetched live instead,
   specifically so it doesn't sit in plaintext on disk between sessions.
   A field excluded like this needs a *default value* (nil, for an
   Optional) so `Decodable` synthesis still works — same rule that lets
   `terminalTTY`/`tmuxPane`/`snoozedUntil` be omitted from older
   persisted JSON without a migration.
