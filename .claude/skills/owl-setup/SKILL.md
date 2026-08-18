---
name: owl-setup
description: Build and install Owl (the notch companion app) and owl-hook, as an alternative to running Scripts/install.sh by hand from a terminal (GH issue #47).
disable-model-invocation: true
allowed-tools: Bash(${CLAUDE_PROJECT_DIR}/Scripts/install.sh)
---

Run Owl's install script and report the result:

```
bash ${CLAUDE_PROJECT_DIR}/Scripts/install.sh
```

This builds a release binary, installs `owl-hook` to
`~/.claude/owl/owl-hook`, and installs `Owl.app` to
`/Applications/Owl.app`, replacing any existing copy there.

If it succeeds, tell the user to launch Owl with
`open /Applications/Owl.app` — it has no Dock icon or menu bar item
(it's an accessory app), so the notch panel appearing is the only
visible sign it's running. The first launch offers to wire Owl's hooks
into `~/.claude/settings.json` automatically; if that's declined, point
to the README's "Wiring up the hooks" section instead.

If it fails, show the actual error output above rather than guessing at
a fix.
