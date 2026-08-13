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
container. `SidebarTitleService` is the one exception, with a static cache
(`cache`/`lastScanAt`); treat that as implicitly main-actor-only, since
nothing in the file itself enforces that.

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

## 13. Anti-pattern to avoid: duplicated hardcoded lists across targets

`ProcessAncestry.terminalProcessNames` (in the `owl-hook` target) and
`SessionFocusService.bundleIdentifier(forTerminalApp:)` (in the `OwlApp`
target) are two independently hardcoded, hand-synced lists of the same
terminal apps. Don't add a third copy anywhere else — this is a known,
tracked gap (see the terminal-allowlist enhancement issue), not a pattern to
replicate.
