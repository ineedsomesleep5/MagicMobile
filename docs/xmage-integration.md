# XMage Integration

## Current milestone

MagicMobile uses the shared `EngineAdapter` contract as the only boundary between app code and rules-engine code. The current implementation is a mock rules engine in `packages/engine` plus an `XmageEngineAdapter` stub. The mock supports game setup, deck loading, shuffling, opening hands, zone movement, tap state, counters, token creation, spell-cast logging, priority, phase and turn advancement, life, poison, commander damage, commander tax, game logs, and reconnect snapshots.

This milestone does not implement full Magic: The Gathering rules. It records player intent and produces consistent game snapshots so UI and multiplayer flows can build against the adapter safely.

## Isolation rules

- UI packages must depend on `EngineAdapter`, not XMage classes.
- `packages/engine` must not import from `apps/web` or any UI-only module.
- The engine worker is the integration boundary for future process or container isolation.
- XMage-specific code should stay behind `XmageEngineAdapter` and worker transport code.

## Update safety

XMage should be treated as an external engine that can change independently. Keep MagicMobile data mapping small and explicit:

- Convert MagicMobile game commands into adapter calls.
- Convert XMage responses into `GameSnapshot`.
- Keep contract tests stable and run them against both the mock adapter and, later, the XMage adapter test harness.
- Do not let XMage model types leak into shared UI contracts.

## Contract tests

`packages/engine/tests/adapter-contract.test.ts` exercises the shared adapter behavior expected by callers. These tests are intentionally written against `EngineAdapter` wherever possible. Any future XMage worker must pass the same contract suite before replacing the mock adapter in a runtime path.

The XMage adapter currently throws a clear stub error. That is intentional until a real worker process exists.

## Future containerized worker

The expected production shape is a separate worker process or container:

1. The web app calls MagicMobile backend routes or realtime commands.
2. Backend code talks to `apps/engine-worker`.
3. `apps/engine-worker` owns the selected `EngineAdapter`.
4. The XMage adapter communicates with an isolated XMage service.
5. Snapshots and game logs return through shared MagicMobile types.

This keeps XMage upgrades, Java runtime requirements, crashes, and rule-engine latency away from UI code.
