# Implementation Notes For Future Codex

This file is for the future Codex session that is connected to the MagicMobile app codebase. This current commit is documentation/design handoff only.

## Source

Use `design/magic-path/MAGICPATH_BOARD_HANDOFF.md` and MagicPath project `420728834988597248` / component `eager-tower-7952` as the visual source of truth.

The current Caleb-reviewed frame is `Dragging Card / Drop Zones Visible` / `420729376641007616` / `sweet-week-7067`.

## Implementation Rules

- Do not copy the MagicPath board as one flat PNG.
- Implement it as real SwiftUI components.
- Use MagicPath for layout, sizing, colors, spacing, and decorative visual direction.
- Cards, prompts, buttons, stack, hand, zones, and actions must remain live components.
- Preserve `MM.*` layer meanings from `layout-map.json` when naming/refactoring SwiftUI views.
- Keep `/play` real-XMage-only.
- Keep `/dev/play-simulator` dev-only.
- Preserve fail-closed prompt behavior.
- Preserve commander-full-ai backend proof.
- Do not touch XMage backend, bridge, or gateway unless a later task explicitly asks.

## Prompt Behavior That Must Survive

- no default yes
- no default colorless
- no default amount `0`
- no default pile `1`
- no default command zone
- no auto-pick first option
- unknown prompt fallback visible and safe
- submit disabled until valid

## Next Implementation Step

Refactor SwiftUI board zones to match MagicPath:

1. Board root and battlefield surface.
2. Top-left opponent vertical HUD.
3. Upper opponent battlefield cards.
4. Lower player battlefield cards.
5. Bottom hand rail with drag interactions.
6. Right phase rail.
7. Transparent right game log.
8. Compact stack indicator and stack sheet.
9. Zone chips and sheet routing.
10. Prompt overlays and prompt-specific views.
11. Bridge/AI status pills and reconnect fallback.

Do this while preserving all existing XMage command, prompt, stack, and zone functionality.
