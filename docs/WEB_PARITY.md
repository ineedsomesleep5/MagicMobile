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
| `combat-cases.json` (existing) | Combat keywords and first-strike beats at the Hearth pace | `testCombatClarityCasesOnBothPlatforms` | `test/arenaPace.test.ts` | runs (`ParityGoldenTest.kt`) |
| `smart-pass-cases.json` | Smart pass stops, Stop for Removal, threat detection, the three skip modes, stored stops, automatic-pass ids | `testSmartPassCasesOnBothPlatforms` | `test/smartPass.test.ts` | follow-up: `OnDeviceSmartPass.kt` has no threat stops |
| `auto-pay-cases.json` | Cost reading, mana ability reading, source order, the plan, the next step, blocked reasons | `testAutoPayCasesOnBothPlatforms` | `test/autoPay.test.ts` | follow-up: Android has no Auto Pay |
| `trigger-cases.json` (planned) | The trigger order plan, which answer each ordering prompt gets, remembered-answer actions | to add | to add | follow-up |
| `prompt-cases.json` (existing) | Prompt to command mapping and answer validation | existing | `test/parity.test.ts` | runs |
| `combo-loop-cases.json` (existing) | Combo loop recording and replay | existing | to add with the combo loop rows | runs |

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
| 1.01 | Snapshots diff into board events; another game is a cut | `BoardEventTimeline.swift` `BoardEventDiffer.events` | partial (logic) | `core/boardEvents.ts` | shared | arena-pace + combat cases pass on iOS and web (2026-10-22) |
| 1.02 | Your spell 0.35 s (0.3), an opponent's 1.6 s reveal (1.2), commander 1.0 / 1.6, triggers 0.5 (0.4) | `BoardFXScheduler.arenaDuration` | partial (logic) | `core/boardEvents.ts` | shared | as 1.01 |
| 1.03 | Other Arena timings: arrival 0.6, departure 0.8, damage 0.6, counters/stats 0.8, phasing 0.9, transform 0.8, steal 1.2, attack 0.25, block 0.3, strike 0.45, first strike 1.0, life 1.0 | `arenaDuration` | partial (logic) | `core/boardEvents.ts` | shared | as 1.01 |
| 1.04 | Strikes land one after another, 0.38 s apart | `arenaStrikeSpacing`, `isSequential` | partial (logic) | `core/boardEvents.ts` | shared | as 1.01 |
| 1.05 | Arrivals fly plainly from the stack card; the tile appears at 42 % of the flight | `ScheduledBoardFX.landing` | partial (logic) | `core/boardEvents.ts` | shared + game | |
| 1.06 | Hand-off, release and later-batch holds (a spell read and a departure finish before anything else moves; at most 4 s) | `handoff`, `release`, `holdsLaterBatchesUntil`, `maximumHold`, `BoardFXDirector.ingest` | partial (logic) | `core/boardEvents.ts` | shared | as 1.01 |
| 1.07 | Smart pass waits for spells, showcases, departures, strikes and the first-strike beat, never for triggers, life, damage or counters | `holdsSmartPass`, `smartPassHoldUntil` | partial (logic) | `core/boardEvents.ts` | shared + game | |
| 1.08 | Smart pass first waits up to 1 s for the board to take in the new snapshot, then for the hold, at most 5 s | `BoardPresentationHold`, `OnDeviceSession.waitForBoardPresentation` | missing | `table/guestSession.ts` | unit + game | |
| 1.09 | Reading a card (the inspector open) holds smart pass until it closes, at most 60 s | `BoardPresentationHold.reading`, `NativeGameView+Arena.swift` | missing | `ui/GameScreen.tsx` | unit + game | |
| 1.10 | Smart pass re-checks the same prompt id and revision after waiting, before it sends | `OnDeviceSession.scheduleSmartPass` | missing | `table/guestSession.ts` | unit | |
| 1.11 | A board wipe (3+ leaving) leaves one card after another, 0.16 s apart, within 1.2 s | `BoardFXScheduler.schedule` sweep | partial (logic) | `core/boardEvents.ts` | shared + game | |
| 1.12 | The wipe recap names the spell and what went, for 3.5 s in the caption | `ArenaSweepRecap`, `NativeGameView.ingestBoardFX` | partial (logic) | `core/boardEvents.ts` | shared + game | |
| 1.13 | The turn banner (0.9 s over the draw) waits while a spell, showcase, departure or hit plays; showcases wait for the banner | `centreBusyUntil`, `NativeGameView` turn banner | missing | | unit + game | |
| 1.14 | An opponent's spell is revealed 1.2x toward the middle for 1.3 s, then settles in 0.3 s; arcs wait for it | `NativeGameView+Arena.arenaStack`, `arenaBeginReveal` | missing | | game | |
| 1.15 | Effects level Full / Reduced / Off; Reduce Motion caps at Reduced; Off during a fast combo loop | `BoardFXLevel.resolved` | partial (logic) | `core/boardEvents.ts` | unit | |
| 1.16 | Card motion: a tile hides while its flight stands in, attackers lunge, attack and block stances hold, flips | `BoardFXDirector.cardMotion` | partial (logic) | `core/boardEvents.ts` | unit + game | |
| 1.17 | AI turns read at Arena pace: polls show each AI action, and smart pass's holds set the pace | session + board | missing | `table/guestSession.ts` | replay + game | |

## 2. Smart pass, stops and skips (priority 2)

| ID | Behaviour | iOS source | Web | Web file | Verified by | Evidence |
|---|---|---|---|---|---|---|
| 2.01 | Passes only ordinary priority for a running, foreground, self-authorised local seat; never with mana floating | `OnDeviceSmartPass.passPrompt` | done (logic) | `core/smartPass.ts` | shared | smart-pass cases pass on iOS and web (2026-10-22) |
| 2.02 | Passes with nothing to play; default stops your mains and their attacks and end step; unknown steps stop | `passPrompt`, `defaultStops` | done (logic) | `core/smartPass.ts` | shared | as 2.01 |
| 2.03 | Your own spell or trigger resolves unless Stop for Own Spells is on (off) | `passPrompt`, `topStackIsMine` | done (logic) | `core/smartPass.ts` | shared | as 2.01 |
| 2.04 | Their object stops only with a response (`respondsToStack`; missing means yes) | `passPrompt`, `hasResponse` | done (logic) | `core/smartPass.ts` | shared | as 2.01 |
| 2.05 | Stop for Removal (on): their removal, sweeper, edict or steal stops you, answer or not | `passPrompt`, `threatensViewer` | partial (logic) | `core/smartPass.ts` | shared + game | |
| 2.06 | Threat test: targets your permanent, or you (a spell), or an untargeted sweep phrase; never with nothing to lose | `threatensViewer` | partial (logic) | `core/smartPass.ts` | shared | as 2.01 |
| 2.07 | Each prompt passed at most once, never retried; log line "Auto-passed: …" | `OnDeviceSession`, `OnDeviceMessageLog.noteAutoPass` | done | `table/guestSession.ts`, `core/messageLog.ts` | unit | `test/smartPass.test.ts` |
| 2.08 | Not scheduled during a skip, under Full control, or with a pending answer, error or held ability prompt | `scheduleSmartPass` | partial | `table/guestSession.ts` | unit | |
| 2.09 | Settings saved: smart pass (on), Stop for Own Spells (off), Stop for Removal (on), phase stops (sorted list; nothing stored is the defaults) | `Settings.load/encode/decode` | partial | `core/smartPass.ts` | shared + unit | |
| 2.10 | Smart pass on for solo games and relay tables | `OnDeviceRootView` | partial (solo only) | `table/guestTable.ts` | unit | |
| 2.11 | A hidden tab cancels an unsent smart pass and stops a skip | `setForeground` | missing | `table/guestSession.ts` | unit | |
| 2.12 | Phase Stops panel on the table (glass): steps by Your turn / Theirs, Reset Stops; opens from the phase strip or the gear | `PhaseStopsSheet`, `PhaseStopsGrid` | missing | | game | |
| 2.13 | Skip menu from the pass-ahead pill: "To end of turn / Skips responses", "To my turn / Skips responses", "To end of turn / Stops if they respond", "Full control" | `ArenaPassAheadPill.items`, `ArenaMenuCard` | missing (pill toggles smart pass) | `ui/GameScreen.tsx` | game | |
| 2.14 | Skip modes: limits 60 s / 64, 120 s / 256, 180 s / 256; start and stop rules; Skip to my turn crosses opponents' turns; skips stop for removal | `OnDeviceYieldPolicy` | partial (logic) | `core/smartPass.ts` | shared | as 2.01 |
| 2.15 | Skip loop: a fresh poll before each pass, `auto-pass-` action ids, stops on any manual action, keeps a pending answer for Retry | `OnDeviceSession.startYield` | missing | `table/guestSession.ts` | unit + game | |
| 2.16 | While skipping, the pill is lit ember and stops the skip; the stop reason shows | `ArenaPassAheadPill` | missing | | game | |
| 2.17 | Full control: hold the primary 0.6 s or the menu row; smart pass stops at every priority this turn; a "Full control" tag | `toggleFullControl`, `FullControlHold` | missing | | unit + game | |
| 2.18 | Passes the app sent (smart and skip) show no waiting pop-up | `isAutomaticPass` | partial (logic) | `core/smartPass.ts` | shared | as 2.01 |

## 3. Auto Pay and mana (priority 3)

| ID | Behaviour | iOS source | Web | Web file | Verified by | Evidence |
|---|---|---|---|---|---|---|
| 3.01 | Reads the remaining cost ({2}{R}, {S}, X skipped, Phyrexian, {2/W}, hybrids, {C}) | `ArenaAutoPay.need` | partial (logic) | `core/autoPay.ts` | shared | auto-pay cases pass on iOS and web (2026-10-22) |
| 3.02 | Reads mana abilities: only {T} and sacrificing the source; producedMana, any colour, first-sentence alternatives | `production` | partial (logic) | `core/autoPay.ts` | shared | as 3.01 |
| 3.03 | Source order: colourless 9, mono 10, dual 14, tri 16, any 18, creature +10, sacrifice 60 | `sources` | partial (logic) | `core/autoPay.ts` | shared | as 3.01 |
| 3.04 | Cheapest full plan; coloured pips first; never starts a cost it can't finish; blocked reasons | `plan`, `next` | partial (logic) | `core/autoPay.ts` | shared | as 3.01 |
| 3.05 | Floating mana spent first | `next` | partial (logic) | `core/autoPay.ts` | shared | as 3.01 |
| 3.06 | Payment corner: Auto Pay (dimmed when it can't pay), "Paying…" + Stop while running, Cancel secondary | `arenaPaymentButtons` | missing | `ui/GameScreen.tsx` | game | |
| 3.07 | One tap per settled snapshot; answers its own colour question with the planned colour and keeps it out of the choice browser; gives up after 30 steps or a repeated state ("Auto Pay stopped: tap the rest yourself") | `arenaAutoPayStep`, `arenaColorChoice`, `ArenaAutoPayDriver` | missing | | unit + game | |
| 3.08 | Undo pill while `undo_mana` is legal | `arenaControls` | missing | | game | |
| 3.09 | Sources that can pay glow orange; lands softer; a click on a source sends make_mana | `arenaGlow`, `arenaLane` | done | `ui/GameScreen.tsx`, `ui/arena/arena.css` | game | 2026-10-21 full game (README) |
| 3.10 | Floating mana symbols above your medallion; spendable ones take a click | `ArenaFloatingMana` | done | `ui/GameScreen.tsx` | game | 2026-10-21 |
| 3.11 | Payment caption "Pay {cost}" ("Pay the cost") | `arenaCaptionText` | partial | `ui/GameScreen.tsx` | game | |
| 3.12 | X starts at the most you can pay; amount pill steps, holds to repeat | `ArenaAmountRange`, `ArenaAmountPill` | done | `ui/arena/Browsers.tsx` | unit | `test/arenaBrowsers.test.ts` |

## 4. Hand, drag and drop (priority 4)

| ID | Behaviour | iOS source | Web | Web file | Verified by | Evidence |
|---|---|---|---|---|---|---|
| 4.01 | Resting hand tucked at the bottom edge; raised fan geometry | `ArenaHandFanLayout.slot` | done | `ui/arena/layout.ts` | unit | `test/arenaLayout.test.ts` |
| 4.02 | One card pops whole (rises 92 pt, 1.18x, upright); moving along the hand moves the pop card by card | `ArenaHandFan.tapped`, `scrubCard` | partial (hover raises the fan, lifts the hovered card) | `ui/GameScreen.tsx` | game | |
| 4.03 | Drag a hand card: it follows the pointer at 1.5x with a tilt, 1.38x and an ember shadow over the table | `ArenaHandFan.panned`, `dragPreview` | missing | | game | |
| 4.04 | Drop rule: inside the play area, outside the controls corner, after 24 pt up or 80 pt any way; otherwise it snaps back | `ArenaLayout.drops` | missing | | unit + game | |
| 4.05 | While carrying over the table its edge lights warm (no box) | `NativeGameView+Arena.arenaTable` | missing | | game | |
| 4.06 | A drop with several actions opens the action choice at the table centre; a refusal shows feedback | `panEnded`, `DragActionChoicePopup` | partial (click menu) | `ui/GameScreen.tsx` | game | |
| 4.07 | The hand rests during payments, targets, combat, choices, dragging, spectating | `ArenaHandPosture.resolve` | done | `ui/GameScreen.tsx` | game | 2026-10-21 |
| 4.08 | A step change lowers the hand; a click on the empty table drops a popped card, then lowers the hand | `arenaTapTable`, `arenaBoard onChange` | partial | `ui/GameScreen.tsx` | game | |
| 4.09 | Read a hand card (hold on iOS): right-click or a 0.35 s mouse hold opens the inspector | `ArenaHandFan.held` | missing | | game | |
| 4.10 | Cards playable from graveyard or exile join the fan's right end with a violet shimmer | `ArenaExtraHand`, `ArenaExtraCardShimmer` | missing | | unit + game | |
| 4.11 | Draws fly from the library (0.5 s), show at the draw spot (0.4 s), join the hand (0.22 s), staggered 0.25 s, at most 3 | `ArenaHandFan.noteArrivals` | missing | | game | |
| 4.12 | Hand up 0.22 s ease-out with overshoot, down 0.18 s | `postureAnimation` | partial | `ui/arena/arena.css` | game | |
| 4.13 | Spread-hand tab (portrait) | `ArenaHandPosture.spread` | n/a (desktop hand always fits; hover reads) | | | |

## 5. Triggers, prompts and remembered answers (priority 5)

| ID | Behaviour | iOS source | Web | Web file | Verified by | Evidence |
|---|---|---|---|---|---|---|
| 5.01 | Trigger order browser chosen by method `GAME_PICK_ABILITY` | `isTriggerOrder`, `arenaAbilityPrompt` | partial (message regex) | `ui/arena/Browsers.tsx` | shared | |
| 5.02 | "Order your triggers": click numbers a card (coin, gold rim), click again un-numbers; Done from N−1 picks ("k of N"); Auto Order | `ArenaAbilityBrowser` | partial (one pick per prompt) | `ui/arena/Browsers.tsx` | game | |
| 5.03 | The chosen order answers each later ordering prompt by itself; the plan survives target questions and ends at your next priority | `arenaOrderTriggers`, `arenaTriggerPlanAnswers`, `arenaTriggerStep` | missing | | shared + game | |
| 5.04 | "Always put my last-resolving pick first" sends `rememberTriggerFirst` | `ArenaAbilityBrowser`, `answerActions` | missing | | shared + game | |
| 5.05 | "Don't ask again this game" on a yes/no question sends `rememberAnswer` (ability scope), only when XMage offers an auto-answer | `canRememberAnswer`, `compactPromptControls` | missing | | shared + game | |
| 5.06 | "Remember my choice" in the choice browser | `ArenaChoiceList.options` | done | `ui/arena/Browsers.tsx` | unit | `test/arenaBrowsers.test.ts` |
| 5.07 | Answer actions only when the engine lists them and they fit the decision; standing actions ride on the next answer | `OnDeviceSession.submit`, `OnDevicePromptAdapter.answerActions` | missing | `table/guestSession.ts` | shared | |
| 5.08 | Gear: "Ask Again (N answered)", "Ask Trigger Order Again" (reset actions) | `GameMenus.swift` | missing | | game | |
| 5.09 | "Pass After Casting" (on) sent as `autoPassAfterCast` | `setAutoPassAfterCast` | missing | | unit | |
| 5.10 | "Resolve All" secondary with 2+ stack objects: one pass carrying `passUntilStackResolved` | `GameplayAffordances.resolveStackCommand` | missing | | shared + game | |
| 5.11 | XMage's "which ability" follow-up answered with the exact ability; its snapshot stays hidden unless that fails | `chosenAbilityAnswer`, `heldAbilitySnapshot` | partial (question flashes) | `table/guestSession.ts` | unit | |
| 5.12 | Commander taken notice (7 s) | `ArenaCommanderSteal` | missing | | shared + game | |
| 5.13 | Main button titles: Resolve; Next (TO MAIN / TO COMBAT / TO MAIN 2); End Turn; Pass; waiting labels | `arenaPassTitle`, `arenaWaitingTitle` | partial | `ui/GameScreen.tsx` | unit | |
| 5.14 | Prompt corner: the prompt's main action, else "Choices"; secondary the next action | `arenaButtonPlan` | partial | `ui/GameScreen.tsx` | game | |
| 5.15 | Question stage, mode, choice, player, split, pile browsers | `ArenaBoardViews.swift` | done | `ui/arena/Browsers.tsx` | unit + game | `test/arenaBrowsers.test.ts`, 2026-10-21 |
| 5.16 | Card choice browsers: effect titles (Scry, Surveil…), wells (BOTTOM / TOP…), multi-select with order coins, "2 OF 3", search over 6 | `BoardCardChoiceView.arenaStage` | partial | `ui/arena/Browsers.tsx` | game | |
| 5.17 | Response cue on your own priority outside your empty-stack main | `BoardResponseCue.make` | missing | | unit | |
| 5.18 | Captions: "Choose attackers." and the rest | `arenaCaptionText` | partial | `ui/GameScreen.tsx` | unit | |
| 5.19 | Keyword glossary in the inspector | `ArenaKeywordGlossary` | missing | | unit | |
| 5.20 | A player-target prompt with more than one pick opens its panel | `arenaSubmitPlayerTarget` | partial | `ui/GameScreen.tsx` | game | |
| 5.21 | Prompts no browser takes fall back to a glass pop-up with "Open choices" | `CompactPromptPopup` | missing | | game | |

## 6. Combat (priority 6)

| ID | Behaviour | iOS source | Web | Web file | Verified by | Evidence |
|---|---|---|---|---|---|---|
| 6.01 | Combat read from declare actions or your target prompt in a declare step | `ArenaCombatPhase.current` | partial | `ui/GameScreen.tsx` | unit | |
| 6.02 | "No Attacks" / "1 Attacker" / "N Attackers"; "No Blocks" / "1 Blocker" / "N Blockers"; Take Back | `arenaCombatButtons` | partial | `ui/GameScreen.tsx` | game | |
| 6.03 | Attack All (one opponent): every eligible attacker one per answer; "Attacking…" + Stop | `arenaStartAllAttack`, `arenaAttackStep` | missing | | unit + game | |
| 6.04 | Two-click declaration with a defender: the opponent's medallion glows red and takes the attack | `arenaOpponentMedallion` | missing | | game | |
| 6.05 | Combat arrows: red attack, grey blocked, gold block, amber dashed preview | `ArenaCombatArrows` | missing | | game | |
| 6.06 | Attackers glow #ff5a2e (keep colour while tapped), blockers #ffd38a | `arenaGlow` | done | `ui/arena/arena.css` | game | 2026-10-21 |
| 6.07 | Declared attackers and blockers stay selectable to undo | `OnDevicePromptAdapter.presentation` | done | `core/promptAdapter.ts` | shared | `prompt-cases.json` |
| 6.08 | Combat keyword badges on attackers and blockers | `ArenaBattlefieldCard` | missing | | game | |

## 7. Effects and sounds (priority 7)

| ID | Behaviour | iOS source | Web | Web file | Verified by | Evidence |
|---|---|---|---|---|---|---|
| 7.01 | Stack landing: settle from 1.07, colour bloom, one shine, motes (0.55 s) | `ArenaStackCard` | partial (settle + gold bloom) | `ui/arena/arena.css` | game | |
| 7.02 | Target arcs from the stack card (cyan yours, red theirs), drawn over 0.45 s; reticles on targets | `ArenaStackArc`, `ArenaTargetReticle` | missing | | game | |
| 7.03 | Arrival flight from the stack card, glow and sparks; tokens gather from motes | `BoardFXOverlay` flights, `gather` | partial (glide) | `ui/arena/ArenaCard.tsx` | game | |
| 7.04 | Departure: flies to its owner, embers; exile pillar and sigil | `BoardFXOverlay`, `exileMoment` | missing | | game | |
| 7.05 | Damage flash with "−N" | `BoardFXOverlay` | missing | | game | |
| 7.06 | Counter moments (+1/+1, −1/−1, loyalty, coin) with labels | `counterMoment`, `BoardFXCounterKind.label` | missing | | game | |
| 7.07 | Stats moment "+X/+Y" | `statsMoment` | missing | | game | |
| 7.08 | Phasing bands; a phased-out tile at 0.42 with "Phased out" | `phaseMoment`, `ArenaBattlefieldCard` | missing | | game | |
| 7.09 | Transform ring of light while the tile flips | `transformMoment` | missing | | game | |
| 7.10 | Steal: the taker's chain drags the card home | `chainMoment` | missing | | game | |
| 7.11 | Attack and block marks | `BoardFXOverlay` | missing | | game | |
| 7.12 | Strike trails and impact | `BoardFXOverlay` | missing | | game | |
| 7.13 | Life change floats at the medallion; the number rolls | `BoardFXOverlay`, `ArenaHeroMedallion` | missing | | game | |
| 7.14 | Board shake and red vignette when you take 5+ | `BoardImpactShake`, `BoardHitVignette` | missing | | game | |
| 7.15 | Turn banner: "Your turn" / "<Name>’s turn", 0.9 s | `BoardTurnBanner.arenaBanner` | missing | | game | |
| 7.16 | Sounds: board cues by event (casts by type, arrivals by land and creature type, attacks, blocks, strikes, deaths, exile, counters, steal, life), UI cues (tap, pickup, play, draw, open/close, error, response alert, turn, victory/defeat), cooldowns; `.caf` converted to `.m4a` | `GameAudio.swift`, `BoardFXSound.cues`, `GameSoundSignature` | missing | | game | |

## 8. Board pieces (priority 7)

| ID | Behaviour | iOS source | Web | Web file | Verified by | Evidence |
|---|---|---|---|---|---|---|
| 8.01 | Corner plaques, ember / leather / quiet label, pressed state | `ArenaPlaqueButtonStyle` | done | `ui/GameScreen.tsx` | game | 2026-10-21 |
| 8.02 | Phase strip: 8 icons always, lit track to the current step, spark along the track, ignite | `ArenaPhaseStrip` | partial | `ui/arena/layout.ts`, `ui/GameScreen.tsx` | game | |
| 8.03 | Day/night coin and storm count above the strip when they matter | `TavernTableHints` | missing | | game | |
| 8.04 | Gear menu: Game Log, Stack (N), Phase Stops, Full control, Game Settings | `arenaGameMenuItems` | partial | `ui/GameScreen.tsx` | game | |
| 8.05 | A new prompt closes the corner menu and the player card | `arenaBoard onChange` | missing | | game | |
| 8.06 | Stack card: only the top object; tab with the count opens the stack browser; it closes when the stack empties | `ArenaStackCard`, `arenaTable` | partial (shows up to 4) | `ui/GameScreen.tsx` | game | |
| 8.07 | Stack browser: count coin, YOUR RESPONSE / WAITING, numbered coins, RESOLVES NEXT, Stop skipping / Resolve All / Done | `ArenaStackBrowser` | partial | `ui/arena/Browsers.tsx` | game | |
| 8.08 | Zone browser: Cast plaques, Choose for targets, library wording | `ArenaZoneBrowser` | partial | `ui/arena/Browsers.tsx` | game | |
| 8.09 | Revealed and Looked-at chips by the opponent's piles | `arenaRevealedChips` | missing | | game | |
| 8.10 | Top of library revealed face up on the deck, playable | `TopOfLibraryCard` | missing | | game | |
| 8.11 | Player card: portrait, life, status badges, zone grid with counts, lit where you can cast from, named exile zones | `ArenaPlayerCard` | partial | `ui/GameScreen.tsx` | game | |
| 8.12 | Medallion glows ember on its owner's turn; status badges around it | `ArenaHeroMedallion`, `TavernEffectOrbitBadges` | partial | `ui/GameScreen.tsx` | game | |
| 8.13 | Game log: gold title, turn dividers, an icon per event, smart pass lines dimmed, card links that open the inspector, oldest at the top, "Latest actions ↓" | `GameLogDrawer` Arena look | partial | `ui/GameScreen.tsx` | game | |
| 8.14 | Inspector: dim 0.45, the card large, live-state notes, glossary, rules when the art can't show them, attachments, double-faced cards turn | `CardInspector.arenaBody` | partial (hover image) | `ui/GameScreen.tsx` | game | |
| 8.15 | Opening hand: "OPENING HAND", message, a large fan dealt in, Mulligan / Keep; click a card to enlarge | `OpeningHandOverlay` | partial | `ui/GameScreen.tsx` | game | |
| 8.16 | Result: gold rays and motes on a win, ash on a loss; reason line and game summary | `GameCompletionOverlay`, `GameResultBackdrop` | partial | `ui/GameScreen.tsx` | game | |
| 8.17 | Notices replace the caption for 2.4 s; rejected actions inline under the caption | `arenaShowNotice`, `ActionRejectionInlineView` | partial (toast) | `ui/GameScreen.tsx` | game | |
| 8.18 | Tiles: counters (2 chips), COPY tag, keyword badges bottom left | `ArenaBattlefieldCard` | partial | `ui/arena/ArenaCard.tsx` | game | |
| 8.19 | Rows shrink to 70 % before scrolling | `ArenaRowFit.fit` | partial (overlap) | `ui/arena/layout.ts` | unit | |
| 8.20 | Turn labels count rounds | `TableRounds` | missing | | unit | |
| 8.21 | Combo loop: offer, repeat modes, forecast, stop reasons | `ComboLoop.swift`, `OnDeviceSession` | missing | | shared + game | |
| 8.22 | The local poll pace shows every AI action (engine-held poll; iOS polls 0.3 s / 0.12 s chain) | `OnDeviceLocalPollSchedule` | done (different mechanism, same result) | `table/guestSession.ts` | game | 2026-10-21 |

## 9. Out of game (priority 8, after every gameplay row)

| ID | Behaviour | iOS source | Web | Web file | Verified by | Evidence |
|---|---|---|---|---|---|---|
| 9.01 | Arena top bar, home, Play panel with deck boxes, custom table | `Menus/Arena*.swift` | missing (setup form) | `ui/SoloSetup.tsx` | game | |
| 9.02 | Deck boxes that open | `ArenaDeckBox` | missing | | game | |
| 9.03 | Options pages (Gameplay, Board, Audio, Display & Artwork, Performance) with Arena controls | `ArenaOptionsView` | missing | | game | |
| 9.04 | Deck import (Archidekt, Moxfield) | `OnDeviceDeckLinkImporter` | missing | | unit | |
| 9.05 | Sign-in and own decks through Supabase | `PlayerAccount`, social backend | missing (needs Caleb) | | game | |
| 9.06 | Profile, Ranked hall | `Ranked/*` | missing | | game | |

## Android follow-ups

Rows whose shared cases Android can't run yet. Each needs a port into `apps/android/core` and a runner in
`ParityGoldenTest.kt` (called from `ContractChecks.kt`):

- Arena pace (`arena-pace-cases.json`): `BoardEventTimeline.kt` has the Hearth pace only.
- Stop for Removal and the skip-mode threat stop (`smart-pass-cases.json`): `OnDeviceSmartPass.kt`.
- Auto Pay (`auto-pay-cases.json`).

## Intentionally different on desktop

- No portrait layout or spread-hand tab: the web board is horizontal only (README).
- Hover reads a card where iOS needs a hold; the full inspector is a right-click.
- Keyboard shortcuts (Desktop input above) have no iOS counterpart.
- Polling: the browser engine holds a poll and answers at the next snapshot, where iOS polls on a timer (8.22).

## Log

- 2026-10-22: checklist written from the iOS Arena sources and the web branch rebased onto `origin/main`
  (`claude/web-arena-parity`). Logic ported and shared: Arena pace (`boardEvents.ts`), smart pass with Stop for Removal
  and the skip modes (`smartPass.ts`), Auto Pay (`autoPay.ts`).
