#!/bin/zsh
# Cut the painted pass button (pass-button-art.png, Codex from Caleb's porthole reference)
# into the layers the flipping button needs:
#   pass-face-front.png  the glowing glass and hourglass, for the disc's front
#   pass-face-back.png   the same face turned over and dimmed to bronze ("waiting")
#   pass-ring-768.png    the riveted brass ring alone, which stays still in the app
# Then render the flip with scripts/brand/pass_button_flip.py.
#   zsh scripts/brand/cut_pass_layers.sh [art dir]
set -eu
D=${1:-$HOME/Movies/motion-assets/magicmobile-brand}
cd $D
# Trim to the solid disc and square it: the ring's outer edge then sits at 377 of 384 px.
box=$(magick pass-button-art.png -alpha extract -threshold 95% -format %@ info:)
magick pass-button-art.png -crop $box +repage -resize 768x768\! pass-square-768.png
# The glass (with its glowing edge line) reaches 272 px; the ring starts just outside.
magick pass-square-768.png -crop 544x544+112+112 +repage -resize 1024x1024 \
  \( -size 1024x1024 xc:none -fill white -draw "circle 512,512 512,0" \) \
  -compose DstIn -composite pass-face-front.png
magick pass-face-front.png -flip -colorspace gray -level 5%,95% +level-colors '#090503,#9a6a36' \
  -modulate 70,100,100 \( -size 1024x1024 xc:none -fill white -draw "circle 512,512 512,0" \) \
  -compose DstIn -composite -colorspace sRGB pass-face-back.png
magick pass-square-768.png \( -size 768x768 xc:none -fill white -draw "circle 384,384 384,7" \) \
  -compose DstIn -composite \
  \( -size 768x768 xc:white -fill black -draw "circle 384,384 384,110" -alpha copy -channel A -negate +channel \) \
  -compose DstOut -composite pass-ring-768.png
print "cut: pass-face-front.png pass-face-back.png pass-ring-768.png"
