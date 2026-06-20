# XMage Integration

## Current milestone

MagicMobile uses the shared `EngineAdapter` contract as the only boundary between app code and rules-engine code. The current implementation has three layers:

- `MockEngineAdapter` for deterministic local contract tests.
- `XmageEngineAdapter` for HTTP calls to an isolated gateway.
- `apps/xmage-gateway`, a runnable local HTTP service that exposes the XMage-facing route shape, AI difficulty mapping, engine health, Commander game creation, legal actions, and command submission.

The gateway currently uses a local simulator so the web/mobile UI can be implemented against stable contracts before the Java XMage RPC bridge is connected. It does not yet implement full Magic: The Gathering rules; real rules enforcement belongs in the next bridge step.

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

## Contract tests

`packages/engine/tests/adapter-contract.test.ts` exercises the shared adapter behavior expected by callers. These tests are intentionally written against `EngineAdapter` wherever possible. Any future XMage worker must pass the same contract suite before replacing the mock adapter in a runtime path.

The XMage adapter now talks to the gateway and reports `EngineHealth` when the gateway is missing or stalled. The gateway simulator must pass the same contract tests as the mock adapter before the Java bridge replaces its internals.

## AI difficulty mapping

MagicMobile difficulty maps to XMage player type and skill:

- `easy`: `Computer - default`, skill `3`
- `normal`: `Computer - mad`, skill `5`
- `hard`: `Computer - mad`, skill `8`
- `expert`: `Computer - monte carlo`, fallback `Computer - mad`, skill `10`

The gateway also exposes an AI watchdog through `EngineHealth`. If progress stalls, clients should offer `recreate_game` recovery rather than freezing the UI.

## Containerized gateway

The expected production shape is a separate worker process or container:

1. The web app calls MagicMobile backend routes or realtime commands.
2. Backend code talks to `EngineAdapter`.
3. `XmageEngineAdapter` talks to `apps/xmage-gateway`.
4. The gateway communicates with an isolated XMage Java service when the bridge is implemented.
5. Snapshots and game logs return through shared MagicMobile types.

This keeps XMage upgrades, Java runtime requirements, crashes, and rule-engine latency away from UI code.
