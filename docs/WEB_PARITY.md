# Web parity with the iOS Arena board

The desktop web game (`apps/web`) plays exactly like the iOS app's Arena board mode, laid out for a desktop browser
(mouse, hover, keyboard), with nothing redesigned. **iOS is the reference**: when the web and iOS disagree, the web
changes. This checklist is the definition of done. Add a row whenever you find a behaviour that is missing here, and
never delete one silently (mark it `dropped` with the reason instead).

Sources: the iOS Arena files on `origin/main` (PRs #217, #219, #220, #221 and the earlier `claude/arena-mode`
merges), `docs/ARENA_STYLE.md`, `docs/TAVERN_STYLE.md`. iOS paths are under `apps/ios/MagicMobile/`, web paths under
`apps/web/src/`.

Status: `done` (behaviour matches and the evidence column says how it was checked), `partial`, `missing`, `n/a`
(a phone-only behaviour with a stated desktop replacement), `dropped`. Priority is the order the work goes in, by how
much each item changes the feel: 1 pace and holds, 2 smart pass and stops, 3 Auto Pay, 4 drag and drop, 5 triggers and
remembered answers, 6 combat, 7 effects, sounds and board pieces, 8 menus and decks.

## How a row is verified

| Kind | What it means |
|---|---|
| **shared** | A JSON case in `apps/android/core/src/test/resources/parity/` that iOS (`swift test --package-path apps/ios --filter ParityGoldenTests`) and the web (`npm --prefix apps/web test`) both pass. Android runs it where its `:core` has the logic; otherwise the row names the Android follow-up. |
| **unit** | A web-only vitest test, for logic iOS keeps inside SwiftUI views (no package hook to share). |
| **replay** | `apps/web/test/replay.test.ts`: a recorded run of engine polls fed through the web session and board logic; its stops, prompts, Auto Pay taps and event order must match the iOS expectations in the same file. |
| **game** | Seen in a real game against the AI on the real engine in desktop Chrome (`apps/web` static build served with the isolation headers). The evidence says what was seen and when. |

## Shared logic (decided 2026-10-22)

Pure logic is shared as JSON cases; only the UI is ported by hand.

| Case file | Covers | iOS runner | Web runner | Android |
|---|---|---|---|---|
| `arena-pace-cases.json` | Board events from a transition, the Arena pace schedule (full and reduced), the smart-pass hold, holds for later batches, the wipe cascade and its recap | `ParityGoldenTests.testArenaPaceCasesOnBothPlatforms` | `test/arenaPace.test.ts` | follow-up: Android's `BoardEventTimeline.kt` has no Arena pace |
| `combat-cases.json` (existing) | Combat keywords, first-strike beats at the Hearth pace, one-line combat log reasons | `testCombatClarityCasesOnBothPlatforms` | `test/arenaPace.test.ts`, `test/gameLog.test.ts` | runs (`ParityGoldenTest.kt`) |
| `smart-pass-cases.json` | Smart pass stops, Stop for Removal, threat detection, the three skip modes, stored stops, automatic-pass ids | `testSmartPassCasesOnBothPlatforms` | `test/smartPass.test.ts` | follow-up: `OnDeviceSmartPass.kt` has no threat stops |
| `auto-pay-cases.json` | Cost reading, mana ability reading, source order, the plan, the next step, blocked reasons | `testAutoPayCasesOnBothPlatforms` | `test/autoPay.test.ts` | follow-up: Android has no Auto Pay |
| `trigger-plan-cases.json` | A chosen trigger order answering XMage's ordering prompts one at a time | `testTriggerPlanCasesOnBothPlatforms` (`ArenaTriggerPlan`) | `test/triggerPlan.test.ts` | follow-up |
| `answer-action-cases.json` | Which remembered-answer actions a decision may carry (rememberAnswer, rememberTriggerFirst, passUntilStackResolved, autoPassAfterCast, resets) | `testAnswerActionCasesOnBothPlatforms` | `test/answerActions.test.ts` | follow-up |
| `arena-board-cases.json` | Drop thresholds, the keyword glossary, commander-taken notices, cards playable from other zones, hand posture, loyalty, amounts, affordable X, split, lethal, choices, colours | `testArenaBoardCasesOnBothPlatforms` | `test/arenaBoard.test.ts` | follow-up |
| `text-cases.json` (existing, `log`) | The game log reader: spans, card references, redacted names, entities, hidden markup | `testTextCasesMatchGolden` (golden) | `test/gameLog.test.ts` | runs |
| `game-summary-cases.json` (existing) | Combat credit and the top attacker | `testGameSummaryCasesOnBothPlatforms` | `test/gameStats.test.ts` | runs |
| `prompt-cases.json` (existing) | Prompt to command mapping and answer validation | existing | `test/parity.test.ts` | runs |
| `combo-loop-cases.json` (existing) | Combo loop spotting | existing | `test/comboLoop.test.ts` | runs |
| `replay/web-game-1.deflate` | 50 raw polls from a real web game: the prompt, smart pass's decision, Auto Pay's next step and the board events at each | `testWebReplaysMatchGoldens` writes `golden/replay-web-game-1.json` | `test/replay.test.ts` (equal, 2026-10-22) | follow-up |

Expectations for a new case come from iOS: the web generator (`apps/web/scripts/gen_arena_pace_cases.ts`) only fills
values that the iOS run then confirms; a difference means the web port is wrong.

## Desktop input

iOS has no keyboard shortcuts, so these are the desktop mapping of its touch gestures (`n/a` rows point here).

| iOS | Desktop |
|---|---|
| Tap a hand card (pops it), tap again (plays) | Hover pops the card under the pointer; click plays it |
| Carry a card up to play it | Drag it onto the table (same `ArenaLayout.drops` thresholds) |
| Hold a card to read it | Hover reads it at the zoom spot; right-click (or hold the mouse 0.35 s) opens the full inspector, which holds smart pass |
| Tap the primary plaque | Space (pass, resolve, the primary answer) |
| Confirm in a browser or the amount pill | Enter |
| Tap outside, Done on a browser | Esc |
| Hold the primary 0.6 s (Full control) | Hold Space 0.6 s, or the skip menu row |
| Undo pill | Ctrl/Cmd+Z while undo is offered |

## 1. Pace and holds (priority 1)

| ID | Behaviour | iOS source | Web | Web file | Verified by | Evidence |
|---|---|---|---|---|---|---|
| 1.01 | Snapshots diff into board events; another game is a cut | `BoardEventTimeline.swift` `BoardEventDiffer.events` | done | `core/boardEvents.ts` | shared + game | arena-pace + combat cases pass on iOS and web; game A, game D |
| 1.02 | Your spell 0.35 s (0.3), an opponent's 1.6 s reveal (1.2), commander 1.0 / 1.6, triggers 0.5 (0.4) | `BoardFXScheduler.arenaDuration` | done | `core/boardEvents.ts` | shared + game | as 1.01; game A: an AI spell revealed, own spells settle |
| 1.03 | Other Arena timings: arrival 0.6, departure 0.8, damage 0.6, counters/stats 0.8, phasing 0.9, transform 0.8, steal 1.2, attack 0.25, block 0.3, strike 0.45, first strike 1.0, life 1.0 | `arenaDuration` | done | `core/boardEvents.ts` | shared + game | as 1.01; game D: 303 board batches, flights land on the tile |
| 1.04 | Strikes land one after another, 0.38 s apart | `arenaStrikeSpacing`, `isSequential` | done | `core/boardEvents.ts` | shared | as 1.01 |
| 1.05 | Arrivals fly plainly from the stack card; the tile appears at 42 % of the flight | `ScheduledBoardFX.landing` | done | `core/boardEvents.ts, ui/arena/BoardFX.tsx` | shared + game | game A: 23 flights from the stack card, tile hidden until landing |
| 1.06 | Hand-off, release and later-batch holds (a spell read and a departure finish before anything else moves; at most 4 s) | `handoff`, `release`, `holdsLaterBatchesUntil`, `maximumHold`, `BoardFXDirector.ingest` | done | `core/boardEvents.ts` | shared + game | as 1.01; game A |
| 1.07 | Smart pass waits for spells, showcases, departures, strikes and the first-strike beat, never for triggers, life, damage or counters | `holdsSmartPass`, `smartPassHoldUntil` | done | `core/boardEvents.ts` | shared + game | game A: an AI Liliana's Devotee held smart pass 2.33 s after it showed; the pass went 9 ms after the hold ended; own Emmara passed at hold 0 |
| 1.08 | Smart pass first waits up to 1 s for the board to take in the new snapshot, then for the hold, at most 5 s | `BoardPresentationHold`, `OnDeviceSession.waitForBoardPresentation` | done | `table/guestSession.ts, ui/arena/useBoardFX.ts` | game | game A (as 1.07); game D: 95 smart passes, none before its board settled |
| 1.09 | Reading a card (the inspector open) holds smart pass until it closes, at most 60 s | `BoardPresentationHold.reading`, `NativeGameView+Arena.swift` | done | `ui/GameScreen.tsx (reading hold)` | game | game I: the AI’s spell read in the inspector for 3 s; no smart pass until it closed (the driver checks it each game) |
| 1.10 | Smart pass re-checks the same prompt id and revision after waiting, before it sends | `OnDeviceSession.scheduleSmartPass` | done | `table/guestSession.ts` | unit + game | scheduleSmartPass rechecks prompt id and revision; game A-game D: no stale passes |
| 1.11 | A board wipe (3+ leaving) leaves one card after another, 0.16 s apart, within 1.2 s | `BoardFXScheduler.schedule` sweep | done | `core/boardEvents.ts, ui/arena/BoardFX.tsx` | shared + game | game I: Fiery Confluence took six; departures started 0.15–0.17 s apart, all within 0.8 s |
| 1.12 | The wipe recap names the spell and what went, for 3.5 s in the caption | `ArenaSweepRecap`, `NativeGameView.ingestBoardFX` | done | `core/boardEvents.ts (sweepRecap), ui/GameScreen.tsx` | shared + game | game I: "Fiery Confluence: 4 to the graveyard, 2 returned or moved" in the caption |
| 1.13 | The turn banner (0.9 s over the draw) waits while a spell, showcase, departure or hit plays; showcases wait for the banner | `centreBusyUntil`, `NativeGameView` turn banner | done | `ui/arena/useBoardFX.ts` | game | game D: 56 banners, each after the centre cleared |
| 1.14 | An opponent's spell is revealed 1.2x toward the middle for 1.3 s, then settles in 0.3 s; arcs wait for it | `NativeGameView+Arena.arenaStack`, `arenaBeginReveal` | done | `ui/GameScreen.tsx (revealID)` | game | game A: 5 reveals; game D: 31 |
| 1.15 | Effects level Full / Reduced / Off; Reduce Motion caps at Reduced; Off during a fast combo loop | `BoardFXLevel.resolved` | done | `core/boardEvents.ts, ui/GameScreen.tsx` | shared + unit | resolvedLevel caps at Reduced under prefers-reduced-motion; Game Settings segmented control |
| 1.16 | Card motion: a tile hides while its flight stands in, attackers lunge, attack and block stances hold, flips | `BoardFXDirector.cardMotion` | done | `ui/arena/useBoardFX.ts, ui/arena/BoardFX.tsx` | game | game A, game D: tiles hidden while their flight stands in |
| 1.17 | AI turns read at Arena pace: polls show each AI action, and smart pass's holds set the pace | session + board | done | `table/guestSession.ts` | game | game A-game D: every AI action shown, smart pass waits on the board |

## 2. Smart pass, stops and skips (priority 2)

| ID | Behaviour | iOS source | Web | Web file | Verified by | Evidence |
|---|---|---|---|---|---|---|
| 2.01 | Passes only ordinary priority for a running, foreground, self-authorised local seat; never with mana floating | `OnDeviceSmartPass.passPrompt` | done (logic) | `core/smartPass.ts` | shared | smart-pass cases pass on iOS and web (2026-10-22) |
| 2.02 | Passes with nothing to play; default stops your mains and their attacks and end step; unknown steps stop | `passPrompt`, `defaultStops` | done (logic) | `core/smartPass.ts` | shared | as 2.01 |
| 2.03 | Your own spell or trigger resolves unless Stop for Own Spells is on (off) | `passPrompt`, `topStackIsMine` | done (logic) | `core/smartPass.ts` | shared | as 2.01 |
| 2.04 | Their object stops only with a response (`respondsToStack`; missing means yes) | `passPrompt`, `hasResponse` | done (logic) | `core/smartPass.ts` | shared | as 2.01 |
| 2.05 | Stop for Removal (on): their removal, sweeper, edict or steal stops you, answer or not | `passPrompt`, `threatensViewer` | done | `core/smartPass.ts` | shared | smart-pass cases (threats) pass on iOS and web |
| 2.06 | Threat test: targets your permanent, or you (a spell), or an untargeted sweep phrase; never with nothing to lose | `threatensViewer` | done | `core/smartPass.ts` | shared | as 2.05 |
| 2.07 | Each prompt passed at most once, never retried; log line "Auto-passed: …" | `OnDeviceSession`, `OnDeviceMessageLog.noteAutoPass` | done | `table/guestSession.ts`, `core/messageLog.ts` | unit | `test/smartPass.test.ts` |
| 2.08 | Not scheduled during a skip, under Full control, or with a pending answer, error or held ability prompt | `scheduleSmartPass` | done | `table/guestSession.ts` | unit | |
| 2.09 | Settings saved: smart pass (on), Stop for Own Spells (off), Stop for Removal (on), phase stops (sorted list; nothing stored is the defaults) | `Settings.load/encode/decode` | done | `core/smartPass.ts, ui/GameScreen.tsx` | unit | loadSmartPass/saveSmartPass keys mm.web.* |
| 2.10 | Smart pass on for solo games and relay tables | `OnDeviceRootView` | done | `table/guestTable.ts, table/soloTable.ts` | unit | relay seats load the same smart-pass settings as iOS’s table attach; guestFlow tests pass; not played on a live relay table here |
| 2.11 | A hidden tab cancels an unsent smart pass and stops a skip | `setForeground` | done | `ui/GameScreen.tsx (visibilitychange)` | unit | 80b1f186 |
| 2.12 | Phase Stops panel on the table (glass): steps by Your turn / Theirs, Reset Stops; opens from the phase strip or the gear | `PhaseStopsSheet`, `PhaseStopsGrid` | done | `ui/arena/Menus.tsx (PhaseStops)` | game | opens from the phase strip and the gear menu |
| 2.13 | Skip menu from the pass-ahead pill: "To end of turn / Skips responses", "To my turn / Skips responses", "To end of turn / Stops if they respond", "Full control" | `ArenaPassAheadPill.items`, `ArenaMenuCard` | done | `ui/GameScreen.tsx (passItems)` | game | |
| 2.14 | Skip modes: limits 60 s / 64, 120 s / 256, 180 s / 256; start and stop rules; Skip to my turn crosses opponents' turns; skips stop for removal | `OnDeviceYieldPolicy` | done | `core/smartPass.ts` | shared | smart-pass cases (yield scenarios) pass on iOS and web |
| 2.15 | Skip loop: a fresh poll before each pass, `auto-pass-` action ids, stops on any manual action, keeps a pending answer for Retry | `OnDeviceSession.startYield` | done | `table/guestSession.ts (startYield)` | unit | |
| 2.16 | While skipping, the pill is lit ember and stops the skip; the stop reason shows | `ArenaPassAheadPill` | done | `ui/GameScreen.tsx (.aff.on)` | game | |
| 2.17 | Full control: hold the primary 0.6 s or the menu row; smart pass stops at every priority this turn; a "Full control" tag | `toggleFullControl`, `FullControlHold` | done | `ui/GameScreen.tsx, table/guestSession.ts` | game | menu row; hold the plaque or Space 0.6 s (80b1f186) |
| 2.18 | Passes the app sent (smart and skip) show no waiting pop-up | `isAutomaticPass` | done | `core/smartPass.ts` | unit | as 2.01 |

## 3. Auto Pay and mana (priority 3)

| ID | Behaviour | iOS source | Web | Web file | Verified by | Evidence |
|---|---|---|---|---|---|---|
| 3.01 | Reads the remaining cost ({2}{R}, {S}, X skipped, Phyrexian, {2/W}, hybrids, {C}) | `ArenaAutoPay.need` | done | `core/autoPay.ts` | shared | auto-pay cases pass on iOS and web |
| 3.02 | Reads mana abilities: only {T} and sacrificing the source; producedMana, any colour, first-sentence alternatives | `production` | done | `core/autoPay.ts` | shared | as 3.01 |
| 3.03 | Source order: colourless 9, mono 10, dual 14, tri 16, any 18, creature +10, sacrifice 60 | `sources` | done | `core/autoPay.ts` | shared | as 3.01 |
| 3.04 | Cheapest full plan; coloured pips first; never starts a cost it can't finish; blocked reasons | `plan`, `next` | done | `core/autoPay.ts` | shared | as 3.01 |
| 3.05 | Floating mana spent first | `next` | done | `core/autoPay.ts` | shared | as 3.01 |
| 3.06 | Payment corner: Auto Pay (dimmed when it can't pay), "Paying…" + Stop while running, Cancel secondary | `arenaPaymentButtons` | done | `ui/GameScreen.tsx, ui/arena/autoPayRun.ts` | game | game C: Auto Pay ×6; game D: ×8; dimmed for convoke costs it cannot pay (as iOS) |
| 3.07 | One tap per settled snapshot; answers its own colour question with the planned colour and keeps it out of the choice browser; gives up after 30 steps or a repeated state ("Auto Pay stopped: tap the rest yourself") | `arenaAutoPayStep`, `arenaColorChoice`, `ArenaAutoPayDriver` | done | `ui/arena/autoPayRun.ts` | unit + game | test/autoPayRun.test.ts; game D: taps one per settled snapshot |
| 3.08 | Undo pill while `undo_mana` is legal | `arenaControls` | done | `ui/GameScreen.tsx (.aundo), Ctrl/Cmd+Z` | game | |
| 3.09 | Sources that can pay glow orange; lands softer; a click on a source sends make_mana | `arenaGlow`, `arenaLane` | done | `ui/GameScreen.tsx`, `ui/arena/arena.css` | game | 2026-10-21 full game (README) |
| 3.10 | Floating mana symbols above your medallion; spendable ones take a click | `ArenaFloatingMana` | done | `ui/GameScreen.tsx` | game | 2026-10-21 |
| 3.11 | Payment caption "Pay {cost}" ("Pay the cost") | `arenaCaptionText` | done | `ui/GameScreen.tsx (promptLine)` | game | "Pay {cost}", "Pay the cost" when the engine gives none (41174270) |
| 3.12 | X starts at the most you can pay; amount pill steps, holds to repeat | `ArenaAmountRange`, `ArenaAmountPill` | done | `ui/arena/Browsers.tsx` | unit | `test/arenaBrowsers.test.ts` |

## 4. Hand, drag and drop (priority 4)

| ID | Behaviour | iOS source | Web | Web file | Verified by | Evidence |
|---|---|---|---|---|---|---|
| 4.01 | Resting hand tucked at the bottom edge; raised fan geometry | `ArenaHandFanLayout.slot` | done | `ui/arena/layout.ts` | unit | `test/arenaLayout.test.ts` |
| 4.02 | One card pops whole (rises 92 pt, 1.18x, upright); moving along the hand moves the pop card by card | `ArenaHandFan.tapped`, `scrubCard` | done | `ui/arena/layout.ts (handPlaces, scrubHand), ui/GameScreen.tsx` | unit + game | test/arenaLayout.test.ts; game F: the hovered card pops whole and upright (c9fc612e) |
| 4.03 | Drag a hand card: it follows the pointer at 1.5x with a tilt, 1.38x and an ember shadow over the table | `ArenaHandFan.panned`, `dragPreview` | done | `ui/GameScreen.tsx (carry)` | game | game D: 15 drag casts |
| 4.04 | Drop rule: inside the play area, outside the controls corner, after 24 pt up or 80 pt any way; otherwise it snaps back | `ArenaLayout.drops` | done | `ui/arena/layout.ts (drops)` | shared + game | arena-board drops cases pass on iOS and web; as 4.03 |
| 4.05 | While carrying over the table its edge lights warm (no box) | `NativeGameView+Arena.arenaTable` | done | `ui/GameScreen.tsx (.adropglow)` | game | |
| 4.06 | A drop with several actions opens the action choice at the table centre; a refusal shows feedback | `panEnded`, `DragActionChoicePopup` | done | `ui/GameScreen.tsx (playFromHand)` | game | one play goes at once; several open the choice at the table centre; none says "is not currently playable" |
| 4.07 | The hand rests during payments, targets, combat, choices, dragging, spectating | `ArenaHandPosture.resolve` | done | `ui/GameScreen.tsx` | game | 2026-10-21 |
| 4.08 | A step change lowers the hand; a click on the empty table drops a popped card, then lowers the hand | `arenaTapTable`, `arenaBoard onChange` | done | `ui/GameScreen.tsx` | game | the pop follows the pointer along the hand; leaving the hand puts it down (desktop hover for the tap) |
| 4.09 | Read a hand card (hold on iOS): right-click or a 0.35 s mouse hold opens the inspector | `ArenaHandFan.held` | done | `ui/GameScreen.tsx (pressCard), ui/arena/Inspector.tsx` | game | |
| 4.10 | Cards playable from graveyard or exile join the fan's right end with a violet shimmer | `ArenaExtraHand`, `ArenaExtraCardShimmer` | done | `core/arenaBoard.ts (extraHandCards), ui/arena/ArenaCard.tsx (.ashimmer)` | shared | arena-board extraHand cases; violet-cyan edge and its zone mark (c9fc612e) |
| 4.11 | Draws fly from the library (0.5 s), show at the draw spot (0.4 s), join the hand (0.22 s), staggered 0.25 s, at most 3 | `ArenaHandFan.noteArrivals` | done | `ui/GameScreen.tsx (arrivals)` | game | game F: a drawn card mid-flight to the fan (c9fc612e) |
| 4.12 | Hand up 0.22 s ease-out with overshoot, down 0.18 s | `postureAnimation` | done | `ui/arena/arena.css ([data-hand])` | game | the pop springs in 0.24 s; the landscape board never raises the fan (ArenaHandPosture) |
| 4.13 | Spread-hand tab (portrait) | `ArenaHandPosture.spread` | n/a (desktop hand always fits; hover reads) | | | |

## 5. Triggers, prompts and remembered answers (priority 5)

| ID | Behaviour | iOS source | Web | Web file | Verified by | Evidence |
|---|---|---|---|---|---|---|
| 5.01 | Trigger order browser chosen by method `GAME_PICK_ABILITY` | `isTriggerOrder`, `arenaAbilityPrompt` | done | `ui/arena/triggerPlan.ts` | unit | test/triggerPlan.test.ts |
| 5.02 | "Order your triggers": click numbers a card (coin, gold rim), click again un-numbers; Done from N−1 picks ("k of N"); Auto Order | `ArenaAbilityBrowser` | done | `ui/arena/Browsers.tsx (AbilityBrowser)` | unit + game | game D: 10 Done answers |
| 5.03 | The chosen order answers each later ordering prompt by itself; the plan survives target questions and ends at your next priority | `arenaOrderTriggers`, `arenaTriggerPlanAnswers`, `arenaTriggerStep` | done | `ui/arena/triggerPlan.ts` | unit | test/triggerPlan.test.ts |
| 5.04 | "Always put my last-resolving pick first" sends `rememberTriggerFirst` | `ArenaAbilityBrowser`, `answerActions` | done | `ui/arena/Browsers.tsx, core/promptAdapter.ts` | shared | answer-action cases pass on iOS and web |
| 5.05 | "Don't ask again this game" on a yes/no question sends `rememberAnswer` (ability scope), only when XMage offers an auto-answer | `canRememberAnswer`, `compactPromptControls` | done | `ui/arena/Browsers.tsx` | shared | as 5.04 |
| 5.06 | "Remember my choice" in the choice browser | `ArenaChoiceList.options` | done | `ui/arena/Browsers.tsx` | unit | `test/arenaBrowsers.test.ts` |
| 5.07 | Answer actions only when the engine lists them and they fit the decision; standing actions ride on the next answer | `OnDeviceSession.submit`, `OnDevicePromptAdapter.answerActions` | done | `core/promptAdapter.ts, table/guestSession.ts` | shared | as 5.04 |
| 5.08 | Gear: "Ask Again (N answered)", "Ask Trigger Order Again" (reset actions) | `GameMenus.swift` | done | `ui/GameScreen.tsx (Game Settings)` | game | |
| 5.09 | "Pass After Casting" (on) sent as `autoPassAfterCast` | `setAutoPassAfterCast` | done | `ui/GameScreen.tsx, table/soloTable.ts` | unit | test/soloFlow.test.ts sends autoPassAfterCast |
| 5.10 | "Resolve All" secondary with 2+ stack objects: one pass carrying `passUntilStackResolved` | `GameplayAffordances.resolveStackCommand` | done | `ui/GameScreen.tsx` | shared | as 5.04 |
| 5.11 | XMage's "which ability" follow-up answered with the exact ability; its snapshot stays hidden unless that fails | `chosenAbilityAnswer`, `heldAbilitySnapshot` | done | `table/guestSession.ts (heldAbility)` | unit | the follow-up snapshot is held while answered, published only if that fails (5c5f81a1); soloFlow tests unchanged |
| 5.12 | Commander taken notice (7 s) | `ArenaCommanderSteal` | done | `core/arenaBoard.ts, ui/GameScreen.tsx` | shared | arena-board commanderTaken cases |
| 5.13 | Main button titles: Resolve; Next (TO MAIN / TO COMBAT / TO MAIN 2); End Turn; Pass; waiting labels | `arenaPassTitle`, `arenaWaitingTitle` | done | `ui/GameScreen.tsx` | game | Resolve / Next (To Main, To Combat, To Main 2) / End Turn / Pass; Waiting… while an answer is pending; Opponent’s Turn (41174270) |
| 5.14 | Prompt corner: the prompt's main action, else "Choices"; secondary the next action | `arenaButtonPlan` | done | `ui/GameScreen.tsx` | game | the prompt’s main action, else Choices (opens More actions); the next action second (b37576cb) |
| 5.15 | Question stage, mode, choice, player, split, pile browsers | `ArenaBoardViews.swift` | done | `ui/arena/Browsers.tsx` | unit + game | `test/arenaBrowsers.test.ts`, 2026-10-21 |
| 5.16 | Card choice browsers: effect titles (Scry, Surveil…), wells (BOTTOM / TOP…), multi-select with order coins, "2 OF 3", search over 6 | `BoardCardChoiceView.arenaStage` | done | `ui/arena/Browsers.tsx (CardChoice), core/cardChoicePlan.ts` | unit | test/cardChoicePlan.test.ts runs the iOS CardChoicePlanTests cases; effect titles, wells, search, Select all / Clear / Choose none, Done with the count (7e6357ae); not yet met in a game |
| 5.17 | Response cue on your own priority outside your empty-stack main | `BoardResponseCue.make` | n/a | |  | the response cue is the Hearth board's side rail; the Arena board has none |
| 5.18 | Captions: "Choose attackers." and the rest | `arenaCaptionText` | done | `ui/GameScreen.tsx (promptLine)` | game | arenaCaptionText: Pay {cost}, Choose attackers / who to attack, Choose blockers / the attacker to block, a board target’s message (41174270) |
| 5.19 | Keyword glossary in the inspector | `ArenaKeywordGlossary` | done | `core/arenaBoard.ts, ui/arena/Inspector.tsx` | shared | arena-board glossary cases |
| 5.20 | A player-target prompt with more than one pick opens its panel | `arenaSubmitPlayerTarget` | done | `ui/GameScreen.tsx (medallion), ui/arena/Browsers.tsx (PlayerChoice)` | unit | one pick answers from the medallion; several open the players panel (arenaSubmitPlayerTarget) |
| 5.21 | Prompts no browser takes fall back to a glass pop-up with "Open choices" | `CompactPromptPopup` | done | `ui/arena/Browsers.tsx, ui/GameScreen.tsx (Choices, More actions)` | unit | every prompt kind that reaches iOS’s compact pop-up on the Arena board has a web browser (question, choices, cards, players, split, piles, amount); one none takes gets Choices, which opens More actions |

## 6. Combat (priority 6)

| ID | Behaviour | iOS source | Web | Web file | Verified by | Evidence |
|---|---|---|---|---|---|---|
| 6.01 | Combat read from declare actions or your target prompt in a declare step | `ArenaCombatPhase.current` | done | `ui/arena/combat.ts` | unit | test/combat.test.ts (real attacker prompt) |
| 6.02 | "No Attacks" / "1 Attacker" / "N Attackers"; "No Blocks" / "1 Blocker" / "N Blockers"; Take Back | `arenaCombatButtons` | done | `ui/arena/combat.ts` | unit + game | game D: No Blocks ×4, 1 Attacker, 2 Attackers ×3 |
| 6.03 | Attack All (one opponent): every eligible attacker one per answer; "Attacking…" + Stop | `arenaStartAllAttack`, `arenaAttackStep` | done | `ui/arena/combat.ts, ui/GameScreen.tsx` | unit + game | game D: All Attack ×6, 15 attack declarations one per answer |
| 6.04 | Two-click declaration with a defender: the opponent's medallion glows red and takes the attack | `arenaOpponentMedallion` | done | `ui/GameScreen.tsx (.amed.targetable.attack), promptLine` | game | after an attacker, XMage’s defender question lights the medallion red and the caption reads "Choose who to attack." (5c5f81a1) |
| 6.05 | Combat arrows: red attack, grey blocked, gold block, amber dashed preview | `ArenaCombatArrows` | done | `ui/arena/combat.ts, ui/GameScreen.tsx` | unit + game | game D end screen: red attack arcs |
| 6.06 | Attackers glow #ff5a2e (keep colour while tapped), blockers #ffd38a | `arenaGlow` | done | `ui/arena/arena.css` | game | 2026-10-21 |
| 6.07 | Declared attackers and blockers stay selectable to undo | `OnDevicePromptAdapter.presentation` | done | `core/promptAdapter.ts` | shared | `prompt-cases.json` |
| 6.08 | Combat keyword badges on attackers and blockers | `ArenaBattlefieldCard` | done | `core/models.ts (abilityBadgePlan), ui/arena/ArenaCard.tsx` | unit | on the Arena board iOS shows keywords as the tile’s icon row, not labelled combat badges; test/arenaBoard.test.ts (46537300) |

## 7. Effects and sounds (priority 7)

| ID | Behaviour | iOS source | Web | Web file | Verified by | Evidence |
|---|---|---|---|---|---|---|
| 7.01 | Stack landing: settle from 1.07, colour bloom, one shine, motes (0.55 s) | `ArenaStackCard` | done | `ui/arena/fxPainter.ts` | game | game H, game I: 48 spell casts settled on the stack card |
| 7.02 | Target arcs from the stack card (cyan yours, red theirs), drawn over 0.45 s; reticles on targets | `ArenaStackArc`, `ArenaTargetReticle` | done | `ui/GameScreen.tsx (arcs, reticles)` | game | |
| 7.03 | Arrival flight from the stack card, glow and sparks; tokens gather from motes | `BoardFXOverlay` flights, `gather` | done | `ui/arena/BoardFX.tsx, ui/arena/fxPainter.ts` | game | game A |
| 7.04 | Departure: flies to its owner, embers; exile pillar and sigil | `BoardFXOverlay`, `exileMoment` | done | `ui/arena/BoardFX.tsx (burn), fxPainter.ts (exileMoment)` | game | game A: 2 burns |
| 7.05 | Damage flash with "−N" | `BoardFXOverlay` | done | `ui/arena/fxPainter.ts` | game | game I: damageMarked ×4 painted |
| 7.06 | Counter moments (+1/+1, −1/−1, loyalty, coin) with labels | `counterMoment`, `BoardFXCounterKind.label` | done | `ui/arena/fxPainter.ts (counterMoment)` | game | game H: a +1/+1 counter moment over the tile (screenshot) |
| 7.07 | Stats moment "+X/+Y" | `statsMoment` | done | `ui/arena/fxPainter.ts (statsMoment)` | unit | test/fxPainter.test.ts paints statsChanged (and every other kind) at both levels without error |
| 7.08 | Phasing bands; a phased-out tile at 0.42 with "Phased out" | `phaseMoment`, `ArenaBattlefieldCard` | done | `ui/arena/fxPainter.ts (phaseMoment), ui/arena/ArenaCard.tsx (.aphased)` | unit | the tile at 0.42 with "Phased out" (5c5f81a1); phasing not met in a game yet |
| 7.09 | Transform ring of light while the tile flips | `transformMoment` | done | `ui/arena/fxPainter.ts` | unit | as 7.07 (transformed) |
| 7.10 | Steal: the taker's chain drags the card home | `chainMoment` | done | `ui/arena/fxPainter.ts (chainMoment), BoardFX.tsx (pulled)` | unit | as 7.07 (controlChanged, with the taker’s chain from where the card was) |
| 7.11 | Attack and block marks | `BoardFXOverlay` | done | `ui/arena/fxPainter.ts` | game | game H: attack slashes on the attackers and their arcs (screenshot); attackDeclared ×31 painted in game H, game I |
| 7.12 | Strike trails and impact | `BoardFXOverlay` | done | `ui/arena/fxPainter.ts` | game | game H, game I: combatStrike ×24 painted |
| 7.13 | Life change floats at the medallion; the number rolls | `BoardFXOverlay`, `ArenaHeroMedallion` | done | `ui/arena/fxPainter.ts (lifeChanged)` | game | game H: "−2" over the medallion (screenshot); lifeChanged ×22 painted |
| 7.14 | Board shake and red vignette when you take 5+ | `BoardImpactShake`, `BoardHitVignette` | done | `ui/arena/useBoardFX.ts (boardShakes), ui/GameScreen.tsx` | unit + game | test/boardShake.test.ts; game G: the red flare at the edges as the AI hit for 9 |
| 7.15 | Turn banner: "Your turn" / "<Name>’s turn", 0.9 s | `BoardTurnBanner.arenaBanner` | done | `ui/arena/useBoardFX.ts` | game | game D |
| 7.16 | Sounds: board cues by event (casts by type, arrivals by land and creature type, attacks, blocks, strikes, deaths, exile, counters, steal, life), UI cues (tap, pickup, play, draw, open/close, error, response alert, turn, victory/defeat), cooldowns; `.caf` converted to `.m4a` | `GameAudio.swift`, `BoardFXSound.cues`, `GameSoundSignature` | done | `ui/audio.ts, ui/arena/useBoardFX.ts` | unit | test/audio.test.ts; 99 recordings converted by prepare_data.py |

## 8. Board pieces (priority 7)

| ID | Behaviour | iOS source | Web | Web file | Verified by | Evidence |
|---|---|---|---|---|---|---|
| 8.01 | Corner plaques, ember / leather / quiet label, pressed state | `ArenaPlaqueButtonStyle` | done | `ui/GameScreen.tsx` | game | 2026-10-21 |
| 8.02 | Phase strip: 8 icons always, lit track to the current step, spark along the track, ignite | `ArenaPhaseStrip` | done | `ui/GameScreen.tsx (PhaseStrip)` | game | |
| 8.03 | Day/night coin and storm count above the strip when they matter | `TavernTableHints` | done | `ui/GameScreen.tsx (.ahints)` | unit | day/night coin and STORM tag above the strip (c9fc612e) |
| 8.04 | Gear menu: Game Log, Stack (N), Phase Stops, Full control, Game Settings | `arenaGameMenuItems` | done | `ui/GameScreen.tsx (gameItems)` | game | Game Log, Stack (N), Phase Stops, Full control, More actions, Game Settings |
| 8.05 | A new prompt closes the corner menu and the player card | `arenaBoard onChange` | done | `ui/GameScreen.tsx` | game | a new prompt id or message closes both |
| 8.06 | Stack card: only the top object; tab with the count opens the stack browser; it closes when the stack empties | `ArenaStackCard`, `arenaTable` | done | `ui/GameScreen.tsx` | game | |
| 8.07 | Stack browser: count coin, YOUR RESPONSE / WAITING, numbered coins, RESOLVES NEXT, Stop skipping / Resolve All / Done | `ArenaStackBrowser` | done | `ui/arena/Browsers.tsx (StackBrowser)` | game | count coin, YOUR RESPONSE / WAITING, numbered coins, gold rim and RESOLVES NEXT, owner, targets, Stop skipping / Resolve All / Done (46537300) |
| 8.08 | Zone browser: Cast plaques, Choose for targets, library wording | `ArenaZoneBrowser` | done | `ui/arena/Browsers.tsx (ZoneBrowser)` | game | Cast / action plaques, Choose for targets, iOS’s wording, closes only on a cast (b37576cb) |
| 8.09 | Revealed and Looked-at chips by the opponent's piles | `arenaRevealedChips` | done | `ui/GameScreen.tsx (.azonepills)` | game | Revealed and Looked at chips at (818, 12) (b37576cb) |
| 8.10 | Top of library revealed face up on the deck, playable | `TopOfLibraryCard` | done | `ui/GameScreen.tsx (.atoplib)` | game | face up on the deck, tilted 8°, ember when playable, opens the zone (b37576cb) |
| 8.11 | Player card: portrait, life, status badges, zone grid with counts, lit where you can cast from, named exile zones | `ArenaPlayerCard` | done | `ui/GameScreen.tsx (.aplayercard), core/playerStatus.ts` | unit + game | test/playerStatus.test.ts; game G: AI 1’s card with Command, Graveyard, Library, Hand and its named exile zone (41174270) |
| 8.12 | Medallion glows ember on its owner's turn; status badges around it | `ArenaHeroMedallion`, `TavernEffectOrbitBadges` | done | `ui/GameScreen.tsx (.amed.active, .aorbit), ui/arena/StatusBadge.tsx` | unit + game | game G: the ember glow on the active player’s medallion; status badges orbit the opponent’s |
| 8.13 | Game log: gold title, turn dividers, an icon per event, smart pass lines dimmed, card links that open the inspector, oldest at the top, "Latest actions ↓" | `GameLogDrawer` Arena look | done | `core/gameLog.ts, ui/arena/GameLog.tsx` | shared + game | text-cases log goldens and combat-cases log reasons pass; game D screenshots at turns 5, 9, 13 |
| 8.14 | Inspector: dim 0.45, the card large, live-state notes, glossary, rules when the art can't show them, attachments, double-faced cards turn | `CardInspector.arenaBody` | done | `ui/arena/Inspector.tsx` | game | |
| 8.15 | Opening hand: "OPENING HAND", message, a large fan dealt in, Mulligan / Keep; click a card to enlarge | `OpeningHandOverlay` | done | `ui/GameScreen.tsx (.amull)` | game | game A-game D: Keep |
| 8.16 | Result: gold rays and motes on a win, ash on a loss; reason line and game summary | `GameCompletionOverlay`, `GameResultBackdrop` | done | `ui/arena/ResultBackdrop.tsx, ui/GameScreen.tsx` | game | game D, game G: DEFEAT, winner, rounds, combat damage, creatures destroyed, top attacker with token art; the backdrop canvas ported after |
| 8.17 | Notices replace the caption for 2.4 s; rejected actions inline under the caption | `arenaShowNotice`, `ActionRejectionInlineView` | done | `ui/GameScreen.tsx (showNotice, .arecovery)` | game | notices take the caption for 2.4 s; on-device iOS shows errors in its recovery banner (Refresh, Retry response, Leave), so the web does too (c9fc612e) |
| 8.18 | Tiles: counters (2 chips), COPY tag, keyword badges bottom left | `ArenaBattlefieldCard` | done | `ui/arena/ArenaCard.tsx (PlainTile)` | unit + game | two counter chips, COPY tag on token copies, the icon row bottom left (46537300) |
| 8.19 | Rows shrink to 70 % before scrolling | `ArenaRowFit.fit` | done | `ui/arena/layout.ts (fitRow)` | unit | cards shrink to 70 %; past that the web overlaps where iOS scrolls (see Intentionally different) |
| 8.20 | Turn labels count rounds | `TableRounds` | done | `core/models.ts (TableRounds), ui/GameScreen.tsx` | unit + game | game D: 20 turns read as 10 |
| 8.21 | Combo loop: offer, repeat modes, forecast, stop reasons | `ComboLoop.swift`, `OnDeviceSession` | done | `core/comboLoop.ts, table/guestSession.ts, ui/arena/ComboLoop.tsx` | shared + unit | combo-loop-cases.json (16 cases) and the iOS ComboLoopTests assertions (test/comboLoop.test.ts); the session offers a round made three times, repeats it from the live choices and sums it up (test/comboSession.test.ts) (d4744476); no loop came up in the test games |
| 8.22 | The local poll pace shows every AI action (engine-held poll; iOS polls 0.3 s / 0.12 s chain) | `OnDeviceLocalPollSchedule` | done (different mechanism, same result) | `table/guestSession.ts` | game | 2026-10-21 |
| 8.23 | Tokens show the Scryfall printing that matches their name, type, rules, colours and printed P/T; a copy shows its source card | `NativeDeckArtwork.imageData` (token path), `NativeAssetStore.matchTokenArtwork`, `NativeArtworkCatalogue.searchToken` | done | `core/tokenArt.ts, ui/cardArt.ts` | unit + game | test/tokenArt.test.ts; game E, game F, game G: token tiles show their printing, no missing art (notFound empty) |

## 9. Out of game (priority 8, after every gameplay row)

| ID | Behaviour | iOS source | Web | Web file | Verified by | Evidence |
|---|---|---|---|---|---|---|
| 9.01 | Arena top bar, home, Play panel with deck boxes, custom table | `Menus/Arena*.swift` | missing (setup form) | `ui/SoloSetup.tsx` | game | |
| 9.02 | Deck boxes that open | `ArenaDeckBox` | missing | | game | |
| 9.03 | Options pages (Gameplay, Board, Audio, Display & Artwork, Performance) with Arena controls | `ArenaOptionsView` | missing | | game | |
| 9.04 | Deck import (Archidekt, Moxfield) | `OnDeviceDeckLinkImporter` | missing | | unit | |
| 9.05 | Sign-in and own decks through Supabase | `PlayerAccount`, social backend | missing (needs Caleb) | | game | |
| 9.06 | Profile, Ranked hall | `Ranked/*` | missing | | game | |

## Games on the real engine

Headless desktop Chrome (`apps/web/scripts/play.mjs`, Playwright with the installed Chrome) against the static build
served by `vite preview` with the isolation headers, the XMage AI on the other side. The driver plays through the
board's own controls (drag to cast, Auto Pay, All Attack, the corner plaques, the browsers) and records every answer,
the board's flights, banners and reveals, and console errors.

| Run | Decks | Result | What it showed |
|---|---|---|---|
| game A (2026-10-22) | Token Triumph vs Grave Danger | stopped turn 9 at the commander-zone question (driver fixed) | smart pass held 2.33 s for an AI spell, passed 9 ms after the hold; 23 flights, 2 burns, 5 reveals, a banner each turn, Auto Pay ×2, All Attack ×1, a drag cast, 20 smart passes, no page errors |
| game B | Token Triumph vs Chaos Incarnate | AI won, turn 11 | 43 smart passes, no page errors (the driver's drags pressed a neighbouring card; fixed) |
| game C | First Flight vs Chaos Incarnate | page blanked turn 15 | 6 drags, Auto Pay ×6, All Attack ×1, 58 smart passes; a negative canvas radius threw inside an effect and React unmounted the table. Fixed: radii clamp, the painter skips a failing mark, effects sit in an error boundary (80b1f186) |
| game D | Token Triumph vs Grave Danger | AI won, turn 20 | 15 drag casts, Auto Pay ×8, All Attack ×6, 15 attack declarations, 10 trigger/question answers, 95 smart passes, 56 banners, 31 reveals, no page errors; the log at turns 5, 9, 13; the result screen with its summary. Token tiles were blank (8.23, fixed after) |
| game E | Token Triumph vs Chaos Incarnate | AI won, turn 17 | 16 drags, Auto Pay ×13, All Attack ×4, 95 smart passes, no page errors; token tiles with their printings |
| game F | First Flight vs Grave Danger | AI won, turn 15 | the hand pops one card; a drawn card flies in; 5 drags, Auto Pay ×5, All Attack ×4, 70 smart passes, no page errors, no missing resources |
| game G | Token Triumph vs Chaos Incarnate | AI won, turn 20 | 15 drags, Auto Pay ×8, All Attack ×2, 80 smart passes, no page errors, no missing resources; the player card; the red hit flare |
| game H | Draconic Destruction vs Grave Danger | AI won, turn 17 (two lands all game) | painted: arrivals 21, casts 16, departures 2, attacks 20, strikes 13, life 5, counters 1; screenshots of each first kind; no page errors, nothing missing |
| game I | First Flight vs Chaos Incarnate | AI won, turn 21 | the reading hold held 3 s; Fiery Confluence's six-card wipe with its cascade and recap; 12 drags, Auto Pay ×8, All Attack ×2, 81 smart passes; no page errors; one token zoom asked Scryfall by name (fixed in 7e6357ae) |
| final 1 | Draconic Destruction vs Chaos Incarnate | AI won, turn 19 | drag casts 8, Auto Pay 8, triggers 7, All Attack 2, reading hold held; no wipe; no errors, nothing missing |
| final 2 | First Flight vs Chaos Incarnate | **won**, turn 24 | drag casts 19, Auto Pay 13, triggers 11, All Attack 4; no wipe; one uncaught canvas error on the win screen (negative particle noise, fixed in 143e1479) |
| final 3 | Token Triumph vs Grave Danger | conceded through the menu, turn 25 | drag casts 23, Auto Pay 16, triggers 49, All Attack 8, blocks 9; no wipe; no errors |
| final 4 | Draconic Destruction vs Grave Danger | AI won, turn 15 | drag casts 9, triggers 6; no Auto Pay or All Attack came up; no errors |
| final 5 | First Flight vs Grave Danger | AI won, turn 17 | drag casts 7, Auto Pay 7, triggers 7, All Attack 6; no wipe; no errors |
| final 6 (`--want-sweeper`) | Draconic Destruction vs Chaos Incarnate | no record: the driver itself crashed | a Playwright read timed out in the driver, not the page; the driver now records its own errors and guards that read |
| final 7 | First Flight vs Chaos Incarnate | AI won, turn 19 | drag casts 5, Auto Pay 5, triggers 11, All Attack 1, reading hold held; no wipe; no errors |
| final 8 | Draconic Destruction vs Grave Danger | AI won, turn 17 | drag casts 10, Auto Pay 8, triggers 8, All Attack 1, reading hold held; no wipe; no errors |
| final 9 | First Flight vs Grave Danger | stopped turn 5 at "Pick a mana color" | the board asked correctly (a choice with no colour name, so Auto Pay can't pick, the same on iOS); the driver answered with `choose_choice`, which the session ignores, instead of the board's `resolve_choice` (fixed in c19fd0bb); no errors |
| final 10 | Draconic Destruction vs Token Triumph | AI won, turn 18 | drag casts 6, triggers 34; no Auto Pay or All Attack came up; no wipe; no errors |

## Android follow-ups

The web and iOS now share these cases; Android's `:core` doesn't run them yet. Each needs a port into
`apps/android/core` and a runner in `ParityGoldenTest.kt` (called from `ContractChecks.kt`). They are listed here
rather than filed, because filing an issue is public and waits for Caleb's word:

- Arena pace and holds (`arena-pace-cases.json`): `BoardEventTimeline.kt` has the Hearth pace only.
- Stop for Removal and the skip modes' threat stop (`smart-pass-cases.json`): `OnDeviceSmartPass.kt`.
- Auto Pay (`auto-pay-cases.json`): Android has no Auto Pay.
- The Arena board's rules (`arena-board-cases.json`) and answer actions (`answer-action-cases.json`).
- The trigger order plan (`trigger-plan-cases.json`): a port of `ArenaTriggerPlan`.
- The recorded-game replay (`replay/*.deflate` against `golden/replay-*.json`): Android needs the same trace, read with
  `java.util.zip.Inflater(true)` (raw DEFLATE).

## Intentionally different on desktop

- No portrait layout or spread-hand tab: the web board is horizontal only (README).
- Hover reads a card where iOS needs a hold; the full inspector is a right-click.
- Keyboard shortcuts (Desktop input above) have no iOS counterpart.
- Polling: the browser engine holds a poll and answers at the next snapshot, where iOS polls on a timer (8.22).
- A full battlefield row overlaps its cards once they reach 70 % instead of scrolling sideways (8.19).
- Hovering the hand pops the card under the pointer; iOS pops it on a tap or a slide (4.02, 4.08).
- With several AI opponents each medallion keeps a name under it; iOS shows one opponent seat at a time.

## Log

- 2026-10-22: checklist written from the iOS Arena sources and the web branch rebased onto `origin/main`
  (`claude/web-arena-parity`). Logic ported and shared: Arena pace (`boardEvents.ts`), smart pass with Stop for Removal
  and the skip modes (`smartPass.ts`), Auto Pay (`autoPay.ts`).
- 2026-10-22 (later): the board ported on top: Arena pace and holds, smart pass with Stop for Removal, the skip menu and
  Full control, Auto Pay, drag to play, the inspector, trigger order and remembered answers, combat, the effects painter
  and sounds, the phase strip, opening hand, result, the game log, desktop keys, board shake, token art. Four games on
  the real engine (above).
- 2026-10-22 (evening): the hand pops one card, draws fly in, extra-hand cards, table hints, the recovery banner, tile
  badges and COPY, the stack and zone browsers, the player card with status badges, the result backdrop, More actions,
  phased-out tiles, the card choice stage with its drafted plan, the combo loop, token art. A recorded game's 50 polls
  replay identically through the web and iOS code (`test/replay.test.ts`, `testWebReplaysMatchGoldens`).
