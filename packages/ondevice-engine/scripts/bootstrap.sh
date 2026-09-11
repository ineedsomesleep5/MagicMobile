#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
SHA=$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["commit"])' "$ROOT/upstream.lock.json")
DEST="$ROOT/.upstream/mage"
command -v git >/dev/null || { echo "Install git" >&2;exit 1; }
if [[ ! -d "$DEST/.git" ]]; then
 mkdir -p "$DEST"; git -C "$DEST" init
 git -C "$DEST" remote add origin https://github.com/magefree/mage.git
fi
if ! git -C "$DEST" rev-parse --verify HEAD >/dev/null 2>&1; then
 git -C "$DEST" fetch --depth 1 origin "$SHA"
 git -C "$DEST" checkout --detach FETCH_HEAD
fi
[[ "$(git -C "$DEST" rev-parse HEAD)" == "$SHA" ]] || { echo "Unexpected checkout; do not overwrite your work. Review upstream.lock.json." >&2;exit 1; }
python3 "$ROOT/scripts/prepare_upstream.py" "$DEST"
echo "Pinned source ready at $DEST"
