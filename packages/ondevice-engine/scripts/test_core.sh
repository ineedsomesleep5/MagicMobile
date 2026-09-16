#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
mkdir -p "$ROOT/build/core" "$ROOT/evidence"
find "$ROOT/engine/core/src/main/java" "$ROOT/engine/core/src/test/java" -name '*.java' | sort > "$ROOT/build/core-sources.txt"
javac --release 17 -Xlint:all -d "$ROOT/build/core" @"$ROOT/build/core-sources.txt"
java -ea -cp "$ROOT/build/core" io.magicmobile.core.CoreTests | tee "$ROOT/evidence/core-tests.txt"
java -ea -cp "$ROOT/build/core" io.magicmobile.core.FailureBoundaryTests | tee "$ROOT/evidence/failure-boundary-tests.txt"
