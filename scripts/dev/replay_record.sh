#!/usr/bin/env bash
# Replays an engine game record on the JVM engine (docs/cloud/game-record.md): a record shared from the
# app's engine report screen, or one kept by the ranked server (ranked_ai_records.record).
#
#   scripts/dev/replay_record.sh record.json [--trace steps.txt] [--any-build]
#
# Prints GameReplay's result JSON and exits 0 only when the replay matches the recorded game. --trace writes
# the game state before every decision, which is the step-by-step view for debugging. --any-build replays a
# record made by another engine build (it may then diverge). Needs JDK 17+ and Maven for the first JVM build.
# The record holds every hand and library order: keep it off shared places.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
ENGINE="$ROOT/packages/ondevice-engine"
[[ $# -ge 1 && -f "$1" ]] || { sed -n '2,10p' "$0" | sed 's/^# \{0,1\}//'; exit 2; }
RECORD=$(cd "$(dirname "$1")" && pwd)/$(basename "$1"); shift
TRACE=""; ARGS=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --trace) TRACE=$(cd "$(dirname "$2")" && pwd)/$(basename "$2"); shift 2 ;;
    --any-build) ARGS+=(--any-build); shift ;;
    *) echo "Unknown option $1" >&2; exit 2 ;;
  esac
done
if ! java -version >/dev/null 2>&1 && [[ -d /opt/homebrew/opt/openjdk@17 ]]; then
  export JAVA_HOME=/opt/homebrew/opt/openjdk@17 PATH="/opt/homebrew/opt/openjdk@17/bin:$PATH"
fi
[[ -s "$ENGINE/build/runtime-classpath.txt" ]] || (cd "$ENGINE" && bash scripts/build_jvm.sh)
CP=$(<"$ENGINE/build/runtime-classpath.txt")
# The engine writes its card database next to where it runs: keep that out of the checkout.
WORK=$(mktemp -d "$ENGINE/build/replay-XXXXXX")
trap 'rm -rf "$WORK"' EXIT
cd "$WORK"
java -Xmx768m -Djava.awt.headless=true ${TRACE:+"-Dmagicmobile.recordTrace=$TRACE"} -cp "$CP" \
  io.magicmobile.xmage.GameReplay "$RECORD" ${ARGS[@]+"${ARGS[@]}"}
