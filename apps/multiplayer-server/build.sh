#!/usr/bin/env bash
set -euo pipefail
SERVER_ROOT=$(cd "$(dirname "$0")" && pwd)
REPO_ROOT=$(cd "$SERVER_ROOT/../.." && pwd)
JAVAC=${JAVA_HOME:+$JAVA_HOME/bin/}javac
mkdir -p "$SERVER_ROOT/build/classes"
find "$REPO_ROOT/packages/ondevice-engine/engine/core/src/main/java" "$SERVER_ROOT/src/main/java" -name '*.java' -print > "$SERVER_ROOT/build/sources.txt"
"$JAVAC" --release 17 -Xlint:all -d "$SERVER_ROOT/build/classes" @"$SERVER_ROOT/build/sources.txt"
