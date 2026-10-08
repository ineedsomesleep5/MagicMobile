#!/bin/zsh
# Install the starting roll's dice (scripts/brand/d20.py) into the iOS resources. Android reads them from
# there too: prepareD20Assets in apps/android/app/build.gradle.kts copies Resources/D20 into the APK's assets.
#
#   blender -b -P scripts/brand/d20.py -- --mode all --out-dir build_output/d20
#   zsh scripts/brand/install_d20.sh [build_output/d20]
#
# The files (see docs/STARTING_ROLL.md): d20.glb (the die), d20.json (its faces), d20-throws.json (the recorded
# throws), d20-table-portrait.glb and d20-table-landscape.glb (the tavern table, unlit), d20-shadow.glb and
# d20-glow.glb (the soft disc under a die, and the winner's halo).
set -euo pipefail
REPO=${0:A:h:h:h}
SRC=${1:-$REPO/build_output/d20}
DEST=$REPO/apps/ios/MagicMobile/Resources/D20
files=(d20.glb d20.json d20-throws.json d20-table-portrait.glb d20-table-landscape.glb d20-shadow.glb d20-glow.glb)
mkdir -p $DEST
for f in $files; do
  [[ -f $SRC/$f ]] || { print -u2 "missing $SRC/$f (run scripts/brand/d20.py --mode all first)"; exit 1; }
  cp $SRC/$f $DEST/$f
done
ls -l $DEST | awk 'NR>1 {printf "%7.0f KB  %s\n", $5/1024, $9}'
