# XMage Integration

## Current milestone

MagicMobile uses the shared `EngineAdapter` contract as the only boundary between app code and rules-engine code. The current implementation has three layers:

- `MockEngineAdapter` for deterministic local contract tests.
- `XmageEngineAdapter` for HTTP calls to an isolated gateway.
- `apps/xmage-gateway`, a runnable local HTTP service that exposes the XMage route shape, AI difficulty mapping, engine health, Commander game creation, legal actions, and command submission.
- `apps/xmage-gateway/bridge`, a Dockerized Java bridge that starts upstream XMage, creates a 1v1 Commander table, seats the human plus an XMage AI player, and translates `GameView` updates into MagicMobile `GameSnapshot`s.

The production `/play` route is XMage-required. The simulator remains available only for UI development at `/dev/play-simulator`; it must not silently replace XMage on the real play route.

## Isolation rules

- UI packages must depend on `EngineAdapter`, not XMage classes.
- `packages/engine` must not import from `apps/web` or any UI-only module.
- The gateway is the integration boundary for future process or container isolation.
- XMage-specific code should stay behind `XmageEngineAdapter` and worker transport code.

## Update safety

XMage should be treated as an external engine that can change independently. Keep MagicMobile data mapping small and explicit:

- Convert MagicMobile game commands into adapter calls.
- Convert XMage responses into `GameSnapshot`.
- Keep contract tests stable and run them against both the mock adapter and, later, the XMage adapter test harness.
- Do not let XMage model types leak into shared UI contracts.
- Keep the Java bridge thin: it should connect, create tables, relay legal choices, and translate snapshots rather than reimplementing rules.

## Contract tests

`packages/engine/tests/adapter-contract.test.ts` exercises the shared adapter behavior expected by callers. These tests are intentionally written against `EngineAdapter` wherever possible. Any future XMage worker must pass the same contract suite before replacing the mock adapter in a runtime path.

The XMage adapter now talks to the gateway and reports `EngineHealth` when the gateway, Java bridge, or XMage server is missing or stalled. Gateway simulator behavior is kept behind explicit simulator mode so contract tests can stay fast.

## AI difficulty mapping

MagicMobile difficulty maps to XMage player type and skill:

- `easy`: `Computer - default`, skill `3`
- `normal`: `Computer - mad`, skill `5`
- `hard`: `Computer - mad`, skill `8`
- `expert`: `Computer - monte carlo`, fallback `Computer - mad`, skill `10`

The gateway also exposes an AI watchdog through `EngineHealth`. If progress stalls, clients should offer `recreate_game` recovery rather than freezing the UI.

## Containerized gateway

Run the full local stack with:

```sh
pnpm dev:xmage
```

For host-based web development against Dockerized XMage only:

```sh
docker compose up --build xmage-bridge xmage-gateway
ENGINE_MODE=xmage XMAGE_GATEWAY_URL=http://localhost:17171 pnpm --filter @magicmobile/web exec next dev --hostname 0.0.0.0
```

The expected production shape is a separate worker process or container:

1. The web app calls MagicMobile backend routes or realtime commands.
2. Backend code talks to `EngineAdapter`.
3. `XmageEngineAdapter` talks to `apps/xmage-gateway`.
4. The gateway communicates with the isolated XMage Java bridge.
5. Snapshots and game logs return through shared MagicMobile types.

This keeps XMage upgrades, Java runtime requirements, crashes, and rule-engine latency away from UI code.

The current Java bridge is a first playable connection. It covers Commander table startup, generated deck loading, snapshot translation, legal playable-object actions, priority pass, choice responses, and concession. Deeper XMage prompt coverage should continue to land inside the bridge while keeping XMage as the source of truth.
