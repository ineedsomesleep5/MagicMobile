# Walnut Tavern style spec

The house style of MagicMobile since 2026-10-02: dark carved walnut, tooled leather, parchment,
riveted brass and ember glass. iOS calls the app-wide palette **Walnut & Ember** (`BrandUI.swift`)
and the board style **Walnut Tavern** (`Board/BoardChrome.swift`). Android ports both in
`ui/TavernKit.kt`, `ui/BrandUI.kt` and `ui/Theme.kt`.

Read this before building or porting any screen, sheet, dialog or control. `DESIGN.md` still holds
the general principles (board-first, 44pt targets, mana colours only for mana); this file says what
those surfaces look like now. Where the two differ, this file wins for anything drawn on the tavern.

**iOS is the reference.** When this file and the Swift code disagree, the code wins: fix this file in
the same PR. Every number here was read from the code on 2026-10-11.

## The one rule for Android

A screen the user can reach on iOS in tavern dress must be in tavern dress on Android too. Do not
reach for plain Material components, `IosAlert`, `IosListRow` or system-styled controls on a tavern
surface: use the `Tavern*` composable that matches the iOS piece (table below). If no Kotlin
counterpart exists yet, port the Swift piece into `ui/TavernKit.kt` first, then use it.

## Palette

### Board kit: `TavernPalette` (iOS `BoardChrome.swift`, Android `ui/TavernKit.kt`)

| Token | sRGB | Hex | Use |
| --- | --- | --- | --- |
| `brass` | 0.86, 0.64, 0.30 | `#DBA34C` | Rims, hairlines, tints, separators (at 0.35 alpha) |
| `brassDark` | 0.36, 0.22, 0.08 | `#5C3814` | Shadowed brass, the bottom of brass rules |
| `leather` | 0.16, 0.08, 0.045 | `#29140B` | Fallback fill for leather surfaces |
| `enamel` | 0.42, 0.07, 0.05 | `#6B120D` | Life badges; fallback fill for ember glass |
| `ember` | 1.0, 0.50, 0.34 | `#FF8057` | Selection, switches on, the call to action |
| `parchment` | 0.95, 0.88, 0.74 | `#F2E0BD` | Text on leather; fallback fill for parchment |
| `ink` | 0.22, 0.11, 0.04 | `#381C0A` | Text on parchment |
| `label` (Android name) | 0.96, 0.80, 0.48 | `#F5CC7A` | Section labels and stack-tray captions |
| `brassLine` | gradient 0.92,0.72,0.38 → 0.50,0.33,0.11 | | Hairlines on parchment rows and inset boxes |
| gold text (`goldText` on Android) | gradient `#FFE08F` → `#CC8F38`, top to bottom | | Engraved titles |

Fixed text colours the kit uses: primary button text `#FFE8A8`, destructive button text `#FFCCB8`,
parchment-tag text `#3D1F0D`, leather-tag text `#FAD17A`, coin numerals `#401F0A`. Danger is
`MagicPalette.oxblood` (`#8A2B26`) laid over leather at 0.7.

### App surfaces: `BrandTheme`, Walnut & Ember (iOS `BrandUI.swift`, Android `ui/Theme.kt`)

| Token | Hex | Use |
| --- | --- | --- |
| `canvas` | `#1B120B` | Walnut: menu and launch backgrounds |
| `surface` | `#2B1B11` | Leather cards |
| `surfaceRaised` | `#3A2416` | Raised leather |
| `border` | `#8A6A3C` | Dim brass edges |
| `ink` | `#F3E6C8` | Parchment text |
| `inkSecondary` | `#C2AB86` | Secondary text |
| `brass` | `#E0AD5C` | Brass accents (`brassGradient` `#FFE08F` → `#CC8F38`) |
| `ember` / `emberLight` | `#FF8058` / `#FF9D7E` | Call to action (`emberGradient`) |
| `rust` | `#A74429` | Deep ember |
| `emberInk` | `#221713` | Text on ember |
| `danger` | `#FF7064` | Destructive text on dark |

Deck Studio is the one light surface (workshop mode, `DeckStudioPalette`): aged parchment pages in
dark brown ink with ember and leather plaques. Its geometry is shared, its colours are not.

## Materials

Rendered textures, never flat colours, when the kit is installed (`TavernUIKit.available` on iOS;
the drawables are always staged on Android by `prepareBrandAssets`).

| Material | Asset | Drawn as | Fallback |
| --- | --- | --- | --- |
| Leather | `tavern-ui-leather` | Tiled | `TavernPalette.leather` |
| Parchment | `tavern-ui-parchment` | Tiled | `TavernPalette.parchment` |
| Ember glass | `tavern-ui-ember` | Stretched | `TavernPalette.enamel` |

iOS `TavernFill(material:)` = Android `Modifier.tavernFill(TavernMaterial.*)`. Sources:
`scripts/brand/tavern_ui_textures.sh` and `scripts/brand/tavern_ui_kit.py`, installed at @3x so cap
insets are in points.

## Frames and trim

- **Brass frame** (`TavernBrassFrame` / `Modifier.tavernBrassFrame`): 9-sliced from
  `tavern-ui-frame`, 96pt with 24pt riveted corners. `scale` shrinks the trim (0.5 gives 12pt
  corners); panels pass `cornerRadius / 12` clamped to 0.4…1. Fallback: a 2pt brass stroke at a
  12×scale radius.
- **Capsule rim** (`TavernCapsuleRim` / `Modifier.tavernCapsuleRim`): riveted `tavern-ui-capsule`
  for 44pt buttons (22pt caps, tiles as it widens) or thin `tavern-ui-capsule-thin` for 22pt tags
  (11pt caps, stretched).
- **Panel** (`TavernPanelChrome` / `Modifier.tavernPanelChrome`): leather with a clear → black 0.3
  vertical gradient, clipped to 12×scale corners, brass frame on top. Off the tavern it falls back
  to the classic iron fill with a 0.38 antique-gold stroke.
- **Title bar** (`TavernTitleBar` / `Modifier.tavernTitleBar`): leather darkened by black 0.22, 10pt
  corners, min height 48, brass frame at 0.5.
- **Wax seal close** (`TavernSealLabel` / `TavernSealButton`): `tavern-ui-seal` at 32pt inside a 44pt
  hit target, with a gold-gradient `xmark` on top (Caleb, 2026-10-03: the pressed x alone is too
  faint).
- **Card frames** (`TavernFrameKind`, iOS `ArenaBoardPresentation.swift`, Android core
  `game/TavernSockets.kt`): creature gold, token walnut, artifact silver, enchantment rose-gold,
  land stone, spell parchment scroll. Each has its own art window fraction; ribbon at 72% height,
  hex gems for power and toughness. Highlights are glow only (`TavernTileGlow`), never a recolour.

## Type

Serif everywhere on the tavern; system sans only for dense numbers that are not on a tavern piece.

**Display face (since 2026-10-14):** Cormorant SC Bold (`TavernDisplayFont` on iOS, `tavernDisplay()` on
Android) for the brand title, panel titles, the menu deck name, brand plaques and the large navigation
title. Everything else stays in the system serif: Cormorant's x-height is about 20% shorter, so it reads
small at body sizes and has no heavier weight or italic. Pass the old serif size; the helper sets it 10%
larger and turns on lining figures (`lnum`). Don't use it below 16pt.

| Piece | Size / weight | Extras |
| --- | --- | --- |
| Button (`TavernButtonStyle`) | 14 heavy serif, 12 compact | 1pt black 0.75 shadow, 2 lines, min scale 0.75 |
| Brand button (menu plaques) | 19 primary, 17 secondary, display face | |
| Panel title (`TavernPanelTitle`) | 16 display face, UPPERCASE | tracking 1.2, gold gradient, accessibility label in normal case |
| Tag (`TavernTag`) | 10 heavy serif | tracking 0.8, 1 line, min scale 0.7 |
| Toggle title / subtitle | 16 semibold / 12 regular serif | subtitle at 0.65 opacity, 2 lines |
| Text field | 15 medium serif, `ink` | |
| Coin numeral | 0.52 × coin size, black serif, monospaced digits | white 0.35 shadow 1pt down |
| Navigation title / large | 17 semibold serif / 32 display face | (`TavernAppearance`) |

Android fonts: Source Serif 4 stands in for New York (`SfDesign.SERIF`), Inter for SF Pro, Nunito
for SF Rounded; `sf(size, weight, design)` fits widths to CoreText. Use `TextStyle.engraved()` for
the 1pt drop shadow.

## Controls

- **Buttons** (`TavernButtonStyle` / `TavernButton`, `TavernPlaqueButton`): a capsule of material
  inset 3pt inside the riveted rim. Primary is ember glass, secondary leather, danger leather under
  oxblood 0.7. Min height 44, horizontal padding 22 (16 compact), vertical 6. Pressed: scale 0.96 and
  brightness +0.08, 0.12s ease-out (none with reduced motion). Disabled: saturation 0.15, brightness
  −0.12. Drop shadow black 0.45, radius 4, 2pt down. Menu plaques (`BrandUI.swift`) are the same idea
  at radius 21, min height 58 primary / 50 otherwise.
- **Tags** (`TavernTag`): parchment for labels ("PAY COST"), leather for status chips; min height 22,
  padding 12, thin rim; an optional 8pt accent jewel carries the prompt's colour cue.
- **Coins** (`TavernCoin`): `tavern-ui-coin`, 24pt default, for counts and generic mana.
- **Toggle** (`TavernToggle`): a 51×31 brass-rimmed switch face, dark leather off, ember glass on;
  the real system toggle stays on top, nearly invisible, so accessibility and UI tests keep working.
- **Stepper, picker, slider** (`TavernStepper`, `TavernPicker`, `TavernSlider`): stepper buttons are
  30pt brass rings with a leather face and gold glyph; segmented selection is ember on leather with
  serif labels; the picker accent on Android is `TavernPickerAccent` (`#993B1A`).
- **Text field** (`TavernFieldChrome` / `TavernTextField`): a recessed parchment slot, black 0.18 →
  clear top shadow, 9pt corners, 1.2pt `brassLine` stroke, min height 40.
- **Menus and confirmations** (`TavernMenu`, `TavernMenuItem`, `tavernConfirmation` /
  `TavernMenu`, `TavernMenuItem`, `TavernMenuHeading`, `TavernMenuDivider`,
  `TavernConfirmationDialog`): leather pop-overs in brass trim with live text. Use these instead of
  system menus, alerts and action sheets.

## Sheet layouts

Every sheet opened from the tavern (settings, downloads, friends, updates, chat, ranked, game menu)
follows one recipe:

1. **Backing:** `TavernSheetBackground`: tiled leather, a clear → black 0.35 vertical gradient, a
   3pt brass rule (brass → `#6B4717`) along the top, edge to edge under the safe area.
2. **Header:** `TavernPanelTitle` on the left, `TavernSealLabel` close on the right, optionally in a
   `TavernTitleBar`.
3. **Rows** (iOS `tavernList()` / `TavernListChrome`): rows are leather darkened by black 0.28,
   separators brass at 0.35, text parchment serif, controls tinted brass, navigation bar hidden and
   dark. Android has no single `tavernList` modifier yet: compose `TavernSheetBackground`, row
   backgrounds of `tavernFill(LEATHER, overlay = Color.Black.copy(alpha = 0.28f))` and brass dividers.
   Porting it as one modifier is a welcome cleanup.
4. **Grouped content:** `TavernPanelChrome` at a 12pt corner (16pt for large panels).
5. **Actions:** `TavernButtonStyle` plaques at the foot; one primary at most.

## The board

The table plate and every socket come from `scripts/brand/tavern_layout.json`: portrait canvas
440×956, landscape 956×440, pad 1180×860, top-left origin, in points. iOS `TavernDesign` /
`TavernSockets` and Android core `game/TavernSockets.kt` (checked by `TavernSocketsTest`) carry the
same numbers; change all three together, and re-render the plate with `scripts/brand/tavern_table.py`.
Controls are table objects in the plate's sockets: medallions (life in an enamel badge), mana gems,
the flipping pass disc, the stack tray, the phase plate. The opponent's status badges (commander damage,
poison, counters, monarch) curve around their medallion (`TavernEffectOrbit`): the worst commander damage
straight out along the socket's bearing (under the portrait in portrait, toward the mat sideways), the rest
alternating either side 25° apart, 22pt at radius hole + 21, with a "+N" coin past the socket's limit. Taps
pass through; the medallion's pop-over lists each badge in words. Table-wide hints (storm, day or night)
stay under the phase plate. See `docs/ANDROID_PARITY.md` for the
piece-by-piece port and `docs/BOARD_FX_ROADMAP.md` for effects.

## Board modes: Hearth and Arena

Two board modes share the tavern kit (Caleb, 2026-10-20); each will get its own themes later.

- **Hearth** is the board above: sockets, the hourglass, the mana rail.
- **Arena** follows the reference game, as approved in the Duel Board Prototype artifact. Its layout is `ArenaLayout` (`ArenaBoardModel.swift`, 956×440 and 440×956 canvases), not `TavernSockets`.
  - The table: a leaning tavern table (`tavern-arena-landscape` / `-portrait`, from `scripts/brand/arena_layout.json`). The vertical mat is wider than the screen, because the camera narrows its far half.
  - Battlefield and stack (the reference's sections, Caleb 2026-10-20): each side's front row, nearest the compass, holds creatures centred and, in a section of its own at the right end, planeswalkers, battles, sagas and other non-creature permanents (planeswalkers and battles outermost, loyalty and defense on a shield). The back row holds lands from the left and mana rocks and Treasures at its right end. Auras and Equipment go with the permanent they're attached to. The stack's top card stays big on the right.
  - Rows use the table's full width: `ArenaRowFit` shrinks the cards (down to 70%) before any section scrolls, and portrait opens a second front row first. Landscape fits 8 creatures at full size and 12 before scrolling; portrait fits 12 in two rows, or 10 beside two planeswalkers. Only past that does a section scroll with the edge fade.
  - The hand and decks: the hand rises while you can play (a full hand flattens and lifts so no card runs off the screen) and rests at the edge otherwise; in vertical it tucks behind the front rail, and a tap on the table puts it down. Decks are 3D stacks with the real card back, and a revealed top card lies face up on them.
  - Controls and medallions: the phase strip and buttons sit in one corner (on the front rail in vertical). The life number sits over the player's picture in the medallion.
  - Tiles lean with the table's own camera (`ArenaTableLean`: the plate's pitch, converging on the screen's centre), so their sides follow the mat's edges. A tapped tile tilts 12° and greys under a big tap mark. Card Frames (Settings, per mode) is off by default in Arena: the reference's cropped card, a name bar and a silver power/toughness box.
  - Floating mana is plain symbols. Cards you can play from the graveyard or exile end the fan with a shimmer. Exile piles sit by the graveyards.

## Known Android gaps (still plain or system-styled)

From `docs/ANDROID_PARITY.md` (2026-10-03), not re-verified since: the game log drawer's contents,
the Friends and relay table sheets beyond their shared controls, Deck Studio screens beyond the
palette, toggles and buttons, and the remaining `IosAlert` dialogs. The settings "About" rows in
`ondevice/OnDeviceRootView.kt` still use `IosListRow`. Close these with the pieces above, and tick
them off in `ANDROID_PARITY.md`.

## Checklist for a screen PR

- Every colour is a `TavernPalette` or `BrandTheme` token, not a new literal.
- Surfaces are materials (leather, parchment, ember glass) in brass trim, not flat fills.
- Titles and controls are serif; buttons are tavern plaques, at least 44pt tall.
- No system alert, menu, list row or switch is visible on a tavern surface.
- The iOS and Android versions were compared with the same `MAGICMOBILE_DESIGN_PREVIEW` state in
  the same orientation, or the PR says that comparison is still pending.
