#!/usr/bin/env bash
# Isolated test-only processes. Never stage these objects into the product or build/native.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
REPO=$(cd "$ROOT/../.." && pwd)
mkdir -p "$ROOT/build" "$ROOT/evidence"
OUT=$(mktemp -d "$ROOT/build/runtime-manager-fixture-XXXXXX")
SRC="$ROOT/swift/Sources"
FIXTURE="$ROOT/tests/runtime-manager"
# The display sanitizer is defined in the prompt adapter, whose other declarations
# depend on the app's broad UI model graph. Compile its production definition only.
DISPLAY_SOURCE="$REPO/apps/ios/MagicMobile/OnDevicePromptAdapter.swift"
printf 'import Foundation\n' > "$OUT/EngineDisplayText.swift"
sed -n '/^enum EngineDisplayText {/,/^}/p' "$DISPLAY_SOURCE" >> "$OUT/EngineDisplayText.swift"
grep -q '^enum EngineDisplayText {$' "$OUT/EngineDisplayText.swift"
[[ "$(tail -n 1 "$OUT/EngineDisplayText.swift")" == '}' ]]
mkdir -p "$OUT/CMagicEngine"
printf 'module CMagicEngine { header "%s" export * }\n' "$SRC/CMagicEngine/include/mm_runtime.h" > "$OUT/CMagicEngine/module.modulemap"
clang -std=c11 -Wall -Wextra -Werror -pthread -I"$SRC/CMagicEngine/include" \
  -c "$SRC/CMagicEngine/mm_runtime.c" -o "$OUT/runtime.o"
clang -std=c11 -Wall -Wextra -Werror -pthread -I"$SRC/CMagicEngine/include" \
  -c "$FIXTURE/fixture.c" -o "$OUT/fixture.o"
swiftc -swift-version 5 -parse-as-library -whole-module-optimization \
  -emit-module -emit-object -module-name MagicMobileOnDevice -I"$OUT/CMagicEngine" \
  "$SRC/MagicMobileOnDevice/JSONValue.swift" "$SRC/MagicMobileOnDevice/EngineClient.swift" \
  "$SRC/MagicMobileOnDevice/HostRouter.swift" -o "$OUT/protocol.o" \
  -emit-module-path "$OUT/MagicMobileOnDevice.swiftmodule"
: > "$ROOT/evidence/runtime-manager-tests.txt"
for CHECK in RuntimeManagerChecks RuntimeLeaseChecks; do
  swiftc -swift-version 5 -parse-as-library -D XMAGE_NATIVE_LINKED \
    -I"$OUT" -I"$OUT/CMagicEngine" -Xcc -I -Xcc "$SRC/CMagicEngine/include" \
    -import-objc-header "$FIXTURE/fixture.h" \
    "$REPO/apps/ios/MagicMobile/OnDeviceRuntimeManager.swift" \
    "$REPO/apps/ios/MagicMobile/OnDeviceBackendRegistration.swift" \
    "$REPO/apps/ios/MagicMobile/DeckStudio/Core/DeckStudioRecordedGame.swift" \
    "$REPO/apps/ios/MagicMobile/DeckStudio/Core/DeckStudioPublicTimeline.swift" \
    "$REPO/apps/ios/MagicMobile/DeckStudio/Services/DeckStudioPlaytestStore.swift" \
    "$REPO/apps/ios/MagicMobile/DeckStudio/Services/DeckStudioRecordingTransport.swift" \
    "$OUT/EngineDisplayText.swift" \
    "$FIXTURE/$CHECK.swift" "$OUT/protocol.o" "$OUT/runtime.o" "$OUT/fixture.o" \
    -o "$OUT/$CHECK"
  "$OUT/$CHECK" | tee -a "$ROOT/evidence/runtime-manager-tests.txt"
done
