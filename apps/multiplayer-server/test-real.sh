#!/usr/bin/env bash
set -euo pipefail
SERVER_ROOT=$(cd "$(dirname "$0")" && pwd)
REPO_ROOT=$(cd "$SERVER_ROOT/../.." && pwd)
ENGINE_CP_FILE="$REPO_ROOT/packages/ondevice-engine/build/runtime-classpath.txt"
[[ -s "$ENGINE_CP_FILE" ]] || { echo 'Current checkout real JVM engine must be built first.' >&2; exit 1; }
bash "$SERVER_ROOT/test.sh"
ENGINE_CP=$(<"$ENGINE_CP_FILE")
JAVA=${JAVA_HOME:+$JAVA_HOME/bin/}java
exec "$JAVA" -Xmx2g -Djava.awt.headless=true -cp "$SERVER_ROOT/build/classes:$ENGINE_CP" io.magicmobile.server.RealEngineSmoke
