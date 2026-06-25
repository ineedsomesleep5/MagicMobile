# MagicMobile Magic Path Handoff

This folder is the editable design handoff for the iOS Commander board. It is meant for Magic Path visual editing, then Codex can map the approved design back into SwiftUI without changing XMage gameplay behavior.

## Live Magic Path canvas

- Project: `MagicMobile iPhone 16 Pro Max Landscape Board`
- Current file URL: https://www.magicpath.ai/files/420728834988597248
- Prior project URL: https://www.magicpath.ai/files/420718288578945024
- Main frame/component: `Normal Battlefield`
- Main component id: `420728860716449792`
- Main generated name: `eager-tower-7952`
- Current edited frame: `Dragging Card / Drop Zones Visible`
- Current edited frame id: `420729376641007616`
- Current edited frame generated name: `sweet-week-7067`

Use the live canvas for visual editing. Keep this folder as the repo-side source of truth for layer names, design tokens, and SwiftUI binding notes.

The current Magic Path file contains these handoff frames:

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

## What to edit in Magic Path

- Move and resize `MM.*` layers in `board-blueprint.svg`.
- Tune panel shapes, borders, spacing, shadows, and glow strength.
- Adjust the rustic fantasy theme through `design-tokens.json`.
- Replace decorative placeholder vectors in `assets/` with approved original decorative frames.
- Keep all layer names stable, especially `MM.HandRail`, `MM.PromptPanel`, `MM.PhasePriorityBar`, and `MM.CenterStackStrip`.

## What not to edit

- Do not turn cards, prompts, legal actions, stack objects, or zone sheets into static art.
- Do not add Wizards logos, official Magic branding, Arena assets, or copied game-board art.
- Do not encode card-specific production logic in the design.
- Do not hide required safety/status surfaces: bridge source, pending/waiting state, unsupported prompt fallback, and refresh/reconnect controls.
- Do not remove space for any prompt family listed in `layout-map.json`.

## Export naming

Use these names for exported assets so Codex can wire them back predictably:

- `mm-background-board.svg`
- `mm-parchment-panel.svg`
- `mm-wood-panel.svg`
- `mm-leather-panel.svg`
- `mm-gold-frame.svg`
- `mm-button-frame.svg`
- `mm-zone-chip.svg`
- `mm-prompt-panel.svg`
- `mm-action-button.svg`

If Magic Path exports a complete frame, name it:

- `MagicMobile-iPhone-Pro-Max-Landscape-Board.svg`

## How Codex will wire it back

Codex will read:

- `layout-map.json` for the SwiftUI component/data binding of each `MM.*` layer.
- `design-tokens.json` for colors, radii, spacing, shadows, z-order, and typography.
- exported SVG assets for decorative frames only.

The SwiftUI implementation must continue to render live `GameSnapshot` data and submit real XMage commands through the existing bridge. The approved Magic Path design should change visual layout and styling, not the gameplay engine.

## Manual import

If Magic Path CLI is not authenticated, import `board-blueprint.svg` manually into Magic Path and keep the group names intact. Then upload or reference `design-tokens.json` and `layout-map.json` beside the canvas as implementation notes.

## SwiftUI design preview mode

The iOS app has a DEBUG-only preview mode for visual/layout work. It uses mock `GameSnapshot` data and must not be used as gameplay proof.

Example launch environment:

```bash
SIMCTL_CHILD_MAGICMOBILE_DESIGN_PREVIEW=mana-payment-prompt \
xcrun simctl launch --terminate-running-process <sim-udid> com.calebfeliciano.magicmobile
```

Available preview states:

- `normal-battlefield`
- `selected-card-action-tray`
- `mana-payment-prompt`
- `search-select-prompt`
- `stack-response-prompt`
- `commander-replacement-prompt`
- `damage-assignment-prompt`
- `ai-thinking`
- `bridge-unavailable`
- `missing-card-art`

The app shows a visible `DESIGN PREVIEW` badge in this mode. Real XMage validation still requires the `commander-full-ai` smoke gate.

## Magic Path frame to SwiftUI state map

| Magic Path frame or expected state | SwiftUI surface/state | Data source or command shape | Handoff note |
|---|---|---|---|
| Normal Battlefield | `NativeGameView`, battlefield rows, HUDs, phase/status rail | `GameSnapshot` with live `source`, `bridgeRevision`, `xmageCycle`, priority and zones | Default board. No static card art or mock gameplay. |
| Selected Card | selected card state, inspector/action section | selected hand/battlefield card plus matching `LegalAction`s | Show exact actions for the selected card; long press can inspect. |
| Stack Response Prompt | `UniversalPromptActionPanel`, stack peek/sheet | stack objects, `pass_priority`, response legal actions, prompt envelope | Keep respond/pass controls ahead of secondary zone chips. |
| Dragging Card / Drop Zones Visible | card selection/drag affordance over legal zones | legal action ids for playable card or targetable object | Drop zones are visual affordances only; command submission still uses exact XMage ids. |
| Search Library Prompt | zone/search sheet and card picker | `choose_card`, `search_select`, or search-like `choose_target` options | Never pick the first legal card automatically. |
| Mana Payment Prompt | mana pool/source panel and payment buttons | `play_mana`, `choose_mana`, `pay_cost`, visible mana choices/sources | Do not invent colors or colorless mana when XMage exposes none. |
| Commander Replacement Prompt | replacement choice panel | `commander_replacement` with explicit command-zone/original-zone choice | Do not default to command zone. |
| Damage Assignment Prompt | allocation controls | `damage_assignment` or combat `choose_multi_amount` metadata | Require explicit per-defender/blocker amounts. |
| AI Thinking / Waiting | waiting toast/status pill | `pendingStatus`, `priorityPlayerId`, `waitingOnPlayerId`, health/live update state | Show waiting honestly; do not imply the game is frozen. |
| Bridge Unavailable / Reconnect | setup/status/reconnect surface | gateway health, WebSocket status, refresh/reconnect action | Refresh/reconnect only; no simulator fallback on `/play`. |
| Choose Mode | prompt option grid | `choose_mode` | Explicit user choice only. |
| Choose Ability | ability picker | `choose_ability` with ability id | Preserve exact ability UUID labels/ids. |
| Choose Amount | amount stepper/input | `choose_amount` or `play_x_mana` | Require a finite explicit amount. |
| Choose Pile | pile picker | `choose_pile` | Disable ambiguous piles; never default to pile 1. |
| Choose Player | player option grid | `choose_player` | Submit exact XMage player UUID. |
| Choose Card | card option grid/sheet | `choose_card` | Submit exact exposed card UUID only. |
| Order Triggers / Items | ordering list with up/down controls | `order_triggers` / `order_items` with `orderedIds` | Submit only the displayed ordered id list. |
| Declare Attackers / Blockers | combat assignment controls | `declare_attackers` / `declare_blockers` pair payloads | Keep current generic action path until richer combat UI lands. |
| Unsupported / Stale / Reconnect | fail-closed prompt/status section | unknown prompt, stale revision/prompt id, health unavailable/stalled | Show refresh/reconnect or unsupported state; never auto-answer. |

## Magic Path component references

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
