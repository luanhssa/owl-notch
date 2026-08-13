#!/bin/bash
# Installs Owl for real day-to-day use:
#   - owl-hook -> ~/.claude/owl/owl-hook (stable path, independent of the
#     build directory, so a `swift build` or a repo move doesn't break the
#     hooks already wired into ~/.claude/settings.json)
#   - Owl.app -> /Applications/Owl.app (required for SMAppService to register
#     it as a login item — it refuses to do so for an app run in place from
#     an arbitrary directory)
#
# This does NOT touch ~/.claude/settings.json — see Scripts/print-hooks-diff.sh
# for the hook entries to add/verify by hand.
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIG="${1:-release}"

echo "Building ($CONFIG)..."
swift build -c "$CONFIG"
./Scripts/build-app-bundle.sh "$CONFIG"

HOOK_DIR="$HOME/.claude/owl"
mkdir -p "$HOOK_DIR"
cp ".build/$CONFIG/owl-hook" "$HOOK_DIR/owl-hook"
echo "Installed owl-hook -> $HOOK_DIR/owl-hook"

if [ -d "/Applications/Owl.app" ]; then
    pkill -f "/Applications/Owl.app/Contents/MacOS/Owl" 2>/dev/null || true
    rm -rf "/Applications/Owl.app"
fi
cp -R "Owl.app" "/Applications/Owl.app"
echo "Installed Owl.app -> /Applications/Owl.app"

echo
echo "Done. Make sure ~/.claude/settings.json hook commands point at:"
echo "  $HOOK_DIR/owl-hook"
echo "(not a .build/debug or .build/release path)."
echo
echo "Launch it with: open /Applications/Owl.app"
