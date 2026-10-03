# Site asset provenance

## Icon (Walnut & Ember)

The site icons come from the Walnut & Ember app-icon art approved October 1–2, 2026 (`~/Movies/motion-assets/magicmobile-brand/a-walnut-icon.png`, 1254 × 1254): the same mark shape as before (cream M in front of a card with a four-point sparkle, cards fanned behind) in carved walnut, brass and ember. Resized with ImageMagick on October 2, 2026:

| File | Size | Use |
| --- | --- | --- |
| `public/app-icon.png` | 192 × 192, 8-bit, 27 KB | join and privacy pages |
| `public/apple-touch-icon.png` | 180 × 180, opaque, 8-bit, 24 KB | iOS home screen |
| `public/favicon.png` | 64 × 64, rounded with transparent corners, 9 KB | browser tab |
| `public/tavern/mark-96.webp` | 96 × 96, 2 KB | masthead and footer mark |

The earlier ivory/coral icon is derived from Caleb's September 23, 2026 artwork (`design/brand/icon-master-2026-09-23.png`) and is no longer shown on the site.

## Tavern materials

From the iOS asset catalog (`apps/ios/MagicMobile/Assets.xcassets`), where the brass parts are Blender renders (`scripts/brand/tavern_ui_kit.py`) and the fills come from `scripts/brand/tavern_ui_textures.sh` (leather from Poly Haven `leather_red_02`, CC0; parchment generated from noise; ember glass cut from the pass-button art). Converted to WebP on October 2, 2026.

| File | Source | Size |
| --- | --- | --- |
| `tavern/backdrop.webp` | `menu-backdrop-tavern` (tavern wall with candles), 760 px wide | 53 KB |
| `tavern/table-landscape.webp` | `battlefield-tavern-landscape` (leather table in walnut), 1600 px wide | 19 KB |
| `tavern/leather.webp` | `tavern-ui-leather`, 512 px seamless tile | 16 KB |
| `tavern/parchment.webp` | `tavern-ui-parchment`, 384 px seamless tile | 3 KB |
| `tavern/ember.webp` | `tavern-ui-ember`, 256 px, stretched | 6 KB |
| `tavern/frame.webp` | `tavern-ui-frame`, riveted brass frame, 288 px (24 pt corners at 3×) | 6 KB |
| `tavern/capsule.webp` | `tavern-ui-capsule`, riveted brass rim; the casting seam in the left middle slice is covered with the row above it so the stretched slice stays clean | 6 KB |
| `tavern/capsule-thin.webp` | `tavern-ui-capsule-thin`; the middle rows (seam and two rivets) are replaced the same way, leaving a plain rim that stretches | 3 KB |
| `tavern/walnut.webp` | Poly Haven `black_walnut_veneer_02` diffuse (CC0, `~/Movies/motion-assets/magicmobile-brand/textures`), whole seamless tile scaled to 512 px, darkened and warmed | 5 KB |

## App screenshots

Actual iOS simulator captures from the Walnut & Ember builds 24–25, October 2, 2026, converted to WebP. The landscape captures carry EXIF orientation 8 over upright landscape pixels, so the tag is stripped and browsers show them as stored.

| File | Source capture | Size | Shown as |
| --- | --- | --- | --- |
| `menu-landscape.webp` | `menu-land.png`, landscape main menu, 1300 × 598 | 55 KB | app reveal ("Actual iOS app preview") |
| `board-portrait.webp` | `b24-crowded-battlefield.png`, portrait board, 660 × 1434 | 131 KB | gameplay phone |
| `board-landscape.webp` | `l2-crowded-battlefield.png`, landscape board, 1400 × 644 | 128 KB | landscape table |

Both battlefield captures are development fixtures (their "Development fixture · No engine" banner stays visible), not live matches, and the captions say so. The retired captures `studio.webp`, `studio-portrait.webp` (Deck Studio, September 17, 2026), `game.webp` and `game-portrait.webp` (portrait arena fixture, September 15, 2026) remain in `public/` but are no longer shown.

`social.png` (the Open Graph image, JPEG data, 1440 × 900) is a capture of the restyled hero.

Black Lotus artwork is sourced through Scryfall. Card artwork belongs to its respective rights holders; the footer includes attribution and identifies the independent fan project. Black Lotus is a visual collectible reference, not a claim that it is Commander-legal.

## Card sleeve texture

All seven displayed card fronts are actual card scans served by Scryfall, converted to WebP quality 86. Both the 3D hand and scrolling phone-reveal fan use these fronts. Reverse faces use the official Magic: The Gathering back from https://cards.scryfall.io/back.png, converted to `magic-card-back.webp`. The generated sleeve described below is a retired asset, no longer displayed.

| Card | Printing | Artist | Source |
| --- | --- | --- | --- |
| Black Lotus | VMA 4 | Chris Rahn | https://scryfall.com/card/vma/4/black-lotus |
| Swords to Plowshares | VMA 51 | Terese Nielsen | https://scryfall.com/card/vma/51/swords-to-plowshares |
| Birds of Paradise | RAV 153 | Marcelo Vignali | https://scryfall.com/card/rav/153/birds-of-paradise |
| Counterspell | VMA 64 | Jason Chan | https://scryfall.com/card/vma/64/counterspell |
| Lightning Bolt | M11 149 | Christopher Moeller | https://scryfall.com/card/m11/149/lightning-bolt |
| Demonic Tutor | VMA 116 | Scott Chou | https://scryfall.com/card/vma/116/demonic-tutor |
| Sol Ring | VMA 283 | Mike Bierek | https://scryfall.com/card/vma/283/sol-ring |

- Generated 2026-09-19 using the built-in OpenAI image generation tool; no reference images.
- Original generation: `/Users/calebfeliciano/.codex/generated_images/01a0ba41-119d-7603-9462-71af84342017/exec-12ffa5a1-df5f-445a-b850-0e6d327a3307.png`.
- Delivery: `card-back.webp`, 1060 × 1484 pixels, exact 5:7 aspect ratio. Converted with `cwebp -q 88`; original generation retained.
- Original artwork for the MagicMobile website. No official Magic card-back artwork, logo, or lettering requested or included.

## Generation prompt

Use case: stylized-concept
Asset type: production card-back texture for a Three.js collectible card, portrait 2.5:3.5 aspect ratio.
Primary request: An original premium collector card sleeve, flat orthographic edge-to-edge artwork. Midnight forest-black background with subtle intricate aged gold botanical lotus engraving. One centered elegant circular compass/lotus motif and a refined symmetrical engraved border. Minimal, high craft, restrained luxury, delicate precise lines and ample dark negative space.
Materials/textures: finely grained dark sleeve surface; muted antique gold etched linework with subtle natural wear.
Composition: Entire image is the rectangular texture, no surrounding scene or margin, straight-on, absolutely no perspective. Symmetrical design.
Constraints: No words, letters, numbers, logos, watermark, official Magic card-back marks, physical scene, hand, table, cast shadow, rounded corners, or mockup. Generate one image.
