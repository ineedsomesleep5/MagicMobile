# Issue #4: source-to-control coverage ledger

This ledger identifies the implemented routes and their tests. It is not a claim
that every card, UI interaction, native runtime, or phone configuration passed.
Executed results and exact commits belong in the release handoff and workflow
artifacts. The rules source remains XMage `8aea65ae9ae3c89970fe865e1316105539e097ca`.

Diagnostic release evidence: app source `7c27eaa`, engine `76c18bf`, full native run
**34731298892**, actual product run **34732453251**, non-simulator run **34732453204**.
Internal-only upload **0.1.0 (2026091203)** succeeded. Build 2026091202 was installed
but failed during native startup; the new diagnostic capture and successful
gameplay still require phone validation in
[issue #7](https://github.com/ineedsomesleep5/MagicMobile/issues/7).
See [the diagnostic handoff](DIAGNOSTIC_TESTFLIGHT_2026091203.md) for hashes,
Apple availability and private report instructions. Compilation is not runtime acceptance.

## Decision path

`PlayerQueryEvent` → `QueryEncoder` → `DecisionSpec` / `MatchMailbox` → native JSON
→ `EngineClient` / `OnDeviceSnapshotAdapter` / `OnDevicePromptAdapter` → existing
compact or full prompt controls → `UniversalPromptResponseCommandBuilder` →
`OnDeviceSession` → exact prompt/request IDs → `DecisionSpec.validate` →
`MobileHumanPlayer.waitForResponse` on the real GAME worker.

A queued response is not a resolved game action. The UI waits for consumption and
new projections. Retrying uncertain transport delivery retains the same command
request UUID; a new prompt cannot accept the old token/revision. There is no
batch-attack, batch-target, guessed special token, or replacement rules engine.

| Upstream event | Native response and existing control | Regression evidence entrypoints |
|---|---|---|
| ASK | Boolean; authoritative Yes/No labels and commands, including mulligan and command-zone decisions. No command-zone inference from message text. | `OnDevicePromptAdapterTests.testAskRoundTripsThroughExistingCommandBuilder`, `testCommanderAskPreservesAuthoritativeConfirmationInsteadOfMessageHeuristic`; real Commander and game-start tests. |
| SELECT: priority | An engine-reported object UUID, boolean pass, supported integer, exact `special`, or explicit named floating-mana response. `canPlayObjects` is the action authority. | `RealQueryTests.selectVariants`; `OnDevicePromptAdapterTests.testPriorityPassAndExplicitSpecialWithoutInventedPlayActions`, `testSelectIntegerResponsesRetainEngineBoundsAndResponseType`; snapshot playability tests. |
| SELECT: combat | One UUID toggle per actual prompt and boolean Done. Highlight lists are not a substitute for upstream legality or deselection. No invented aggregate attack/block command. | `RealQueryTests.selectVariants`; `OnDevicePromptAdapterTests.testCombatSelectUsesSequentialUUIDTogglesAndBooleanDone`; real combat projections. |
| PLAY_MANA | Mana-source UUID is distinct from a floating-mana object containing the payload's player UUID and named color. Cancellation is boolean false; the special button uses only the published token. | `RealQueryTests.mana`; `testManaUsesPayloadPlayerIdentityAndExactNamedColors`, `testManaCancelUsesInlinePaymentActionAndSendsOnlyBooleanFalse`; native mana-source snapshot tests. |
| PLAY_X_MANA | Bounded integer X, source UUID, explicit floating mana, or boolean cancellation. Full detail controls remain reachable alongside quick controls. | `RealQueryTests.mana`; mana/X adapter tests and existing amount-control helpers. Physical use of the complete payment sequence remains a device check. |
| CHOOSE_CHOICE | One exact string key; published order, hints and special keys remain distinct. Optional cancel is empty string; special-empty is typed null, not `#`. | `RealQueryTests.choices`, `replacementLoop`; `testChoiceKeysSpecialsAndOptionalCancelRemainExact`, `testEmptySpecialHasDistinctActionAndTypedNullWithExactMetadata`. |
| CHOOSE_MODE | One exact mode UUID, including only the upstream-provided Done/Cancel UUID choices. | `RealQueryTests.modes`, `modeLoop`; `testModesPreserveEngineOrderAndSubmitOneUUID`. |
| CHOOSE_ABILITY / PICK_ABILITY | One ability UUID, not its source-card UUID; preserve split/MDFC labels and trigger-order instructions. | `RealQueryTests.abilityFaces`, `orderingMetadata`; `testAbilityFamiliesUseAbilityUUIDAndRetainLabels`. |
| PICK_TARGET | One published candidate UUID per prompt, including current selections for deselection and explicit MDFC aliases. Search and ordering use supplied card views only. Optional completion is boolean false when authorized. | `RealQueryTests.targetCandidates`, `targetLoop`, `targetFaces`, `libraryOrder`; target/order/four-player/face-alias adapter tests. |
| AMOUNT | Exact signed integer bounds; narrow quick buttons or manual entry. No implicit zero minimum. | `RealQueryTests.amounts`, `amountLoops`; `testAmountsRespectSignedEngineBounds`, `testAmountButtonsExposePublishedNegativeRangeWithoutInventedBounds`. |
| MULTI_AMOUNT | One list matching the allocation rows, individual bounds and total. The native adapter translates it into upstream's space-separated integer answer. Cancellation requires explicit permission. | `RealQueryTests.amounts`, `amountLoops`; `testAllocationsEnforceRowsSumAndExplicitCancellation`. |
| CHOOSE_PILE | Boolean true means pile 1, false means pile 2. Only explicitly disclosed pile cards are shown. | `testPileSelectionTranslatesToBooleanAndMapsOnlyExplicitCards`; `RealResolvingCancellationTests` uses a genuinely resolving Fact or Fiction choice. |
| PERSONAL_MESSAGE | Not a decision. The mailbox emits a private informational event; `OnDeviceMessageLog` carries it into the existing per-seat game log without answering/replacing a prompt. History is bounded, in-memory, replay-safe and cleared on close. | `OnDeviceMessageLogTests`; `OnDeviceMessageSessionTests.testPrivateNoticesReachExistingLogWithoutReplayOrCrossGameRetention`. These routing tests use explicit event fixtures, not a substitute game. |
| DRAFT_PICK_CARD / TOURNAMENT_CONSTRUCT | Explicitly outside this constructed-Commander MVP. They fail with a format-specific error rather than being auto-answered. | `QueryEncoder`'s explicit format boundary. |

## Zones, identity and privacy

The final source audit also added explicit regressions for incomplete controls:
`testFloatingManaChoicesUseThePayloadPlayersPoolAndExactResponses`,
`testSpecialPaymentWithoutButtonMetadataUsesOnlyPinnedProtocolToken`,
`testDeclaredAttackerRemainsSelectableOnTheNextPromptWithoutAddingOtherCards`,
`testLocalAndAuthorizedControlledAttackersRemainSelectableWithViewerCommands`
and `testUnauthorizedOrMismatchedControlledAttackerIdentityFailsClosed`.
Actual payment details remain reachable beside quick actions.

| Surface | Implemented authority and boundary | Tests |
|---|---|---|
| Hand and library | Own/explicitly controlled hand views only; opponents' hidden hands and libraries remain counts. No card reconstruction from hidden UUIDs. | `RealControlPrivacyTests`; `testActualFourSeatPollPreservesViewerAndHiddenZoneCounts`. |
| Battlefield, graveyard, command and stack | Per-seat upstream views; public combat identities, exact stack order and current engine playability. A displayed card type never creates a legal action. | `RealPortraitProjectionTests`; snapshot stack/combat/playability tests. |
| Exile, revealed, looked-at and companion groups | Named, explicitly supplied groups, including authorized inspections. No cross-zone lookup to disclose a hidden object. | `RealControlPrivacyTests`; `testPublicZonesAndAuthorizedInspectionsAreMappedWithoutHiddenHandLookup`, `testNamedExileSourceRetainsOnlyItsEngineReportedPlayableAction`. |
| Face-down cards | Preserve upstream redaction; do not use original card data, images or a catalogue to reverse it. | `testSignedAndVariableStatsRemainExactAndHiddenDetailsAreNotRebuilt` and real privacy tests. |
| Commander tax and damage | Public per-commander definitions and upstream watchers. Partners remain independent; absent tax information is not treated as a known zero. | `RealCommanderRulesTests`, `RealPortraitProjectionTests`, `testPartnerTaxAndDamageStayIndependent`. |
| Four-player identity | Authenticated seats and engine UUIDs are distinct. Explicit viewer identity is checked before projection; opponents are selectable without fixed `human` / `ai-1` assumptions. | Four-seat real JVM games, snapshot/model tests and SDK-only board identity tests. SDK test compilation is not execution. |

Private notices are historical information actually delivered to the viewer, not
current opponent-hand snapshots. They are not persisted or exported. This is not
a complete desktop-style action history: unrelated raw state or arbitrary engine
objects are never dumped to fill gaps in the log.

## Setup, lifecycle and networking

- `OnDeviceAppConfiguration` selects the embedded path for native-linked builds.
  An unlinked Release displays a missing-engine error even with debug arguments;
  only explicit debug/reference builds retain the legacy UI. No automatic server
  fallback exists in the native consumer path.
- Included/imported deck selection, AI deck/count and human-count preferences are
  retained separately from match state. Invalid/deleted selections recover to
  valid local defaults. These preferences are not a saved or resumable game.
- `OnDeviceRuntimeManager` installs the immutable C backend once per process, but
  creates and owns each isolate separately. Failed installation remains retryable.
  A busy/failed destroy retains ownership for explicit cleanup; it never frees a
  live worker's memory to make a retry appear successful.
- Actual MAD AI is integrated. JVM regressions are distinct from native AI
  validation; diagnostic `aiEnabled` / `nativeDeviceValidated` flags remain honest.
- `GameKitTransport`, `HostRouter` and the application dispatcher retain per-peer
  ordering, authenticated immutable seat bindings, build/epoch/sequence matching,
  request correlations, bounded queues/packets and safe uncertain-delivery retries.
  Peers cannot request raw create/destroy/shutdown or choose another seat.
- Background/presence changes stop user submissions and communicate suspension.
  A terminated/disconnected host is not silently migrated. The UI explains that
  players must stay in the foreground and may need to start a new match.

Tests: `OnDeviceAppConfigurationTests`, `OnDeviceBackendRegistrationTests`,
`OnDeviceDeckResolverTests`, `OnDeviceSessionTests`, `OnDeviceMultiplayerTests`,
Swift protocol/packet tests, C lifetime/shutdown fixtures, real JVM lifecycle,
AI, controlled-turn, privacy and resolving-cancellation regressions. The workflow
also sends the exact same-commit Swift-exported five bundled decks through real
XMage validation and a first prompt.

## Explicit limits and device gates

`RealAILifecycleTests.cancelledOpeningSelection` deterministically covers the
opening-player cancellation end check and its copies; both real MAD lifecycle
configurations and complete-game regressions passed after the fix. Busy teardown
retries only `engine_busy_shutdown` within 20 seconds and preserves worker-exit,
idle-simulation-pool and ownership assertions. It does not waive a stuck worker.

Chained/nested turn control is explicitly unsupported rather than misrouted.
Durable match restore, host migration, draft and tournament construction are not
implemented. The host is a trusted friend's phone, not a cheat-proof competitive
server. No exhaustive card/UI parity is asserted.

The full ARM64 archive and unsigned product link must succeed independently of
this source ledger. On physical devices/TestFlight, still execute native startup,
offline completed games, all prompt/payment families, repeated matches and cleanup,
1–3 AI opponents, memory/thermal measurements, 2–4-phone Game Center games,
authorized/hidden-zone checks, rotation/accessibility and interruption recovery.
Signing, build-number selection and TestFlight upload belong to desktop Codex.
