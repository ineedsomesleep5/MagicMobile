# XMage Mobile Route Coverage

MagicMobile is Commander-only for the current product milestone, but the mobile client must stay generic: XMage owns legality, priority, stack, prompts, AI, and Commander state. Fixture cards such as Sol Ring, Arcane Signet, Evolving Wilds, a commander, or a removal spell are proof cases only. They must not become card-specific bridge routes.

## Route Rule

Every gameplay route should follow this chain:

1. XMage exposes state, playable objects, or a callback prompt.
2. The Java bridge preserves exact XMage ids, callback metadata, and prompt identity.
3. Shared `LegalAction`, `PromptEnvelopeV2`, or `GameCommand` carries the needed ids without client guessing.
4. Swift models decode the shape without losing ids.
5. iOS renders a safe mobile surface and submits only exact action/prompt data.
6. XMage returns the authoritative snapshot.

If any step is missing, the UI should show an unsupported/incomplete state and refresh from the latest snapshot. It must not auto-pick the first option, default yes, default pile 1, default amount 0, default colorless mana, or default command-zone replacement.

## Status Legend

- **complete**: route is typed, bridge-wired, rendered/submittable on iOS, and has current enough live proof for the milestone path.
- **wired but unproven**: implementation exists, but current live or deterministic proof is missing.
- **UI missing**: bridge/shared/Swift can carry it, but iOS does not yet provide the right user control.
- **bridge missing**: route is not emitted or accepted by the Java bridge as a generic XMage route.
- **fixture missing**: implementation exists, but no targeted live fixture proves it.
- **deterministic fixture-proven**: route is proven by a dev/test-only real-XMage fixture report with `source: "xmage-java-bridge"` and `directStateSeeded: true`.
- **later scope**: not required for the immediate iOS Commander alpha path, but should remain visible as future XMage parity work.

## Current Generic Route Matrix

| Route/feature | XMage source/callback/action | Bridge emits it? | Shared type supports it? | Swift model decodes it? | iOS command builder submits it? | iOS UI renders it? | Live fixture exists? | Deterministic fixture proven? | Current status | Next fix |
|---|---|---|---|---|---|---|---|---|---|---|
| keep hand | Opening hand boolean response; `keep_hand` | Yes; sends `sendPlayerBoolean(false)` | Yes | Yes | Yes | Yes, action tray/prompt action | Yes, core-flow smoke | No; normal smoke only | complete | Keep in core smoke. |
| mulligan | Opening hand boolean response; `mulligan` | Yes; sends `sendPlayerBoolean(true)` | Yes | Yes | Yes | Yes, action tray | Partial; typed path exists | No | fixture missing | Add repeated-mulligan live case. |
| play land | `GameView.getCanPlayObjects()` card click | Yes; emits `play_land` from hand and sends source UUID | Yes | Yes | Yes | Yes, hand drag/tap/action tray | Yes, core-flow smoke | No; legal deck order is nondeterministic | complete | Keep source-UUID regression tests. |
| cast spell | `GameView.getCanPlayObjects()` card/command click | Yes; emits `cast_spell` and sends source UUID | Yes | Yes | Yes | Yes, hand/action tray | Yes, commander-gauntlet | Yes | deterministic fixture-proven | Keep source-UUID regression tests. |
| make mana | Playable mana source/action | Yes; emits `make_mana`, adds source mana during payment, sends source UUID | Yes | Yes | Yes | Yes, battlefield tap and payment source buttons | Yes, core-flow smoke and `mana-rock` fixture | Yes for Sol Ring mana-rock proof | deterministic fixture-proven | Keep Sol Ring mana-rock proof current; keep Arcane Signet as a separate manual/debug regression until reproved. |
| play mana | `GAME_PLAY_MANA` | Yes; emits prompt `manaChoices` and accepts `play_mana` | Yes | Yes | Yes | Yes, from explicit `manaChoices` or visible floating mana only | Yes, commander-gauntlet | Yes | deterministic fixture-proven | Keep payment prompt proof current; do not show guessed colors when XMage exposes no choices and the pool is empty. |
| choose mana | Mana choice prompt / bridge response kind `mana` | Yes for `choose_mana`, but `GAME_PLAY_MANA` maps primarily to `play_mana` | Yes | Yes | Yes | Yes, mana choice picker | No targeted live case | No | fixture missing | Add explicit color-choice fixture. |
| pay cost | `GAME_ASK` classified as pay/cost, payment prompt | Yes; explicit `pay` boolean required; `GAME_PLAY_MANA` covers mana payment prompts | Yes | Yes | Yes | Yes, confirmation/payment buttons and source mana panel | Yes, commander-gauntlet payment prompt | Yes for payment prompt | deterministic fixture-proven | Add explicit decline fixture later. |
| activate ability | Playable object ability id | Yes; emits `activate_ability`, requires the selected ability id for validation, then dispatches through XMage's source-click playable path | Yes | Yes | Yes | Yes as generic action button | Yes, `activated-ability-stack` and Terramorphic Expanse in commander-gauntlet | Yes | deterministic fixture-proven | Keep source-click plus ability-id validation regression tests. |
| target prompt | `GAME_TARGET` | Yes; emits `choose_target` options | Yes | Yes | Yes | Yes, option grid/target action | Yes, `activated-ability-stack` target selection | Yes for targeted activated ability | deterministic fixture-proven | Add targeted spell fixture later. |
| card prompt | `GAME_SELECT` / card list prompt | Yes; emits `choose_card` or `search_select` | Yes | Yes | Yes | Yes, card picker | Partial through search-like callbacks | No | fixture missing | Add explicit choose-card fixture. |
| player prompt | `GAME_TARGET` with player UUID | Yes; emits player options / `choose_player` | Yes | Yes | Yes | Yes, player option grid | Partial through target/player callbacks | No | fixture missing | Add explicit choose-player fixture. |
| mode prompt | `GAME_CHOOSE_CHOICE` message containing mode | Yes; emits `choose_mode` | Yes | Yes | Yes | Yes, option grid | Targeted `prompt-mode` fixture probe exists | No | fixture missing | Current Austere Command probe seeds real XMage state but surfaces as `GAME_CHOOSE_ABILITY:ability`; find a representative fixture that emits a true mode prompt or add evidence-backed bridge classification without guessing. |
| ability prompt | `GAME_CHOOSE_ABILITY` / `AbilityPickerView` | Yes; emits `choose_ability` | Yes | Yes | Yes | Yes, ability picker | Yes, `activated-ability-stack` | Yes | deterministic fixture-proven | Add more multi-ability fixtures later. |
| amount prompt | `GAME_GET_AMOUNT` / `GAME_PLAY_XMANA` | Yes; emits `choose_amount` / `play_x_mana` | Yes | Yes | Yes | Yes, amount picker | No | No | fixture missing | Add bounded numeric prompt fixture. |
| multi amount prompt | `GAME_GET_MULTI_AMOUNT` | Yes; emits `choose_multi_amount` | Yes | Yes | Yes | Safe fallback only; iOS shows unsupported instead of submitting ambiguous values | No | No | UI missing | Build real multi-amount UI with per-slot labels/ranges and fixture. |
| pile prompt | `GAME_CHOOSE_PILE` | Yes; emits pile choices/cards | Yes | Yes | Yes | Yes, pile buttons with counts | No | No | fixture missing | Add split-pile fixture. |
| search select | Search/select callbacks; XMage may expose this as `GAME_TARGET`/`choose_target` for library choices | Yes; emits `search_select` when exposed and preserves `choose_target` search prompts when XMage uses target callback | Yes | Yes | Yes | Partial; card picker or exposed-selection fallback | Yes, commander-gauntlet Terramorphic search | Yes | deterministic fixture-proven | Add explicit `search_select` callback fixture later. |
| order triggers | `GAME_CHOOSE_CHOICE` order/stack prompt | Yes; maps order response to `order_items`; shared also has `order_triggers` | Yes | Yes | Yes | Yes, basic up/down ordering control submits exact `orderedIds` | No | No | fixture missing | Add targeted trigger-order fixture and bridge classifier if XMage exposes ordering through `GAME_TARGET`. |
| order items | `GAME_CHOOSE_CHOICE` order/stack prompt | Yes; emits `orderedItems` / `order_items` | Yes | Yes | Yes | Yes, basic up/down ordering control submits exact `orderedIds` | No | No | fixture missing | Add targeted order-items fixture. |
| commander replacement | `GAME_ASK` mentioning commander/command zone | Yes; emits `commander_replacement` | Yes | Yes | Yes | Yes, command-zone/original-zone buttons | Yes, commander-gauntlet | Yes | deterministic fixture-proven | Keep no-default-command-zone tests. |
| answer yes/no | `GAME_ASK` confirmation | Yes; explicit `confirmed` required | Yes | Yes | Yes | Yes, confirmation buttons | Partial | No | wired but unproven | Add generic yes/no fixture beyond commander/payment. |
| declare attackers | Combat step `declare-attackers` | Yes; emits attacker/defender pair payloads | Yes | Yes | Yes | Partial; action button submits pair, no full combat assignment UI | Yes, `commander-damage` | Yes | deterministic fixture-proven | Improve combat picker UI and add blocker-pair proof. |
| declare blockers | Combat step `declare-blockers` | Yes; emits blocker/attacker pair payloads | Yes | Yes | Yes | Partial; generic action button submits single exposed LegalAction, no full blocker picker | Yes, `blocker-flow` submitted `declare_blockers` | Yes | deterministic fixture-proven | Add richer blocker picker UI for multi-attacker/blocker assignments. Current fixture uses Commander-legal `Memnite` as the colorless AI attacker. |
| damage assignment | Combat damage assignment prompt/routes | No generic route found | No | No | No | Safe fallback only for unknown prompts/actions | Probe only; no successful fixture proof | No | bridge missing | Map the actual XMage damage assignment callback/action when encountered; current full-AI gate must fail until this is real or formally excluded. |
| pass variants | Priority and skip actions | Yes; `pass_priority`, `pass_until_response`, `pass_until_next_turn`, `advance_phase` | Yes | Yes | Yes | Yes, action tray | Yes, core-flow smoke | No | complete | Keep AI/pass reliability in smoke gate. |
| stack objects | `GameView.getStack()` | Yes; emits `xmage.stack`, player stack zone, source id/name, rules text, paid status, and controller/targets only when XMage exposes them | Yes | Yes; optional controller/source-zone/target metadata decodes and renders when present | N/A | Yes, stack surface shows count/top/source/respond-pass/pending prompt plus optional metadata | Yes, `activated-ability-stack` and `triggered-ability-stack` | Yes | deterministic fixture-proven | Widen Swift stack metadata for optional controller/targets. |
| activated ability stack | Activated ability object on stack | Generic stack can carry it; `activated-ability-stack` scenario is live-proven | Yes as stack/action types | Partial; see stack metadata note | Ability submit yes | Stack renders generic object | Yes, `activated-ability-stack` | Yes | deterministic fixture-proven | Widen Swift stack metadata for optional controller/targets. |
| trigger stack | Triggered ability object/order prompt | Generic stack/order can carry it; `triggered-ability-stack` proves ETB trigger visibility through a real XMage stack snapshot | Yes for stack and order routes | Partial; see stack metadata note | Order submit partial | Stack renders generic object; trigger ordering UI partial | Yes, `triggered-ability-stack` | Yes | deterministic fixture-proven | Add explicit multi-trigger ordering proof when XMage exposes an order prompt. |
| replacement prompts | Generic replacement-choice prompts | Partial; commander replacement classified, generic replacement not distinct | Partial through `answer_yes_no` / `commander_replacement` | Yes for those shapes | Yes for those shapes | Partial | No | No | bridge missing | Add generic replacement prompt classifier if XMage exposes one. |
| revealed/looked zones | `GameView.getRevealed()` / `getLookedAt()` | Yes; emits `xmage.revealed` and `xmage.lookedAt` | Yes | Yes | N/A | No dedicated iOS surface; panels decode only | No | No | UI missing | Add revealed/looked-at zone sheets and viewer scoping. |
| library count | `PlayerView.getLibraryCount()` hidden cards | Yes; emits hidden library placeholders | Yes | Yes | N/A | Partial; count implicit in decoded zone, not surfaced as zone control | No | No | wired but unproven | Display library count and prove obfuscation. |
| graveyard | `PlayerView.getGraveyard()` | Yes; snapshot and `xmage.players[].zones.graveyard` | Yes | Yes | N/A | Yes, surface chip/zone sheet | Yes in snapshots, not targeted | No | wired but unproven | Add zone movement fixture. |
| exile | `PlayerView.getExile()` / named exile zones | Yes; player exile and named `exileZones` | Yes | Yes | N/A | Yes, surface chip/zone sheet | Partial | No | fixture missing | Add exile/commander replacement fixture. |
| command zone | `CommandObjectView` and player command zone | Yes; command zone cards and command cast source zone | Yes | Yes | Yes for command-zone cast | Yes, command surface | Yes, commander-gauntlet | Yes | deterministic fixture-proven | Keep command-zone cast proof current. |
| commander tax | Parsed from command object rules text | Yes; emits `commanderTax` | Yes | Yes | N/A | Partial; model decodes but UI only indirectly shows player state | Yes, commander-gauntlet | Yes | deterministic fixture-proven | Render tax more prominently on iOS. |
| commander damage | Parsed from commander rules text/log variants | Yes; emits `commanderDamage` map | Yes | Yes | N/A | Partial; decoded but not prominent UI | Yes, `commander-damage` | Yes | deterministic fixture-proven | Render commander damage more prominently on iOS. |
| AI waiting | AI priority/waiting snapshot state | Yes; `waitingOnPlayerId`, `priorityPlayerId`, pending status | Yes | Yes | N/A | Yes, status/live update text | Yes, core-flow smoke | No | complete | Keep long-wait watchdog coverage. |
| stalled recovery | Health/watchdog stale AI/game state | Gateway health returns `stalled` / `recreate_game` | Yes | Yes | N/A | Partial; health/status text, no one-tap recovery flow | Unit-tested | No | wired but unproven | Add iOS recovery CTA and live stalled fixture. |
| stale action recovery | Bridge revision/prompt identity mismatch | Yes; rejects stale revision/prompt and gateway can refresh 409 snapshot | Yes | Yes | Yes; sends `expectedBridgeRevision` | Partial; user sees error/status, not a tailored retry UI | Unit-tested | No | wired but unproven | Add iOS retry/refresh affordance. |
| bridge unavailable | Bridge/gateway health unavailable | Yes; health returns `unavailable` / `restart_gateway` | Yes | Yes | N/A | Yes, status text during setup/check | Unit-tested | N/A | complete | Keep setup health messaging clear. |

## Fixture Reality

The intended release-gate command is:

```sh
ENABLE_XMAGE_FIXTURES=true NODE_ENV=test XMAGE_GATEWAY_URL=http://localhost:17171 XMAGE_SMOKE_SCENARIO=commander-gauntlet XMAGE_USE_FIXTURE=true pnpm smoke:xmage
```

For full Commander vs AI parity, use the stricter aggregate gate:

```sh
ENABLE_XMAGE_FIXTURES=true NODE_ENV=test XMAGE_GATEWAY_URL=http://localhost:17171 XMAGE_SMOKE_SCENARIO=commander-full-ai XMAGE_USE_FIXTURE=true pnpm smoke:xmage
```

`commander-full-ai` runs the required deterministic scenarios and reports `allRequiredScenariosPassed`, `routeFamiliesCovered`, `routeFamiliesMissing`, `stepsBlocked`, `iOSRequiredRoutesMissing`, and `readinessVerdict`. It is expected to fail until `prompt-variety` and `damage-assignment` have real XMage proof or are explicitly excluded with safe iOS fallback behavior.

This gate passed locally on June 23, 2026. The fixture route is dev/test-only and production-disabled. The old default bridge remains a remote XMage `Session` client, but fixture mode now launches an embedded same-JVM `MagicMobileEmbeddedServerBridge` so the route can reach server-owned `GameController` / `Game.cheat(...)`. The latest successful report used game `1f47d3b4-6e7a-43ac-9440-f1923a41c1b1` with real gameplay snapshots, `source: "xmage-java-bridge"`, `fixtureCallUsed: true`, `directStateSeeded: true`, `seededStateVerified: true`, final `bridgeRevision: 133`, final `xmageCycle: 223`, and `stepsBlocked: []`.

The full gauntlet now reports explicit route-family proof for `play_land`, `cast_spell`, `make_mana`, `activate_ability`, `search_select/choose_card`, `choose_target`, `answer_yes_no`, `pay_cost`, `commander_replacement`, `pass_priority`, `stack_object_seen`, `trigger_seen`, `zone_update_seen`, and `commander_tax_seen`. `prompt-variety` separately requires stack objects, activated abilities, choose-ability, choose-mode, order-triggers/items, choose-amount, choose-multi-amount, and choose-pile. A blocked report should show missing coverage as `route_family:*` entries in `stepsBlocked` / `routeFamiliesMissing`; simulator snapshots or loose prompt counts do not satisfy them.

Targeted deterministic stack proof commands:

```sh
ENABLE_XMAGE_FIXTURES=true NODE_ENV=test XMAGE_GATEWAY_URL=http://localhost:17171 XMAGE_SMOKE_SCENARIO=activated-ability-stack XMAGE_USE_FIXTURE=true pnpm smoke:xmage
ENABLE_XMAGE_FIXTURES=true NODE_ENV=test XMAGE_GATEWAY_URL=http://localhost:17171 XMAGE_SMOKE_SCENARIO=triggered-ability-stack XMAGE_USE_FIXTURE=true pnpm smoke:xmage
```

Targeted live smoke has now proven additional pieces of the route chain, including mana-rock, Arcane Signet as a generic mana-rock regression, activated-ability stack, triggered-ability stack, commander damage, and blocker assignment. The current deterministic gauntlet still leaves `mana-rock`, `commander-damage`, `blocker-flow`, and `prompt-variety` in `laterScope`; treat targeted reports as separate deterministic fixture proof, not as evidence that the gauntlet release gate requires those routes. For full Commander vs AI, the aggregate `commander-full-ai` gate is the intended source of truth and must fail while `prompt-variety` or `damage-assignment` is missing.

Latest targeted triggered-stack proof on June 23, 2026 used game `578bbd14-38ce-44c9-83a5-d8de64af28ea`, `source: "xmage-java-bridge"`, `fixtureCallUsed: true`, `directStateSeeded: true`, `seededStateVerified: true`, final `bridgeRevision: 27`, final `xmageCycle: 51`, `routeFamiliesMissing: []`, and `stepsBlocked: []`.

Latest targeted mana-rock proof on June 23, 2026 used game `c827f2b8-c34a-4279-9c25-469d7109c441`, `source: "xmage-java-bridge"`, `fixtureCallUsed: true`, `directStateSeeded: true`, `seededStateVerified: true`, `manaRock.cardName: "Sol Ring"`, two real source `make_mana` actions, final `bridgeRevision: 15`, final `xmageCycle: 24`, and `stepsBlocked: []`. This proves the generic mana-rock fixture route with Sol Ring. It does not prove the separate Arcane Signet manual regression; rerun `mana-rock` with `XMAGE_SMOKE_MANA_ROCK_CARD="Arcane Signet"` before claiming that card-specific regression is gone.

Current optional Arcane Signet proof on June 23, 2026 used game `901b063a-b913-4547-83d1-8f9436772bc4`, `source: "xmage-java-bridge"`, `fixtureCallUsed: true`, `directStateSeeded: true`, `seededStateVerified: true`, `manaRock.cardName: "Arcane Signet"`, `arcaneSignet.castSeen/paymentSourceSeen/resolvedSeen: true`, final `bridgeRevision: 17`, final `xmageCycle: 29`, and `stepsBlocked: []`. This remains a generic route regression proof, not card-specific production logic.

## Fail-Closed Client Policy

Current bridge and iOS behavior should stay fail-closed:

- `choose_pile` requires pile `1` or `2`; iOS disables ambiguous pile buttons instead of defaulting to pile 1.
- `choose_amount` and `play_x_mana` require an explicit finite amount.
- `choose_mana` and `play_mana` require `W`, `U`, `B`, `R`, `G`, or `C`.
- `choose_ability` requires an explicit ability id unless XMage marks the prompt optional.
- `answer_yes_no`, `pay_cost`, and `commander_replacement` require an explicit boolean or exact replacement target.
- iOS does not auto-submit multi-item trigger/item ordering; it renders an up/down order list and submits only the displayed `orderedIds`.
- iOS only renders generic `play_mana` color buttons from explicit `manaChoices` or currently visible floating mana, not a guessed six-color palette.
- Prompt replies with stale `promptId`, `messageId`, or `expectedBridgeRevision` are rejected.
- Prompt choices not exposed by XMage, duplicate selections, and disabled choices are rejected.
- `play_land`, normal `cast_spell`, basic `make_mana`, and playable-object `activate_ability` submit source card UUIDs to XMage; `activate_ability` still requires and validates the selected ability UUID before dispatch.
- Unknown action types are unsupported until bridge/shared/Swift/iOS define them.

A visible unsupported prompt is better than a wrong game action.
