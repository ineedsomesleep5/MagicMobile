# MagicMobile

MagicMobile is a Commander-only digital play client powered by XMage. The current product focus is a smooth mobile/web Commander experience where players can import or build valid 100-card Commander decks and play digitally against XMage AI first, then against human opponents, and later in 3-4 player Commander pods.

The real game path uses XMage as the rules, AI, priority, stack, prompt, Commander, and game-state authority. The app UI may show immediate local feedback while an action is pending, but authoritative board state must come from XMage snapshots.

## Apps and Packages

- `apps/web`: Next.js App Router scaffold with Commander deck, card, play, room, settings, and dev routes.
- `apps/mobile`: Expo scaffold kept compiling while the native iOS client is the primary phone target.
- `apps/ios`: Native Swift iOS client for Commander setup and landscape gameplay.
- `apps/xmage-gateway`: Local HTTP gateway that exposes the XMage engine API, AI difficulty mapping, health checks, WebSocket updates, and a dev-only simulator.
- `packages/ui`: Reusable React UI primitives for Commander gameplay surfaces.
- `packages/shared`: Shared TypeScript contracts owned by the architecture workstream.
- `packages/card-data` and `packages/deck`: Seed card data, deck parsing, Commander validation, stats, Rule 0, and bracket scoring.
- `packages/engine`: Mock `EngineAdapter` plus HTTP `XmageEngineAdapter`.
- `packages/realtime` and `packages/video`: In-memory room/realtime services and mock video provider boundaries.
- `packages/recommendations`: Mock/local recommendation providers and disabled EDHREC integration boundary.

## Getting Started

```sh
pnpm install
pnpm dev
```

Optional local Scryfall cache:

```sh
pnpm sync:scryfall
```

Useful checks:

```sh
pnpm typecheck
pnpm lint
pnpm test
pnpm build
docker compose config
```

Local XMage services:

```sh
docker compose up --build xmage-bridge xmage-gateway
```

Live XMage smoke is intentionally separate from normal CI because it depends on Docker and a healthy XMage runtime:

```sh
XMAGE_GATEWAY_URL=http://localhost:17171 pnpm smoke:xmage
XMAGE_GATEWAY_URL=http://localhost:17171 pnpm smoke:xmage:gauntlet
```

Smoke reports are generated under `build_output/smoke/*.json` and are ignored by git. Treat them as local or CI artifacts, not committed proof. Simulator/dev-route success does not count as real gameplay evidence.

## Environment

Copy `.env.example` into a local `.env` file when a package needs runtime configuration. Use `ENGINE_MODE=xmage` with `XMAGE_GATEWAY_URL=http://localhost:17171` to route real game calls through the gateway.

## Milestone Boundaries

- No Wizards logos or official branding are included.
- Commander-only is the current production scope: 100-card decks, command zone, commander tax, commander damage, 40 life, color identity, singleton rules, Commander legality, and XMage-backed Commander prompts.
- 1v1 Commander vs XMage AI is the first playable target. Human-vs-human and 3-4 player digital Commander pods are later milestones.
- Draft, sealed, tournaments, non-Commander formats, webcam play, hybrid paper/digital play, and SpellTable-style recognition are not current implementation targets.
- EDHREC support is limited to documented link-outs and disabled provider stubs. No scraping is included.
- The production `/play` route must use XMage through the gateway and Java bridge. It must not silently fall back to simulator mode.
- The simulator remains available only for fast UI development and should stay clearly labeled under dev-only routes such as `/dev/play-simulator`.
- The current integration hardening focus is prompt/action parity: every XMage prompt should render in iOS/web, respond with exact prompt metadata, reject stale prompts, and reconcile through server-authoritative snapshots.

## CI and Release Evidence

Normal GitHub Actions CI runs on `pull_request` and pushes to `main`, and covers `pnpm install`, `pnpm typecheck`, `pnpm lint`, `pnpm test`, and `pnpm build`. Live XMage smoke is available as a manual workflow (`XMage Smoke`) and should not be required for ordinary PRs until Docker/XMage startup is reliable enough for a required gate.

## Performance Goals

MagicMobile should feel like a polished mobile Commander client, not a frozen remote control for a desktop Java app. See [docs/PERFORMANCE_TARGETS.md](docs/PERFORMANCE_TARGETS.md) for the current latency targets, pending-state requirements, WebSocket-first update path, and measurement checklist.
