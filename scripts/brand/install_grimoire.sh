#!/bin/zsh
# Encode the rendered spell book frames (scripts/brand/grimoire.py) into the four short films the
# apps play, and install them in the iOS resources. Android copies them from there
# (prepareBrandAssets in apps/android/app/build.gradle.kts).
#
#   zsh scripts/brand/install_grimoire.sh [build_output/tavern/grimoire]
#
# Each orientation gets the opening and the same frames backwards (the closing): H.264, 30 frames a
# second, no sound, a keyframe on every frame of these one-second clips so playback starts at once.
set -euo pipefail
REPO=${0:A:h:h:h}
SRC=${1:-$REPO/build_output/tavern/grimoire}
DEST=$REPO/apps/ios/MagicMobile/Resources/Grimoire
command -v ffmpeg >/dev/null || { print -u2 'ffmpeg is required (brew install ffmpeg)'; exit 1; }
mkdir -p $DEST
for orientation in portrait landscape; do
  frames=$SRC/$orientation
  [[ -f $frames/frame-0000.png ]] || { print -u2 "missing frames in $frames"; exit 1; }
  common=(-y -loglevel error -framerate 30 -i $frames/frame-%04d.png -an -c:v libx264 -profile:v high -level 4.1
          -pix_fmt yuv420p -crf 21 -preset slow -g 6 -movflags +faststart
          -color_primaries bt709 -color_trc bt709 -colorspace bt709)
  # The last frame is held a few frames so the hand-off to the live page never shows a jump.
  ffmpeg $common -vf "tpad=stop_mode=clone:stop_duration=0.1,scale=trunc(iw/2)*2:trunc(ih/2)*2" $DEST/grimoire-open-$orientation.mp4
  ffmpeg $common -vf "reverse,tpad=stop_mode=clone:stop_duration=0.1,scale=trunc(iw/2)*2:trunc(ih/2)*2" $DEST/grimoire-close-$orientation.mp4
done
ls -l $DEST | awk 'NR>1 {printf "%7.0f KB  %s\n", $5/1024, $9}'
