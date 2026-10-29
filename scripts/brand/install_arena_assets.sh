#!/bin/zsh
# Copy the Arena board's table renders (scripts/brand/tavern_table.py with scripts/brand/arena_layout.json)
# into the iOS asset catalog. Their `tavern-` names also reach Android's drawables (prepareBrandAssets).
#   zsh scripts/brand/install_arena_assets.sh <render dir holding landscape/ and portrait/>
set -euo pipefail
SRC=${1:?render dir}
ROOT=${0:A:h:h:h}
CAT=$ROOT/apps/ios/MagicMobile/Assets.xcassets
imageset() {  # name file -> path of the file inside a fresh image set
  local dir=$CAT/$1.imageset
  mkdir -p $dir
  print -r -- "{
  \"images\": [{ \"filename\": \"$2\", \"idiom\": \"universal\" }],
  \"info\": { \"author\": \"xcode\", \"version\": 1 }
}" > $dir/Contents.json
  print -r -- $dir/$2
}
for variant in landscape portrait; do
  sips -s format jpeg -s formatOptions 85 $SRC/$variant/tavern-$variant.png \
    --out "$(imageset tavern-arena-$variant tavern-arena-$variant.jpg)" >/dev/null
  print "plate: tavern-arena-$variant"
done
