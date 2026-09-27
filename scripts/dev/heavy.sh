#!/bin/zsh
# Machine-wide lock for heavy MagicMobile work on the 8 GB Mac: Gradle, xcodebuild,
# swift build/test, the real-engine JVM tests, image batches and simulator UI runs.
# One holder at a time across every checkout and worktree (docs/WORKFLOW_EFFICIENCY.md).
#
#   zsh scripts/dev/heavy.sh "<label>" -- <command> [args...]
#   zsh scripts/dev/heavy.sh --stop-gradle "<label>" -- <command> [args...]
#   zsh scripts/dev/heavy.sh --status
#
# Waits for the lock, runs the command and exits with its status. The lock is a
# kernel file lock (zsh/system flock) on a fixed path, so it is released when the
# holder exits or is killed: there is no stale lock to clean up. --stop-gradle runs
# `gradlew --stop` after the command, still under the lock, to free the daemons'
# memory. MAGICMOBILE_HEAVY_LOCK overrides the lock path, for testing this script.
zmodload zsh/system || { print -u2 'heavy.sh: zsh/system is unavailable'; exit 2; }
LOCK=${MAGICMOBILE_HEAVY_LOCK:-/tmp/magicmobile-heavy.lock}
HOLDER=$LOCK.holder
REPO=${0:A:h:h:h}

usage() {
  print -u2 'usage: heavy.sh [--stop-gradle] "<label>" -- <command> [args...] | heavy.sh --status'
  exit 2
}
for p in $LOCK $HOLDER; do
  [[ -L $p ]] && { print -u2 "heavy.sh: refusing symlinked $p"; exit 2; }
done
[[ -e $LOCK ]] || : >> $LOCK || exit 2
holder() { [[ -s $HOLDER ]] && print -r -- "$(<$HOLDER)" || print 'unknown holder'; }

if [[ $1 == --status ]]; then
  # A subshell is its own process, so this probe cannot keep the lock.
  if ( zsystem flock -t 0 $LOCK ) 2>/dev/null; then print free; else print -r -- "held by: $(holder)"; fi
  exit 0
fi
stop_gradle=0
[[ $1 == --stop-gradle ]] && { stop_gradle=1; shift; }
label=$1
(( $# )) && shift
[[ $1 == -- ]] && shift
[[ -n $label && $# -gt 0 ]] || usage

start=$SECONDS
if ! zsystem flock -t 0 -f lockfd $LOCK 2>/dev/null; then
  print -u2 "[heavy] waiting for: $(holder)"
  until zsystem flock -t 120 -i 2 -f lockfd $LOCK 2>/dev/null; do
    print -u2 "[heavy] still waiting ($(( SECONDS - start ))s) for: $(holder)"
  done
fi
# Write the holder note to its own file: closing any descriptor of the locked file
# in this process would drop the lock.
print -r -- "$label (pid $$, since $(date '+%H:%M:%S'), in ${PWD/#$HOME/~})" > $HOLDER
trap 'exit 130' INT
trap 'exit 143' TERM
print -u2 "[heavy] acquired for: $label (waited $(( SECONDS - start ))s)"
"$@"
result=$?
if (( stop_gradle )); then
  gradlew=$REPO/apps/android/gradlew
  [[ ${1:t} == gradlew && -x $1 ]] && gradlew=$1
  if [[ -x $gradlew ]]; then
    print -u2 "[heavy] stopping Gradle daemons: $gradlew --stop"
    (cd ${gradlew:h} && ./gradlew --stop >&2) || print -u2 '[heavy] gradlew --stop failed; daemons may still be running'
  fi
fi
: > $HOLDER
exit $result
