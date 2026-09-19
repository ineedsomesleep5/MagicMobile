# Site asset provenance

## App screenshots and icon

The icon is the existing MagicMobile iOS app icon. Deck Studio images are actual simulator captures from the build-5000000000 release UI checks, September 17, 2026, in `MagicMobile-runtime-hardening/build_output/deck-studio-5000000000-populated`. The landscape capture is stored rotated; CSS restores its viewing orientation without changing the app UI.

The battlefield image is `build_output/arena-review/portrait-arena-expanded-hand.png`, September 15, 2026. It is an actual app UI development fixture, not a live-match screenshot. Its fixture banner and the website caption remain visible.

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
