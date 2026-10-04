#!/bin/zsh
# Copy Walnut Tavern renders (scripts/brand/tavern_table.py) into the iOS asset catalog.
#   zsh scripts/brand/install_tavern_assets.sh build_output/tavern
# The plate ships as JPEG (quality 85, like the other backdrops); sprites keep PNG alpha.
set -eu
SRC=${1:?usage: install_tavern_assets.sh <render dir>}
ASSETS=${0:A:h:h:h}/apps/ios/MagicMobile/Assets.xcassets

imageset() {  # name file
  local dir=$ASSETS/$1.imageset
  mkdir -p $dir
  print -r -- "{
  \"images\": [{ \"filename\": \"$2\", \"idiom\": \"universal\" }],
  \"info\": { \"author\": \"xcode\", \"version\": 1 }
}" > $dir/Contents.json
  print -r -- $dir/$2
}

if [[ -f $SRC/tavern-portrait.png ]]; then
  sips -s format jpeg -s formatOptions 85 $SRC/tavern-portrait.png \
    --out "$(imageset battlefield-tavern-portrait battlefield-tavern-portrait.jpg)" >/dev/null
  print "plate: battlefield-tavern-portrait"
fi
if [[ -f $SRC/tavern-landscape.png ]]; then
  sips -s format jpeg -s formatOptions 85 $SRC/tavern-landscape.png \
    --out "$(imageset battlefield-tavern-landscape battlefield-tavern-landscape.jpg)" >/dev/null
  print "plate: battlefield-tavern-landscape"
fi
# The iPad plate (tavern_layout.json "pad"), stretched to the screen like its sockets.
if [[ -f $SRC/tavern-pad.png ]]; then
  sips -s format jpeg -s formatOptions 85 $SRC/tavern-pad.png \
    --out "$(imageset battlefield-tavern-pad battlefield-tavern-pad.jpg)" >/dev/null
  print "plate: battlefield-tavern-pad"
fi
# The pass button is painted art (Codex, from the approved porthole reference), not a
# render: trim it to its solid disc, square it and cut a clean feathered circle.
ART=${PASS_ART:-$HOME/Movies/motion-assets/magicmobile-brand/pass-button-art.png}
if [[ -f $ART ]]; then
  box=$(magick $ART -alpha extract -threshold 95% -format %@ info:)
  magick $ART -crop $box +repage -resize 768x768\! \
    \( -size 768x768 xc:none -fill white -draw "circle 384,384 384,7" -blur 0x1.5 \) \
    -compose DstIn -composite -resize 256x256 $SRC/tavern-hourglass-button.png
  print "pass button: painted art"
fi
# The flipping pass button: the still brass ring plus the disc's turn, rendered by
# scripts/brand/pass_button_flip.py into <render dir>/pass-flip.
RING=${ART:h}/pass-ring-768.png
if [[ -f $RING && -d $SRC/pass-flip ]]; then
  magick $RING -resize 300x300 "$(imageset tavern-pass-ring tavern-pass-ring.png)"
  for frame in $SRC/pass-flip/tavern-pass-flip-*.png(N); do
    name=${frame:t:r}
    cp $frame "$(imageset $name $name.png)"
  done
  print "pass button: ring and $(ls $SRC/pass-flip | wc -l | tr -d ' ') flip frames"
fi
# The UI kit (scripts/brand/tavern_ui_kit.py and tavern_ui_textures.sh, into <render dir>/ui):
# rendered at 3 px per pt, so it is registered as @3x and the app's cap insets are in points.
if [[ -d $SRC/ui ]]; then
  for part in $SRC/ui/tavern-ui-*.png(N); do
    name=${part:t:r}
    dir=$ASSETS/$name.imageset
    mkdir -p $dir
    cp $part $dir/$name.png
    print -r -- "{
  \"images\": [{ \"filename\": \"$name.png\", \"idiom\": \"universal\", \"scale\": \"3x\" }],
  \"info\": { \"author\": \"xcode\", \"version\": 1 }
}" > $dir/Contents.json
  done
  print "ui kit: $(ls $SRC/ui/tavern-ui-*.png | wc -l | tr -d ' ') parts"
fi
# The menus' backdrop (Codex, from the approved menu reference): a dim tavern wall.
BACKDROP=${ART:h}/menu-ref/menu-backdrop.png
if [[ -f $BACKDROP ]]; then
  sips -s format jpeg -s formatOptions 85 $BACKDROP --out "$(imageset menu-backdrop-tavern menu-backdrop-tavern.jpg)" >/dev/null
  print "menu backdrop: menu-backdrop-tavern"
fi
# Battlefield card frames, ribbon and stat gems (scripts/brand/card_frames.sh, into
# <render dir>/frames): one frame per card type, art showing through the arched window.
if [[ -d $SRC/frames ]]; then
  for part in $SRC/frames/tavern-*.png(N); do
    name=${part:t:r}
    cp $part "$(imageset $name $name.png)"
  done
  print "card frames: $(ls $SRC/frames/tavern-*.png | wc -l | tr -d ' ') parts"
fi
for sprite in tavern-hourglass-button tavern-mana-W tavern-mana-U tavern-mana-B tavern-mana-R tavern-mana-G tavern-mana-C tavern-mana-generic; do
  if [[ -f $SRC/$sprite.png ]]; then
    cp $SRC/$sprite.png "$(imageset $sprite $sprite.png)"
    print "sprite: $sprite"
  else
    print "sprite missing (drawn fallback stays): $sprite"
  fi
done
