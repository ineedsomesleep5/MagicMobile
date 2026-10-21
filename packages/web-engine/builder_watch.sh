#!/usr/bin/env bash
# Watches a running Web Image build (CI only, docs/WEB_ENGINE_M1.md "Fitting the free runner") and records where the
# builder's memory goes, so a cut can be judged by measurement rather than by the build output's "@ GiB" peaks:
#   - every 30 s: RAM, swap and the builder JVM's resident set;
#   - at the start of stages 6, 7 and 8, then every MM_WATCH_EVERY seconds (default 240) during stage 8: a live-object
#     class histogram (jcmd GC.class_histogram, which runs a full GC first) and, when the builder runs with
#     -XX:NativeMemoryTracking=summary, the JVM's native memory summary.
#   builder_watch.sh <native-image.log> <output dir>      (runs until killed; start it in the background)
set -uo pipefail
LOG=$1 OUT=$2 EVERY=${MM_WATCH_EVERY:-240}
JCMD="${GRAALVM_HOME:+$GRAALVM_HOME/bin/}jcmd"
mkdir -p "$OUT"
start=$SECONDS last_histo=-100000 stage8=
declare -A taken=()
histo() { # <pid> <label>
  local t0=$SECONDS f="$OUT/histo-$(printf '%04d' $((SECONDS - start)))s-$2.txt"
  "$JCMD" "$1" GC.class_histogram > "$f" 2>&1
  "$JCMD" "$1" VM.native_memory summary >> "$f" 2>&1
  echo "[watch] $(date -u +%T) histogram $2 took $((SECONDS - t0)) s: $(grep -m1 '^Total' "$f")"
  last_histo=$SECONDS
}
while true; do
  sleep 30
  pid=$(pgrep -f 'com.oracle.svm.hosted.NativeImageGeneratorRunner' | head -1)
  mem=$(free -m | awk '/Mem:/{printf "used=%sMB avail=%sMB ", $3, $7} /Swap:/{printf "swap=%sMB", $3}')
  rss=; [[ -n $pid ]] && rss=$(ps -o rss= -p "$pid" 2>/dev/null | awk '{printf "%d", $1/1024}')
  echo "[watch] $(date -u +%T) +$((SECONDS - start))s $mem builder_rss=${rss:-none}MB" >> "$OUT/memory.txt"
  [[ -n $pid && -s $LOG ]] || continue
  for s in 6 7 8; do
    if [[ -z ${taken[$s]:-} ]] && grep -q "\[$s/8\]" "$LOG"; then taken[$s]=1; histo "$pid" "stage$s-start"; [[ $s == 8 ]] && stage8=1; fi
  done
  if [[ -n $stage8 ]] && (( SECONDS - last_histo >= EVERY )); then histo "$pid" stage8; fi
done
