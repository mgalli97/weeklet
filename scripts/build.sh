#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
export CLANG_MODULE_CACHE_PATH="$ROOT/.build/ModuleCache"
export SWIFT_MODULECACHE_PATH="$ROOT/.build/ModuleCache"
OPTIONS=(--configuration release --disable-sandbox --cache-path "$ROOT/.build/cache" --config-path "$ROOT/.build/config" --security-path "$ROOT/.build/security")
swift build "${OPTIONS[@]}" "$@"
BIN_DIR="$(swift build "${OPTIONS[@]}" "$@" --show-bin-path)"
APP="$ROOT/build/Weeklet.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/Weeklet" "$APP/Contents/MacOS/Weeklet"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
swift "$ROOT/scripts/make-icon.swift" "$ROOT/build/AppIcon.iconset"
iconutil --convert icns "$ROOT/build/AppIcon.iconset" --output "$APP/Contents/Resources/AppIcon.icns"
codesign --force --options runtime --timestamp=none --sign "${SIGNING_IDENTITY:--}" "$APP"
codesign --verify --strict "$APP"
printf '\nBuilt: %s\n' "$APP"
