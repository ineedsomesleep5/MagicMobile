#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
BUILD=$(mktemp -d)
trap 'rm -rf "$BUILD"' EXIT
javac --release 17 -d "$BUILD/java" "$ROOT/packages/ondevice-engine/engine/core/src/main/java/io/magicmobile/core/Json.java" "$ROOT/packages/ondevice-engine/engine/core/src/main/java/io/magicmobile/core/BridgeException.java"
kotlinc "$ROOT"/apps/android/core/src/main/kotlin/io/magicmobile/android/core/*.kt "$ROOT"/apps/android/core/src/test/kotlin/io/magicmobile/android/core/*.kt -cp "$BUILD/java" -include-runtime -d "$BUILD/checks.jar"
java -cp "$BUILD/checks.jar:$BUILD/java" io.magicmobile.android.core.ContractChecksKt "$ROOT"
