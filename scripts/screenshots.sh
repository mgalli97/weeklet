#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/build/Weeklet.app/Contents/MacOS/Weeklet"
if [[ ! -x "$APP" ]]; then "$ROOT/scripts/build.sh"; fi
mkdir -p "$ROOT/docs/images"
"$APP" --snapshot "$ROOT/docs/images/popover.png"
"$APP" --snapshot "$ROOT/docs/images/session-expired.png" --sample-errors
cp "$ROOT/build/AppIcon.iconset/icon_128x128@2x.png" "$ROOT/docs/images/icon.png"
printf 'Saved native interface previews with sample data.\n'
