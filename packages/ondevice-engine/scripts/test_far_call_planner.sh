#!/usr/bin/env bash
# Executes the exact compiler layout planner; no iOS/simulator execution.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
mkdir -p "$ROOT/build" "$ROOT/evidence"
OUT=$(mktemp -d "$ROOT/build/far-call-planner-XXXXXX")
trap 'rm -rf "$OUT"' EXIT
javac -d "$OUT" "$ROOT/native/gluon/compiler-patches/src/com/oracle/svm/hosted/image/FarCallPlanner.java" \
  "$ROOT/native/gluon/compiler-patches/tests/FarCallPlannerTest.java"
java -cp "$OUT" FarCallPlannerTest | tee "$ROOT/evidence/far-call-planner.log"
