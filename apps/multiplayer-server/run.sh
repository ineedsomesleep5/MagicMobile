#!/usr/bin/env bash
set -euo pipefail
SERVER_ROOT=$(cd "$(dirname "$0")" && pwd)
if [[ -f "$SERVER_ROOT/runtime-classpath.txt" ]]; then
  cd "$SERVER_ROOT"
  ENGINE_CP_FILE="$SERVER_ROOT/runtime-classpath.txt"
  SERVER_CP=""
else
  REPO_ROOT=$(cd "$SERVER_ROOT/../.." && pwd)
  ENGINE_CP_FILE="$REPO_ROOT/packages/ondevice-engine/build/runtime-classpath.txt"
  SERVER_CP="$SERVER_ROOT/build/classes:"
fi
[[ -s "$ENGINE_CP_FILE" ]] || { echo 'Build the real JVM engine using packages/ondevice-engine/scripts/build_jvm.sh first.' >&2; exit 1; }
ENGINE_CP=$(<"$ENGINE_CP_FILE")
JAVA=${JAVA_HOME:+$JAVA_HOME/bin/}java
JAVA_HEAP_INITIAL=${JAVA_HEAP_INITIAL:-256m}
JAVA_HEAP_MAX=${JAVA_HEAP_MAX:-3g}
JAVA_PROCESSORS=${JAVA_PROCESSORS:-1}
[[ "$JAVA_HEAP_INITIAL" =~ ^[1-9][0-9]*[mMgG]$ && "$JAVA_HEAP_MAX" =~ ^[1-9][0-9]*[mMgG]$ && "$JAVA_PROCESSORS" =~ ^[1-4]$ ]] || { echo 'Invalid JVM resource budget.' >&2; exit 2; }
exec "$JAVA" "-Xms$JAVA_HEAP_INITIAL" "-Xmx$JAVA_HEAP_MAX" "-XX:ActiveProcessorCount=$JAVA_PROCESSORS" -Djava.awt.headless=true -Dsun.net.httpserver.maxReqTime=15 -Dsun.net.httpserver.maxRspTime=20 -Dsun.net.httpserver.maxConnections=64 -cp "$SERVER_CP$ENGINE_CP" io.magicmobile.server.Main
