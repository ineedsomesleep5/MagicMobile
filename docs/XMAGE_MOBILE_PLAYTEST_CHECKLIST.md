# XMage Mobile Playtest Checklist

Use this checklist when validating the XMage-backed Commander play loop from Docker, web, or an iPhone build. The current product scope is Commander-only digital play. The production play route must use XMage through the gateway and Java bridge; the simulator is only for `/dev/play-simulator`.

## Current Pause State - June 23, 2026

Latest CI/docs validation pass on June 23, 2026. Treat the smoke details below as local artifact summaries only; rerun the commands on the current checkout before using them as release evidence. Generated JSON reports belong under `build_output/smoke/*.json`, not in docs.

- `pnpm --filter @magicmobile/xmage-gateway test` passed.
- `docker build -t magicmobile-xmage-bridge-check apps/xmage-gateway/bridge` passed.
- `docker compose config` passed.
- `pnpm typecheck` passed.
- `pnpm lint` passed.
- `pnpm test` passed.
- `pnpm build` passed.
- `docker compose up -d --build xmage-bridge xmage-gateway` rebuilt the bridge image and started both containers.
- Gateway health initially returned `starting`, then reached `status: "ready"` with reason `XMage Java bridge connected to 127.0.0.1:17171.`
- Normal real-XMage smoke remains diagnostic only. The latest non-fixtured `core-flow` used `source: "xmage-java-bridge"` and failed honestly because that random legal-deck state observed only part of the requested turn coverage.
- A dev-only fixture harness route exists at `POST /dev/xmage-fixtures/commander`. It requires `ENABLE_XMAGE_FIXTURES=true`, is disabled in production, reports `fixtureHarness` metadata, and now has an embedded same-JVM setup path that can reach server-owned `GameController` / `Game.cheat(...)`.
- The deterministic fixture gauntlet passed after the latest bridge rebuild with real `source: "xmage-java-bridge"`, direct server-side fixture seeding, final `bridgeRevision: 133`, final `xmageCycle: 223`, and empty top-level `stepsBlocked`.
- `XMAGE_SMOKE_SCENARIO=blocker-flow` passed with a real `declare_blockers` payload after the targeted combat fixture seeded an XMage-owned attacker/combat state. The AI proof attacker is now `Memnite` so the Kozilek Commander deck remains legal.
- `XMAGE_SMOKE_SCENARIO=commander-damage` passed after the combat-selection bridge fix with direct server-side fixture seeding and non-empty commander-damage evidence.
- `XMAGE_SMOKE_SCENARIO=commander-replacement-tax` reproved commander tax. Commander damage is separately covered by the targeted `commander-damage` fixture.
- `XMAGE_SMOKE_SCENARIO=triggered-ability-stack` passed with direct server-side fixture seeding, `routeFamiliesMissing: []`, and empty `stepsBlocked`.
- `XMAGE_SMOKE_SCENARIO=mana-rock` now uses a Commander-legal singleton fixture deck (`Sol Ring` x1, `Plains` x98), direct server-side seeding, and passed with real `source: "xmage-java-bridge"`, `directStateSeeded: true`, final `bridgeRevision: 15`, final `xmageCycle: 24`, and `stepsBlocked: []`.
- `XMAGE_SMOKE_SCENARIO=prompt-variety` is still not green. Current fixture-gated smoke uses real XMage and direct seeding, but the broader prompt-variety family still needs targeted proof for amount, multi-amount, and pile.
- `XMAGE_SMOKE_SCENARIO=prompt-mode` is a targeted mode-choice proof. The latest June 23, 2026 run used real XMage, `directStateSeeded: true`, `seededStateVerified: true`, `actionsByType.choose_mode: 1`, final `bridgeRevision: 51`, final `xmageCycle: 91`, and empty `stepsBlocked` with Lavabrink Venturer's upstream `ChooseModeEffect`.
- `XMAGE_SMOKE_SCENARIO=prompt-order` is a targeted trigger/item ordering proof. The latest June 24, 2026 run used real XMage, `directStateSeeded: true`, `seededStateVerified: true`, `promptFamiliesSeen: ["GAME_PLAY_MANA:mana", "GAME_TARGET:order"]`, `actionsByType.order_items: 1`, final `bridgeRevision: 29`, final `xmageCycle: 50`, and empty `stepsBlocked` with Soul Warden plus Spirited Companion.
- `XMAGE_SMOKE_SCENARIO=commander-full-ai` is the full Commander vs AI truth gate. It must fail until prompt-variety and damage-assignment are implemented/proven or explicitly excluded with safe fallbacks.
- `XMAGE_SMOKE_MANA_ROCK_CARD="Arcane Signet" pnpm smoke:xmage:mana-rock` passed with real cast/payment/resolution evidence. Keep this as generic routing proof, not a card-specific production path.
- `xcodebuild test -project apps/ios/MagicMobileiOS.xcodeproj -scheme MagicMobile -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' -only-testing:MagicMobileTests -quiet` exited 0 for the iOS unit test target. This is not real iPhone product success.

Latest incremental verification against the local Docker gateway at `http://localhost:17171`:

```sh
pnpm --filter @magicmobile/xmage-gateway test
docker compose up -d --build xmage-bridge xmage-gateway
XMAGE_GATEWAY_URL=http://localhost:17171 pnpm smoke:xmage
ENABLE_XMAGE_FIXTURES=true NODE_ENV=test XMAGE_GATEWAY_URL=http://localhost:17171 XMAGE_SMOKE_SCENARIO=blocker-flow XMAGE_USE_FIXTURE=true pnpm smoke:xmage
ENABLE_XMAGE_FIXTURES=true NODE_ENV=test XMAGE_GATEWAY_URL=http://localhost:17171 XMAGE_SMOKE_SCENARIO=commander-replacement-tax XMAGE_USE_FIXTURE=true pnpm smoke:xmage
ENABLE_XMAGE_FIXTURES=true NODE_ENV=test XMAGE_GATEWAY_URL=http://localhost:17171 XMAGE_SMOKE_SCENARIO=triggered-ability-stack XMAGE_USE_FIXTURE=true pnpm smoke:xmage
ENABLE_XMAGE_FIXTURES=true NODE_ENV=test XMAGE_GATEWAY_URL=http://localhost:17171 XMAGE_SMOKE_SCENARIO=mana-rock XMAGE_USE_FIXTURE=true pnpm smoke:xmage
```

Historical/local notes from earlier runs; rerun before treating any item as current proof:

- Gateway unit tests passed.
- Docker rebuild of `xmage-bridge` and `xmage-gateway` succeeded.
- Health returned `ready` after the bridge reconnected to XMage.
- A prior general real-XMage smoke passed with `source: "xmage-java-bridge"` and advancing bridge state.
- The general smoke proved keep, repeated pass priority, AI wait/return, real `make_mana`, combat-step traversal, and four observed turns without simulator fallback.
- The bridge fix in this pass corrected generic prompt UUID routing: `GAME_TARGET` / `GAME_SELECT` UUID clicks now send only the UUID, matching XMage desktop behavior, instead of immediately sending a boolean cancel/done response that could overwrite the UUID before XMage read it.
- The previous mana-payment loop was also fixed: `GAME_PLAY_MANA` choices are now derived from the human player's real floating mana pool, so a generic `{1}` cost uses available mana such as `{G}` instead of inventing `{C}` when no colorless mana is floating.
- Targeted `XMAGE_SMOKE_SCENARIO=blocker-flow` initially failed during game creation after a reconnect, then produced `declare_attackers` evidence when rerun after the bridge settled.
- Targeted `XMAGE_SMOKE_SCENARIO=commander-replacement-tax` reproved commander tax after casting Isamaru from the command zone. The separate `commander-damage` fixture covers commander damage with non-empty commander-damage evidence.

Current pause blocker:

- Commander damage and blocker assignment are now live-verified by targeted fixtures, but prompt-variety remains unproven. Real iPhone manual QA is still unchecked.
- Earlier AI-priority stalls are now sharper: the bridge keeps the XMage remoting session warm with periodic `Session.ping()`, and the smoke harness fails as `bridge-disconnected` if health drops while waiting for AI.

## Preflight

- [ ] Confirm Docker Compose config renders cleanly:

  ```sh
  docker compose config
  ```

- [ ] Start the XMage stack:

  ```sh
  pnpm dev:xmage
  ```

- [ ] Confirm gateway health is ready:

  ```sh
  curl -fsS http://localhost:17171/health
  ```

- [ ] Run the gateway smoke script against the live stack:

  ```sh
  XMAGE_GATEWAY_URL=http://localhost:17171 pnpm smoke:xmage
  ENABLE_XMAGE_FIXTURES=true NODE_ENV=test XMAGE_GATEWAY_URL=http://localhost:17171 XMAGE_SMOKE_SCENARIO=blocker-flow XMAGE_USE_FIXTURE=true pnpm smoke:xmage
  ENABLE_XMAGE_FIXTURES=true NODE_ENV=test XMAGE_GATEWAY_URL=http://localhost:17171 XMAGE_SMOKE_SCENARIO=commander-replacement-tax XMAGE_USE_FIXTURE=true pnpm smoke:xmage
  ENABLE_XMAGE_FIXTURES=true NODE_ENV=test XMAGE_GATEWAY_URL=http://localhost:17171 XMAGE_SMOKE_SCENARIO=triggered-ability-stack XMAGE_USE_FIXTURE=true pnpm smoke:xmage
  ENABLE_XMAGE_FIXTURES=true NODE_ENV=test XMAGE_GATEWAY_URL=http://localhost:17171 XMAGE_SMOKE_SCENARIO=commander-damage XMAGE_USE_FIXTURE=true pnpm smoke:xmage
  ENABLE_XMAGE_FIXTURES=true NODE_ENV=test XMAGE_GATEWAY_URL=http://localhost:17171 XMAGE_SMOKE_SCENARIO=commander-gauntlet XMAGE_USE_FIXTURE=true pnpm smoke:xmage
  ENABLE_XMAGE_FIXTURES=true NODE_ENV=test XMAGE_GATEWAY_URL=http://localhost:17171 XMAGE_SMOKE_SCENARIO=activated-ability-stack XMAGE_USE_FIXTURE=true pnpm smoke:xmage
  ENABLE_XMAGE_FIXTURES=true NODE_ENV=test XMAGE_GATEWAY_URL=http://localhost:17171 XMAGE_SMOKE_SCENARIO=triggered-ability-stack XMAGE_USE_FIXTURE=true pnpm smoke:xmage
  ENABLE_XMAGE_FIXTURES=true NODE_ENV=test XMAGE_GATEWAY_URL=http://localhost:17171 XMAGE_SMOKE_SCENARIO=prompt-mode XMAGE_USE_FIXTURE=true pnpm smoke:xmage
  ENABLE_XMAGE_FIXTURES=true NODE_ENV=test XMAGE_GATEWAY_URL=http://localhost:17171 XMAGE_SMOKE_SCENARIO=prompt-order XMAGE_USE_FIXTURE=true pnpm smoke:xmage
  ENABLE_XMAGE_FIXTURES=true NODE_ENV=test XMAGE_GATEWAY_URL=http://localhost:17171 XMAGE_SMOKE_SCENARIO=prompt-variety XMAGE_USE_FIXTURE=true pnpm smoke:xmage
  ENABLE_XMAGE_FIXTURES=true NODE_ENV=test XMAGE_GATEWAY_URL=http://localhost:17171 XMAGE_SMOKE_SCENARIO=damage-assignment XMAGE_USE_FIXTURE=true pnpm smoke:xmage
  ENABLE_XMAGE_FIXTURES=true NODE_ENV=test XMAGE_GATEWAY_URL=http://localhost:17171 XMAGE_SMOKE_SCENARIO=commander-full-ai XMAGE_USE_FIXTURE=true pnpm smoke:xmage
  ```

Expected result: health reports `ready`, the smoke output includes a game id, source, completed play-loop steps, and advancing `bridgeRevision` / `xmageCycle` when the Java bridge is active.

`commander-gauntlet` is the current backend alpha acceptance gate. It must use `XMAGE_USE_FIXTURE=true`, `source: "xmage-java-bridge"`, and report top-level `stepsCompleted` / `stepsBlocked`. A passing release-gate report must show deterministic real-XMage fixture proof and empty `stepsBlocked`; simulator success and non-fixtured legal-deck gauntlets do not satisfy it.

When `XMAGE_USE_FIXTURE=true`, the smoke must also report `fixtureHarness.enabled: true`, `fixtureHarness.directStateSeeded: true`, `seededStateVerified: true`, and `setupMethod: "in_server_game_cheat"`. Legal-deck gauntlet evidence remains diagnostic only, not release proof.

If the live smoke fails, capture the exact failing step instead of treating simulator success as product success. Current high-value failures are usually in pass priority, AI waiting, stale prompt answers, or a missing legal action after XMage changes state.

## Historical Local Smoke Notes

Historical: verified on June 22, 2026 against the local Docker gateway at `http://localhost:17171`.

Current June 23, 2026 attempt: bridge/gateway containers started after rebuild and gateway health reached `ready`. The normal live smoke produced real bridge evidence but did not pass because a non-fixtured game state missed `cast_spell`. The fixture gauntlet passed with deterministic server-side setup proof, but this is backend evidence only; real iPhone manual QA remains unchecked. Do not paste generated smoke report bodies here as release proof.

Commands run:

```sh
docker compose config --quiet
docker build -t magicmobile-xmage-bridge-check apps/xmage-gateway/bridge
pnpm --filter @magicmobile/xmage-gateway test
pnpm --filter @magicmobile/web test -- apps/web/src/app/play
pnpm typecheck
docker compose up -d --build xmage-bridge xmage-gateway
XMAGE_GATEWAY_URL=http://localhost:17171 pnpm smoke:xmage
ENABLE_XMAGE_FIXTURES=true NODE_ENV=test XMAGE_GATEWAY_URL=http://localhost:17171 XMAGE_SMOKE_SCENARIO=blocker-flow XMAGE_USE_FIXTURE=true pnpm smoke:xmage
ENABLE_XMAGE_FIXTURES=true NODE_ENV=test XMAGE_GATEWAY_URL=http://localhost:17171 XMAGE_SMOKE_SCENARIO=commander-replacement-tax XMAGE_USE_FIXTURE=true pnpm smoke:xmage
ENABLE_XMAGE_FIXTURES=true NODE_ENV=test XMAGE_GATEWAY_URL=http://localhost:17171 XMAGE_SMOKE_SCENARIO=commander-gauntlet XMAGE_USE_FIXTURE=true pnpm smoke:xmage
pnpm lint
pnpm test
pnpm build
```

The Docker services were running, the bridge container was rebuilt, the gateway was restarted to pick up local source changes, and the smoke test used the live gateway/Java bridge path.

Current bridge health during smoke:

```json
{
  "status": "ready",
  "reason": "XMage Java bridge connected to 127.0.0.1:17171.",
  "recoveryAction": "wait"
}
```

Historical broad smoke output showed `source: "xmage-java-bridge"`, advancing bridge state, and core actions including hand keep, land, mana, spell casting, mana payment, priority pass, and yes/no prompts. Rerun `pnpm smoke:xmage` for current evidence instead of relying on this historical summary.

Targeted fixture smoke outputs:

- `XMAGE_SMOKE_SCENARIO=blocker-flow`: passed on game `51ea0b22-dbdc-45cf-850d-d11c3d5329a6` with real `source: "xmage-java-bridge"`, `directStateSeeded: true`, one submitted `declare_blockers` action, `blockerAssignmentExercised: true`, final `bridgeRevision: 11`, final `xmageCycle: 14`, and `stepsBlocked: []`.
- `XMAGE_SMOKE_SCENARIO=commander-replacement-tax`: older artifacts observed commander tax and damage, but this must be reproved on the current bridge before it is treated as release-gate green.
- `XMAGE_SMOKE_SCENARIO=mana-rock`: passed on game `c827f2b8-c34a-4279-9c25-469d7109c441` with real `source: "xmage-java-bridge"`, `directStateSeeded: true`, `seededStateVerified: true`, `manaRock.cardName: "Sol Ring"`, two source `make_mana` actions, final `bridgeRevision: 15`, final `xmageCycle: 24`, and `stepsBlocked: []`.
- `XMAGE_SMOKE_SCENARIO=commander-gauntlet` with `XMAGE_USE_FIXTURE=true`: passed after the latest bridge rebuild with direct server-side fixture seeding, final `bridgeRevision: 133`, final `xmageCycle: 223`, and `stepsBlocked: []`.
- `XMAGE_SMOKE_SCENARIO=triggered-ability-stack` with `XMAGE_USE_FIXTURE=true`: passed on game `578bbd14-38ce-44c9-83a5-d8de64af28ea` with real `source: "xmage-java-bridge"`, `directStateSeeded: true`, `seededStateVerified: true`, final `bridgeRevision: 27`, final `xmageCycle: 51`, `routeFamiliesMissing: []`, and `stepsBlocked: []`.

Confirmed live steps across the local verification run:

- created a real Commander game with `source: "xmage-java-bridge"`
- received numeric `bridgeRevision`
- received `xmageCycle`
- kept opening hand
- the latest fixture gauntlet played land, made mana from real battlefield sources, answered a mana-payment prompt, cast spells, activated/search-selected through Terramorphic Expanse, handled commander replacement, and recast the commander with tax
- inferred and submitted multi-select target choices for XMage search prompts when the callback text exposes `selected 0 of N`
- submitted a typed attacker-to-defender payload in the deterministic combat fixture
- commander tax/damage parsing exists, but current release proof must come from a fresh targeted smoke with non-empty `commanderTaxChanges` and `commanderDamageChanges`
- passed priority
- ended in a real XMage priority state instead of mock/simulator state

Failures fixed during this verification:

- June 23: `make_mana`, command-zone `cast_spell`, and playable-object `activate_ability` can silently no-op if the bridge sends the wrong XMage UUID. These routes now validate the selected playable ability where needed, then dispatch through XMage's source-card click path.
- Earlier: `make_mana` advanced the revision but did not add mana because the bridge sent the wrong playable UUID for that action shape.
- command responses that advanced only `xmageCycle` were incorrectly returned as pending, leaving clients with only `concede` legal actions.
- mana-payment prompts exposed only generic `play_mana` choices and did not expose real untapped battlefield mana sources.
- the smoke helper was pre-tapping lands while searching for a cast action, which could hide the real castable spell state.
- commander tax and damage parsed directly from rules text in the bridge.
- prompt choice legal actions used raw UUID labels for library/search-style prompts, which made the smoke runner pick an invalid nonland for `Select a basic land card`.
- XMage multi-select target/card prompts exposed `maxChoices: 0` even when prompt text said `selected 0 of 2`; the bridge now infers that choice count and confirms `GAME_TARGET` / `GAME_SELECT` UUID selections.
- `PermanentView.isCanAttack()` / `isCanBlock()` was too conservative for the client view, so combat legal actions now use the current XMage combat step plus visible untapped creatures and still let XMage validate the submitted UUIDs.
- the smoke runner now treats recovered stale-action `409`s as a refresh-and-retry path rather than counting them as semantic progress.

Remaining live-coverage gaps:

- Deterministic fixture setup is no longer the current `commander-gauntlet` blocker. The same-JVM seeding hook reached ready and produced refreshed real-XMage snapshot proof. Real iPhone manual QA remains the main product blocker.
- player-scoped snapshots are still required before human-vs-human or pods.
- damage assignment prompts have not been live-fixtured yet. The current probe can seed a combat state, but the bridge/shared/Swift/iOS `damage_assignment` route is not implemented and must be treated as a full-AI blocker.
- `mana-rock` is targeted-fixture proven with `Sol Ring`, and the optional `Arcane Signet` variant now passes as generic route proof. Manual phone QA still needs to confirm the same flow through the iOS UI.
- full `commander-gauntlet` now has deterministic real-XMage setup support for singleton test cards and reached commander cast, replacement, and recast-with-tax. Commander damage, blocker assignment, and prompt-variety remain later-scope unless explicitly moved into the alpha gate, with commander damage and blocker assignment separately targeted-fixture proven.

## Commander Gauntlet Acceptance Loop

Run this once the live bridge is healthy:

```sh
ENABLE_XMAGE_FIXTURES=true NODE_ENV=test XMAGE_GATEWAY_URL=http://localhost:17171 XMAGE_SMOKE_SCENARIO=commander-gauntlet XMAGE_USE_FIXTURE=true pnpm smoke:xmage
```

Required final proof before Commander vs AI alpha:

- [ ] `source` is `xmage-java-bridge`.
- [ ] `fixtureCallUsed` is true, `directStateSeeded` is true, and `seededStateVerified` is true.
- [ ] Top-level `stepsBlocked` is empty after real gameplay proof, not merely empty because the run stopped before gameplay.
- [ ] Play a land.
- [ ] Cast `Sol Ring` or equivalent mana rock.
- [ ] Tap a mana source.
- [ ] Activate a fetch-style land.
- [ ] Resolve a search/select prompt and update zones.
- [ ] Cast the commander.
- [ ] See an ETB/trigger or equivalent stack/prompt/state change.
- [ ] Activate a non-mana ability if the fixture supports one.
- [ ] Show a spell or ability on the stack.
- [ ] Remove the commander.
- [ ] Answer commander replacement explicitly.
- [ ] Recast the commander with tax.
- [ ] Continue through at least one AI turn.

If the gauntlet fails, keep the generated JSON report as a local/CI artifact under `build_output/smoke/*.json`. The useful fields are `directStateSeeded`, `seededStateVerified`, `routeFamiliesRequired`, `routeFamiliesSeen`, `routeFamiliesMissing`, `stepsCompleted`, `stepsBlocked`, `failedStep`, `failureReason`, `promptFamiliesSeen`, `bridgeRevision`, `xmageCycle`, `completed`, and the final `legalActions`. Do not commit generated reports as release proof.

## Web Play Loop

- [ ] Open `http://localhost:3000/play`.
- [ ] Confirm `/play` refuses to run without XMage health instead of falling back to the simulator.
- [ ] Confirm `/dev/play-simulator` is clearly labeled as simulator/dev mode.
- [ ] Create or enter a Commander game backed by the XMage gateway.
- [ ] Keep the opening hand when the mulligan prompt appears.
- [ ] Play a land from hand.
- [ ] Tap the land or another mana source with a `make_mana` action.
- [ ] Cast a simple legal spell from hand.
- [ ] Confirm the spell appears on the stack when XMage exposes stack state.
- [ ] Pass priority.
- [ ] Respond to at least one real `promptEnvelopeV2` prompt if XMage asks for a target, card, player, amount, mana, mode, ability, yes/no answer, or commander replacement choice.
- [ ] Confirm the battlefield, hand, stack, prompt text, and legal actions update without refreshing the page.
- [ ] Confirm stale snapshots do not replace newer snapshots. In debug output, `bridgeRevision` should not go backward.
- [ ] When XMage asks for a choice, confirm `promptEnvelopeV2` appears in the debug view and the UI exposes a matching response action.
- [ ] Confirm `pendingStatus: "waiting_for_xmage"` shows a waiting state instead of freezing the UI.
- [ ] Confirm AI turns show AI waiting/thinking rather than a dead screen.
- [ ] Confirm missing card art renders a placeholder and does not block gameplay.

### Casting And Mana Payment Regression

- [ ] Reach a state with at least two untapped mana sources on your battlefield and `Arcane Signet` or another two-mana spell in hand.
- [ ] Select the hand card and confirm the context panel shows a primary `Cast` action.
- [ ] Run the cast action without manually pre-tapping lands.
- [ ] If XMage asks for mana/payment, confirm the prompt panel shows `Available Mana Sources` before generic mana buttons.
- [ ] Tap exposed mana-source actions only from XMage legal actions.
- [ ] Confirm floating mana/prompt state updates from the next authoritative snapshot.
- [ ] Confirm the card moves to stack/battlefield/graveyard only after XMage returns that state.
- [ ] Select a non-castable hand card and confirm the UI explains that XMage did not expose a cast/play action instead of silently doing nothing.

## iPhone Play Loop

- [ ] Put the iPhone and development machine on the same network.
- [ ] Set the app's gateway base URL to the development machine host reachable from the phone.
- [ ] Install and launch the iPhone build.
- [ ] Start a Commander game from the real play entry point, not the simulator-only route.
- [ ] Confirm the created snapshot source is not mock. Real games should report `source: xmage-java-bridge` and a non-nil `bridgeRevision`.
- [ ] Keep hand, play land, make mana, cast a simple spell, and pass priority.
- [ ] Confirm the mobile UI updates after each action without duplicate taps or manual refresh.
- [ ] Confirm the action tray changes from hand actions to battlefield or prompt actions as the snapshot changes.
- [ ] Confirm an XMage choice prompt renders from `promptEnvelopeV2` when the bridge asks for a target, card, player, mode, ability, amount, multi-amount, mana, pay cost, yes/no, commander replacement, order, search/select, or combat response.
- [ ] Confirm prompt controls do not auto-pick the first choice or default yes/colorless/zero when XMage did not expose enough data.
- [ ] Test declare attackers and declare blockers; command payloads must include attacker/defender or blocker/attacker pairs.
- [ ] Stop the XMage gateway and confirm iPhone shows bridge/XMage unavailable instead of entering mock gameplay.
- [ ] Confirm selected cards, tapped cards, pending actions, and prompt selections show instant local feedback.
- [ ] Confirm the real board state only changes after an authoritative XMage snapshot.
- [ ] Confirm the stack, command zone, graveyard, exile, life total, poison, commander tax, commander damage, phase/step, active player, priority player, pending status, legal action count, and game log are reachable.
- [ ] Confirm manual reconnect/refresh recovers after a network interruption without duplicate command submission.
- [ ] If the UI appears frozen, compare the visible state to `GET /games/{gameId}/debug` and verify whether `bridgeRevision` or `xmageCycle` is still advancing.

### iPhone Arcane Signet / Two Lands Regression

- [ ] With two untapped lands on the battlefield, tap `Arcane Signet` in hand.
- [ ] Confirm tapping selects the card and shows a selected-card action section; it must not open the inspector unless long-pressed.
- [ ] Confirm `Cast Arcane Signet` or a clear cast/play chooser appears when XMage exposes the action.
- [ ] Dragging the card to the battlefield may be used as a shortcut, but the visible button must also work.
- [ ] After casting, confirm any payment prompt shows source-based `Tap [land/artifact]` buttons.
- [ ] Confirm every source button uses a real `make_mana` legal action and shows produced mana hints when available.
- [ ] Confirm rejected or stale actions refresh from XMage and show a visible message instead of leaving the card half-played.

## Commander Deck Flow

- [ ] Import a pasted Commander text list.
- [ ] Import text exported from Moxfield or Archidekt when available.
- [ ] Validate exactly 100 cards including commander.
- [ ] Validate singleton rules except basic lands.
- [ ] Validate color identity and Commander legality where card data is available.
- [ ] Submit the selected deck into the XMage Commander game startup path.
- [ ] Confirm deck-loading errors surface clearly instead of starting a fake simulator game.

## Timing Capture

For slow actions, record:

- [ ] client action time
- [ ] API command response time
- [ ] gateway command timing
- [ ] Java bridge command timing
- [ ] `pendingStatus` returned, if any
- [ ] latest `bridgeRevision` and `xmageCycle`
- [ ] whether a WebSocket update arrived
- [ ] whether card image loading was involved

## Failure Notes To Capture

- Gateway `/health` response and recovery action.
- The command type that failed: `keep_hand`, `play_land`, `make_mana`, `cast_spell`, `pass_priority`, or prompt response.
- Previous and next `bridgeRevision` / `xmageCycle`.
- Whether `promptEnvelopeV2` was present and whether matching legal actions were exposed.
- Browser console logs or iPhone device logs around the failed command.
- Whether the app was waiting on a human player, AI player, or XMage prompt.
