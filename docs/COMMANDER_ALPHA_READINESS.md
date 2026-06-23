# Commander Alpha Release Readiness Report

This document outlines the CI configuration status, Docker environment verification, and latency measurements for the MagicMobile Commander Alpha release.

> [!IMPORTANT]
> The production gameplay path at `/play` strictly requires a healthy XMage gateway and Java bridge. The simulator mode is kept isolated at `/dev/play-simulator` for UI and component development.
> Smoke reports are local artifacts, not evergreen release proof. Keep generated JSON under `build_output/smoke/*.json` and rerun the relevant smoke command on the current checkout before citing a pass.

---

## 1. CI Workflow Status

We inspected the CI configuration file [ci.yml](../.github/workflows/ci.yml).

### Key Properties:
- **Environment**: Node.js `22`, pnpm `10.12.4`
- **Runner OS**: `ubuntu-latest`
- **Updated Steps**:
  1. **Checkout**: `actions/checkout@v4`
  2. **Setup pnpm**: `pnpm/action-setup@v4`
  3. **Setup Node**: `actions/setup-node@v4`
  4. **Install**: `pnpm install --no-frozen-lockfile`
  5. **Typecheck (Added)**: Runs `pnpm typecheck` to verify strict TypeScript rules before testing and building.
  6. **Lint**: `pnpm lint`
  7. **Test**: `pnpm test`
  8. **Build**: `pnpm build`

Normal CI is intentionally limited to install/typecheck/lint/test/build. Live XMage smoke is not required for normal PRs because Docker/XMage startup is not reliable enough for a required gate yet.

Manual live smoke is available in `.github/workflows/xmage-smoke.yml` through `workflow_dispatch`. It rebuilds the bridge image, starts `xmage-bridge` and `xmage-gateway` with `ENABLE_XMAGE_FIXTURES=true NODE_ENV=test` for gauntlet coverage, runs `pnpm smoke:xmage`, runs `pnpm smoke:xmage:gauntlet`, and uploads `build_output/smoke/*.json`.

If GitHub Actions does not appear in the repository UI after these files are pushed, the usual reason is that workflow files are not present on the default branch yet or Actions are disabled for the repository. Exact fix: push `.github/workflows/ci.yml` and `.github/workflows/xmage-smoke.yml` to the default branch or merge a PR containing them, then enable Actions under repository Settings if the Actions tab is disabled.

---

## 2. Docker Architecture Status

The project runs on a 5-tier architecture defined in [docker-compose.yml](../docker-compose.yml):

| Service | Image/Context | Port(s) | Health Check Status | Description |
|---|---|---|---|---|
| `postgres` | `postgres:16-alpine` | `5432` | `pg_isready` (5 retries) | Relational database storage |
| `redis` | `redis:7-alpine` | `6379` | `redis-cli ping` (5 retries) | In-memory key-value cache and room pub/sub |
| `xmage-bridge` | `./apps/xmage-gateway/bridge` | `17172`, `17179` | HTTP `/health` check (20 retries) | Java 17 service wrapping the XMage server and client connections |
| `xmage-gateway` | `node:22-bookworm-slim` | `17171` | N/A (Starts after bridge) | Node proxy gateway managing AI game creation and websocket broadcasts |
| `web` | `node:22-bookworm-slim` | `3000` | N/A (Starts after postgres/redis/gateway) | Next.js production web server rendering the UI |

Local Docker compose rendered successfully on June 23, 2026. The bridge image rebuilt successfully after the source-UUID `make_mana` routing work, and the local gateway health reached `ready` after the bridge finished starting XMage.

---

## 3. Command Latency & Performance Measurements

All commands below were run locally on macOS on June 23, 2026 against the shared checkout from that pass. Treat them as historical local evidence until rerun on the current checkout.

| Command | Purpose | Duration (s) | Result |
|---|---|---|---|
| `pnpm --filter @magicmobile/xmage-gateway test` | Gateway unit/bridge-source tests | <2s | Pass: 35 tests passed |
| `docker build -t magicmobile-xmage-bridge-check apps/xmage-gateway/bridge` | Bridge Java image compile check | ~15s cached / Java compile path verified | Pass |
| `docker compose config` | Compose syntax/render check | ~3s | Pass |
| `pnpm typecheck` | Workspace TypeScript compiler check | ~30s | Pass |
| `pnpm lint` | Workspace lint/type checks | ~30s | Pass |
| `pnpm test` | Package-wide test suites | ~30s | Pass: gateway, packages, engine-worker, and web tests completed |
| `pnpm build` | Production packages & Next.js build | ~34s | Pass |
| `ENABLE_XMAGE_FIXTURES=true NODE_ENV=test docker compose up -d --build xmage-bridge xmage-gateway` | Embedded same-JVM fixture startup | ~2-3m to ready after cached rebuild | Pass: gateway health reached `status: "ready"` after XMage card/server startup |
| `curl http://localhost:17171/health` | Gateway/bridge health | Ready after startup polling | Pass: `status: "ready"`, `reason: "XMage Java bridge connected to 127.0.0.1:17171."` |
| `XMAGE_GATEWAY_URL=http://localhost:17171 pnpm smoke:xmage` | Live gateway & Java bridge non-fixtured play loop | Diagnostic only | Not a release gate; nondeterministic legal-deck state can miss required proof routes |
| `ENABLE_XMAGE_FIXTURES=true NODE_ENV=test XMAGE_GATEWAY_URL=http://localhost:17171 XMAGE_SMOKE_SCENARIO=commander-gauntlet XMAGE_USE_FIXTURE=true pnpm smoke:xmage` | Full deterministic Commander gauntlet smoke | ~90s after services ready | Historical pass: real `source: "xmage-java-bridge"`, direct fixture seeding, `stepsBlocked: []` |
| `ENABLE_XMAGE_FIXTURES=true NODE_ENV=test XMAGE_GATEWAY_URL=http://localhost:17171 XMAGE_SMOKE_SCENARIO=commander-damage XMAGE_USE_FIXTURE=true pnpm smoke:xmage` | Targeted deterministic commander damage smoke | ~40s after services ready | Historical pass: real `source: "xmage-java-bridge"`, commander-damage evidence, `stepsBlocked: []` |

### Key Smoke Test Verification Points:
- The bridge image was rebuilt after the source-UUID `make_mana` fix and after the activation-dispatch/commander prompt classifier fixes in this pass.
- Final deterministic smoke evidence from this pass used `source: "xmage-java-bridge"`, direct fixture seeding, seeded-state verification, and `stepsBlocked: []`.
- Focused activated-ability fixture evidence from the same pass used `source: "xmage-java-bridge"`, direct fixture seeding, no missing route families, and `stepsBlocked: []`.
- Focused commander-damage fixture evidence from the same pass used `source: "xmage-java-bridge"` and non-empty commander-damage evidence after the combat-selection bridge fix.
- The successful gauntlet used `setupMethod: "in_server_game_cheat"` and `source: "xmage-server-fixture-service"` for setup metadata, then all gameplay actions went through the real Java bridge command path.
- Live route-family evidence in the passing report: `play_land`, `cast_spell`, `make_mana`, `activate_ability`, `search_select/choose_card` via XMage `GAME_TARGET` search selection, `choose_target`, `answer_yes_no`, `pay_cost` via `GAME_PLAY_MANA`, `commander_replacement`, `pass_priority`, `stack_object_seen`, `trigger_seen`, `zone_update_seen`, and `commander_tax_seen`.
- `laterScope` remains non-empty in the gauntlet report for `mana-rock`, `commander-damage`, `blocker-flow`, and `prompt-variety`; targeted commander-damage is now separately deterministic-fixture proven, while real blocker assignment and prompt-variety are still not green.
- Historical generated reports must be treated as artifacts only; new reports are written under `build_output/smoke/*.json` and ignored by git.
- Added a dev-only fixture harness route at `POST /dev/xmage-fixtures/commander`, guarded by `ENABLE_XMAGE_FIXTURES=true` and disabled when `NODE_ENV=production`.
- Fixture smoke can now be invoked with `ENABLE_XMAGE_FIXTURES=true NODE_ENV=test XMAGE_GATEWAY_URL=http://localhost:17171 XMAGE_SMOKE_SCENARIO=commander-gauntlet XMAGE_USE_FIXTURE=true pnpm smoke:xmage`.
- Current fixture harness implementation includes a dev/test-only embedded same-JVM startup path. In fixture mode, `MagicMobileEmbeddedServerBridge` starts `mage.server.Main.main(args)` and gives `MagicMobileBridge` access to the server-side manager factory so the route can seed through XMage-owned `GameController` / `Game.cheat(...)`.
- June 23 bridge fix: default XMage card-click actions now send source card UUIDs for `play_land`, normal `cast_spell`, basic `make_mana`, and playable-object `activate_ability`; non-mana `activate_ability` still requires the selected ability UUID for stale-action validation before dispatch. Combat selections now finish attacker/blocker UUID submission with XMage's explicit Done/OK boolean (`false`) instead of the previous cancel-like `true`.
- Performed opening hand keep (`keep_hand`).
- Played a Forest land card from hand (`play_land`).
- Tapped land to generate green mana (`make_mana`).
- Cast a simple creature spell from hand (`cast_spell`).
- Resolved the mana-payment prompt (`GAME_PLAY_MANA` prompt envelope).
- Passed priority to the AI (`pass_priority`) and verified AI response execution.
- Submitted typed combat attacker payloads in the combat fixture.
- Parsed commander tax from real XMage snapshots in the current gauntlet and commander-state smoke. Commander damage is now separately deterministic-fixture proven by `commander-damage` with a non-empty `commanderDamageChanges` array; it is still not required by the current gauntlet release gate.
- Added a legal singleton `commander-gauntlet` smoke scenario that reports completed and blocked gauntlet steps from real XMage state. This is the current alpha milestone gate and passed locally with no `stepsBlocked`.
- Fixed player-only `GAME_TARGET` prompts so starting-player selection is exposed as `choose_player` and submitted with XMage player UUIDs, not the local actor alias.
- Fixed `GAME_OVER` prompt snapshots to fail closed by exposing only terminal-safe actions instead of stale playable battlefield actions.
- iOS simulator tests now pass through XcodeBuildMCP: `MagicMobileTests` ran 4 tests, 0 failures, after enabling generated Info.plist for the test target. This does not count as real phone product success.

---

## 4. Manual & Docker Verification Workflows

Developers can verify the readiness of the system manually using the following steps:

### Step 1: Pre-build Verification
Ensure the monorepo passes compiler and lint checks:
```sh
pnpm install
pnpm typecheck
pnpm lint
pnpm test
```

### Step 2: Build & Start Docker Services
Start the localized Docker containers:
```sh
pnpm dev:xmage
```
*(Alternatively, target only the bridge and gateway services: `docker compose up --build xmage-bridge xmage-gateway`)*

For gauntlet fixture coverage, start the targeted stack with fixture mode enabled:

```sh
ENABLE_XMAGE_FIXTURES=true NODE_ENV=test docker compose up --build xmage-bridge xmage-gateway
```

### Step 3: Verify Gateway Health
Query the gateway health endpoint:
```sh
curl -s http://localhost:17171/health
```
**Expected response:**
```json
{
  "status": "ready",
  "reason": "XMage Java bridge connected to 127.0.0.1:17171.",
  "recoveryAction": "wait"
}
```

### Step 4: Run Live Smoke test
With services up and healthy, run the smoke test:
```sh
pnpm smoke:xmage
```
**Expected output:** A JSON snapshot containing final game state, showing the core loop progressed through keep, land, mana, cast, payment, AI wait/progress, combat step, and final revision status. Non-fixtured smoke remains diagnostic; use the fixture gauntlet for release-gate evidence.

---

## 5. Assumptions, Blockers, & TODOs

### Assumptions:
- Upstream XMage server artifact (`mage-full_1.4.60-dev_2026-06-20_17-27.zip`) is reachable and cached by Docker.
- Monorepo package versions are locked at Node 22 and pnpm 10.12.4.

### Blockers:
- Normal CI checks are green in this pass.
- The deterministic real-XMage Commander gauntlet is green for the current alpha route-family gate: `stepsBlocked: []`.
- Non-fixtured `core-flow` remains diagnostic only because legal-deck draw/order is nondeterministic.
- `mana-rock`, `commander-damage`, `blocker-flow`, and `prompt-variety` are still `laterScope` in the latest gauntlet report. Targeted commander damage is now separately proven, and a separate `blocker-flow` smoke passed with `declare_attackers` evidence, but real blocker assignment is still unproven. Do not claim later-scope routes as part of the gauntlet gate unless fresh reports move them into the required gate and prove them with real XMage.
- Prompt-variety is not green until real XMage proof covers `stack_object_seen`, `activate_ability`, `choose_ability`, `choose_mode`, `order_triggers/order_items`, `choose_amount`, `choose_multi_amount`, and `choose_pile`.

### Remaining TODOs / Gaps:
1. **Viewer-scoped Snapshots**: Multiplayer human pods need snapshot filtering so opponents cannot inspect other players' libraries or hands.
2. **Advanced UI Prompts**: Render and handle reordering triggers/items, mode/ability/pile/amount choices, commander replacement, and blockers directly in UI components.
3. **Card Art fallback**: Handle missing image urls smoothly without throwing render errors.
4. **Casting/payment manual QA**: The live gauntlet proves land, mana, spell, search, commander replacement, and payment prompt flow, but iPhone/web still need manual regression coverage for the two-lands-into-`Arcane Signet` case documented in [CASTING_AND_MANA_FLOW.md](CASTING_AND_MANA_FLOW.md).
5. **Long AI endurance**: Some runs still expose AI waiting/stall behavior, especially with weaker fixture AI or awkward fixture decks. The app must continue surfacing AI thinking/stalled states honestly while targeted fixtures keep the core loop deterministic.
6. **Later-scope fixture expansion**: Add targeted deterministic scenarios for mana-rock activation, blocker assignment, and prompt-variety once those are explicitly in alpha scope.

### Exact blockers before iPhone alpha:
1. Run the full validation set on the final checkout after doc updates.
2. Perform real iPhone manual QA against the same fixture-ready gateway; simulator success still does not count.
3. Confirm the iOS `/play` experience surfaces source, bridge health, revision/cycle, priority, pending status, unsupported prompts, and failed commands without falling back to simulator.
4. Decide whether `mana-rock`, `blocker-flow`, or `prompt-variety` must move from `laterScope` into the iPhone alpha gate. Commander damage already has targeted real-XMage fixture proof, but it is not part of the current gauntlet gate.
