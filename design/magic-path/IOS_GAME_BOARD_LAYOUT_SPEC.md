# iOS Game Board Layout Spec

Target device: iPhone 16 Pro Max landscape when available; otherwise the closest installed Pro Max simulator or physical iPhone.

Design canvas: approximately `956 x 440` points. Leave flexible margins for Dynamic Island, rounded corners, and the home indicator. The current simulator used during this pass was iPhone 17 Pro Max, captured as a rotated landscape frame for visual review.

Current Magic Path file: https://www.magicpath.ai/files/420728834988597248

Current handoff frames:

- Normal Battlefield
- Selected Card
- Stack Response Prompt
- Dragging Card / Drop Zones Visible
- Search Library Prompt
- Mana Payment Prompt
- Commander Replacement Prompt
- Damage Assignment Prompt
- AI Thinking / Waiting
- Bridge Unavailable / Reconnect

## Screen zones

- Top: opponent HUD with AI life, commander, library/hand/graveyard/exile chips, and compact bridge/live status.
- Upper middle: opponent battlefield and lands with compact rows and no prompt overlap.
- Center: stack strip, phase/priority strip, and current prompt summary.
- Lower middle: player battlefield and lands with selected permanent highlight and visible mana sources.
- Bottom: hand rail, selected card primary action, compact action tray, mana pool, and pass priority.
- Sheets: full stack, command zone, graveyard, exile, card inspector, full action list, and game log.

## Required safe areas

- Keep primary controls away from the Dynamic Island side cutout.
- Keep hand and action tray above the home indicator.
- Avoid permanent overlays on the card rows.
- Put debug-style details behind compact pills or sheets.

## Prompt families requiring UI space

- choose target
- choose card
- choose player
- choose mode
- choose ability
- choose amount
- choose multi-amount
- choose pile
- order triggers/items
- search select
- commander replacement
- mana/payment
- declare attackers
- declare blockers
- damage assignment as multi-amount
- stack response/pass priority
- unknown prompt fallback

## SwiftUI frame/state mapping

| Frame or explicit state | SwiftUI target | Expected behavior |
|---|---|---|
| Normal Battlefield | `NativeGameView` board rows, HUDs, phase/status rail | Render authoritative `GameSnapshot` state with bridge/source/revision visible. |
| Selected Card | selected-card action/inspector state | Surface exact legal actions for the selected card without hiding priority controls. |
| Stack Response Prompt | `UniversalPromptActionPanel` plus stack peek/sheet | Show stack object context, pass/respond actions, and current prompt identity. |
| Dragging Card / Drop Zones Visible | card selection/drag affordance | Highlight only legal destinations; submit exact XMage ids through the existing command path. |
| Search Library Prompt | search/card picker sheet | Map search/select, choose-card, or search-like choose-target prompts to explicit card choices. |
| Mana Payment Prompt | mana pool/source/payment controls | Use explicit `manaChoices`, visible floating mana, or legal mana-source actions only. |
| Commander Replacement Prompt | replacement choice controls | Require explicit command-zone/original-zone choice. |
| Damage Assignment Prompt | allocation controls | Require explicit damage or multi-amount allocation before submit. |
| AI Thinking / Waiting | waiting/status pill | Show pending/waiting/reconnecting state without blocking the board. |
| Bridge Unavailable / Reconnect | setup/status/reconnect surface | Offer refresh/reconnect and keep `/play` honest about bridge health. |
| Choose Mode | option grid | Submit exact `choose_mode` option. |
| Choose Ability | ability picker | Submit exact `choose_ability` id. |
| Choose Amount | stepper/input | Submit explicit finite `choose_amount` or `play_x_mana` value. |
| Choose Pile | pile picker | Submit explicit `choose_pile`; no default pile. |
| Choose Player | player picker | Submit exact player UUID. |
| Choose Card | card picker | Submit exact card UUID. |
| Order Triggers / Items | reorder list | Submit displayed `orderedIds` only. |
| Declare Attackers / Blockers | combat assignment action UI | Submit attacker/defender or blocker/attacker pairs when exposed. |
| Unsupported / Stale / Reconnect | fail-closed status/prompt section | Refresh/reconnect or show unsupported; never auto-pick a gameplay answer. |

## Visual direction

The board should feel like a readable mobile tabletop fantasy game: dark leather edges, carved wood rails, aged parchment panels, warm gold highlights, subtle emerald/arcane blue state indicators, and restrained texture. Readability wins over decoration.
