# Commander Alpha Release Readiness Report

This document outlines the CI configuration status, Docker environment verification, and latency measurements for the MagicMobile Commander Alpha release.

> [!IMPORTANT]
> The production gameplay path at `/play` strictly requires a healthy XMage gateway and Java bridge. The simulator mode is kept isolated at `/dev/play-simulator` for UI and component development.

---

## 1. CI Workflow Status

We inspected the CI configuration file [ci.yml](file:///Users/calebfeliciano/Documents/MagicMobile/.github/workflows/ci.yml). 

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

---

## 2. Docker Architecture Status

The project runs on a 5-tier architecture defined in [docker-compose.yml](file:///Users/calebfeliciano/Documents/MagicMobile/docker-compose.yml):

| Service | Image/Context | Port(s) | Health Check Status | Description |
|---|---|---|---|---|
| `postgres` | `postgres:16-alpine` | `5432` | `pg_isready` (5 retries) | Relational database storage |
| `redis` | `redis:7-alpine` | `6379` | `redis-cli ping` (5 retries) | In-memory key-value cache and room pub/sub |
| `xmage-bridge` | `./apps/xmage-gateway/bridge` | `17172`, `17179` | HTTP `/health` check (20 retries) | Java 17 service wrapping the XMage server and client connections |
| `xmage-gateway` | `node:22-bookworm-slim` | `17171` | N/A (Starts after bridge) | Node proxy gateway managing AI game creation and websocket broadcasts |
| `web` | `node:22-bookworm-slim` | `3000` | N/A (Starts after postgres/redis/gateway) | Next.js production web server rendering the UI |

Local Docker services were verified as running and healthy on June 22, 2026.

---

## 3. Command Latency & Performance Measurements

All performance tests and builds were run locally on macOS. 

| Command | Purpose | Duration (s) | Result |
|---|---|---|---|
| `pnpm lint` | Workspace lint/type checks | **28.3s** | Pass |
| `pnpm test` | Package-wide test suites | **28.9s** | Pass |
| `pnpm typecheck` | TypeScript compiler check | **13.6s** | Pass |
| `pnpm build` | Production packages & Next.js build | **~60s** | Pass |
| `XMAGE_GATEWAY_URL=http://localhost:17171 pnpm smoke:xmage` | Live gateway & Java bridge play loop | **~60s** | Not current gate-green after latest bridge work; rerun after rebuilding bridge image with source-UUID `make_mana` fix |
| `XMAGE_GATEWAY_URL=http://localhost:17171 XMAGE_SMOKE_SCENARIO=combat pnpm smoke:xmage` | Typed combat fixture | **~30s** | Pass (`declare_attackers`) |
| `XMAGE_GATEWAY_URL=http://localhost:17171 XMAGE_SMOKE_SCENARIO=commander-state pnpm smoke:xmage` | Commander tax/damage fixture | varies | Not current gate-green; older artifacts observed tax/damage, but latest targeted work moved the blocker to AI-start/pass-yield stability |
| `ENABLE_XMAGE_FIXTURES=true XMAGE_GATEWAY_URL=http://localhost:17171 XMAGE_SMOKE_SCENARIO=commander-gauntlet XMAGE_USE_FIXTURE=true pnpm smoke:xmage` | Full Commander Gauntlet fixture through dev-only fixture harness | ~1-2m | Fails honestly; latest normal-AI run proved land, mana, command-zone cast, pass priority, and AI continuation, but cannot deterministically hit one-of proof cards without server-side fixture seeding |

### Key Smoke Test Verification Points:
- Created a game via HTTP client against the live Java bridge.
- Added a dev-only fixture harness route at `POST /dev/xmage-fixtures/commander`, guarded by `ENABLE_XMAGE_FIXTURES=true` and disabled when `NODE_ENV=production`.
- Fixture smoke can now be invoked with `ENABLE_XMAGE_FIXTURES=true XMAGE_GATEWAY_URL=http://localhost:17171 XMAGE_SMOKE_SCENARIO=commander-gauntlet XMAGE_USE_FIXTURE=true pnpm smoke:xmage`.
- Current fixture harness metadata is honest: it reports `directStateSeeded: false` and `fallback: "deterministic_real_xmage_decks"` because the remote bridge cannot call XMage server-side `Game.cheat(...)` yet.
- June 23 bridge fix: default XMage card-click actions now send source card UUIDs for `play_land`, normal `cast_spell`, and basic `make_mana`; explicit `activate_ability` still sends the selected ability UUID. This is a generic playable-object routing fix, not card-specific logic.
- Performed opening hand keep (`keep_hand`).
- Played a Forest land card from hand (`play_land`).
- Tapped land to generate green mana (`make_mana`).
- Cast a simple creature spell from hand (`cast_spell`).
- Resolved the mana-payment prompt (`GAME_PLAY_MANA` prompt envelope).
- Passed priority to the AI (`pass_priority`) and verified AI response execution.
- Submitted typed combat attacker payloads in the combat fixture.
- Parsed commander tax and commander damage from real XMage snapshots in the commander-state fixture.
- Added a legal singleton `commander-gauntlet` smoke scenario that reports completed and blocked gauntlet steps from real XMage state. This is the new alpha milestone gate, but it is not yet a passing release gate because the Java bridge cannot currently seed a deterministic hand/library/battlefield after XMage shuffles.
- Latest `commander-gauntlet` evidence after the June 23 routing fixes: `source: xmage-java-bridge`, fixture metadata present, `directStateSeeded: false`, normal XMage AI progressed repeatedly, and the smoke proved `play_land`, command-zone cast, `make_mana`, pass priority, and AI continuation. Treat the remaining deterministic fixture coverage as blocked until a real server-side setup hook or equivalent path can seed exact proof cards/zones without faking gameplay.

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
**Expected output:** A JSON snapshot containing final game state, showing the core loop progressed through keep, land, mana, cast, payment, AI wait/progress, combat step, and final revision status.

---

## 5. Assumptions, Blockers, & TODOs

### Assumptions:
- Upstream XMage server artifact (`mage-full_1.4.60-dev_2026-06-20_17-27.zip`) is reachable and cached by Docker.
- Monorepo package versions are locked at Node 22 and pnpm 10.12.4.

### Blockers:
- A real-XMage blocker remains: the current bridge can create and advance real games, but smoke fixtures are not deterministic enough to prove every required Commander route in one run. The app must keep showing AI thinking/stalled honestly, and the release gate should not pass until the bridge/smoke can reliably progress through AI priority and all targeted proof routes.
- The attempted `arcane-signet` fixture is not a valid release gate yet because XMage correctly rejects repeated nonbasic `Arcane Signet` copies under Commander legality.
- The full Commander Gauntlet cannot be deterministic from a legal singleton deck alone. The dev-only fixture harness route exists and is production-disabled, but the real Java bridge can only choose decks and submit legal XMage actions today; it cannot currently seed opening hand, library order, battlefield, or turn state. A future in-server real-XMage setup hook is needed before `commander-gauntlet` can reliably prove Sol Ring/payment, fetch/search, commander replacement, recast tax, and commander damage in one run.

### Remaining TODOs / Gaps:
1. **Viewer-scoped Snapshots**: Multiplayer human pods need snapshot filtering so opponents cannot inspect other players' libraries or hands.
2. **Advanced UI Prompts**: Render and handle reordering triggers/items, mode/ability/pile/amount choices, commander replacement, and blockers directly in UI components.
3. **Card Art fallback**: Handle missing image urls smoothly without throwing render errors.
4. **Casting/payment manual QA**: The live smoke proves land, mana, spell, and prompt flow, but iPhone/web still need manual regression coverage for the two-lands-into-`Arcane Signet` case documented in [CASTING_AND_MANA_FLOW.md](file:///Users/calebfeliciano/Documents/MagicMobile/docs/CASTING_AND_MANA_FLOW.md).
5. **Long AI endurance**: Some runs still expose AI waiting/stall behavior, especially with weaker fixture AI or awkward fixture decks. The app must continue surfacing AI thinking/stalled states honestly while targeted fixtures keep the core loop deterministic.
6. **Commander Gauntlet setup**: Add a disabled-by-default, smoke-only real-XMage setup path or another upstream-supported deterministic setup method so the legal singleton fixture can reliably start with Sol Ring, Evolving Wilds, Swords to Plowshares, and Spirited Companion available for the full acceptance loop.
