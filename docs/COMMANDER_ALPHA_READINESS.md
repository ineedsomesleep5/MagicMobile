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
| `pnpm test` | Package-wide test suites | **13.433s** | Pass (92 tests across 11 packages) |
| `pnpm typecheck` | TypeScript compiler check | **11.782s** | Pass (All workspace projects) |
| `pnpm build` | Production packages & Next.js build | **29.385s** | Pass (Compiled static/dynamic routes) |
| `pnpm smoke:xmage` | Live gateway & Java bridge play loop | **1m 12.37s** | Pass (Turns 1-4 game progress) |

### Key Smoke Test Verification Points:
- Created a game via HTTP client against the live Java bridge.
- Performed opening hand keep (`keep_hand`).
- Played a Forest land card from hand (`play_land`).
- Tapped land to generate green mana (`make_mana`).
- Cast `Llanowar Elves` spell from hand (`cast_spell`).
- Resolved the mana-payment prompt (`GAME_PLAY_MANA` prompt envelope).
- Passed priority to the AI (`pass_priority`) and verified AI response execution.

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
**Expected output:** A JSON snapshot containing final game state, showing turns progressed to 1-4 and a final revision status.

---

## 5. Assumptions, Blockers, & TODOs

### Assumptions:
- Upstream XMage server artifact (`mage-full_1.4.60-dev_2026-06-20_17-27.zip`) is reachable and cached by Docker.
- Monorepo package versions are locked at Node 22 and pnpm 10.12.4.

### Blockers:
- No critical blockers prevent 1v1 digital play against XMage AI.

### Remaining TODOs / Gaps:
1. **Viewer-scoped Snapshots**: Multiplayer human pods need snapshot filtering so opponents cannot inspect other players' libraries or hands.
2. **Advanced UI Prompts**: Render and handle reordering triggers/items and declaring attackers/blockers directly in UI components.
3. **Card Art fallback**: Handle missing image urls smoothly without throwing render errors.
