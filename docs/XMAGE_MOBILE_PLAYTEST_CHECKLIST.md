# XMage Mobile Playtest Checklist

Use this checklist when validating the XMage-backed Commander play loop from Docker, web, or an iPhone build. The current product scope is Commander-only digital play. The production play route must use XMage through the gateway and Java bridge; the simulator is only for `/dev/play-simulator`.

## Current Pause State - June 24, 2026

Latest CI/docs validation pass on June 24, 2026. Treat the smoke details below as local artifact summaries only; rerun the commands on the current checkout before using them as release evidence. Generated JSON reports belong under `build_output/smoke/*.json`, not in docs.

Latest iOS product-readiness pass on June 24, 2026:

- Backend route gate was rerun on the current checkout with `ENABLE_XMAGE_FIXTURES=true NODE_ENV=test XMAGE_GATEWAY_URL=http://localhost:17171 XMAGE_SMOKE_SCENARIO=commander-full-ai XMAGE_USE_FIXTURE=true pnpm smoke:xmage`.
- `commander-full-ai` passed with `source: "xmage-java-bridge"`, `directStateSeeded: true`, `seededStateVerified: true`, `allRequiredScenariosPassed: true`, `routeFamiliesMissing: []`, `stepsBlocked: []`, `iOSRequiredRoutesMissing: []`, and `readinessVerdict: "full-commander-vs-ai-ready"`.
- iOS generic hardware build passed with `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project apps/ios/MagicMobileiOS.xcodeproj -scheme MagicMobile -configuration Debug -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build`.
- iPhone 16 Pro Max Simulator was unavailable, so layout QA used iPhone 17 Pro Max Simulator, iOS 26.5. The app declares landscape-only orientations and rendered the landscape board, but this CoreSimulator runtime did not expose `simctl ui ... orientation` and rejected landscape display geometry, so the raw screenshots needed readable rotation copies. Simulator evidence is layout/build evidence only, not real iPhone product success.
- Captured simulator screenshots under `build_output/ios-screenshots/`: `iphone-17-pro-max-setup-local-api.jpg`, `iphone-17-pro-max-setup-local-api-landscape-readable.jpg`, `iphone-17-pro-max-fixture-board-rustic.jpg`, `iphone-17-pro-max-fixture-board-rustic-landscape-readable.jpg`, `iphone-17-pro-max-hand-selected-card-targets-landscape-readable.jpg`, `iphone-17-pro-max-action-dock-priority-first-landscape-readable.jpg`, and `iphone-17-pro-max-missing-art-placeholders-landscape-readable.jpg`.
- The iOS setup screen now scrolls in landscape so the debug fixture control and start controls remain reachable on Pro Max.
- The iOS API timeout is now long enough for real XMage table/fixture startup instead of failing at 15 seconds.
- The iOS gameplay surface has a rustic leather/parchment/wood treatment, compact non-blocking waiting toast, visible source/bridge/revision/cycle/priority/pending/phase state, stable missing-art placeholders, zone-scoped card accessibility labels/identifiers, prompt/action-first right dock ordering, and readable stack/command/graveyard/exile plus Library/Revealed/Looked access without debug JSON when XMage exposes those zones.
- Simulator QA used the `card-hand-sol-ring-<id>` accessibility target to select Sol Ring from hand and confirm the primary Cast action stays visible. A second simulator launch used `MAGICMOBILE_FORCE_CARD_PLACEHOLDERS=true` to disable only client card-image URLs while keeping the real XMage fixture snapshot, producing `build_output/screenshots/ios-missing-art.png` as missing-art placeholder evidence.
- Real iPhone install/play QA is still pending. The June 24 device check showed Caleb's iPhone 16 Pro Max as `unavailable` and a separate physical iPhone (`Ruthie's iPhone 16`, reported as iPhone 16 Pro Max-class hardware) as `connected`; the app was not installed or launched on that device without explicit permission. Product release remains blocked until a physical iPhone can start a local-gateway Commander game, exercise the fixture/normal play loop, and capture bridgeRevision/xmageCycle evidence.

Local iOS simulator setup used for this pass:

```sh
ENABLE_XMAGE_FIXTURES=true NODE_ENV=test docker compose up -d --build xmage-bridge xmage-gateway
ENGINE_MODE=xmage XMAGE_GATEWAY_URL=http://localhost:17171 ENABLE_XMAGE_FIXTURES=true NODE_ENV=development pnpm --filter @magicmobile/web exec next dev --hostname 0.0.0.0
```

The web API layer exposed `/api/engine/*` for the iOS client and forwarded to the raw gateway at `http://localhost:17171`. The debug fixture button uses the dev-only `/dev/xmage-fixtures/commander` proxy on the local web API; this remains gated by `ENABLE_XMAGE_FIXTURES=true` and disabled in production.

For simulator launches against a local web API, use `MAGICMOBILE_SERVER_URL=http://127.0.0.1:<web-port>` so the setup screen points at the local Next server without manual typing. Also set `MAGICMOBILE_XMAGE_WS_URL=http://127.0.0.1:17171` so native live updates connect to the real XMage gateway WebSocket endpoint instead of trying to open `/ws/games/:gameId` on the Next dev server.

For missing-art visual QA only, also launch a Debug simulator build with `MAGICMOBILE_FORCE_CARD_PLACEHOLDERS=true`. This does not alter XMage state or route proof; it only forces `CardImageURL.normal(...)` to return `nil` so the existing iOS placeholder renderer is exercised against a real fixture board. Release builds ignore this environment toggle.

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
- `XMAGE_SMOKE_SCENARIO=prompt-variety` is now green as an aggregate. The latest June 24, 2026 run used real `source: "xmage-java-bridge"`, `directStateSeeded: true`, `seededStateVerified: true`, `allRequiredScenariosPassed: true`, `routeFamiliesMissing: []`, and empty `stepsBlocked` across activated-stack, triggered-stack, mode, order, amount, multi-amount, and pile child scenarios.
- `XMAGE_SMOKE_SCENARIO=prompt-mode` is a targeted mode-choice proof. The latest June 23, 2026 run used real XMage, `directStateSeeded: true`, `seededStateVerified: true`, `actionsByType.choose_mode: 1`, final `bridgeRevision: 51`, final `xmageCycle: 91`, and empty `stepsBlocked` with Lavabrink Venturer's upstream `ChooseModeEffect`.
- `XMAGE_SMOKE_SCENARIO=prompt-order` is a targeted trigger/item ordering proof. The latest June 24, 2026 run used real XMage, `directStateSeeded: true`, `seededStateVerified: true`, `promptFamiliesSeen: ["GAME_PLAY_MANA:mana", "GAME_TARGET:order"]`, `actionsByType.order_items: 1`, final `bridgeRevision: 29`, final `xmageCycle: 50`, and empty `stepsBlocked` with Soul Warden plus Spirited Companion.
- `XMAGE_SMOKE_SCENARIO=prompt-amount` is a targeted amount-choice proof. The latest June 24, 2026 run used real XMage, `directStateSeeded: true`, `seededStateVerified: true`, `promptFamiliesSeen: ["GAME_GET_AMOUNT:amount"]`, `actionsByType.choose_amount: 1`, final `bridgeRevision: 18`, final `xmageCycle: 24`, and empty `stepsBlocked` with Wheel of Misfortune's upstream `Player.getAmount(...)` callback.
- `XMAGE_SMOKE_SCENARIO=prompt-multi-amount` is a targeted multi-amount proof. The latest June 24, 2026 run used real XMage, `directStateSeeded: true`, `seededStateVerified: true`, `promptFamiliesSeen: ["GAME_GET_MULTI_AMOUNT:multi_amount"]`, `actionsByType.choose_multi_amount: 1`, final `bridgeRevision: 18`, final `xmageCycle: 29`, and empty `stepsBlocked` with Manamorphose's upstream `AddManaInAnyCombinationEffect`.
- `XMAGE_SMOKE_SCENARIO=prompt-pile` is a targeted pile proof. The latest June 24, 2026 run used real XMage, `directStateSeeded: true`, `seededStateVerified: true`, `promptFamiliesSeen: ["GAME_CHOOSE_PILE:pile"]`, `actionsByType.choose_pile: 1`, final `bridgeRevision: 20`, final `xmageCycle: 33`, and empty `stepsBlocked` with Fact or Fiction's upstream `RevealAndSeparatePilesEffect`.
- `XMAGE_SMOKE_SCENARIO=commander-full-ai` is the full Commander vs AI truth gate. The latest June 24, 2026 run passed with real `source: "xmage-java-bridge"`, `directStateSeeded: true`, `seededStateVerified: true`, `allRequiredScenariosPassed: true`, `routeFamiliesMissing: []`, `stepsBlocked: []`, `iOSRequiredRoutesMissing: []`, and `readinessVerdict: "full-commander-vs-ai-ready"`.
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

- Commander damage, blocker assignment, damage assignment, standalone aggregate prompt-variety, and full `commander-full-ai` are now live-verified by deterministic fixtures. Real iPhone manual QA is still unchecked.
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

- [ ] For iPhone or simulator app testing, start the local web API layer that the iOS client expects:

  ```sh
  ENGINE_MODE=xmage XMAGE_GATEWAY_URL=http://localhost:17171 ENABLE_XMAGE_FIXTURES=true NODE_ENV=development pnpm --filter @magicmobile/web exec next dev --hostname 0.0.0.0
  ```

  Use `http://localhost:3000` or the printed fallback port in Simulator. On a physical iPhone, use `http://<Mac-LAN-IP>:<printed-port>` and keep the Mac and iPhone on the same local network. The raw gateway health URL stays `http://<Mac-LAN-IP>:17171/health`; the app URL should point at the web API port, not the raw gateway, for normal `/api/engine/*` play. For Debug launches, set `MAGICMOBILE_XMAGE_WS_URL=http://<Mac-LAN-IP>:17171` so the native WebSocket badge can reach the gateway `/ws/games/:gameId` endpoint.

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
  ENABLE_XMAGE_FIXTURES=true NODE_ENV=test XMAGE_GATEWAY_URL=http://localhost:17171 XMAGE_SMOKE_SCENARIO=prompt-amount XMAGE_USE_FIXTURE=true pnpm smoke:xmage
  ENABLE_XMAGE_FIXTURES=true NODE_ENV=test XMAGE_GATEWAY_URL=http://localhost:17171 XMAGE_SMOKE_SCENARIO=prompt-multi-amount XMAGE_USE_FIXTURE=true pnpm smoke:xmage
  ENABLE_XMAGE_FIXTURES=true NODE_ENV=test XMAGE_GATEWAY_URL=http://localhost:17171 XMAGE_SMOKE_SCENARIO=prompt-pile XMAGE_USE_FIXTURE=true pnpm smoke:xmage
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
- damage assignment prompts are now deterministic-fixture proven through a real combat-damage `GAME_GET_MULTI_AMOUNT` prompt classified as `damage_assignment`; keep the iOS allocation UI under real phone QA.
- `mana-rock` is targeted-fixture proven with `Sol Ring`, and the optional `Arcane Signet` variant now passes as generic route proof. Manual phone QA still needs to confirm the same flow through the iOS UI.
- full `commander-gauntlet` now has deterministic real-XMage setup support for singleton test cards and reached commander cast, replacement, and recast-with-tax. Commander damage, blocker assignment, damage assignment, and prompt-variety remain outside the narrower gauntlet, with separate deterministic fixture proof and a green `commander-full-ai` aggregate tying them together.

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

## iPhone 16 Pro Max Manual QA Checklist

Real iPhone QA is required before product release. Simulator screenshots, simulator gameplay, and generic iPhoneOS builds do not count as product success. Keep visual/layout evidence in [IOS_VISUAL_QA_CHECKLIST.md](IOS_VISUAL_QA_CHECKLIST.md) and keep backend route proof in smoke reports.

- [ ] Put the iPhone 16 Pro Max and development Mac on the same Wi-Fi.
- [ ] Start Docker with fixtures enabled: `ENABLE_XMAGE_FIXTURES=true NODE_ENV=test docker compose up -d --build xmage-bridge xmage-gateway`.
- [ ] Confirm fixture-ready gateway health from the Mac: `curl -fsS http://localhost:17171/health` returns `status: "ready"` with `XMage Java bridge connected to 127.0.0.1:17171.`
- [ ] Start the local web API that the iOS client expects: `ENGINE_MODE=xmage XMAGE_GATEWAY_URL=http://localhost:17171 ENABLE_XMAGE_FIXTURES=true NODE_ENV=development pnpm --filter @magicmobile/web exec next dev --hostname 0.0.0.0`.
- [ ] On the iPhone, set the server URL to `http://<Mac-LAN-IP>:<web-port>`, not `localhost` and not the raw `http://<Mac-LAN-IP>:17171` gateway.
- [ ] Launch the Debug iPhone build with `MAGICMOBILE_XMAGE_WS_URL=http://<Mac-LAN-IP>:17171`, or add the equivalent value through Xcode scheme environment, so WebSocket status can reach the raw gateway while HTTP remains on the web API.
- [ ] Install and launch the iPhone build, then confirm the setup health line reports the fixture-ready gateway.
- [ ] Start a Commander game or the debug Commander fixture through the local web API. Do not use simulator-only gameplay proof.
- [ ] Confirm the play screen shows `source: xmage-java-bridge`, numeric `bridgeRevision`, numeric `xmageCycle`, active/priority player, phase/step/turn, pending status, and WebSocket status.
- [ ] Play gauntlet-style actions through the native UI: keep hand, play land, make mana, cast/pay for a spell, pass priority, answer visible prompts, open stack, open command zone, and continue through at least one AI action.
- [ ] Verify prompt/action UI exposes explicit controls for target/card/player, mana/payment, yes/no, commander replacement, mode, ability, amount, multi-amount, pile, ordering, attacker/blocker, and damage-assignment prompts when those prompts appear.
- [ ] Verify stack, command zone, graveyard, exile, library count, revealed/looked-at zones when exposed, commander tax, commander damage, mana pool, missing-art placeholders, AI waiting, and unavailable/stalled bridge states are reachable without debug JSON.
- [ ] Confirm unknown/unsupported prompts never auto-pick yes, colorless, 0, pile 1, first choice, or command zone.
- [ ] Capture screenshots for setup health, fixture/game board, active prompt, stack/zone sheet, missing-art placeholder, AI waiting state, and any failure state.
- [ ] Record game id if visible, `source`, latest `bridgeRevision`, latest `xmageCycle`, WebSocket state, pending status, Mac LAN IP and web port used, gateway `/health`, and Docker/web API logs for failures.
- [ ] Pass/fail: pass only if the physical iPhone can continue a real XMage Commander vs AI game without simulator fallback or debug JSON. Fail if startup hangs without status, controls overlap, fixture mode is production-accessible, actions mutate local UI without an authoritative XMage snapshot, or the phone cannot reach the local web API.

## Pro Max Simulator Checklist

- [x] iPhone 16 Pro Max Simulator was not installed; used iPhone 17 Pro Max Simulator, iOS 26.5.
- [x] Landscape build/run passed through XcodeBuildMCP.
- [x] Setup screen scrollability fixed so the debug fixture control is reachable.
- [x] Fixture board screenshot captured at `build_output/ios-screenshots/iphone-17-pro-max-fixture-board-normalized-readable.jpg`.
- [x] Missing-art placeholder screenshot captured at `build_output/ios-screenshots/iphone-17-pro-max-missing-art-placeholders-landscape-readable.jpg` using `MAGICMOBILE_FORCE_CARD_PLACEHOLDERS=true` against a real XMage fixture snapshot.
- [x] Waiting/failure screenshots captured for `Creating XMage table`, fixture timeout before timeout fix, and default-deck validation failure.
- [ ] Simulator result is not release approval; repeat on a physical iPhone before product release.
- [x] Confirm missing card art renders a placeholder and does not block gameplay in simulator visual QA.
- [ ] Repeat missing-art and slow-image checks on a physical iPhone network before product release.

Use [IOS_VISUAL_QA_CHECKLIST.md](IOS_VISUAL_QA_CHECKLIST.md) for the full simulator screenshot inventory, pass/fail criteria, known visual issues, and the real-device QA boundary.

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
