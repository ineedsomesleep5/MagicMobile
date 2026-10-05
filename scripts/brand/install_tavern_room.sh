#!/bin/zsh
# Install the rendered tavern room (scripts/brand/tavern_room.py) into the iOS asset catalogue and
# Resources/tavern-room.json. Android picks the layers up from there too: prepareBrandAssets in
# apps/android/app/build.gradle.kts copies tavern-*.imageset art, and scripts/android/prepare_assets.py
# copies tavern-room.json.
#
#   zsh scripts/brand/install_tavern_room.sh [build_output/tavern/room]
set -euo pipefail
REPO=${0:A:h:h:h}
SRC=${1:-$REPO/build_output/tavern/room}
CATALOG=$REPO/apps/ios/MagicMobile/Assets.xcassets
command -v pngquant >/dev/null || { print -u2 'pngquant is required (brew install pngquant)'; exit 1; }
command -v magick >/dev/null || { print -u2 'ImageMagick is required (brew install imagemagick)'; exit 1; }

imageset() {  # name, file name
  cat > $CATALOG/$1.imageset/Contents.json <<JSON
{
  "images" : [
    { "filename" : "$2", "idiom" : "universal", "scale" : "3x" }
  ],
  "info" : { "author" : "xcode", "version" : 1 }
}
JSON
}

for orientation in portrait landscape; do
  name=tavern-room-$orientation-back
  mkdir -p $CATALOG/$name.imageset
  # The room behind everything: a JPEG, softened a touch so it never competes with the menu.
  magick $SRC/$name.jpg -strip -interlace none -quality 84 $CATALOG/$name.imageset/$name.jpg
  imageset $name $name.jpg
  for layer in mid front; do
    name=tavern-room-$orientation-$layer
    mkdir -p $CATALOG/$name.imageset
    pngquant --quality 65-90 --speed 1 --strip --force --output $CATALOG/$name.imageset/$name.png -- $SRC/$name.png \
      || cp $SRC/$name.png $CATALOG/$name.imageset/$name.png
    imageset $name $name.png
  done
done

python3 - "$SRC" "$REPO/apps/ios/MagicMobile/Resources/tavern-room.json" <<'PY'
import json, struct, sys
src, target = sys.argv[1], sys.argv[2]
def size(path):  # PNG header: width and height
    with open(path, 'rb') as f:
        head = f.read(24)
    return struct.unpack('>II', head[16:24])
out = {}
for orientation in ('portrait', 'landscape'):
    width, height = size(f'{src}/tavern-room-{orientation}-mid.png')
    lights = json.load(open(f'{src}/tavern-room-{orientation}-lights.json'))['lights']
    out[orientation] = {'width': width, 'height': height, 'lights': lights}
json.dump(out, open(target, 'w'), indent=1)
open(target, 'a').write('\n')
print('wrote', target)
PY
du -ch $CATALOG/tavern-room-*.imageset/*.{jpg,png} | tail -1
