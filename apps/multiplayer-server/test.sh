#!/usr/bin/env bash
set -euo pipefail
SERVER_ROOT=$(cd "$(dirname "$0")" && pwd)
bash "$SERVER_ROOT/build.sh"
JAVAC=${JAVA_HOME:+$JAVA_HOME/bin/}javac
JAVA=${JAVA_HOME:+$JAVA_HOME/bin/}java
find "$SERVER_ROOT/src/test/java" -name '*.java' -print > "$SERVER_ROOT/build/tests.txt"
"$JAVAC" --release 17 -cp "$SERVER_ROOT/build/classes" -d "$SERVER_ROOT/build/classes" @"$SERVER_ROOT/build/tests.txt"
"$JAVA" -cp "$SERVER_ROOT/build/classes" io.magicmobile.server.ServerTests
"$JAVA" -cp "$SERVER_ROOT/build/classes" io.magicmobile.server.FailureRegressions
"$JAVA" -cp "$SERVER_ROOT/build/classes" io.magicmobile.server.AdmissionRegressions
"$JAVA" -cp "$SERVER_ROOT/build/classes" io.magicmobile.server.BackendResponseRegressions
"$JAVA" -cp "$SERVER_ROOT/build/classes" io.magicmobile.server.ConfigurationTests
