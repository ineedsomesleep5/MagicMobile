#!/bin/zsh
# Fills for the Walnut Tavern UI kit, written next to the brass parts (tavern_ui_kit.py):
#   tavern-ui-leather    dark red-brown leather, seamless tile (Poly Haven leather_red_02, CC0)
#   tavern-ui-parchment  aged parchment, seamless tile, made here from blurred noise
#   tavern-ui-ember      glowing ember glass, cut from the pass button's painted face
#   zsh scripts/brand/tavern_ui_textures.sh build_output/tavern/ui
set -eu
OUT=${1:?usage: tavern_ui_textures.sh <out dir>}
ART=$HOME/Movies/motion-assets/magicmobile-brand
mkdir -p $OUT
# The whole Poly Haven tile is seamless, so scaling all of it keeps it seamless.
magick $ART/textures/leather_red_02_diff.jpg -resize 512x512 -modulate 78,95,100 \
  -fill '#2a1007' -colorize 12% $OUT/tavern-ui-leather.png
# Noise blurred with wrap-around edges tiles seamlessly; three scales give mottling and fibres.
noise() { magick -size 512x512 xc: -seed $1 +noise Random -virtual-pixel tile -blur 0x$2 -auto-level -colorspace gray "$3"; }
T=$(mktemp -d)
noise 7 40 $T/a.png
noise 11 12 $T/b.png
noise 13 2 $T/c.png
magick $T/a.png $T/b.png -compose Multiply -composite $T/c.png -compose Overlay -composite \
  -level 0%,90% +level-colors '#d2b07c,#f7ebd0' $OUT/tavern-ui-parchment.png
rm -rf $T
# A patch of the pass button's glass between its glowing rim and the hourglass; buttons
# stretch it rather than tile it.
magick $ART/pass-face-front.png -crop 180x180+110+420 +repage -resize 256x256 $OUT/tavern-ui-ember.png
print "wrote tavern-ui-leather.png tavern-ui-parchment.png tavern-ui-ember.png"
