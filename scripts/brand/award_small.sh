#!/bin/zsh
# The small copy of every award and trophy coin (design/awards/small/), which the apps show and keep on the phone. The big file
# is only for the ceremony. Run it after adding or replacing art in design/awards/. Needs pngquant (Homebrew).
set -e
cd "$(dirname "$0")/../../design/awards"
mkdir -p small
for art in *.png; do
  [ small/$art -nt $art ] && continue
  sips -Z 192 $art --out small/$art >/dev/null
  pngquant --quality 0-90 --speed 1 --force --strip --output small/$art small/$art
done
