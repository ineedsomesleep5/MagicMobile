#!/bin/zsh
# Install the board's card-moment sprites (scripts/brand/fx_sprites.py) as iOS image sets. Android picks them up too:
# prepareBrandAssets in apps/android/app/build.gradle.kts copies every tavern-*.imageset PNG into drawable-nodpi
# (tavern-fx-counter-plus -> R.drawable.tavern_fx_counter_plus).
#
#   blender -b --factory-startup --python-exit-code 1 -P scripts/brand/fx_sprites.py -- --out-dir build_output/fx-sprites
#   zsh scripts/brand/install_fx_sprites.sh [build_output/fx-sprites]
set -euo pipefail
REPO=${0:A:h:h:h}
SRC=${1:-$REPO/build_output/fx-sprites}
CATALOGUE=$REPO/apps/ios/MagicMobile/Assets.xcassets
for name in counter-plus counter-minus counter-loyalty counter-coin exile-ring; do
  file=tavern-fx-$name.png
  [[ -f $SRC/$file ]] || { print -u2 "missing $SRC/$file (run scripts/brand/fx_sprites.py first)"; exit 1; }
  set_dir=$CATALOGUE/tavern-fx-$name.imageset
  mkdir -p $set_dir
  cp $SRC/$file $set_dir/$file
  cat > $set_dir/Contents.json <<JSON
{
  "images" : [
    { "filename" : "$file", "idiom" : "universal", "scale" : "3x" }
  ],
  "info" : { "author" : "xcode", "version" : 1 }
}
JSON
  printf "%6.0f KB  %s\n" $(( $(stat -f%z $set_dir/$file) / 1024 )) tavern-fx-$name
done
