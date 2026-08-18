# Owl 🦉

A tiny macOS menu bar companion that lives in your MacBook's notch and tells
you, at a glance, when any of your [Claude Code](https://claude.com/product/claude-code)
sessions needs you — waiting for a decision, waiting for input, or done.

> Not an official Anthropic product. Owl is an independent, unofficial
> companion tool built by a Claude Code user for personal use.

## Why

Claude Code sessions run in terminal tabs that are easy to lose track of,
especially when you're juggling several projects at once. Owl watches Claude
Code's [hook events](https://docs.claude.com/en/docs/claude-code/hooks) and
surfaces a small always-on-top pill in the notch area that expands into a
list of active sessions, each showing what it's doing and whether it needs
you.

Owl is strictly an **informant, never a gatekeeper**: it only observes hook
events and displays state. It never blocks a tool call, never influences a
permission decision, and fails open — if Owl isn't running or doesn't
respond within ~250ms, Claude Code behaves exactly as if Owl didn't exist.

Click the pill to expand it, or press **⌥⌘O** from anywhere to toggle it
open/closed on demand, even if Owl isn't the frontmost app. The small
info button in the expanded header opens an About panel with a link to
Preferences — the stale-session cutoff, whether a finished session counts
as urgent, an optional system notification for when a session needs
attention while the notch itself isn't a reliable signal (locked screen,
no notch display), which display the panel is pinned to on a multi-monitor
setup, an opt-in (off by default) mode that shows the real last message
instead of just a tool name, the token budgets for the usage bars (below),
and the "open at login" toggle. The moon button next to it snoozes every
session's urgent highlight for 30 minutes of focus time; each session also
has its own snooze button, in its expanded row.

The expanded panel also carries usage bars laid out like Claude Code's own
`/usage` panel — one row per limit, with its name, when it resets and the
percentage consumed. Owl shows two: the current 5-hour window and the
calendar week. The numbers come from the transcripts under
`~/.claude/projects`; Claude Code doesn't publish your plan's allowances,
so the ceilings the bars fill against are ones you set in Preferences.

The About panel also has the app's only quit button — Owl has no Dock icon
or menu bar item, so ⌘Q has nothing to hang off.

## How it works

```
Claude Code ──(hook event on stdin)──▶ owl-hook ──(unix socket)──▶ OwlServer/OwlApp ──▶ notch UI
```

- **`owl-hook`** — a tiny, fast CLI invoked by Claude Code's hook
  configuration (`PreToolUse`, `Notification`, `Stop`, `UserPromptSubmit`,
  ...). It reads the hook's JSON payload from stdin, wraps it with a bit of
  context (which terminal app, CLI vs. Claude Desktop), and forwards it
  fire-and-forget over a local unix domain socket. It never waits for a
  response and always exits `0`, so a missing or unresponsive Owl can never
  slow down or change Claude Code's behavior.
- **`OwlApp`** — a SwiftUI menu bar app with no dock icon (`LSUIElement`)
  that owns the unix socket server, keeps in-memory state per session
  (`running` / `needs attention` / `needs approval` / `done`), and renders it
  as a notch-shaped panel that expands into a session list on click.
- **`OwlServer`** — an earlier standalone milestone of the socket server,
  kept as a minimal reference implementation; day-to-day usage runs entirely
  through `OwlApp`, which embeds its own IPC server.

## Requirements

- macOS 13 (Ventura) or later
- Swift 5.9+ / Xcode command line tools
- [Claude Code](https://claude.com/product/claude-code)

## Install

```bash
git clone git@github.com:luanhssa/owl-notch.git
cd owl-notch
./Scripts/install.sh release
```

This builds the project, packages `OwlApp` into a proper `Owl.app` bundle,
and installs:

- `owl-hook` → `~/.claude/owl/owl-hook` (a stable path independent of this
  repo's location, so moving the repo or rebuilding never breaks hooks
  already wired into `~/.claude/settings.json`)
- `Owl.app` → `/Applications/Owl.app` (a real bundled `.app` is required for
  macOS's `SMAppService` to register it as a login item)

Launch it once with:

```bash
open /Applications/Owl.app
```

Already in a Claude Code session at this repo instead of a plain terminal?
Run `/owl-setup` — it does the same install, without leaving the session
(GH issue #47).

### Wiring up the hooks

`install.sh` does **not** touch `~/.claude/settings.json` on its own — the
first time you launch `Owl.app` after `owl-hook` is at its installed path,
it offers to add the hook commands below automatically (never without
asking first, and never removing any hooks you already have). Choose "Ver
instruções no README" in that prompt, or just do it by hand, pointing at
the installed path (`~/.claude/owl/owl-hook`, not a path inside `.build/`):

```json
{
  "hooks": {
    "Notification": [
      { "hooks": [{ "type": "command", "command": "~/.claude/owl/owl-hook notification" }] }
    ],
    "Stop": [
      { "hooks": [{ "type": "command", "command": "~/.claude/owl/owl-hook stop" }] }
    ],
    "UserPromptSubmit": [
      { "hooks": [{ "type": "command", "command": "~/.claude/owl/owl-hook userpromptsubmit" }] }
    ],
    "PreToolUse": [
      { "hooks": [{ "type": "command", "command": "~/.claude/owl/owl-hook pretooluse" }] }
    ]
  }
}
```

Owl only needs `Notification` and `Stop` to know when a session needs you;
`UserPromptSubmit` and `PreToolUse` just keep the "running" state fresh.

## Development

```bash
swift build                          # debug build
./Scripts/build-app-bundle.sh debug  # produce a runnable Owl.app for local testing
open Owl.app
```

Logs and the unix socket live under
`~/Library/Application Support/Owl/` (`owl.log`, `owl.sock`).

## Contributing

Found a bug or have an idea? Open an issue — the [issue
template](.github/ISSUE_TEMPLATE/bug_or_improvement.md) walks you through
Owl's reporting format (description, repro steps, expected vs. actual,
supporting assets, environment). Existing reports:
[bugs](https://github.com/luanhssa/owl-notch/issues?q=is%3Aissue+label%3Abug) ·
[enhancements](https://github.com/luanhssa/owl-notch/issues?q=is%3Aissue+label%3Aenhancement).

The conventions the code already follows are written up in
[docs/PATTERNS.md](docs/PATTERNS.md) — worth a skim before sending a PR.

## Versioning

Owl follows [Semantic Versioning](https://semver.org/). See
[CHANGELOG.md](CHANGELOG.md) for release history.

## Uninstall

```bash
pkill -f /Applications/Owl.app/Contents/MacOS/Owl
rm -rf /Applications/Owl.app ~/.claude/owl
```

Then remove the `owl-hook` entries from `~/.claude/settings.json`.

## License

[MIT](LICENSE)
