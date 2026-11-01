#!/bin/zsh
# Copy a world's plates (scripts/brand/arena_world.py) into the iOS asset catalog as arena-world-<slug>-<variant>.
#   zsh scripts/brand/install_arena_world.sh radio-night <render dir holding landscape.png and portrait.png>
set -euo pipefail
SLUG=${1:?world slug}
SRC=${2:?render dir}
CAT=${0:A:h:h:h}/apps/ios/MagicMobile/Assets.xcassets
for variant in landscape portrait; do
  name=arena-world-$SLUG-$variant
  mkdir -p $CAT/$name.imageset
  print -r -- "{
  \"images\": [{ \"filename\": \"$name.jpg\", \"idiom\": \"universal\" }],
  \"info\": { \"author\": \"xcode\", \"version\": 1 }
}" > $CAT/$name.imageset/Contents.json
  sips -s format jpeg -s formatOptions 86 $SRC/$variant.png --out $CAT/$name.imageset/$name.jpg >/dev/null
  print "plate: $name ($(stat -f %z $CAT/$name.imageset/$name.jpg) bytes)"
done
