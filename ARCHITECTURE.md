# MagicMobile Architecture

## Overview

MagicMobile is a Commander-first multiplayer foundation with a web app, an iOS mobile app, shared TypeScript contracts, local deck/card intelligence, mockable game engines, and replaceable video/recommendation providers.

## Monorepo Layout

```text
apps/
  web/             Next.js web app and API routes
  mobile/          Expo iOS/mobile scaffold
  engine-worker/   Future isolated game-engine worker
  xmage-gateway/   Local XMage-facing HTTP gateway and simulator boundary
packages/
  shared/          Cross-app contracts and shared types
  card-data/       Card data provider and Scryfall sync boundary
  deck/            Deck parser, validation, stats, Rule 0, bracket scoring
  recommendations/ Recommendation providers and policy boundaries
  video/           Video provider boundary and mocks
  ui/              Shared React UI components
docs/
  data-policy.md
  xmage-integration.md
```

## Dependency Rules

- Apps can import packages.
- Packages can import `@magicmobile/shared`.
- UI must never import XMage classes directly.
- XMage integration belongs behind `EngineAdapter`.
- EDHREC integration must be explicit, disabled by default, and never scrape unapproved endpoints.

## Service Boundaries

- Web API routes expose deck, recommendation, room, and engine-adjacent contracts.
- Realtime and video are provider-backed so local mocks can be swapped for production services later.
- Database assumptions are documented as TypeScript model shapes until migrations are introduced.

## Adapter Strategy

External systems are isolated behind provider interfaces:

- `EngineAdapter`: mock engine now, XMage worker later.
- `XmageEngineAdapter`: HTTP adapter for the isolated gateway.
- `VideoProvider`: mock sessions now, LiveKit later.
- `RecommendationProvider`: mock/local synergy now, approved EDHREC integration later.
- `DeckParser` and `DeckAnalyzer`: local deterministic deck features.
- `CardDataProvider`: seed data now, Scryfall bulk sync later.

## XMage Integration Map

- Keep UI and app routes typed against `EngineAdapter`, not XMage classes.
- Put XMage process/client code behind `apps/xmage-gateway`.
- Translate XMage state into `GameSnapshot` before returning across package boundaries.
- Add adapter contract tests that replay create, join, load deck, priority, and phase flows.
- Document setup and operational constraints in `docs/xmage-integration.md` when the worker exists.

The first gateway milestone is a local HTTP simulator with the same route and snapshot shape that the Java XMage bridge will expose. This keeps Three.js, web, and mobile clients independent from XMage internals while local Docker and hosted deployments share one service boundary.

## Testing Strategy

- Contract tests prove provider behavior.
- Package unit tests cover parsing, validation, recommendations, and mock engine behavior.
- App smoke tests verify core routes and scaffold rendering.
- Integration checks run through pnpm scripts and Docker Compose config validation.
