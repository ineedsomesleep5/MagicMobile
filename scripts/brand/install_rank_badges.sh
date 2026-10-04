#!/bin/zsh
# Install the rendered rank badges (scripts/brand/rank_badges.py) into the iOS asset catalogue,
# compressed with pngquant. Android picks them up from there as tavern_rank_* drawables
# (prepareBrandAssets in apps/android/app/build.gradle.kts copies tavern-*.imageset PNGs).
#
#   zsh scripts/brand/install_rank_badges.sh [build_output/tavern/rank]
set -euo pipefail
REPO=${0:A:h:h:h}
SRC=${1:-$REPO/build_output/tavern/rank}
CATALOG=$REPO/apps/ios/MagicMobile/Assets.xcassets
command -v pngquant >/dev/null || { print -u2 'pngquant is required (brew install pngquant)'; exit 1; }
count=0
for png in $SRC/tavern-rank-*.png(N); do
  name=${png:t:r}
  set=$CATALOG/$name.imageset
  mkdir -p $set
  pngquant --quality 70-92 --speed 1 --strip --force --output $set/$name.png -- $png || cp $png $set/$name.png
  # Stills are 600 px and spin frames 300 px, both drawn at explicit sizes: one @3x image each.
  cat > $set/Contents.json <<JSON
{
  "images" : [
    { "filename" : "$name.png", "idiom" : "universal", "scale" : "3x" }
  ],
  "info" : { "author" : "xcode", "version" : 1 }
}
JSON
  count=$((count + 1))
done
print "installed $count rank badge images into ${CATALOG:t}"
