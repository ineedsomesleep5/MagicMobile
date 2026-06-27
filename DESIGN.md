---
version: alpha
name: MagicMobile
description: "A dense, playable Magic: The Gathering interface for mobile, web, and XMage-backed game flows."
colors:
  primary: "#d8b45a"
  background: "#07120f"
  surface: "#101c18"
  surface-raised: "#16251f"
  surface-muted: "#22332c"
  text-primary: "#f3efe2"
  text-secondary: "#c9c0aa"
  accent-strong: "#f1cc6b"
  danger: "#d95f54"
  success: "#65b783"
  mana-white: "#f4ead0"
  mana-blue: "#78a8d8"
  mana-black: "#37323a"
  mana-red: "#d66f53"
  mana-green: "#72a766"
  mana-colorless: "#b8b1a2"
typography:
  headline:
    fontFamily: Inter
    fontSize: 28px
    fontWeight: 700
    lineHeight: 1.15
    letterSpacing: 0em
  title:
    fontFamily: Inter
    fontSize: 18px
    fontWeight: 700
    lineHeight: 1.25
    letterSpacing: 0em
  body:
    fontFamily: Inter
    fontSize: 15px
    fontWeight: 400
    lineHeight: 1.4
    letterSpacing: 0em
  label:
    fontFamily: Inter
    fontSize: 12px
    fontWeight: 700
    lineHeight: 1.2
    letterSpacing: 0.04em
  card-meta:
    fontFamily: Inter
    fontSize: 11px
    fontWeight: 600
    lineHeight: 1.2
    letterSpacing: 0em
rounded:
  sm: 4px
  md: 8px
  lg: 12px
  full: 9999px
spacing:
  unit: 8px
  board-gap: 8px
  zone-padding: 10px
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

MagicMobile should feel like a serious tabletop companion: compact, readable,
and action-focused. The interface must prioritize board comprehension over
decoration. The product personality is tactical and warm, using dark playmat
surfaces, readable card zones, and restrained gold highlights for meaningful
actions.

## Colors

The palette is built around a dark green-black playmat foundation with parchment
text and a single gold interaction accent.

- **Background:** Used behind full board and play surfaces.
- **Surface:** Used for zones, panels, and dense game-state containers.
- **Accent:** Reserved for primary legal actions, current prompts, and active
  selections.
- **Mana colors:** Used only for mana identity, costs, and resource indicators;
  do not recolor generic UI with mana colors.
- **Danger and success:** Used for destructive actions, errors, resolved checks,
  and health/status feedback.

## Typography

Typography must stay compact and legible on mobile. Use heavier labels for
zone headers, legal actions, and card metadata. Do not use oversized marketing
headlines inside gameplay surfaces.

## Layout

Gameplay layout is board-first. Preserve stable zone dimensions, avoid layout
shift during prompts, and keep the most likely legal actions within easy thumb
reach. Dense panels should group related state tightly while leaving enough
space for card names and action text to remain readable.

## Elevation & Depth

Use tonal separation, borders, and active highlights instead of heavy shadows.
Overlays and prompt panels may sit above the board, but they must not obscure
the active choice without a clear dismissal or resolution path.

## Shapes

Use small radii for dense gameplay surfaces. Cards, zones, prompts, and buttons
should feel tactile but not bubbly. Keep repeated board items consistent so
players can scan them quickly.

## Components

Primary actions use the accent token and should appear only when the player can
take an important legal action. Secondary actions use muted surfaces. Game
zones should show their purpose, count, and relevant state without requiring a
modal. Mana chips must stay visually tied to actual mana information.

## Do's and Don'ts

- Do preserve card readability and board-state scanability.
- Do use mana colors only for mana-related meaning.
- Do keep touch targets at least 44px when an action can change game state.
- Do keep prompt and stack UI visually distinct from passive board information.
- Don't introduce decorative gradients, glass effects, or large hero treatment
  inside gameplay surfaces.
- Don't hide legal actions behind vague icon-only controls.
- Don't let overlays cover the selected source, target, or active prompt.
