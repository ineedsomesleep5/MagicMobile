#!/bin/zsh
# Converts the iOS asset catalogue's Walnut Tavern art into the WebP files apps/web/public/tavern
# commits (like apps/site/public/tavern). Run after the tavern art changes; outputs are committed.
set -euo pipefail
here=${0:A:h}
repo=${here:h:h:h}
cat=$repo/apps/ios/MagicMobile/Assets.xcassets
out=$here/../public/tavern
mkdir -p $out
webp() { cwebp -quiet -q ${3:-82} -alpha_q 90 "$1" -o "$out/$2.webp"; }
webp $cat/battlefield-tavern-landscape.imageset/battlefield-tavern-landscape.jpg table 78
for n in seal coin capsule capsule-thin leather parchment ember frame; do webp $cat/tavern-ui-$n.imageset/tavern-ui-$n.png $n; done
webp $cat/tavern-pass-ring.imageset/tavern-pass-ring.png pass-ring
webp $cat/tavern-gem-power.imageset/tavern-gem-power.png gem-power
webp $cat/tavern-gem-toughness.imageset/tavern-gem-toughness.png gem-toughness
webp $cat/tavern-card-ribbon.imageset/tavern-card-ribbon.png ribbon
for k in creature token artifact enchantment land spell; do webp $cat/tavern-frame-$k.imageset/tavern-frame-$k.png frame-$k; done
for m in W U B R G C generic; do webp $cat/tavern-mana-$m.imageset/tavern-mana-$m.png mana-$m; done
ls -la $out
