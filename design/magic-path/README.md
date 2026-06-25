# MagicPath iPhone Board Design

This folder records the approved MagicPath design source for the MagicMobile iPhone board. It is a design handoff only; it does not implement SwiftUI and does not change XMage gameplay, bridge, gateway, or shared package behavior.

## Source Of Truth

- MagicPath project name: `MagicMobile iPhone 16 Pro Max Landscape Board`
- MagicPath project ID: `420728834988597248`
- MagicPath project URL: `https://www.magicpath.ai/files/420728834988597248`
- Main frame/component: `Normal Battlefield`
- Main component ID: `420728860716449792`
- Main generated name: `eager-tower-7952`
- Current edited frame Caleb is reviewing: `Dragging Card / Drop Zones Visible`
- Current edited frame ID: `420729376641007616`
- Current edited frame generated name: `sweet-week-7067`
- Target size: `956 x 440` points, iPhone 16 Pro Max landscape approximation

## Frames And States

| State | Component ID | Generated name |
| --- | --- | --- |
| Normal Battlefield | `420728860716449792` | `eager-tower-7952` |
| Dragging Card / Drop Zones Visible | `420729376641007616` | `sweet-week-7067` |
| Selected Card | `420729389609795584` | `cleverly-tide-3424` |
| Mana Payment Prompt | `420729401509023744` | `safely-garden-7226` |
| Search Library Prompt | `420729414448467968` | `steady-river-7644` |
| Stack Response Prompt | `420729424338628608` | `eagerly-river-8898` |
| Commander Replacement Prompt | `420729435940089856` | `cleverly-autumn-9282` |
| Damage Assignment Prompt | `420729447843528704` | `lively-sand-1892` |
| AI Thinking / Waiting | `420729460581601280` | `clear-week-6056` |
| Bridge Unavailable / Reconnect | `420729482081615872` | `kind-forest-2398` |

## Caleb Manual Edit Notes

Caleb's latest MagicPath canvas edits are the visual source of truth, especially the `Dragging Card / Drop Zones Visible` frame. Preserve:

- clean, wide battlefield with no large idle boxes
- vertical top-left opponent HUD
- right-side phase rail
- right-side transparent log
- bottom hand rail
- drag/drop zones visible only in the dragging frame
- named `MM.*` layer/component hooks for SwiftUI mapping

## How Future Codex Should Use This

The repo-connected Codex session should inspect `MAGICPATH_BOARD_HANDOFF.md`, `IOS_GAME_BOARD_LAYOUT_SPEC.md`, `design-tokens.json`, and `layout-map.json`, then use MagicPath project `420728834988597248` and component `eager-tower-7952` as the visual source of truth.

The future implementation should refactor the iOS SwiftUI board into live components that match the MagicPath layout. It must not copy the board as a single static image.

## Safe Manual Edits In MagicPath

- visual spacing and safe-area padding
- card rail curve and overlap
- fantasy trim, texture, glass, parchment, and glow intensity
- prompt overlay placement and copy clarity
- preview card labels and placeholder art treatments

## Do Not Manually Edit

- `MM.*` layer names
- frame/state names or component ID references in these docs
- rule that drop zones only appear during dragging
- fail-closed prompt behavior
- one-primary-flow-button interaction model
- live component separation between cards, zones, prompts, stack, log, and actions

## Exports

Preview PNGs and MagicPath metadata are under `design/magic-path/exports/`. MagicPath CLI provided preview image URLs and inspectable source; it did not expose a dedicated SVG or raw canvas JSON export command.
