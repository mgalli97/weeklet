#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="${WEEKLET_SCREENSHOT_APP:-$ROOT/build/Weeklet.app/Contents/MacOS/Weeklet}"
if [[ ! -x "$APP" ]]; then "$ROOT/scripts/build.sh"; fi
mkdir -p "$ROOT/docs/images"
"$APP" --snapshot-menu "$ROOT/docs/images/menu-bar.png"
"$APP" --snapshot "$ROOT/docs/images/popover.png"
"$APP" --snapshot "$ROOT/docs/images/session-expired.png" --sample-errors
"$APP" --snapshot "$ROOT/docs/images/help.png" --sample-help --sample-errors
"$APP" --snapshot "$ROOT/docs/images/no-providers.png" --sample-empty
cp "$ROOT/build/AppIcon.iconset/icon_128x128@2x.png" "$ROOT/docs/images/icon.png"
printf 'Saved native interface previews with sample data.\n'
