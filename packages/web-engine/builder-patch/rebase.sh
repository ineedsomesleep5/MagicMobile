#!/usr/bin/env bash
# Moves the builder patch to another GraalVM (build_patch.sh's header): three-way merges each patched file in src/
# from the oracle/graal commit it was taken from onto the same file at <new commit>, the web-image entry of SOURCE in
# the new toolchain's $GRAALVM_HOME/release. Conflicts are left marked in src/ for review. Afterwards: check that the
# new commit's unchanged files compile to the new toolchain's shipped classes, regenerate expected.sha256 from the
# shipped classes, update BASE below, and run a CI build.
#   rebase.sh <new oracle/graal commit>          (needs gh, authenticated, for the GitHub API)
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
BASE=95ce1499c8c96ab7d5a6697c5b4bf42160f3b68b
NEW=${1:?usage: rebase.sh <new oracle/graal commit>}
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
status=0
while IFS= read -r file; do
  rel=${file#"$HERE/src/"}
  # Web Image's sources live in two projects of the graal repository.
  for project in com.oracle.svm.hosted.webimage com.oracle.svm.webimage; do
    path="web-image/src/$project/src/$rel"
    if gh api -H 'Accept: application/vnd.github.raw' "repos/oracle/graal/contents/$path?ref=$BASE" > "$tmp/base" 2>/dev/null; then
      gh api -H 'Accept: application/vnd.github.raw' "repos/oracle/graal/contents/$path?ref=$NEW" > "$tmp/new" ||
        { echo "missing at $NEW: $path" >&2; status=1; continue 2; }
      if git merge-file -L patched -L "$BASE" -L "$NEW" "$file" "$tmp/base" "$tmp/new"; then echo "merged: $rel"
      else echo "CONFLICT: $rel" >&2; status=1; fi
      continue 2
    fi
  done
  echo "not found at $BASE: $rel" >&2; status=1
done < <(find "$HERE/src" -name '*.java' | sort)
exit $status
