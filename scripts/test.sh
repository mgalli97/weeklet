#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
export CLANG_MODULE_CACHE_PATH="$ROOT/.build/ModuleCache"
export SWIFT_MODULECACHE_PATH="$ROOT/.build/ModuleCache"
TEST_FLAGS=()
FRAMEWORKS="$(xcode-select -p)/Library/Developer/Frameworks"
if [[ -d "$FRAMEWORKS/Testing.framework" ]]; then
    TEST_FLAGS=(-Xswiftc -F -Xswiftc "$FRAMEWORKS" -Xlinker -F -Xlinker "$FRAMEWORKS" -Xlinker -rpath -Xlinker "$FRAMEWORKS" -Xlinker -rpath -Xlinker "$FRAMEWORKS/../usr/lib")
fi
swift test --disable-xctest --enable-swift-testing --disable-sandbox --cache-path "$ROOT/.build/cache" --config-path "$ROOT/.build/config" --security-path "$ROOT/.build/security" "${TEST_FLAGS[@]}" "$@"
