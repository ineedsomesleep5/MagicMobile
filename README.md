# MagicMobile

Commander-first web and mobile scaffold for digital, webcam, and hybrid tabletop play. This milestone is intentionally mock-backed, with shared contracts, engine, room, card-data, and recommendation boundaries wired far enough for local development.

## Apps and Packages

- `apps/web`: Next.js App Router scaffold with Commander deck, card, play, room, settings, and dev routes.
- `apps/mobile`: Expo scaffold with local login placeholder, deck list, game room placeholder, and phone camera seat placeholder.
- `packages/ui`: Reusable React UI primitives for Commander gameplay surfaces.
- `packages/shared`: Shared TypeScript contracts owned by the architecture workstream.
- `packages/card-data` and `packages/deck`: Seed card data, deck parsing, Commander validation, stats, Rule 0, and bracket scoring.
- `packages/engine`: Mock `EngineAdapter` plus XMage adapter stub.
- `packages/realtime` and `packages/video`: In-memory room/realtime services and mock video provider boundaries.
- `packages/recommendations`: Mock/local recommendation providers and disabled EDHREC integration boundary.

## Getting Started

```sh
pnpm install
pnpm dev
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
docker compose up -d postgres redis
```

## Environment

Copy `.env.example` into a local `.env` file when a package needs runtime configuration. Current UI scaffolds use seed data, in-memory services, and mock providers.

## Milestone Boundaries

- No Wizards logos or official branding are included.
- EDHREC support is limited to documented link-outs and disabled provider stubs. No scraping is included.
- Room and recommendation APIs use in-memory providers for this milestone.
- Deck detail connects to seed card data, Commander analysis, and mock recommendations.
- Play UI connects to the mock engine through the shared adapter boundary.
- Hybrid and webcam seats are visual placeholders, not live video or recognition implementations.
