#!/bin/bash
# Packages the built OwlApp executable into a proper Owl.app bundle.
# A real .app bundle (with Info.plist + CFBundleIdentifier) is what
# SMAppService needs to register Owl as a login item — a bare SwiftPM
# executable run via `.build/debug/OwlApp` can't do that.
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIG="${1:-debug}"
# OWL_UNIVERSAL=1 builds for both Apple Silicon and Intel — what a
# published release needs, since the CI runner is arm64 and a plain
# build would only run on Macs like it. Local installs skip it: it's
# slower and only ever runs on the machine that built it.
# (`${ARCH_FLAGS[@]+...}` because macOS bash 3.2 treats an empty array
# as unset under `set -u`.)
ARCH_FLAGS=()
if [ "${OWL_UNIVERSAL:-0}" = "1" ]; then
    ARCH_FLAGS=(--arch arm64 --arch x86_64)
fi
swift build -c "$CONFIG" ${ARCH_FLAGS[@]+"${ARCH_FLAGS[@]}"}
# Multi-arch builds land somewhere other than `.build/$CONFIG`, so ask
# SwiftPM rather than hard-coding either path.
BIN_DIR=$(swift build -c "$CONFIG" ${ARCH_FLAGS[@]+"${ARCH_FLAGS[@]}"} --show-bin-path)

APP_DIR="Owl.app"
BIN_SRC="$BIN_DIR/OwlApp"
BIN_DST="$APP_DIR/Contents/MacOS/Owl"

rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS"
cp "$BIN_SRC" "$BIN_DST"
cp "Resources/Info.plist" "$APP_DIR/Contents/Info.plist"

# Ad-hoc sign so Gatekeeper/SMAppService are happy running it locally.
codesign --force --deep --sign - "$APP_DIR" >/dev/null 2>&1 || true

echo "Built $APP_DIR"
