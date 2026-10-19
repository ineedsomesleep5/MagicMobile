# Battlefield backgrounds

Walnut Tavern (`tavern`) is the only table players get (the picker went on 2026-10-11). `arena` stays as
the classic board layout for the UI tests that pin it (`-magicmobile.boardAppearance arena`); it draws the
plain dark gradient. Both apps share these identifiers (`GameBoardTheme.swift`, Android `BattlefieldViews.kt`).

## Retired materials (2026-10-14)

The five square materials (stone `arena`, `wood`, `moss`, `ember`, `tide`) and the `midnight` choice were
removed from both apps on 2026-10-14: about 2.7 MB of the iOS asset catalog and 1.7 MB of the Android APK
that no player could reach any more (docs/audits/APP_AUDIT_2026-10.md). Saved values for them resolve to the
tavern. To bring one back, restore it from git history: the generated PNGs are in `791198b`
(`apps/ios/MagicMobile/Assets.xcassets/battlefield-{id}.imageset/battlefield-{id}.png`) and the shipped
encodes (iOS JPEG at quality 85, Android `cwebp -q 90 -m 6 -sharp_yuv`) in `1586a02d`. Re-encode from the
PNGs, never from the lossy files. The older stone and painted menu/board backgrounds (`commander-stone-arena`,
`mage-mobile-*-background`) left iOS on 2026-09-27 and Android in #156.

## Walnut Tavern (composed)

`tavern` is a composed table rendered per orientation (`battlefield-tavern-portrait`,
`battlefield-tavern-landscape`, plus `battlefield-tavern-pad` on iPad) by `scripts/brand/tavern_table.py` from
`scripts/brand/tavern_layout.json`, with sockets placed under the tavern controls. It carries its own
lighting, so `BattlefieldSurface` skips the generic shading (`hasBakedLighting`). See
docs/BOARD_FX_ROADMAP.md phase 12. Android copies the same JPEGs from the iOS catalogue at build time.

## Integration

Use `BattlefieldBackdropArt(theme: .resolved(value))`. Frame and clip at the consumer.
`BattlefieldBackdropTests` checks the two remaining values, the fallback for retired ones, that the retired
textures stay out of the bundle, and that the composed tables ship both orientations.

## Provenance and exact prompts (retired materials)

Created with the built-in image generation tool on 2026-09-19. No API/paid CLI fallback. Original generated files remain under `/Users/calebfeliciano/.codex/generated_images/01a0bb12-bae8-79b0-b2d5-5514db7a5b49/`; the encoded copies were in the app asset catalog until 2026-10-14.

### arena

Use case: stylized-concept. Create ONE square 1536x1536 raster texture for a premium mobile fantasy trading-card battlefield background called Stone Arena. Orthographic straight overhead view, no perspective horizon. Entire image is an uninterrupted dark charcoal slate surface, fine natural stone grain, broad flat subtly varied slabs with very faint irregular seams. Restrained cool grey mineral highlights only at outer perimeter, center 75% extremely quiet and low contrast so real game cards and UI remain the focus. The texture must remain attractive when center-cropped to 9:19 portrait OR 19:9 landscape. Refined realistic material rendering, soft diffuse light, matte finish. No rings, no circular medallions, no card slots, no lanes, no avatars, no health circles, no painted UI, no text or symbols, no logos, no gold frame, no objects, no theatrical glowing lights, no dramatic cracks. Deliver the bare background material filling all pixels.

/Users/calebfeliciano/.codex/generated_images/01a0bb12-bae8-79b0-b2d5-5514db7a5b49/exec-04734051-dbe0-48be-a887-fa625dc28462.png

### wood

Use case: stylized-concept. Asset: ONE square 1536x1536 premium mobile fantasy trading-card battlefield material background, Classic Wood. Dark smoked walnut tabletop, broad continuous weathered walnut grain with restrained rich coffee-brown warmth, very few subtle plank joins, satin matte finish, soft warm natural diffuse light. No orange tint, no varnished glare, no carvings. Orthographic straight overhead material view, no perspective horizon. Center 75% extremely low contrast and quiet so real game cards and UI remain the focus. Texture must work center-cropped to either tall 9:19 portrait or wide 19:9 landscape. Refined realistic material rendering, soft diffuse lighting, barely visible vignette. Bare texture fills all pixels. No rings, circular medallions, card slots, lanes, avatars, health circles, painted UI, text, symbols, logos, gold frame, objects, diagonal hero lighting, or dramatic composition.

/Users/calebfeliciano/.codex/generated_images/01a0bb12-bae8-79b0-b2d5-5514db7a5b49/exec-5322c022-4aa1-4197-8906-8d3f130cf889.png

### moss

Use case: stylized-concept. Asset: ONE square 1536x1536 premium mobile fantasy trading-card battlefield material background, Moss Sanctuary. Dark deep forest green weathered basalt surface. Fine sage moss grows only along irregular seams near the outer 12 percent perimeter; the central surface is smooth dark muted green-grey stone. No leafy objects or vines crossing the center, no flowers. Orthographic straight overhead material view, no perspective horizon. Center 75% extremely low contrast and quiet so real game cards and UI remain the focus. Texture must work center-cropped to either tall 9:19 portrait or wide 19:9 landscape. Refined realistic material rendering, soft diffuse lighting, barely visible vignette. Bare texture fills all pixels. No rings, circular medallions, card slots, lanes, avatars, health circles, painted UI, text, symbols, logos, gold frame, objects, diagonal hero lighting, or dramatic composition.

/Users/calebfeliciano/.codex/generated_images/01a0bb12-bae8-79b0-b2d5-5514db7a5b49/exec-811bfbba-d4a0-4f9f-a783-f845d699aa9d.png

### ember

Use case: stylized-concept. Asset: ONE square 1536x1536 premium mobile fantasy trading-card battlefield material background, Obsidian Ember. Dark nearly-black volcanic glass rock with satin charcoal sheen, a very few faint desaturated burnt-copper mineral veins at the outer 12 percent perimeter. The large central surface is quiet deep brown-black obsidian. No glowing lava, no flames, no bright cracks. Orthographic straight overhead material view, no perspective horizon. Center 75% extremely low contrast and quiet so real game cards and UI remain the focus. Texture must work center-cropped to either tall 9:19 portrait or wide 19:9 landscape. Refined realistic material rendering, soft diffuse lighting, barely visible vignette. Bare texture fills all pixels. No rings, circular medallions, card slots, lanes, avatars, health circles, painted UI, text, symbols, logos, gold frame, objects, diagonal hero lighting, or dramatic composition.

/Users/calebfeliciano/.codex/generated_images/01a0bb12-bae8-79b0-b2d5-5514db7a5b49/exec-b858ae64-e445-4b75-b6de-1a2ce499f557.png

### tide

Use case: stylized-concept. Asset: ONE square 1536x1536 premium mobile fantasy trading-card battlefield material background, Tidal Slate. Dark marine blue-grey sea-worn slate surface with broad very subtle flowing mineral striations, faint desaturated teal salt patina around outer 12 percent perimeter. The center is smooth calm dark navy slate. No water pools, waves, shells or objects. Orthographic straight overhead material view, no perspective horizon. Center 75% extremely low contrast and quiet so real game cards and UI remain the focus. Texture must work center-cropped to either tall 9:19 portrait or wide 19:9 landscape. Refined realistic material rendering, soft diffuse lighting, barely visible vignette. Bare texture fills all pixels. No rings, circular medallions, card slots, lanes, avatars, health circles, painted UI, text, symbols, logos, gold frame, objects, diagonal hero lighting, or dramatic composition.

/Users/calebfeliciano/.codex/generated_images/01a0bb12-bae8-79b0-b2d5-5514db7a5b49/exec-d4a87940-6595-499a-ac62-7604854d6ae9.png
