# Battlefield material backgrounds

Six stable preferences: `arena`, `midnight`, `wood`, `moss`, `ember`, `tide`. Midnight preserves the existing native gradient. Five raster materials replace the old painted stone/wood treatment and add moss, obsidian and tidal slate. Old source assets remain intact for unrelated menu references.

## Integration

Use `BattlefieldBackdrop.allCases` for the selector and `BattlefieldBackdropArt(theme: .resolved(value))` for both the selector preview and battlefield. Frame and clip at the consumer. Each image is square, with a quiet center and no artwork encoding seats, cards, health or legal actions. Existing saved `arena`, `midnight`, `wood` preferences remain valid. New enum and artwork view are in `GameBoardTheme.swift`. Android should use identical identifiers and image bytes.

Assets: `Assets.xcassets/battlefield-{arena,wood,moss,ember,tide}.imageset/battlefield-{id}.png`. Actual output is 1254×1254 for each, approximately 12.3 MB combined. The generation request suggested 1536×1536; no claim of that requested resolution is made.

## Verification

Inspected all five generated outputs: no text, symbols, painted controls, avatars, life circles, card slots or borders. Material detail stays subordinate to cards. Both center-crop directions retain the quiet center; this is an asset composition assessment, not a simulator board acceptance. Checked PNG dimensions and asset-catalog JSON names. Added `BattlefieldBackdropTests` for preserved preference IDs and bundled square assets; these UIKit tests need the app test target, not the portable package. No Xcode build or simulator was run by this subtask.

## Provenance and exact prompts

Created with the built-in image generation tool on 2026-09-19. No API/paid CLI fallback. Original generated files remain under `/Users/calebfeliciano/.codex/generated_images/01a0bb12-bae8-79b0-b2d5-5514db7a5b49/`; final copies are inside the app asset catalog.

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
