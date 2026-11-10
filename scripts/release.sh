#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
MODE="${1:---prepare}"
if [[ "$MODE" != --prepare && "$MODE" != --publish ]]; then
    printf 'Usage: ./scripts/release.sh [--prepare|--publish]\n' >&2
    exit 1
fi
if [[ -n "$(git status --porcelain)" ]]; then
    printf 'Commit the source and version before preparing a release.\n' >&2
    exit 1
fi
SOURCE=$(git rev-parse HEAD)
VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Resources/Info.plist)
BUILD=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' Resources/Info.plist)
ARCH=$(uname -m)
if [[ "$ARCH" != arm64 && "$ARCH" != x86_64 ]]; then exit 1; fi
./scripts/test.sh
STAGE="$ROOT/build/release"
mkdir -p "$STAGE"
WEEKLET_APP_OUTPUT="$STAGE/Weeklet.app" ./scripts/build.sh
ARCHIVE="$STAGE/Weeklet-macOS-$ARCH.zip"
rm -f "$ARCHIVE"
ditto -c -k --norsrc --keepParent "$STAGE/Weeklet.app" "$ARCHIVE"
export CLANG_MODULE_CACHE_PATH="$ROOT/.build/ModuleCache"
export SWIFT_MODULECACHE_PATH="$ROOT/.build/ModuleCache"
BIN_DIR=$(swift build --configuration release --disable-sandbox --cache-path "$ROOT/.build/cache" --config-path "$ROOT/.build/config" --security-path "$ROOT/.build/security" --show-bin-path)
"$BIN_DIR/WeekletRelease" sign "$ARCHIVE" "$VERSION" "$BUILD" "$SOURCE" "$STAGE/update.json"
cp "docs/releases/$VERSION.md" "$STAGE/notes.md"
WEEKLET_RELEASE_TOOL="$BIN_DIR/WeekletRelease" python3 scripts/verify-release.py "$STAGE" "$SOURCE"
if [[ "$MODE" == --prepare ]]; then
    printf 'Prepared signed release: %s\n' "$STAGE"
    exit 0
fi
INDEX_DIR=$(mktemp -d "$ROOT/build/release-index.XXXXXX")
trap 'rm -rf "$INDEX_DIR"' EXIT
INDEX_FILE="$INDEX_DIR/index"
GIT_INDEX_FILE="$INDEX_FILE" git read-tree HEAD
for FILE in "Weeklet-macOS-$ARCH.zip" update.json notes.md; do
    BLOB=$(git hash-object -w "$STAGE/$FILE")
    GIT_INDEX_FILE="$INDEX_FILE" git update-index --add --cacheinfo "100644,$BLOB,release/$FILE"
done
TREE=$(GIT_INDEX_FILE="$INDEX_FILE" git write-tree)
COMMIT=$(printf 'Stage signed Weeklet %s\n' "$VERSION" | git commit-tree "$TREE" -p "$SOURCE")
git push origin "$COMMIT:refs/heads/release-staging/v$VERSION"
printf 'GitHub Actions will verify and publish v%s. No signing key was uploaded.\n' "$VERSION"
