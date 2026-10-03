#!/bin/zsh
# Walnut Tavern battlefield frames (option B, approved by Caleb 2026-10-02) from the Codex
# art in ~/Movies/motion-assets/magicmobile-brand/ui-ref: frame-b-<kind>.png (one frame on a
# flat key colour with a black arched window) and frames-b-parts.png (ribbon and gems on
# green). Keys out the background and the window, takes a band out of the plain side rails
# and fits each frame to the 1 : 1.08 battlefield tile, then prints each art window's box
# as fractions of the tile for TavernFrameKind.window.
#   zsh scripts/brand/card_frames.sh build_output/tavern/frames
set -eu
OUT=${1:?usage: card_frames.sh <out dir>}
REF=${CARD_FRAME_ART:-$HOME/Movies/motion-assets/magicmobile-brand/ui-ref}
mkdir -p $OUT
W=330; H=356   # 3 px per pt for the largest (92 pt) tile, with headroom

# Alpha from a key colour's dominance, with its spill taken back out of the edges.
key_magenta=(-channel A -fx "1 - min(1, max(0, (min(r,b) - g - 0.10) / 0.25))" +channel
  -channel RB -fx "u - max(0, min(u.r, u.b) - u.g)" +channel)
key_green=(-channel A -fx "1 - min(1, max(0, (g - max(r,b) - 0.12) / 0.28))" +channel
  -channel G -fx "min(g, max(r,b) + 0.03)" +channel)

frame() {  # kind key band-start(fraction of height)
  local kind=$1 src=$REF/frame-b-$1.png tmp=$OUT/.$1.png
  [[ -f $src ]] || { print "missing $src"; return }
  local -a keyed; keyed=("${(@P)${:-key_$2}}")
  # Some art arrives already cut out, with a faint drop shadow: drop the shadow instead.
  [[ $(magick identify -format '%[opaque]' $src) == False ]] && keyed=(-channel A -level 45%,100% +channel)
  magick $src -alpha set $keyed -trim +repage $tmp
  local w=$(magick identify -format %w $tmp) h=$(magick identify -format %h $tmp)
  # The window: everything inside the frame, flooded from its centre (an arch: the centre
  # sits below the middle). The frame's own pixels are opaque and not black; closing that
  # mask first keeps the flood out of the frame's dark crevices.
  magick $tmp -alpha extract -threshold 50% $OUT/.alpha.png
  magick $tmp -alpha off -colorspace Gray -threshold 10% $OUT/.light.png
  magick $OUT/.alpha.png $OUT/.light.png -compose Multiply -composite -morphology Close Disk:3 \
    -fill red -draw "color $((w / 2)),$((h * 6 / 10)) floodfill" -fill black +opaque red -fill white -opaque red \
    -morphology Dilate Disk:1 $OUT/.window.png
  magick $tmp \( -clone 0 -alpha extract \( $OUT/.window.png -negate \) -compose Multiply -composite \) \
    -compose CopyOpacity -composite $tmp
  rm -f $OUT/.alpha.png $OUT/.light.png $OUT/.window.png
  # A band of plain rail comes out (at most 15% of the height); a slight squash does the rest.
  local cut=$(( h - w * 108 / 100 )); (( cut > h * 15 / 100 )) && cut=$(( h * 15 / 100 ))
  local y0=$(( h * $3 / 100 ))
  if (( cut > 0 )); then
    magick $tmp \( -clone 0 -crop ${w}x${y0}+0+0 +repage \) \( -clone 0 -crop ${w}x$((h - y0 - cut))+0+$((y0 + cut)) +repage \) \
      -delete 0 -append +repage $tmp
  fi
  magick $tmp -resize ${W}x${H}\! $OUT/tavern-frame-$kind.png
  # The window's box: transparent pixels connected to its centre.
  local box=$(magick $OUT/tavern-frame-$kind.png -alpha extract -threshold 50% -fill red \
    -draw "color $((W / 2)),$((H * 6 / 10)) floodfill" -fill black +opaque red -fill white -opaque red -format %@ info:)
  local bw=${box%%x*} rest=${box#*x}; local bh=${rest%%+*}; rest=${rest#*+}; local bx=${rest%%+*} by=${rest#*+}
  printf '%-12s window x %.3f y %.3f w %.3f h %.3f\n' $kind $((bx * 1.0 / W)) $((by * 1.0 / H)) $((bw * 1.0 / W)) $((bh * 1.0 / H))
  rm -f $tmp
}

frame creature magenta ${CREATURE_BAND:-47}
frame artifact magenta ${ARTIFACT_BAND:-50}
frame token magenta ${TOKEN_BAND:-47}
frame enchantment green ${ENCHANTMENT_BAND:-45}
frame land magenta ${LAND_BAND:-47}
frame spell magenta ${SPELL_BAND:-47}

# The shared ribbon and stat gems (green key).
PARTS=$REF/frames-b-parts.png
if [[ -f $PARTS ]]; then
  part() { magick $PARTS -crop $2 +repage -alpha set $key_green -trim +repage -resize $3 $OUT/$1.png; print "part: $1"; }
  part tavern-card-ribbon 880x200+30+185 600x
  part tavern-gem-power 300x330+56+480 120x
  part tavern-gem-toughness 300x330+430+480 120x
fi
