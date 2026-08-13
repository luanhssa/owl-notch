#!/bin/bash
# Packages the built OwlApp executable into a proper Owl.app bundle.
# A real .app bundle (with Info.plist + CFBundleIdentifier) is what
# SMAppService needs to register Owl as a login item — a bare SwiftPM
# executable run via `.build/debug/OwlApp` can't do that.
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIG="${1:-debug}"
swift build -c "$CONFIG"

APP_DIR="Owl.app"
BIN_SRC=".build/$CONFIG/OwlApp"
BIN_DST="$APP_DIR/Contents/MacOS/Owl"

rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS"
cp "$BIN_SRC" "$BIN_DST"
cp "Resources/Info.plist" "$APP_DIR/Contents/Info.plist"

# Ad-hoc sign so Gatekeeper/SMAppService are happy running it locally.
codesign --force --deep --sign - "$APP_DIR" >/dev/null 2>&1 || true

echo "Built $APP_DIR"
