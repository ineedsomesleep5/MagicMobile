# MagicMobile

Commander-first web and mobile scaffold for digital, webcam, and hybrid tabletop play. This milestone adds a rules-engine boundary for Commander play, a local XMage gateway simulator, Scryfall card-image caching, and a Three.js battlefield shell while preserving the modern React/Expo UI.

## Apps and Packages

- `apps/web`: Next.js App Router scaffold with Commander deck, card, play, room, settings, and dev routes.
- `apps/mobile`: Expo scaffold with landscape Commander gameplay controls, deck list, and room placeholders.
- `apps/xmage-gateway`: Local HTTP gateway that exposes the XMage-ready engine API, AI difficulty mapping, health checks, and a simulator used until the Java bridge is connected.
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
pnpm lint
pnpm test
pnpm build
docker compose config
```

Local services:

```sh
docker compose up web xmage-gateway postgres redis
```

## Environment

Copy `.env.example` into a local `.env` file when a package needs runtime configuration. Use `ENGINE_MODE=xmage` with `XMAGE_GATEWAY_URL=http://localhost:17171` to route engine calls through the gateway.

## Milestone Boundaries

- No Wizards logos or official branding are included.
- EDHREC support is limited to documented link-outs and disabled provider stubs. No scraping is included.
- Room and recommendation APIs use in-memory providers for this milestone.
- Deck detail connects to seed card data, Commander analysis, and mock recommendations.
- Play UI renders a Three.js battlefield and connects through the shared engine adapter boundary.
- The XMage gateway currently runs a local simulator with XMage-compatible command and health endpoints. A deeper upstream XMage Java bridge is the next integration step.
- Hybrid and webcam seats are visual placeholders, not live video or recognition implementations.
