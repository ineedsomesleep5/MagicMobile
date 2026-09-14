# Portrait polish: routing and coverage checklist

## Current review checkpoint — 2026-09-14

The checklist below records fixes verified in the current uncommitted source in
`MagicMobile-runtime-hardening`. Rawls's original routing ledger is preserved below
as historical review evidence; its unchecked baseline gaps are not a claim that
these repairs remain absent. This checkpoint is a source review, not visual or
physical-device execution, and is not a release approval.

- [x] **Authorized zone/action reachability:** `PlayerZoneMenu` exposes supplied named
  exile/companion/revealed/looked-at groups; the prompt-details sheet supplies current
  selected-card actions and enables `showsGameSurfaceSections`. Inspector action
  menus retain all exposed actions and a separate authorized target route.
- [x] **Stack inspection inside its modal:** the stack sheet renders its own
  `CardInspector` overlay with an explicit **Close card** button.
- [x] **Current-authority inspection refresh:** `PortraitInteractionPolicy.authorizedCards`
  includes player zones, named groups, prompt cards, pile cards and stack source
  cards. Board and root inspector refresh paths use current supplied projections;
  the helper does not reconstruct hidden cards or expand viewer authority.
- [x] **Footer budget:** portrait reserves 170 points, the compact mana HUD scrolls
  horizontally, and auto-pass status no longer adds an overflowing footer row.
  Actual small-screen, Dynamic Type and touch geometry still need rendered validation.
- [x] **Pile contents and in-sheet inspection:** `pilePicker` shows only supplied
  cards, retains empty piles and keeps choosing separate from inspection. Confirmed
  that the new `.overlay` is on **UniversalPromptActionPanel itself**, before that
  struct's `priorityLabel` member, and renders `CardInspector` plus **Close card**.
  Therefore it belongs to the active prompt-details sheet rather than the board
  underneath. Closing inspection changes only `inspectedCard`, not the pile answer.
- [x] **Display and exact routing:** prompt/playable labels use `EngineDisplayText`;
  IDs, response tokens and authoritative response values remain separate. Explicit
  skip-menu modes route through local ordinary-priority scheduling, retain stop
  controls, and stop for required choices; aggressive modes are labeled as skipping
  stack responses. No new engine skip command or peer authority was inferred.

**Latest evidence:** root reports **152 passing macOS portable tests** for the
integrated polish. This documentation pass did not rerun them. Earlier focused
display regressions were observed failing before the fix and passing afterward;
portable tests do not execute ContentView/RootView modal layering or phone geometry.
Root's third SDK compilation was reported in progress when this checkpoint was
written; no SDK success is asserted here. SDK/release provenance remains root-owned.

**Critic status:** the four concrete portrait findings and the follow-up pile-modal
inspection finding are addressed in inspected source. No remaining high-impact
blocker was identified in that bounded re-review. This does not establish all-card
gameplay parity, complete prompt-family execution, multiplayer/device acceptance,
rendered portrait correctness, native-build acceptance or TestFlight readiness.

## Preserved baseline review and routing ledger

Source review: `9a86cab236fe642f2970cb06a1b3b78cd5099d6c`, runtime-hardening checkout, 2026-09-14. Line anchors below refer to source inspected before the concurrent polish edits; use the named symbol if lines move. Initial review owned only this document. A subsequent bounded authorization also permitted editing only `CompactZoneInspectorOverlay` and `pilePicker` in ContentView. Root owns the other ContentView/interaction-state/tests; Pauli owns prompt adapter/display text; Descartes owns session/safe yield. No compilation or release was performed here.

Bounded follow-up implemented: the overlay preserves root's all-card-action chooser, Inspect and 76×106 cards, uses a matching 100-point minimum grid column, and provides 44-point control hit areas. Optional API: `targetableIDs: Set<String> = []`, `runTargetAction: ((ZoneCard) -> Void)? = nil`; root must wire current prompt authorization and submission. Piles now show only their supplied cards with inspection and a separate explicit choose button, including empty piles. Source changes are not compiled/tested yet. The baseline gap checklist below remains a routing record, not a claim that concurrent repairs are absent.

Requirement: for 2–4 players, portrait shows the viewer battlefield and **exactly one selected opponent battlefield**, with a toggle when there are multiple opponents. Switching focus is inspection, not a change of viewer, priority, controller, or target authorization. Preserve the same identity contract for later landscape parity. Referenced user photos are not attached to this review thread; no photo-specific geometry or visual acceptance is inferred.

Path key: **CV** = `apps/ios/MagicMobile/ContentView.swift`; **BI** = `apps/ios/MagicMobile/GameBoardInteractionState.swift`; **PA** = `apps/ios/MagicMobile/OnDevicePromptAdapter.swift`; **SA** = `apps/ios/MagicMobile/OnDeviceSnapshotAdapter.swift`; **SS** = `apps/ios/MagicMobile/OnDeviceSession.swift`; **RV** = `apps/ios/MagicMobile/OnDeviceRootView.swift`; **AT** = `apps/ios/MagicMobileTests/`. All are repository-relative.

## Concrete gaps root must route

- [ ] **P1 — Authorized zone/action routes are disconnected.** `CV:2935` is the only `UniversalPromptActionPanel` construction; it passes `selectedCardActions: []` and `showsGameSurfaceSections: false`. `CV:5646–5675` consequently hides Selected, Spells & Lands, Abilities & Mana, Other Actions and `MobileSurfacesPanel`. The portrait menu at `CV:9431` exposes only the viewer's command/graveyard/exile. Opponent HUD has no zone callback (`CV:8658`, `PortraitOpponentStatusBar`); companion and named-exile inspection in `MobileSurfacesPanel` is unreachable from this shell. Add an explicit portrait zone/action route using the existing snapshot projections, not a second battlefield or inferred permissions. Regression: four players, choose opponent C, inspect C's public graveyard/exile/command and an explicit companion/named-exile group; viewer identity and hand remain unchanged.
- [ ] **P1 — Non-battlefield abilities and multiple actions have no usable inspector route.** `CV:11520,11608` filters through `BI:legalPlayActions`, which permits only `play_land`/`cast_spell`. An exposed graveyard/exile/command/companion `activate_ability` cannot run there. Multiple play actions display “Select”/“Select for actions,” but the panel above never renders selected actions; `CV:selectedActions` is unused. Show every current `BI.cardActions` option in an explicit chooser, retaining pending/stale disabling. Do not auto-run the first ability or manufacture actions. Regression: one graveyard activation, two legal actions on one command-zone card, and removal of the action on the next snapshot.
- [ ] **P1 — Pile selection is blind.** `CV:6153` `pilePicker` shows only `pile.label` and card count, then submits immediately. `PA:125` already supplies the authorized cards. Show the contents of each pile with inspection before the explicit choose action; preserve a legitimate empty pile. Regression: two equally sized piles with different cards, plus 0/5 piles; verify the chosen pile maps to the original boolean, not card order/count.
- [ ] **P1 privacy/display — Inspections retain revoked/stale card views.** `CV:2466` copies cards into `@State inspectingZoneCards`; `CV:2740,3272` renders that copy against later snapshots. `selectedCard`/`inspectedCard` also retain full card values. `RV:120,129–145` similarly captures external zone arrays. There is no snapshot-authority reconciliation for these values; the match-ID handler at `CV:3015` resets only opponent focus. Repro: open a looked-at/control-hand card, then receive a snapshot removing that authorization or hiding that card; leave the inspector open. Close or re-resolve inspections against current authorized groups/cards on update, and clear on session change/close. This is stale disclosure rendering, not proof that the transport fetched a new unauthorized card. Root must coordinate RV ownership if that external path also needs a fix; this reviewer must not edit it.
- [ ] **P2 — Decision text remains clipped even in details.** `CV:5626–5633,5704–5710` limits the full decision message to three lines with shrinking; mode/ability/allocation rows also have small capped text. Pauli can clean engine markup, but root must allow full message/choice inspection in the scrollable detail dialog. Preserve IDs and boolean meanings separately from labels. Regression: long distinct ability/mode text and a commander ASK whose authoritative labels must not be replaced by a message heuristic.

## Zone routes and exact action boundaries

| Zone / surface | Actual source route | Required checklist / privacy contract |
| --- | --- | --- |
| Viewer hand | `SA:29–37`; `CV:3180` hand fan, `CV:9121` `HandRow`, `CV:9824` portrait hand | Inspect authorized cards; cast/play only from current object actions. Drag with multiple actions opens a chooser. Never optimistically remove a card before authoritative state. Controlled-player hand is not automatically the viewer hand. |
| Opponent hand | `SA:29,105–106`; top HUD count | Count only normally. Explicit `authorizedOpponentHands` belongs in an authorized inspection group, not an unrestricted “show hand” action. Focus switch must never change which private projection was received. |
| Battlefield / lands | `CV:3114–3118,3160–3164`; `PortraitBattlefieldPermanentGroup`, `BattlefieldRow`; `BI.cardActions/boardTargetableIds` | Existing portrait renders one opponent already. Preserve card UUIDs through grouping/overflow; expose all authorized play/mana/activate/target/combat routes, not card-type heuristics. Long press inspects; distinguish tap-to-act from tap-to-select. |
| Graveyard | Viewer menu `CV:9433`; aggregate implementation `CV:7014`; inspector `CV:11568` | Add per-player browse/owner labels and all exposed actions (including abilities). Browsing a public zone is not permission to move, cast, or select every card as a target. |
| Exile / named exile | `SA:102`; `CV:7018,7027`; viewer menu `CV:9434` | Preserve group name/identity, visible faces and `hideInfo` redaction. Exile counts need not equal disclosed card count. Route named groups, not only flattened viewer exile. |
| Command | `SA:35`; `CV:9432,7010`; commander metadata `CV:6938` | Route each player's command zone, current cast/activate actions, per-commander tax/damage. Unknown tax/damage stays unknown; moving to command is an ASK response, not a zone-browser shortcut. |
| Library | `SA:37–40` deliberately supplies empty card arrays plus counts; `CV:6919,7032` | No free browse/draw/shuffle/reorder. Search/look/top-card display only from explicit prompt cards or authorized looked-at groups. Do not label an undisclosed library “empty.” |
| Stack | `SA:stack mapping`; `CV:9528–9615` `PortraitStackLane`, `snapshot.stackTopFirst` | Existing lane scrolls all stack objects and inspects source cards; targeting currently routes through prompt details, not stack-card tap. Preserve stack-object UUID versus source-card UUID and top-first order. A “resolve” button must not claim resolution merely because a pass was queued. |
| Revealed | `SA:103`; `CV:3139–3143`, `CV:7036` | Existing center button opens explicitly revealed cards. Keep group/owner context and reconcile open inspections as disclosure changes. No catalogue reconstruction of hidden faces. |
| Looked-at / controlled hand | `SA:105–106`; `CV:3144–3148,7040`; `RV:120` external callback | Show only explicitly authorized groups; stale-inspection fix above is required. A group name is not authority to enumerate that player's whole zone. |
| Companion | `SA:104,108,128`; unreachable `CV:6925–6927` | Add reachable inspection plus current `canPlayObjects` action. Do not offer “take companion” merely because a card is present. |
| Sideboard / other zones | `SA:68`, `SA:108–111`; `CV:7027` named groups | Only currently supplied projections are eligible for display; no generic arbitrary-zone request or hidden sideboard expansion. Other actions require a real exposed LegalAction. Unsupported draft/tournament/unknown zones remain explicit limitations, not fabricated buttons. |

`SA:240–284` `playableObjects` derives object actions from `canPlayObjects`: play/cast/activate only for active priority SELECT, mana sources during PLAY_MANA/PLAY_X_MANA. It selects the **object UUID** so XMage can request the exact ability next. `SS:send(action:)` rechecks current action; `send(command:)` uses current prompt and the adapter's exact response. Retain that rejection boundary during UI polish.

## Prompt/dialog routing checklist

All production detail dialogs route `CV:2935 → UniversalPromptActionPanel.promptEnvelopeV2Section:5703 → UniversalPromptResponseCommandBuilder → SS.send → PA.answer`. Keep original prompt ID/revision, viewer identity and exact response token; label cleanup must never rewrite them. Actual encoder family switch: `packages/ondevice-engine/engine/xmage/src/main/java/io/magicmobile/xmage/QueryEncoder.java:32–148`.

| Family | Presentation / control entrypoints | Preserve / expose |
| --- | --- | --- |
| ASK / commander replacement / yes-no cost | `PA:35`; `CV:6399` confirmation; compact `CV:7514` | Exact supplied yes/no commands and labels; no inference that every commander mention means “Command zone.” Dismiss details does not answer Cancel/No. |
| SELECT priority | `PA:46–50`; `CV:3370` pass action; `BI.GameActionDockModel` | One real pass response, current priority only. Safe-yield belongs to Descartes: user-visible stop/cancel, no skipping a decision or sending stale prompts. Existing native adapter exposes pass, not invented end-turn/resolve opcodes. |
| SELECT attackers/blockers | `PA:51–77`; `CV:3416` combat tap/submission helpers; `BI.mode/boardTargetableIds` | Sequential UUID toggles and explicit boolean Done; reselect declared attackers to undo when authorized. Switching opponents must not submit or alter defenders. Never infer controlled acting player from selected opponent. |
| PICK_TARGET: cards, players, defenders, search, ordering | `PA:167–196`; `CV:5735` targets; `5993` cardPicker; `6054` searchSelectionPicker; `3390` submitTarget | One UUID per native prompt; only published candidate/alias IDs and explicitly supplied CardViews. Hidden/unfocused targets remain selectable in details without showing another battlefield. Card inspection is not target selection. Native ordering may be successive PICK_TARGET prompts, not one array submission. |
| CHOOSE_CHOICE | `PA:142–161`; `CV:5964` optionGrid | Preserve engine order and exact string keys, `#` specials, optional empty-string cancellation, and distinct typed-null empty-special action. Long choices must remain distinguishable. |
| CHOOSE_MODE | `PA:162–166`; `CV:5754` modes → optionGrid | One exact mode UUID per prompt, repeated if engine requests more. Do not turn modal wording into an invented multi-select answer. |
| CHOOSE_ABILITY / PICK_ABILITY | `PA:131–141`; `CV:6137` abilityPicker | Exact ability UUID; all labels inspectable; cancel only when exposed. Object category selection is not itself the ability UUID. |
| AMOUNT / X | `PA:115–124`; `CV:6169` quick amounts, `6350` manualAmountPicker | Engine signed bounds, wide ranges, typed numeric entry and enabled submit; keyboard must not hide submit/dismiss. Do not impose nonnegative bounds or silently accept unparsable text. |
| MULTI_AMOUNT / damage | `PA:101–114`; `CV:6198` multiAmountPicker | Per-row order/bounds and total bounds, exact integer array; explicit cancel only if offered. Root must make long labels and small +/- controls usable, without substituting an auto damage allocation. |
| PLAY_MANA / PLAY_X_MANA | `PA:82–100`; `CV:5943,6289`, `ManaPaymentTray:~7800`, native payment branch `~8115` | Acting `manaPlayerId` and prompt-provided pool amounts, named color, object source UUID, exact special payment, explicit false cancel. Keep special chooser reachable even with empty metadata; never use focused opponent/viewer's pool instead. PLAY_X_MANA factory coverage is not proof of a real upstream X-query emission. |
| CHOOSE_PILE | `PA:125–130`; `CV:6153` | Fix blind content route above; two exact booleans, including empty pile. No selected-card list answer. |
| Legacy order_items / order_triggers | `CV:6504` orderPicker; `6761` orderOptions; `PA.answer` native whitelist | Preserve complete ordered IDs only when that command is actually supported. Do not route native PICK_TARGET ordering through the legacy array command. |
| Unsupported / DRAFT_PICK_CARD | encoder `:148`; `PA` default; `CV:6442` unsupported fallback | Explain unsupported route; never send a guessed pass/default choice. Draft is outside this Commander polish. |

## Opponent focus and transient-state regression checklist

- [ ] **Zone-target direct route is absent, not an engine deadlock.** `CV:11612` inspector tap only assigns `selectedCard`; the overlay has no prompt/target callback and no Confirm Target action. Add an explicitly authorized target action using the current prompt's candidate/alias IDs, separate from cast/activate. Do not treat every displayed zone card as a target. Existing fallback survives: `CV:5735` target option buttons, or `CV:5993–6051` prompt card picker with Confirm Card. A zone selection can feed that picker only if the card is among its current explicit cards. Test a graveyard target, a noncandidate card in the same zone, and a prompt revision change while the zone stays open.
- [ ] **Landscape lower stack objects lack an inspection route.** `CV:2850` passes reversed native objects to `XmageStackPeek:5140`, which displays only `objects.last` (the correct top object). Unlike portrait `PortraitStackLane:9528`, it cannot browse lower objects; the aggregate stack browser is inside the hidden `MobileSurfacesPanel`. Add an all-stack inspection route later without changing top-first semantics or substituting a source-card UUID for a stack target. Generic stack targets remain reachable in prompt details today.
- [ ] **Landscape multi-opponent focus already works at source level.** `CV:2506` applies the same focused snapshot before orientation branching; `CV:2550` supplies the landscape menu, and `CV:2597–2601` uses only that opponent's battlefield/lands. No additional simultaneous opponent rows are needed. Both layouts' HUD tap is combat-specific; generic player targets use `prompt.targets` buttons. Preserve this fallback for off-focus players; `CombatPlayerIdentity.side:8604` deliberately returns nil for an unfocused opponent instead of drawing to the wrong HUD.
- [ ] Keep `CV:2377` `BoardOpponentFocus` and `CV:2392` menu semantics: exclude viewer, ignore invalid/departed selection, retain player order and viewer ID; selected opponent alone supplies both opponent permanent/land rows (`CV:3114–3118`). For two total players no redundant toggle is needed; three/four players require it. Existing menu is wired at `CV:8683`; do not add simultaneous opponent battlefields.
- [ ] Generic player/stack targets remain reachable through prompt detail even when off-board. Existing combat HUD routing is separate from generic PICK_TARGET. Test target C while B is focused, then toggle C; no fallback arrow should mislabel B as the defender.
- [ ] Reconcile selected/inspected/zone cards, drag chooser, and dialog-local order/amount/search state against match + prompt revision. Engine rejection protects authority but does not make a stale label or private inspector correct. Never retarget an old pending command to the newly focused player.
- [ ] Root/Descartes verify pending, uncertain retry, background/resume, session close/new match and yield cancellation do not auto-submit dialogs. The command acknowledgement is queued, not resolved. Overlay priority must keep current mandatory prompt details reachable above board/zone inspection.

## Evidence and ownership handoff

Source/test contracts reviewed (not executed this turn): `AT/OnDeviceBoardIdentityTests.swift` opponent-focus and off-focus combat-anchor tests; `AT/OnDevicePromptAdapterTests.swift` ASK labels, exact choice/mode/ability tokens, piles, bounds, controlled mana, target aliases/ordered views, stale commands; `AT/OnDeviceSnapshotAdapterTests.swift:136` authorized public/named groups and face-down projection test; `AT/OnDeviceSessionTests.swift` canonical action, uncertain retry and background tests. These do **not** prove that a screen exposes the tested data.

`apps/ios/Package.swift:14–18,27` excludes ContentView, GameBoardInteractionState, OnDeviceRootView and OnDeviceBoardIdentityTests from portable tests. Consequently a green portable adapter/session suite cannot validate pile contents, zone reachability, overlay revocation or portrait toggle geometry. Root should add targeted contracts in its owned tests and separately verify the actual rendered routes when authorized. Prior native/link/TestFlight evidence belongs to the earlier source; it is not phone acceptance of this polish. No native phone evidence was generated or reviewed for these new changes.

This is a bounded routing review, not all-card parity or a request for new engine capabilities. Root owns the concrete UI fixes above; Pauli preserves protocol tokens while improving display text; Descartes owns safe-yield/session behavior. RV is called out for coordination, not silently added to anyone's edit ownership.
