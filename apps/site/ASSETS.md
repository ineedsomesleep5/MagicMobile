# Site asset provenance

Everything on the page is real: the app's own art, badges and die, actual card scans, and actual app screens. Nothing is
generated. Card artwork belongs to its artists and rights holders; MagicMobile is unofficial Fan Content (footer).

## Icons and mark

From the apps' brass M mark (the app icon since October 22, 2026, `af74fd47`):

| File | Source | Use |
| --- | --- | --- |
| `public/favicon.png` | `apps/ios/MagicMobile/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png` at 64 px | browser tab |
| `public/apple-touch-icon.png` | the same at 180 px | iOS home screen |
| `public/app-icon.png` | the same at 512 px | join page |
| `public/site/mark.png` | the Arena top bar's borderless brass mark, 300 px with alpha | bar, footer, privacy and support pages |

`public/social.jpg` (the Open Graph image, 1440 × 900) is a capture of this page's first screen.

## Commander art and cards

`public/site/art/*.webp` is the apps' home art (`home-art-*`, see `docs/ARENA_STYLE.md`): Scryfall's art crops upscaled
2×, 1252 × 914, re-encoded as WebP. `public/site/cards/*.webp` are the cards' Scryfall PNG scans (alpha corners), 520 px
wide.

| Commander | Printing | Artist | Shown as |
| --- | --- | --- | --- |
| The Ur-Dragon | CMM 361 | Jaime Jones | hero, Quick Match |
| Edgar Markov | art only | Volkan Baǵa | Ranked |
| Y'shtola, Night's Blessed | FIC 7 | Magali Villeneuve | Deck Studio |
| Atraxa, Praetors' Voice | 2XM 190 | Victor Adame Minguez | Custom table |
| Krenko, Mob Boss | FDN 204 | Lie Setiawan | Friends |
| Miirym, Sentinel Wyrm | CLB 284 | Kekai Kotaki | Hearth |
| Giada, Font of Hope | FDN 141 | Kai Carpenter | How to play, the close |

Each exhibit credits its artist beside the art.

## Rank badges

`public/site/ranks/*.webp` are the apps' tier badges (`tavern-rank-*`), 360 px. `public/site/spin/m0–m31.webp` are the
Mythic badge's 32-frame turn from the iOS asset catalog (`tavern-rank-mythic-spin-NN`), 300 px.

## The D20

`public/site/d20/` is copied unchanged from `apps/ios/MagicMobile/Resources/D20/`: the resin die (`d20.glb`), the
winner's glow quad (`d20-glow.glb`), the face map (`d20.json`) and the recorded throws (`d20-throws.json`).

## App screens

iOS simulator captures from October 23, 2026 (3× pixels, real card art, no placeholder art), cropped:

| File | Source capture | Crop | Shown as |
| --- | --- | --- | --- |
| `site/shots/draw.webp` | portrait opening hand, 1206 × 2622 | 1206 × 900 from y 840: title, fan, Mulligan and Keep | Draw |
| `site/shots/attack.webp` | landscape board, 2622 × 1206 | the board below the top 150 px (drops the dev-fixture label), 2200 px wide | Attack, wide screens |
| `site/shots/attack-phone.webp` | the same capture | 1360 × 1056 around the battlefield, 1080 px wide | Attack, phones |
