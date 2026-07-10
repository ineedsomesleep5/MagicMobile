---
version: beta
name: MagicMobile
description: "A polished, board-first Commander experience for native iPhone play."
colors:
  primary: "#d6a640"
  background: "#0a0806"
  surface: "#1c120d"
  surface-raised: "#292321"
  surface-muted: "#332116"
  text-primary: "#f7f2e6"
  text-secondary: "#c9bda6"
  text-tertiary: "#9c8f7a"
  accent-strong: "#e8c46b"
  danger: "#8a2b26"
  success: "#2ec778"
  warning: "#d9892b"
  arcane: "#45a6d9"
  mana-white: "#f4ead0"
  mana-blue: "#78a8d8"
  mana-black: "#37323a"
  mana-red: "#d66f53"
  mana-green: "#72a766"
  mana-colorless: "#b8b1a2"
typography:
  headline:
    fontFamily: "System Serif"
    fontSize: 34px
    fontWeight: 700
    lineHeight: 1.1
    letterSpacing: 0em
  title:
    fontFamily: "System Serif"
    fontSize: 22px
    fontWeight: 700
    lineHeight: 1.25
    letterSpacing: 0em
  body:
    fontFamily: "System"
    fontSize: 17px
    fontWeight: 400
    lineHeight: 1.4
    letterSpacing: 0em
  label:
    fontFamily: "System"
    fontSize: 12px
    fontWeight: 700
    lineHeight: 1.2
    letterSpacing: 0.04em
  card-meta:
    fontFamily: "System"
    fontSize: 11px
    fontWeight: 600
    lineHeight: 1.2
    letterSpacing: 0em
rounded:
  sm: 6px
  md: 10px
  lg: 14px
  hero: 20px
  full: 9999px
spacing:
  unit: 4px
  board-gap: 6px
  zone-padding: 8px
  panel-padding: 16px
  touch-target: 44px
components:
  action-primary:
    backgroundColor: "{colors.primary}"
    textColor: "{colors.background}"
    typography: "{typography.label}"
    rounded: "{rounded.md}"
    height: "{spacing.touch-target}"
    padding: 12px
  action-secondary:
    backgroundColor: "{colors.surface-muted}"
    textColor: "{colors.text-primary}"
    typography: "{typography.label}"
    rounded: "{rounded.md}"
    height: "{spacing.touch-target}"
    padding: 12px
  game-zone:
    backgroundColor: "{colors.surface}"
    textColor: "{colors.text-primary}"
    rounded: "{rounded.md}"
    padding: "{spacing.zone-padding}"
  prompt-panel:
    backgroundColor: "{colors.surface-raised}"
    textColor: "{colors.text-primary}"
    rounded: "{rounded.lg}"
    padding: "{spacing.panel-padding}"
  mana-chip:
    backgroundColor: "{colors.surface-muted}"
    textColor: "{colors.text-primary}"
    typography: "{typography.card-meta}"
    rounded: "{rounded.full}"
    padding: 6px
  action-primary-hover:
    backgroundColor: "{colors.accent-strong}"
    textColor: "{colors.background}"
    typography: "{typography.label}"
    rounded: "{rounded.md}"
    height: "{spacing.touch-target}"
    padding: 12px
  zone-header:
    backgroundColor: transparent
    textColor: "{colors.text-secondary}"
    typography: "{typography.label}"
    rounded: "{rounded.sm}"
    padding: 4px
  selected-game-zone:
    backgroundColor: "{colors.surface-raised}"
    textColor: "{colors.text-primary}"
    rounded: "{rounded.md}"
    padding: "{spacing.zone-padding}"
  status-success:
    backgroundColor: "{colors.success}"
    textColor: "{colors.background}"
    typography: "{typography.label}"
    rounded: "{rounded.md}"
    padding: 8px
  status-danger:
    backgroundColor: "{colors.danger}"
    textColor: "{colors.background}"
    typography: "{typography.label}"
    rounded: "{rounded.md}"
    padding: 8px
  mana-white-chip:
    backgroundColor: "{colors.mana-white}"
    textColor: "{colors.background}"
    typography: "{typography.card-meta}"
    rounded: "{rounded.full}"
    padding: 6px
  mana-blue-chip:
    backgroundColor: "{colors.mana-blue}"
    textColor: "{colors.background}"
    typography: "{typography.card-meta}"
    rounded: "{rounded.full}"
    padding: 6px
  mana-black-chip:
    backgroundColor: "{colors.mana-black}"
    textColor: "{colors.text-primary}"
    typography: "{typography.card-meta}"
    rounded: "{rounded.full}"
    padding: 6px
  mana-red-chip:
    backgroundColor: "{colors.mana-red}"
    textColor: "{colors.background}"
    typography: "{typography.card-meta}"
    rounded: "{rounded.full}"
    padding: 6px
  mana-green-chip:
    backgroundColor: "{colors.mana-green}"
    textColor: "{colors.background}"
    typography: "{typography.card-meta}"
    rounded: "{rounded.full}"
    padding: 6px
  mana-colorless-chip:
    backgroundColor: "{colors.mana-colorless}"
    textColor: "{colors.background}"
    typography: "{typography.card-meta}"
    rounded: "{rounded.full}"
    padding: 6px
---

## Overview

MagicMobile is a native iPhone Commander client, not a desktop control panel
compressed onto a phone. It should feel crafted, tactical, and immediately
playable. The visual language is refined rustic fantasy: charred oak, worn
leather, aged brass, iron, and parchment. Ornament is restrained so the cards,
current decision, and legal actions remain the focus.

The home experience is calm and simple. Setup is guided. Gameplay is dense only
where the rules demand it, with stable controls and a board-first hierarchy in
both portrait and landscape.

## Colors

The palette is built around charred wood and near-black iron, with parchment
text and aged-brass interaction accents. Deep moss is a supporting battlefield
tone, not the generic panel color.

- **Background:** Used behind full board and play surfaces.
- **Surface:** Used for zones, panels, and dense game-state containers.
- **Accent:** Reserved for primary legal actions, current prompts, and active
  selections.
- **Magic state colors:** Emerald means priority/ready, amber means waiting,
  oxblood means danger, and arcane blue means stack or spell information.
- **Mana colors:** Used only for mana identity, costs, and resource indicators;
  do not recolor generic UI with mana colors.
- **Danger and success:** Used for destructive actions, errors, resolved checks,
  and health/status feedback.

## Typography

Use the native system serif face for brand, screen, and major section titles.
Use the default system face for controls, body copy, numbers, and game data.
This keeps the medieval personality without sacrificing scan speed or Dynamic
Type support. Gameplay labels may be compact, but never below 11pt for essential
information. Do not use oversized marketing headlines inside gameplay surfaces.

## Layout

### Home

- Present one dominant `Play Commander` action.
- Show the current player/deck and resumable game as compact supporting cards.
- Move server, asset-cache, and orientation controls into Settings.
- Surface connection problems as a concise badge or dismissible message; never
  let technical status compete with the product title.

### Setup

- Use three explicit steps: `Player & Deck`, `Opponent`, and `Review`.
- Keep Back and Continue/Start in stable positions.
- Reveal advanced bridge and cache details only on demand.
- State the selected player, decks, difficulty, avatar, and rules before Start.

### Gameplay

- Gameplay is board-first. Preserve stable zone dimensions and avoid layout
  shifts during prompts.
- Keep the hand and primary legal actions in thumb reach.
- Show the current phase and priority persistently, but make the full game log
  on demand. A single latest-event chip may remain visible.
- Never show conflicting states such as `Wait` while also declaring `Your
  decision`.
- Tap is the complete interaction path. Drag may be a shortcut, but no action
  can require drag alone.

### Orientation

Portrait and landscape expose the same information and actions. They may
recompose, but neither orientation may lose prompts, zone access, stack access,
timing controls, player status, or game-log access. Landscape should increase
board space rather than adding permanent developer panels.

## Elevation & Depth

Use material gradients only to imply oak, leather, iron, or brass. Keep them
subtle. Tonal separation and thin brass borders do most of the work. Standard
panels use a short soft shadow; only decision sheets and floating controls use
the elevated shadow. Overlays and prompts must not obscure the active source,
target, or choice without a clear resolution path.

## Shapes

Use 8-12pt radii for dense gameplay surfaces, 14-18pt for sheets, and 20pt only
for a home hero panel. Pills are reserved for statuses, filters, and compact
metadata. Cards, zones, prompts, and buttons should feel tactile but not bubbly.

## Components

Primary actions use the accent token and should appear only when the player can
take an important legal action. Secondary actions use muted surfaces. Game
zones should show their purpose, count, and relevant state without requiring a
modal. Mana chips must stay visually tied to actual mana information.

Native implementation uses `GameBoardTheme.current` for semantic color and
material values, `GameBoardDesignTokens.current` for dimensions and motion, and
the reusable `magicPanel`, `magicBadge`, `MagicPrimaryButtonStyle`,
`MagicSecondaryButtonStyle`, and `MagicIconButtonStyle` primitives. Feature
views should not introduce raw rustic colors when one of these semantics fits.

## Do's and Don'ts

- Do preserve card readability and board-state scanability.
- Do use mana colors only for mana-related meaning.
- Do keep touch targets at least 44px when an action can change game state.
- Do keep prompt and stack UI visually distinct from passive board information.
- Do use the serif face sparingly for brand and hierarchy, not dense rules text.
- Do keep status colors semantic and consistent.
- Don't introduce glass effects or decorative texture over card art.
- Don't add large hero treatment inside gameplay surfaces.
- Don't hide legal actions behind vague icon-only controls.
- Don't let overlays cover the selected source, target, or active prompt.
- Don't make server health, cache counts, or cleanup errors the primary content
  of the home screen.
- Don't require a gesture that has no tap alternative.
