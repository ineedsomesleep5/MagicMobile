# iOS Gameplay Layout Plan

## Scope

This plan audits the current native iOS landscape gameplay screen and defines a concrete named-region layout contract for the implementation pass. It is based on the current SwiftUI code in `apps/ios/MagicMobile/ContentView.swift`, with model/API context from `Models.swift` and `MagicMobileAPI.swift`.

The implementation goal is not a visual redesign. The goal is to stop critical gameplay surfaces from competing for the same pixels on iPhone landscape by giving each surface a reserved rectangle, a predictable overflow rule, and a small set of measurable pass/fail checks.

## Current Major Elements

- Top HUD: `TurnStatusBadge`, `LiveUpdateBadge`, and `GameDiagnosticsBadge` are placed near `topHUDY`.
- Opponent HUD: compact `PlayerHeroHUD` for "Noaddrag" near the top-left play area.
- Player HUD: compact `PlayerHeroHUD` for "TabletopPolish" near the lower-left, above the hand.
- Opponent board and lands: two `BattlefieldRow` views for non-land permanents and lands.
- Player board and lands: two `BattlefieldRow` views for non-land permanents and lands.
- Center prompt and stack: `PromptPill` sits on the battlefield center line, while `XmageStackPeek` or `StackPeek` is nearby.
- Phase rail: `CompactPhaseRail` plus log/settings buttons sit in a narrow right rail.
- Right prompt/action panel: `UniversalPromptActionPanel` includes surfaces, prompt controls, choice controls, action sections, mana/payment controls, command/grave/exile/stack chips, and mini zone rows.
- Hand fan: `HandFan` uses a card fan anchored to the bottom play area and also owns drag-to-play behavior.
- Mana HUD: `ManaPoolHUD` floats above player lands.
- Command/grave/exile/stack surfaces: summarized inside `MobileSurfacesPanel`, with full-zone presentation through `ZoneInspectorSheet`.
- Inspector/log/pending: `CardInspector`, `GameLogDrawer`, and the "Waiting for XMage" pending toast are additional floating overlays.

## Current Collision And Crowding Causes

- The gameplay screen is a single absolute-positioned `ZStack`. Most elements use `.position(...)`, so visual priority is implicit and there is no central overlap policy.
- `BattlefieldLayoutMetrics` reserves a right action dock and right rail first, then gives the remainder to `playWidth`. On narrow landscape widths, battlefield rows, prompt, stack, top HUD, and hand all compress together.
- The center lane is overloaded. `centerLineY` is used for both the battlefield divider and `PromptPill`, while stack peek sits close to the same space. Any stack prompt, pending toast, or long prompt text can cover battlefield cards.
- The right side is double-booked. `phaseRailRect` and action dock are separate, but the action panel can grow to 340 pt high and is centered near the bottom, which can collide visually with hand/player-land territory.
- The top HUD area has several independent elements: turn badge, live badge, diagnostics badge, and opponent HUD. These are not treated as a unified top status region, so diagnostics can drift into battlefield rows.
- The player bottom zone is overloaded by player HUD, mana HUD, player lands, selected hand card lift, drag target highlight, and pending toast.
- The hand fan has dynamic spread, scale, rotation, and selected-card lift. Its visual bounds exceed `handFrameHeight`, so nearby bottom HUD and action panel calculations can be optimistic.
- Battlefield rows horizontally scroll and use negative card spacing. This preserves access to wide boards, but dense rows can still hide board state because all rows share a small vertical budget.
- `UniversalPromptActionPanel` mixes critical actions, optional surfaces, mini zone previews, and prompt-specific controls in one scroll view. It can be correct functionally but still feel crowded because high-priority buttons are not visually separated from secondary surfaces.
- Inspector and log are floating overlays without reserved detail space. They can cover battlefield rows or the right dock depending on current card/log state.
- Zone surfaces are duplicated conceptually: stack can appear as a battlefield peek, a surfaces chip/mini row, a sheet, and possibly prompt text. This adds cognitive and spatial noise.

## Target Named Regions

Implement a replacement metrics contract that produces named rects from `safeFrame`, then place existing views inside those rects. Keep the names stable so later tests can assert geometry without snapshot brittle UI tests.

Assume iPhone 16 Pro Max landscape first:

- Logical viewport: about `956 x 440` pt in landscape.
- Safe frame: derive from `GeometryProxy.safeAreaInsets`; do not hard-code Dynamic Island or home indicator values.
- Minimum content gap: `8` pt.
- Preferred battlefield card aspect ratio: `1.40`.
- Preferred touch target: `44 x 44` pt for primary controls, `32 x 32` pt minimum for rail icon buttons.

### `safeFrame`

Definition:

- `safeFrame = CGRect(x: safe.leading + 8, y: safe.top + 6, width: size.width - safe.leading - safe.trailing - 16, height: size.height - safe.top - safe.bottom - 12)`

Rules:

- All named regions must be contained by `safeFrame` except transient drag cards, which may temporarily overlap while dragging.
- If `safeFrame.width < 760` or `safeFrame.height < 360`, enter compact fallback mode.

### `rightDockRect`

Purpose: right prompt/action panel.

Sizing:

- Width: `clamp(safeFrame.width * 0.24, 220, 286)`.
- Height: from below `topStatusRect` to above `bottomActionRect`, with an 8 pt gap.
- X: pinned to `safeFrame.maxX`.

Rules:

- This is the only permanent right-side action panel.
- `UniversalPromptActionPanel` should fill this rect and keep internal scroll.
- Primary pass/confirm/cast actions should remain at the top of the panel or be repeated in `bottomActionRect` when available.
- `MobileSurfacesPanel` should be collapsible or placed below primary prompt controls, not above them, when a prompt is active.

### `phaseRailRect`

Purpose: compact phase/status rail and log/settings buttons.

Sizing:

- Width: `56` pt preferred, `48` pt compact.
- Height: `min(210, rightDockRect.height)`.
- Position: immediately left of `rightDockRect`, aligned to `topStatusRect.maxY + 8`.

Rules:

- The rail must not reduce battlefield width below `420` pt in iPhone 16 Pro Max landscape.
- In compact fallback, merge the rail into the top of `rightDockRect` and hide the separate rail column.

### `topStatusRect`

Purpose: unified top HUD strip.

Sizing:

- X: `safeFrame.minX`.
- Y: `safeFrame.minY`.
- Width: from `safeFrame.minX` to `phaseRailRect.minX - 8` or `rightDockRect.minX - 8` if rail is merged.
- Height: `52` pt preferred, `44` pt compact.

Rules:

- `TurnStatusBadge` owns the center of this rect.
- Opponent `PlayerHeroHUD` owns the leading side.
- `LiveUpdateBadge` and `GameDiagnosticsBadge` should be collapsed into one trailing diagnostics pill in this rect. Full diagnostics can move to log/detail sheet.
- Nothing in this rect may overlap battlefield rows.

### `handRect`

Purpose: visual hand fan and drag origin.

Sizing:

- Height: `min(max(safeFrame.height * 0.27, 106), 128)` preferred.
- Width: battlefield column width, not including right dock/rail.
- X: `safeFrame.minX`.
- Y: `safeFrame.maxY - handHeight`.

Rules:

- Hand visual overflow may extend upward by at most `36` pt for selected/dragged cards.
- No persistent HUD or toast should sit inside the top `36` pt overflow band.
- If hand has more than 9 cards, reduce rotation first, then card width; do not let cards push above `playerLandsRect`.

### `bottomActionRect`

Purpose: high-priority transient action/status area.

Sizing:

- X: `safeFrame.minX`.
- Y: `handRect.minY - 46`.
- Width: battlefield column width.
- Height: `40` pt.

Rules:

- Use for pending toast, compact pass/confirm action, or one-line human prompt status.
- Never stack `PromptPill` and pending toast in separate center overlays. In pending state, replace the bottom action content with waiting status.
- In compact fallback, bottom actions may overlay the hand only as a translucent one-line bar pinned to `handRect.minY`.

### Battlefield Column

Definition:

- `battlefieldColumnRect = CGRect(x: safeFrame.minX, y: topStatusRect.maxY + 8, width: phaseRailRect.minX - safeFrame.minX - 8, height: bottomActionRect.minY - topStatusRect.maxY - 16)`
- If rail is merged, use `rightDockRect.minX - safeFrame.minX - 8` for width.

Rules:

- Minimum usable width: `420` pt preferred, `360` pt compact.
- Minimum usable height: `210` pt preferred, `180` pt compact.
- The battlefield column is the only owner of board rows, center prompt/stack, player HUD, opponent HUD if not in top status, and mana HUD.

### `opponentBattlefieldRect`

Purpose: opponent non-land permanents.

Sizing:

- Height: `rowHeight`, computed from available battlefield height.
- Y: top of battlefield column.

Rules:

- Prefer card width `44-56` pt.
- If vertical pressure is high, reduce row label height and card width before overlapping center prompt.

### `opponentLandsRect`

Purpose: opponent lands.

Sizing:

- Height: `landRowHeight`.
- Y: below `opponentBattlefieldRect` with 4-6 pt gap.

Rules:

- Lands may use smaller card width than non-land permanents.
- This rect must end above `centerPromptStackRect.minY`.

### `centerPromptStackRect`

Purpose: center prompt, stack peek, and battlefield divider.

Sizing:

- Height: `50` pt preferred, `42` pt compact.
- Y: centered between opponent and player rows.

Rules:

- Combine `PromptPill` and `StackPeek` into this one region:
  - Prompt text owns the leading/center area.
  - Stack count/top object owns the trailing area.
- If the stack has cards and prompt text is long, show one-line prompt plus stack chip; full stack opens via right dock surface or detail sheet.
- The battlefield divider should be visual background inside this rect, not a separate element competing with prompt.

### `playerBattlefieldRect`

Purpose: player non-land permanents.

Sizing:

- Height: `rowHeight`.
- Y: below `centerPromptStackRect` with 4-6 pt gap.

Rules:

- Drag target highlight should be clipped to `playerBattlefieldRect.union(playerLandsRect).insetBy(dx: 0, dy: -6)`.
- Selected cards should not open an inspector in this rect; inspector belongs in `detailSheetRect`.

### `playerLandsRect`

Purpose: player lands and mana source tapping.

Sizing:

- Height: `landRowHeight`.
- Y: below `playerBattlefieldRect` with 4-6 pt gap.

Rules:

- Mana source legal highlighting must remain visible at small card sizes.
- `ManaPoolHUD` should dock to the leading edge of this rect or to `bottomActionRect`, not float between row coordinates.

### `detailSheetRect`

Purpose: card inspector, log drawer, full zone sheets, and expanded diagnostics.

Sizing:

- Default presentation: bottom sheet or popover anchored above `handRect`, width `min(520, safeFrame.width - 32)`, height `min(300, safeFrame.height * 0.68)`.
- In iPhone landscape, prefer a sheet over a floating battlefield overlay.

Rules:

- `CardInspector` and `GameLogDrawer` should be mutually exclusive.
- Zone inspector may continue as `.sheet`, but its intended geometry should be documented as `detailSheetRect`.
- Detail surfaces can cover gameplay temporarily because they are modal/intentional. Persistent play elements should not.

## Sizing Algorithm

1. Build `safeFrame` from safe area insets and margins.
2. Reserve `rightDockRect`.
3. Reserve `phaseRailRect`, unless compact fallback merges it into `rightDockRect`.
4. Reserve `topStatusRect`.
5. Reserve `handRect`.
6. Reserve `bottomActionRect`.
7. Compute `battlefieldColumnRect` from the remaining space.
8. Allocate battlefield vertical lanes in this order:
   - `centerPromptStackRect` gets its fixed preferred height first.
   - Remaining height is split into two permanent rows and two land rows.
   - Permanent rows get about `30%` each of remaining height.
   - Land rows get about `20%` each of remaining height.
   - Clamp card widths by both row height and row width.
9. If any row falls below minimum size, enter compact fallback.

## Fallback Behavior

Compact fallback triggers when:

- `safeFrame.width < 760`, or
- `safeFrame.height < 360`, or
- battlefield column width after dock/rail reservation is below `360`, or
- computed permanent card width is below `34`.

Compact fallback rules:

- Merge `phaseRailRect` into `rightDockRect`.
- Collapse diagnostics to one status chip in `topStatusRect`; move detailed revision/cycle/source data to log/detail.
- Hide persistent stack peek if stack is empty; if non-empty, show only a stack chip in `centerPromptStackRect`.
- Move `ManaPoolHUD` into `bottomActionRect` unless a pending action is active.
- Make `UniversalPromptActionPanel` start with primary prompt/actions and place surfaces below.
- Use one persistent overlay at a time: pending, inspector, or log/detail.

## Pass/Fail Criteria

Pass:

- On iPhone 16 Pro Max landscape, all named rects are inside `safeFrame`.
- `topStatusRect`, battlefield lane rects, `centerPromptStackRect`, `handRect`, `rightDockRect`, `phaseRailRect`, and `bottomActionRect` do not intersect except for explicitly allowed hand selected-card overflow.
- With 7-card hand, 8 non-land permanents per side, 10 lands per side, active stack, active prompt, mana in pool, and pending action, the prompt/action controls remain tappable and no persistent element covers a battlefield row label or card midpoint.
- With 12-card hand, hand cards stay within `handRect` plus allowed overflow and do not cover `playerLandsRect`.
- With long prompt text, `centerPromptStackRect` truncates to one or two lines and routes detail to right dock/detail sheet.
- With log open or card inspected, the detail surface is intentional/modal and can be dismissed without changing game state.
- Primary action targets meet at least `44 x 44` pt where possible; rail icons are at least `32 x 32` pt.
- The layout remains stable when `pendingActionId` changes; pending status replaces an existing region instead of adding another center overlay.

Fail:

- Any persistent region intersects another persistent region outside the allowed hand overflow.
- A selected hand card covers player lands or mana controls.
- Stack peek, prompt pill, and pending toast are visible as three independent center overlays.
- The right action panel hides pass/confirm/cast controls below surfaces when a prompt is active.
- Diagnostics text consumes battlefield space or overlaps opponent board.
- Compact fallback still leaves computed card width below `34` pt.

## Practical Layout Helpers And Tests

Suggested helpers:

- Introduce a pure Swift value type, for example `GameplayLayoutRegions`, initialized from `CGSize` and `EdgeInsets`.
- Give it named properties exactly matching this plan: `safeFrame`, `topStatusRect`, `opponentBattlefieldRect`, `opponentLandsRect`, `centerPromptStackRect`, `playerBattlefieldRect`, `playerLandsRect`, `handRect`, `rightDockRect`, `phaseRailRect`, `bottomActionRect`, and `detailSheetRect`.
- Add derived booleans like `isCompact`, `railMergedIntoDock`, and `allowsHandOverflow`.
- Add a debug-only helper returning `[BattlefieldLane]` or `[String: CGRect]` so tests and preview overlays can inspect the layout without rendering SwiftUI.

Suggested tests:

- Unit test `GameplayLayoutRegions` with iPhone 16 Pro Max landscape size and representative safe area insets.
- Unit test compact fallback sizes such as `740 x 360`, `812 x 375`, and an exaggerated safe-area case.
- Unit test that persistent rects do not intersect:
  - `topStatusRect`
  - `opponentBattlefieldRect`
  - `opponentLandsRect`
  - `centerPromptStackRect`
  - `playerBattlefieldRect`
  - `playerLandsRect`
  - `handRect`
  - `rightDockRect`
  - `phaseRailRect` when not merged
  - `bottomActionRect`
- Unit test that battlefield row card widths stay above minimum thresholds in preferred and compact modes.
- If UI tests become practical, add one landscape screenshot smoke test for the debug XMage gauntlet fixture and assert that key accessibility identifiers exist for top status, right dock, hand, and board rows.

## Recommended Implementation Changes

1. Replace `BattlefieldLayoutMetrics` coordinate properties with a named-rect layout value.
2. Move existing SwiftUI views into those rects with `.frame(width:height:)` and `.position(x: rect.midX, y: rect.midY)` as a low-risk first pass.
3. Combine the prompt pill, stack peek, and pending toast behavior so only one center/bottom prompt surface is persistent at a time.
4. Treat diagnostics, card inspector, log, and full zones as detail surfaces instead of permanent battlefield overlays.
5. Reorder `UniversalPromptActionPanel` so critical prompt/action controls appear before `MobileSurfacesPanel` whenever human input is required.
6. Add pure layout unit tests before or alongside visual tuning.

## Assumptions

- The target first pass is iPhone landscape, especially iPhone 16 Pro Max.
- The implementation should keep existing visual components and gameplay behavior unless moving a component is required to honor named regions.
- Source files should remain untouched by this audit; this document is the handoff for the implementation agent.
- Exact safe-area inset values should come from SwiftUI at runtime. Any hard-coded device numbers in this document are planning assumptions, not constants.

## Open TODOs

- Capture real device/simulator screenshots after implementation to confirm the assumed landscape safe frame.
- Decide whether the phase rail remains separate in preferred mode or is always folded into the right dock.
- Decide whether `MobileSurfacesPanel` should default collapsed when there is an active prompt.
- Add accessibility identifiers during implementation if UI screenshot tests are desired.
