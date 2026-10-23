#!/bin/zsh
# Renders the Arena table at the desktop shapes the web board uses (public/arena/table-*.jpg). The plate itself
# (public/arena/table.jpg, 956 x 440) is the Duel Board Prototype's landscape plate.
#
#   zsh apps/web/scripts/render_arena_plates.sh [variant ...]     # default: desk195 desk169 desk1610 desk43
#
# The renderer is scripts/brand/tavern_table.py as of the Arena board commit (claude/arena-mode f8c8706c), which adds
# --bare/--pitch/--lens/--zoom; it is read from git, so this checkout needs that commit. Each render is a heavy job
# (Blender, about 2.5 minutes and up to a few GB of memory on the 8 GB Mac), so they run one at a time under heavy.sh.
set -euo pipefail
web=${0:A:h:h}
repo=${web:h:h}
work=$(mktemp -d)
trap 'rm -rf $work' EXIT
git -C $repo show f8c8706c:scripts/brand/tavern_table.py > $work/tavern_table.py
blender=${BLENDER:-/Applications/Blender.app/Contents/MacOS/Blender}
typeset -A out=(desk195 table-195 desk169 table-169 desk1610 table-1610 desk43 table-43)
for variant in ${@:-desk195 desk169 desk1610 desk43}; do
  zsh $repo/scripts/dev/heavy.sh "arena plate $variant" -- $blender -b --python-exit-code 1 -P $work/tavern_table.py -- \
    --layout $web/scripts/arena_plates.json --variant $variant --scale 2 --bare --pitch 22 --lens 35 --zoom 1.07 \
    --skip-sprites --out-dir $work/out
  magick $work/out/tavern-$variant.png -strip -quality 84 -sampling-factor 4:2:0 $web/public/arena/${out[$variant]}.jpg
  print "public/arena/${out[$variant]}.jpg"
done
