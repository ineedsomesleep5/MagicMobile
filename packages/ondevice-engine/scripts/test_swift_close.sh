#!/usr/bin/env bash
# Isolated test-only backend; does not install a fixture in the normal Swift suite.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
# Gluon automatically copies build/native objects into its production output.
# Keep this macOS test build away from that reserved directory.
OUT="$ROOT/build/swift-close-fixture"
mkdir -p "$OUT" "$ROOT/evidence"
clang -std=c11 -Wall -Wextra -Werror -pthread \
  -I"$ROOT/swift/Sources/CMagicEngine/include" \
  -c "$ROOT/swift/Sources/CMagicEngine/mm_runtime.c" -o "$OUT/runtime_swift_close.o"
swiftc -swift-version 6 -parse-as-library -I"$ROOT/native/tests" \
  "$ROOT/swift/Sources/MagicMobileOnDevice/JSONValue.swift" \
  "$ROOT/swift/Sources/MagicMobileOnDevice/EngineClient.swift" \
  "$ROOT/native/tests/NativeCloseTests.swift" "$OUT/runtime_swift_close.o" \
  -o "$OUT/swift_close_tests"
"$OUT/swift_close_tests" | tee "$ROOT/evidence/swift-close-tests.txt"
