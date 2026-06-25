# iOS Game Board Layout Spec

## Device And Canvas

- Target device: iPhone 16 Pro Max landscape.
- MagicPath frame size: `956 x 440` points.
- Treat the outer `8px top/bottom` and `18px left/right` in MagicPath as safe-area-aware guard rails.
- Use responsive SwiftUI sizing later, but preserve the MagicPath proportions.

## Board Root

`MM.BoardRoot` owns the full landscape game surface. It should contain no production game logic by itself; it coordinates visual zones and state overlays.

`MM.BattlefieldSurface` is the rustic dark stone / magical tabletop surface. It can include subtle texture, rune line, warm gold trim, dark leather/wood undertones, and blue/green magical atmosphere. It must not become a flat background screenshot.

## Top-Left Opponent Vertical HUD

`MM.OpponentVerticalHUD` sits in the top-left as a narrow vertical control. It includes:

- opponent avatar/icon
- opponent name
- life total
- commander badge/count
- hand count
- library count
- graveyard count
- exile count
- optional status/timer

It must not become a horizontal top bar.

## Opponent Battlefield

`MM.OpponentBattlefieldCards` occupies the upper battlefield, beginning right of the opponent HUD. Cards are slightly smaller than player cards. There should be no large visible battlefield box in idle states; spacing, shadows, and scale imply the lane.

## Player Battlefield

`MM.PlayerBattlefieldCards` occupies the lower half above the hand rail. Creatures sit closer to center, lands/mana sources lower, and commander/important permanents may carry small badges. No visible grid or drop box should appear unless the player is dragging.

## Bottom Hand Rail

`MM.PlayerHandRail` runs along the bottom with a slight fan/curve and modest overlap. Cards must remain readable and tappable. `MM.SelectedCardLift` lifts and glows the selected card without covering the primary flow button or prompt overlays.

## Right Phase Rail

`MM.RightPhaseRail` is a compact right-side/corner rail. It includes:

- Beginning
- Main
- Combat
- Second Main
- End

The current phase glows. It must not become a wide phase bar across the middle.

## Primary Flow Button

`MM.PrimaryFlowButton` is the only large game-flow button. It changes label by game state: `Pass`, `Next`, `Resolve`, `Done`, `Continue`, or `Submit`. It should never be duplicated into a row of cast/tap/action buttons.

## Right Transparent Game Log

`MM.RightTransparentGameLog` is a compact dark glass panel on the right side. It shows the latest 4 to 8 events and can expand to a full log sheet. It should remain transparent enough to feel like an overlay, but readable over the board.

## Stack

`MM.StackMiniIndicator` is a compact indicator for top stack object, stack count, source, and active glow. `MM.StackExpandedSheet` is used only when the user opens the stack.

## Zone Chips

`MM.ZoneChips` owns the tucked chips/icons for stack, command, graveyard, exile, library, log, and settings/debug. Chips include:

- `MM.CommandZoneChip`
- `MM.GraveyardChip`
- `MM.ExileChip`
- `MM.LibraryChip`
- `MM.DebugSheet`

These should stay small and out of the main card lanes.

## Drag-Only Drop Zones

Drop zones must be visible only in `Dragging Card / Drop Zones Visible`.

- `MM.DragGhostCard` follows the dragged card.
- `MM.DragDropZoneCast` marks valid cast/play area.
- `MM.DragDropZoneBattlefield` marks valid permanent/battlefield landing.
- `MM.ValidTargetGlow` marks valid target cards or players.
- `MM.InvalidTargetDim` dims invalid targets with danger red treatment.

Idle frames should not show large battlefield/drop boxes.

## Prompt Overlays

`MM.PromptOverlay` appears only when XMage asks for input. Required prompt variants:

- `MM.ManaPrompt`
- `MM.SearchPrompt`
- `MM.CommanderReplacementPrompt`
- `MM.DamageAssignmentPrompt`
- stack response prompt using `MM.PromptOverlay` and `MM.StackExpandedSheet`
- `MM.AIThinkingStatus`
- `MM.BridgeStatusPill`
- `MM.UnsupportedPromptFallback`

All prompts preserve fail-closed behavior: no hidden defaults and no submit until valid.
