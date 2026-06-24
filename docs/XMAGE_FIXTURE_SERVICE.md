# XMage Fixture Service

`POST /dev/xmage-fixtures/commander` is a dev/test-only deterministic setup route for real XMage games. It exists to seed a real server-owned `mage.game.Game` before MagicMobile routes normal gameplay actions through the existing Java bridge.

## Process Model

Default production mode still runs two Java processes in the bridge container:

- `mage.server.Main` from `mage-server-*.jar`
- `MagicMobileBridge` as a remote `mage.remote.Session` client

That default bridge can create games, join games, receive `GameView` callbacks, and send legal XMage responses. It cannot directly mutate `GameController.game`, because the server-owned `GameController` and `Game` live in a different JVM.

Fixture mode changes only dev/test startup. When `ENABLE_XMAGE_FIXTURES=true` and `NODE_ENV` is not `production`, `start.sh` launches `MagicMobileEmbeddedServerBridge`. That class starts `mage.server.Main.main(args)` and `MagicMobileBridge` in the same JVM, then gives the bridge a `ManagerFactory` provider. The fixture route can then resolve:

- `ManagerFactory.gameManager()`
- `GameManager.getGameController().get(gameId)`
- private `GameController.game`
- `Game.cheat(...)`

XMage remains source of truth. The service does not implement rules and does not bypass legality after setup.

## Safety

The route fails closed unless both gates are true:

- `ENABLE_XMAGE_FIXTURES=true`
- `NODE_ENV` is set and is not `production`

In default/production mode the route returns `xmage_fixtures_disabled` or an explicit blocked report with `directStateSeeded: false`. Docker Compose passes `NODE_ENV: ${NODE_ENV:-production}`, so production/default startup does not expose fixture seeding.

## State Proof

The bridge does not set `fixtureHarness.directStateSeeded: true` just because fixture code ran.

Success requires all of these:

- a real XMage Commander game was created through normal bridge/XMage APIs
- the embedded bridge found the server `GameController`
- `Game.cheat(...)` or direct XMage `GameState`/`Player` APIs mutated the real `Game`
- `GameController.updateGame()` produced a refreshed real `GameView`
- the bridge snapshot revision/cycle advanced
- the refreshed snapshot contains at least one seeded proof card name

If mutation happens but snapshot proof fails, the route returns `xmage_fixture_snapshot_proof_failed` with `directStateSeeded: false`.

## Supported Operations

Current supported setup operations:

- human and AI life totals
- clear human hand and library
- seed human hand
- seed human battlefield, including tapped metadata
- seed human library top
- seed human graveyard
- seed human exile
- seed AI battlefield
- set active player
- set priority player
- set turn number
- set phase/step for supported fixture starts

`commander-gauntlet` currently defaults missing schema zones to a small deterministic setup using cards such as `Sol Ring`, `Arcane Signet`, `Terramorphic Expanse`, `Swords to Plowshares`, `Spirited Companion`, and `Plains`.

## Unsupported Or Partial Operations

- Command-zone reseeding is not performed. Commander game startup already creates command-zone commanders, and blindly adding another command-zone card could duplicate commander state.
- Existing permanent tap/untap by id is not separately implemented beyond tapped battlefield insertion.
- The service does not bypass XMage legality after fixture setup. All later play/cast/target/mana/combat decisions still go through existing bridge commands and XMage prompts.

## Response Shape

Blocked reports include:

- `fixtureName`
- `gameId`
- `directStateSeeded: false`
- `operationsAttempted`
- `operationsApplied`
- `unsupportedOperations`
- `serverProcessEvidence`
- `errors`
- `safetyMode`

Successful fixture route responses are normal top-level game snapshots with `fixtureHarness` attached. `fixtureHarness` carries the same fixture report fields plus `directStateSeeded: true`, `bridgeRevision`, and `xmageCycle`.

## How To Run

```sh
ENABLE_XMAGE_FIXTURES=true NODE_ENV=test docker compose up --build xmage-bridge xmage-gateway
```

Then run the gauntlet smoke against the gateway:

```sh
ENABLE_XMAGE_FIXTURES=true NODE_ENV=test XMAGE_GATEWAY_URL=http://localhost:17171 XMAGE_SMOKE_SCENARIO=commander-gauntlet XMAGE_USE_FIXTURE=true pnpm smoke:xmage
```

The smoke is only release-proof when the report has `source: "xmage-java-bridge"` and `fixtureHarness.directStateSeeded: true`.

## Current Live Evidence

On June 23, 2026, the embedded fixture hook reached ready locally after XMage card/server startup, seeded a real Commander game in the server JVM, and returned a refreshed `source: "xmage-java-bridge"` snapshot with:

- `fixtureHarness.directStateSeeded: true`
- `seededStateVerified: true`
- `setupMethod: "in_server_game_cheat"`
- `seededZones`: `human.hand`, `human.battlefield`, `human.commandZone`, `human.libraryTopHidden:24`, `ai-1.aiBattlefield`
- `stepsBlocked: []` in `build_output/smoke/smoke-report-commander-gauntlet.json`

The latest successful local gauntlet used game `be79e0b6-eec6-4a42-99f3-d62cd200879c`, final `bridgeRevision: 133`, and final `xmageCycle: 223`.

If fixture mutation happens but refreshed snapshot proof does not arrive quickly, the gateway now polls the real bridge snapshot for up to 20 seconds before returning `xmage_fixture_snapshot_proof_failed`. Do not weaken this proof gate; a fixture only counts when the refreshed real XMage snapshot proves the seed.

## Full Commander vs AI Gate

The narrower `commander-gauntlet` route proves the current core Commander flow, but full Commander vs AI must use the aggregate gate:

```sh
ENABLE_XMAGE_FIXTURES=true NODE_ENV=test XMAGE_GATEWAY_URL=http://localhost:17171 XMAGE_SMOKE_SCENARIO=commander-full-ai XMAGE_USE_FIXTURE=true pnpm smoke:xmage
```

`commander-full-ai` runs the deterministic fixture scenarios as separate real-XMage smokes and writes `build_output/smoke/smoke-report-commander-full-ai.json`. It should report `source: "xmage-java-bridge"`, `directStateSeeded: true`, and `seededStateVerified: true` for all passing fixture scenarios, then fail the readiness verdict if any required scenario still has `stepsBlocked`.

Current full-AI blockers:

- `prompt-variety`: targeted slices now have deterministic real-XMage proof for mode, order, amount, multi-amount, and pile. `prompt-mode` uses Lavabrink Venturer for XMage's upstream `ChooseModeEffect`; `prompt-order` uses Soul Warden plus Spirited Companion and XMage's target-style triggered-ability ordering prompt; `prompt-amount` uses Wheel of Misfortune's upstream `GAME_GET_AMOUNT` callback; `prompt-multi-amount` uses Manamorphose's upstream `GAME_GET_MULTI_AMOUNT` callback; `prompt-pile` uses Fact or Fiction's upstream `GAME_CHOOSE_PILE` callback. The standalone aggregate `prompt-variety` gate still needs reconciliation before full readiness. The earlier Austere Command attempt was intentionally left as a non-proof because XMage surfaced it as `GAME_CHOOSE_ABILITY:ability`.
- `damage-assignment`: probe fixture exists, but no bridge/shared/Swift/iOS `damage_assignment` route is implemented or live-proven.

Representative fixture candidate for the next full-AI blocker is a deterministic damage-assignment state. Keep using Commander-legal fixture shells and keep production routing generic.
