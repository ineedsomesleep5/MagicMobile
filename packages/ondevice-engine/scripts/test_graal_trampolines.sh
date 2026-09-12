#!/usr/bin/env bash
# Range-planner regression only, never reported as native engine execution.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
work=$(mktemp -d "${TMPDIR:-/tmp}/magicmobile-layout-XXXXXX")
trap 'rm -rf "$work"' EXIT
javac --release 17 -d "$work" \
  "$ROOT/native/gluon/compiler-patch/MagicMobileTrampolineLayout.java" \
  "$ROOT/native/gluon/compiler-patch/TrampolineLayoutTests.java"
java -cp "$work" TrampolineLayoutTests
