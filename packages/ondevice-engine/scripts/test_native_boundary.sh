#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
OUT="$ROOT/build/native-boundary-fixture"
mkdir -p "$OUT" "$ROOT/evidence"
clang -std=c11 -Wall -Wextra -Werror -fsanitize=address,undefined -pthread \
 -I"$ROOT/swift/Sources/CMagicEngine/include" \
 "$ROOT/swift/Sources/CMagicEngine/mm_runtime.c" "$ROOT/native/runtime_tests.c" \
 -o "$OUT/runtime_tests"
"$OUT/runtime_tests" | tee "$ROOT/evidence/native-boundary-tests.txt"
SDK_FLAGS=("-I$ROOT/native/tests")
if [[ -n "${MM_GRAAL_SDK:-}" ]]; then
  [[ -s "$MM_GRAAL_SDK/lib/graal_isolate.h" ]]
  SDK_FLAGS+=(-DMM_TEST_USE_GRAAL_SDK "-I$MM_GRAAL_SDK/lib")
fi
clang -std=c11 -D_POSIX_C_SOURCE=200809L -Wall -Wextra -Werror \
 -fsanitize=address,undefined -pthread "${SDK_FLAGS[@]}" \
 -I"$ROOT/native" -I"$ROOT/swift/Sources/CMagicEngine/include" \
 "$ROOT/native/mm_graal_backend.c" "$ROOT/swift/Sources/CMagicEngine/mm_runtime.c" \
 "$ROOT/native/tests/backend_shutdown_tests.c" -o "$OUT/backend_shutdown_tests"
for scenario in busy attach shutdown teardown detach; do
  "$OUT/backend_shutdown_tests" "$scenario"
done | tee "$ROOT/evidence/native-shutdown-tests.txt"
