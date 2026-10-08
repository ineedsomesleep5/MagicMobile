#!/bin/zsh
# Install the binder's brass parts (scripts/brand/binder_parts.py, rendered from Meshy models) into the
# iOS asset catalogue as single @3x images, unchanged (they are small, so no lossy compression).
# Android picks them up from there as tavern_binder_* drawables (prepareBrandAssets in
# apps/android/app/build.gradle.kts copies tavern-*.imageset PNGs).
#
#   zsh scripts/brand/install_binder_parts.sh [build_output/tavern/binder]
set -euo pipefail
REPO=${0:A:h:h:h}
SRC=${1:-$REPO/build_output/tavern/binder}
CATALOG=$REPO/apps/ios/MagicMobile/Assets.xcassets
count=0
for png in $SRC/tavern-binder-*.png(N); do
  name=${png:t:r}
  set=$CATALOG/$name.imageset
  mkdir -p $set
  cp $png $set/$name.png
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
print "installed $count binder parts into ${CATALOG:t}"
