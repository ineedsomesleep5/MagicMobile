#!/usr/bin/env bash
# Isolated test-only process. Never stage these objects into the product or build/native.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
REPO=$(cd "$ROOT/../.." && pwd)
mkdir -p "$ROOT/build" "$ROOT/evidence"
OUT=$(mktemp -d "$ROOT/build/runtime-manager-fixture-XXXXXX")
SRC="$ROOT/swift/Sources"
FIXTURE="$ROOT/tests/runtime-manager"
mkdir -p "$OUT/CMagicEngine" "$ROOT/evidence"
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
swiftc -swift-version 5 -parse-as-library -D XMAGE_NATIVE_LINKED \
  -I"$OUT" -I"$OUT/CMagicEngine" -Xcc -I -Xcc "$SRC/CMagicEngine/include" \
  -import-objc-header "$FIXTURE/fixture.h" \
  "$REPO/apps/ios/MagicMobile/OnDeviceRuntimeManager.swift" \
  "$REPO/apps/ios/MagicMobile/OnDeviceBackendRegistration.swift" \
  "$FIXTURE/RuntimeManagerChecks.swift" "$OUT/protocol.o" "$OUT/runtime.o" "$OUT/fixture.o" \
  -o "$OUT/runtime-manager-checks"
"$OUT/runtime-manager-checks" | tee "$ROOT/evidence/runtime-manager-tests.txt"
