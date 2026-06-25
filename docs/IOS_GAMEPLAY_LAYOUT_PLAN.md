# iOS Gameplay Layout Plan

## Scope

This is a code-level audit of the native iOS landscape gameplay layout on `main` starting from commit `03c51aa7` (`Polish iOS arena battlefield visual hierarchy`), then updated after the parent integration pass. It defines the target named-region contract, safe-area rules, Pro Max assumptions, smaller-device fallback behavior, and visual pass/fail criteria for continued iOS polish.

Integration note: the original audit captured a transient red layout-test profile while layout edits were still in flight. The current integrated tree has since been revalidated by the parent orchestrator; the Pro Max and compact landscape layout tests now pass.

This document is intentionally not a release signoff. Simulator geometry and unit tests can prove layout invariants; they do not prove real XMage gameplay readiness, fixture determinism, product polish, or end-to-end Commander playability.

## Current Implementation Audit

The gameplay screen enters `ImmersivePlayShell` from `ContentView` when `screen == .play`, then renders `NativeGameView` around a single `GeometryReader` and `ZStack`. The current implementation already centralizes most placement in `BattlefieldLayoutMetrics`, but views are still placed with absolute `.position(...)` calls.

Current named geometry in `BattlefieldLayoutMetrics`:

- `safeFrame`: derived from `GeometryProxy.safeAreaInsets` with a 10 pt horizontal margin, 8 pt top offset, and 16 pt total vertical inset. It clamps to at least `320 x 300`.
- `topStatusRect`: full safe-frame width, 40 pt tall.
- `rightDockRect`: pinned to `safeFrame.maxX`, width `clamp(safeFrame.width * 0.20, 210, 268)`, from below top status to the bottom of `safeFrame`.
- `boardColumnRect`: the left gameplay column, separated from the dock by 12 pt and clamped to at least 320 pt wide.
- `handRect`: bottom of the board column, height `handCardHeight + 14`.
- `bottomActionRect`: centered above the hand, 38 pt high, width `clamp(boardColumnRect.width * 0.58, 320, 460)`.
- `rightActionPanelRect`: anchored below the compact phase/log/settings strip and fills the remaining right dock height.
- `phaseRailRect`: currently a compact horizontal strip inside the right dock, not a separate vertical rail. The integrated implementation keeps it short enough for the Pro Max layout test guard.
- `detailSheetRect`: a floating left-side detail surface, width `clamp(boardColumnRect.width * 0.33, 220, 292)`, height `clamp(safeFrame.height * 0.40, 184, 240)`.
- `opponentBattlefieldRect`, `opponentLandsRect`, `centerStripRect`, `playerBattlefieldRect`, and `playerLandsRect`: derived from `battlefieldRect` between the top status and hand, with a 3 pt lane gap.

Current view ownership:

- Top status: `TurnStatusBadge`, `LiveUpdateBadge`, `GameDiagnosticsBadge`, and opponent `PlayerHeroHUD`.
- Battlefield lanes: two `BattlefieldRow` views for the opponent, two for the player, plus a center divider.
- Center strip: `XmageStackPeek` or `StackPeek` plus `PromptPill` in one horizontal region.
- Right dock: `RightDockBackdrop`, `GameDiagnosticsBadge`, `CompactPhaseRail`, log/settings buttons, and `UniversalPromptActionPanel`.
- Prompt/action panel: `UniversalPromptActionPanel` places prompt controls first, then selected-card actions, pass/step actions, spells/lands, abilities/mana, other actions, and `MobileSurfacesPanel`.
- Hand: `HandFan` with selected-card lift, drag-to-play, and pending-card highlighting.
- Player lower HUD: `PlayerHeroHUD` and `ManaPoolHUD`.
- Modal/detail: `CardInspector`, `GameLogDrawer`, and `ZoneInspectorSheet`.
- Pending status: a "Waiting for XMage" toast in `bottomActionRect`.

Model/API surfaces that affect layout:

- `GameSnapshot` supplies phase, priority, prompt text, log, players, legal actions, choice prompts, prompt envelopes, XMage stack, bridge revision, XMage cycle, and pending status.
- `XmageMobileSnapshot` can expose stack, combat, command, graveyard, exile, revealed, looked-at, playable objects, and panel flags.
- `MagicMobileAPI` keeps prompt/action routing fail-closed for missing action data and includes `expectedBridgeRevision`; this layout work must not weaken that behavior.

## Current Risks

- The screen is still visually absolute-positioned. The metrics object gives central coordinates, but there is no formal compact-mode state or one-pass region allocator.
- The current "phase rail" is a horizontal strip inside the right dock, not a separate vertical rail. That is acceptable for the current compact dock direction, but future docs/tests should name it as a dock-header strip if it stays horizontal.
- The current right side is crowded because diagnostics, phase rail, settings/log buttons, and the prompt panel all share the dock.
- `GameDiagnosticsBadge` is positioned in the dock, while `topStatusRect` still spans the full safe frame. This makes the top status contract fuzzier than the target.
- `HandFan` selected cards lift by 30 pt and scale to 1.16x; visual overflow can exceed `handRect` even though hit geometry remains bounded.
- `ManaPoolHUD` floats just above player lands and can become crowded with player HUD, selected hand cards, and bottom pending status.
- `CardInspector` and `GameLogDrawer` are floating overlays, not modal owners of a reserved region. They can intentionally cover gameplay but should not be mistaken for persistent layout proof.
- `MobileSurfacesPanel` is always inside the prompt scroll content. In dense prompt states, secondary zone surfaces can still compete with primary controls, although the current ordering is better than putting zones first.

## Target Named Regions

The next implementation should keep the existing SwiftUI components and move them into an explicit region contract. Do not rewrite the gameplay architecture as part of the layout pass.

### Pro Max Baseline

Use runtime safe-area values, not hard-coded device constants. For automated proof, the existing test baseline is:

- Viewport: `932 x 430` pt.
- Safe area: top `0`, leading `47`, bottom `21`, trailing `47`.
- Current integrated evidence: hand-card width and compact phase-rail height meet the Pro Max layout test guards, and the compact landscape metric test also passes.

For planning language, "Pro Max landscape" means the large landscape phone class. The exact physical model may vary between iPhone 16 Pro Max and the installed iPhone 17 Pro Max simulator, so tests should assert geometry classes instead of marketing-model names.

### `safeFrame`

Purpose: parent constraint for all persistent gameplay regions.

Rules:

- Derive from `GeometryProxy.safeAreaInsets`.
- Keep all persistent regions inside `safeFrame`.
- Allow only transient drag cards to leave `safeFrame`.
- Use margins in the 8-10 pt range unless a test proves a different value is required.

### `topStatusRect`

Purpose: unified top HUD strip.

Rules:

- Own turn status, live status, opponent compact HUD, and collapsed diagnostics.
- Persistent diagnostics text should not consume board-lane space.
- Target height: 40-52 pt. If the compact phase/control strip remains horizontal, it must not inflate this strip unpredictably.

### `rightDockRect`

Purpose: permanent right-side command area.

Rules:

- Own the right action panel, secondary zone surfaces, and dock backdrop.
- Keep primary prompt/pass/cast controls reachable before secondary surfaces.
- Do not move XMage routing decisions into layout code.
- Target width: large-phone preferred range 220-286 pt, with current code at 210-268 pt.

### `phaseRailRect`

Purpose: compact phase, log, and settings controls.

Rules:

- Decide explicitly between a separate rail column and a dock-header strip. The current code uses a dock-header strip.
- If it remains a strip, rename the target or test accordingly so "rail" does not imply a separate column.
- If it becomes a separate rail, it must not reduce the battlefield column below the compact usable minimum.
- Current test contract: `testBattlefieldLayoutMetricsFitProMaxLandscape` expects the strip to stay at or below 42 pt, and the integrated implementation satisfies that guard.

### `boardColumnRect`

Purpose: battlefield, center prompt/stack, player HUD, mana HUD, hand, and bottom status.

Rules:

- Keep a minimum 10-12 pt gap from `rightDockRect`.
- Preferred minimum width: 420 pt on large phones.
- Compact minimum width: 360 pt.
- Current test coverage asserts it does not intersect the right dock or right action panel.

### Battlefield Lanes

Regions:

- `opponentBattlefieldRect`
- `opponentLandsRect`
- `centerStripRect` or target name `centerPromptStackRect`
- `playerBattlefieldRect`
- `playerLandsRect`

Rules:

- The center prompt/stack region owns both stack peek and prompt pill; do not introduce a second persistent center prompt.
- Board rows must not intersect the center region.
- Permanent rows should stay at least 52 pt tall.
- Land rows should stay at least 44 pt tall.
- Prefer scaling card size before overlapping rows.

### `handRect`

Purpose: hand fan, selection, and drag origin.

Rules:

- Own all normal hand-card rendering.
- Allow selected-card visual overflow upward, but keep it out of player lands and mana controls.
- Large-phone target should keep hand cards near or above 74 pt wide if tests retain that criterion.
- With 12 cards, reduce spread and rotation before allowing hand cards to cover `playerLandsRect`.

### `bottomActionRect`

Purpose: high-priority transient status/action bar.

Rules:

- Own pending status, compact pass/confirm action, or a one-line prompt status.
- Pending status should replace an existing prompt/status surface instead of adding another center overlay.
- Current code correctly places the XMage pending toast here.

### `detailSheetRect`

Purpose: inspector, log, expanded diagnostics, and full zone details.

Rules:

- Treat details as intentional overlays or sheets, not persistent board regions.
- `CardInspector` and `GameLogDrawer` should be mutually exclusive.
- `ZoneInspectorSheet` can remain a SwiftUI sheet.

## Smaller-Device Fallback

The current code has no explicit `isCompact` or `railMergedIntoDock` state. Add one before making further visual promises.

Compact fallback should trigger when any of these are true:

- `safeFrame.width < 760`
- `safeFrame.height < 360`
- `boardColumnRect.width < 360`
- computed permanent-card width falls below 44 pt
- hand-card width falls below 58 pt

Compact fallback rules:

- Keep the phase control strip inside `rightDockRect`; do not reserve a separate rail column.
- Collapse diagnostics to a one-line chip or move details to `detailSheetRect`.
- Hide empty stack peek; when stack is non-empty, keep it as a chip inside the center prompt/stack region.
- Move `ManaPoolHUD` into `bottomActionRect` or pin it to `playerLandsRect` leading edge when space is tight.
- Allow only one transient overlay at a time: pending, inspector, or log/detail.
- Keep `UniversalPromptActionPanel` internally scrollable, with prompt controls above zone surfaces.

## Pass/Fail Visual Criteria

Pass:

- All persistent named regions are inside `safeFrame`.
- `boardColumnRect`, `rightDockRect`, `rightActionPanelRect`, `handRect`, `bottomActionRect`, `phaseRailRect`, and battlefield lane rects do not intersect except for documented selected-hand visual overflow.
- On the Pro Max baseline, hand cards meet the agreed width target, permanent cards remain tappable/readable, land rows remain visible, and the phase strip/rail fits its tested height.
- With 7-card hand, 8 non-land permanents per side, 10 lands per side, active stack, active prompt, mana in pool, and pending action, prompt/action controls remain tappable and no persistent element covers a board card midpoint.
- With 12-card hand, cards remain in `handRect` plus allowed selected-card overflow and do not cover player lands.
- Long prompt text truncates within the center/right prompt regions and routes detail to the right dock or detail sheet.
- Pending status appears in `bottomActionRect`, not as an additional center overlay.
- Primary action targets are at least 44 pt where possible; rail/dock icon controls are at least 32 pt.

Fail:

- Any persistent region intersects another persistent region outside documented hand overflow.
- Selected or dragged hand cards hide player lands, mana controls, or bottom pending status after the drag ends.
- Prompt pill, stack peek, and pending toast appear as three independent persistent center overlays.
- The right action panel pushes pass/confirm/cast controls below zone surfaces in an active human prompt.
- Diagnostics overlap opponent battlefield content or consume board-lane height.
- Any layout metrics test remains red without either updating the layout or intentionally updating the test contract.

## Implementation Guardrails

- Only refactor layout ownership; do not rewrite XMage routing, fixtures, command templates, or fail-closed prompt behavior.
- Preserve `MagicMobileAPI.command(for:)` behavior around source instance IDs, ability IDs, prompt IDs, message IDs, and `expectedBridgeRevision`.
- Keep `MobileSurfacesPanel` secondary to prompt controls unless the user explicitly asks for a zone-first interaction model.
- Add or adjust pure layout tests before claiming visual stability.
- Screenshot QA is necessary after implementation, but screenshot QA is not gameplay/product release proof.

## Required Final Report

### Files Inspected

- `apps/ios/MagicMobile/ContentView.swift`
- `apps/ios/MagicMobile/Models.swift`
- `apps/ios/MagicMobile/MagicMobileAPI.swift`
- `apps/ios/MagicMobileTests/MagicMobileTests.swift`
- `docs/IOS_GAMEPLAY_LAYOUT_PLAN.md`

### Files Changed

- `docs/IOS_GAMEPLAY_LAYOUT_PLAN.md`

Note: subsequent parent integration also updated `apps/ios/MagicMobile/ContentView.swift`, `apps/ios/MagicMobileTests/MagicMobileTests.swift`, and `docs/IOS_VISUAL_QA_CHECKLIST.md` to implement and verify the current layout pass.

### Screenshots Taken Or Reason None

None. This audit was limited to source/test inspection and documentation. The app was not launched into a seeded gameplay fixture, so a screenshot would only prove simulator rendering at one moment, not real gameplay readiness.

### Tests/Build Commands Run With Exact Pass/Fail

- PASS: `git status --short --branch && git rev-parse --show-toplevel && git rev-parse --abbrev-ref HEAD && git rev-parse --short HEAD`
  - Confirmed current checkout is `/Users/calebfeliciano/Documents/MagicMobile`, branch `main`, commit `03c51aa7`.
- PASS: `xcodebuild -list -project apps/ios/MagicMobileiOS.xcodeproj`
  - Confirmed scheme `MagicMobile` and targets `MagicMobile`, `MagicMobileTests`.
- HISTORICAL RED: early audit runs failed the Pro Max and compact layout metric tests while layout edits were still in flight. Those failures drove the current hand-card, phase-strip, and right-dock assertions.
- PASS: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test -project apps/ios/MagicMobileiOS.xcodeproj -scheme MagicMobile -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' -only-testing:MagicMobileTests -quiet -derivedDataPath /tmp/MagicMobileParentFullTestDerivedData`
  - Parent rerun passed on the integrated checkout, including `testBattlefieldLayoutMetricsFitProMaxLandscape` and `testBattlefieldLayoutMetricsKeepCompactLandscapeUsable`.
- PASS: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project apps/ios/MagicMobileiOS.xcodeproj -scheme MagicMobile -configuration Debug -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO -derivedDataPath /tmp/MagicMobileParentGenericDerivedData build`
  - Parent rerun produced `** BUILD SUCCEEDED **`.

### Assumptions

- The requested baseline started at `03c51aa7`; this document now also includes the parent integration changes made after that commit.
- The first implementation target is large-phone landscape, with the existing Pro Max test using `932 x 430` pt and safe insets top `0`, leading/trailing `47`, bottom `21`.
- Runtime safe-area insets remain authoritative; device numbers in this document are test/planning inputs, not constants.
- Swift code and backend code are intentionally untouched by this audit.
- Runtime screenshots remain required after each significant visual pass, because metric tests cannot prove final aesthetics or touch feel.

### Blockers

- The initial Pro Max and compact metric failures were resolved in the integrated tree.
- Simulator screenshots were captured after integration. The current readable reference is `build_output/screenshots/ios-17-pro-max-arena-pass-7-readable.jpg`, which uses a real XMage fixture snapshot, explicit native gateway WebSocket URL, `WS Live`, and the simplified compact phase strip.
- No deterministic seeded XMage gameplay run was performed, so this document cannot certify gameplay/product release readiness.
- Compact fallback is still implicit rather than represented by a first-class `isCompact` layout state.

### Remaining TODOs

- Decide whether `phaseRailRect` should be a true rail or renamed/treated as a dock-header strip.
- Keep `BattlefieldLayoutMetrics` and its tests synchronized whenever hand-card, dock, rail, or compact fallback sizing changes.
- Add explicit compact-mode state and tests for fallback thresholds.
- Capture landscape screenshots after implementation using a debug fixture, then record what the screenshot proves and does not prove.
- Keep blocker docs honest if visual QA passes while XMage gameplay fixture proof remains incomplete.
