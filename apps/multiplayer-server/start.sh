#!/usr/bin/env bash
set -euo pipefail
RUNTIME_ROOT=$(cd "$(dirname "$0")" && pwd)
cd "$RUNTIME_ROOT"
if [[ "${RUN_STARTUP_SMOKE:-0}" == 1 ]]; then
  [[ -f diagnostics/classes/io/magicmobile/server/RealEngineSmoke.class ]] || { echo 'Startup smoke classes missing.' >&2; exit 2; }
  JAVA=${JAVA_HOME:+$JAVA_HOME/bin/}java
  INITIAL=${JAVA_HEAP_INITIAL:-64m}
  MAXIMUM=${JAVA_HEAP_MAX:-256m}
  [[ "$INITIAL" =~ ^[1-9][0-9]*[mMgG]$ && "$MAXIMUM" =~ ^[1-9][0-9]*[mMgG]$ ]] || exit 2
  RUNTIME_CP=$(<runtime-classpath.txt)
  shopt -s nullglob
  SMOKE_DECKS=(diagnostics/decks/*.json)
  [[ ${#SMOKE_DECKS[@]} == 5 ]] || { echo 'Exactly five included resolved decks required for startup acceptance.' >&2; exit 2; }
  echo 'Starting isolated real-XMage acceptance; synthetic Auth/lobby only, no Supabase writes.'
  timeout 150 "$JAVA" "-Xms$INITIAL" "-Xmx$MAXIMUM" -XX:ActiveProcessorCount=1 -Djava.awt.headless=true \
    -cp "diagnostics/classes:$RUNTIME_CP" io.magicmobile.server.RealEngineSmoke "${SMOKE_DECKS[@]}"
  echo 'Startup real-XMage smoke passed; device multiplayer and extended host-memory acceptance remain separate.'
fi
# Production never includes diagnostic classes in its classpath.
exec bash "$RUNTIME_ROOT/run.sh"
