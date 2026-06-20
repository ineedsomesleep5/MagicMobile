# MagicMobile Implementation Plan

## Milestone Goal

Build a working foundation for a Commander-first web and iOS mobile app. This milestone uses mocks and stubs where full production integrations would be premature, but every boundary should be explicit and testable.

## Parent Assumptions

- Monorepo package manager: pnpm.
- Language: TypeScript.
- Web app: Next.js App Router in `apps/web`.
- Mobile app: Expo in `apps/mobile`.
- Package tests: Vitest.
- Local services: Postgres and Redis through Docker Compose.
- GitHub repo creation is intentionally out of scope until requested.

## Shared Contracts First

The parent orchestrator owns the initial contracts in `packages/shared`:

- `EngineAdapter`
- `VideoProvider`
- `RecommendationProvider`
- `DeckParser`
- `DeckAnalyzer`
- `CardDataProvider`
- Database model assumptions

No UI code may import XMage internals directly. Future XMage updates must be isolated behind `EngineAdapter` and contract tests.

## Workstreams

### 1. Architecture / Monorepo / Shared Contracts

Owns package boundaries, architecture docs, shared scripts, and contract alignment.

### 2. Card Data / Scryfall / Deck Builder / Imports

Owns `packages/card-data`, `packages/deck`, card seed data, deck parsing, Commander validation, deck stats, Rule 0 summaries, and bracket scoring.

### 3. Recommendations / EDHREC-Style System / Data Policy

Owns `packages/recommendations`, recommendation endpoints, recommendation UI placeholder, and EDHREC policy docs. No EDHREC scraping.

### 4. Game Engine / XMage Adapter / Mock Rules Engine

Owns `apps/engine-worker`, mock engine behavior, XMage adapter stub, engine contract tests, and XMage integration docs.

### 5. Multiplayer / Rooms / WebSocket / Video / Hybrid Seats

Owns room APIs, realtime abstractions, video provider package, hybrid action protocol, and recognition placeholders.

### 6. UX / Web App / Mobile Scaffold / QA / Dev Experience

Owns `apps/web`, `apps/mobile`, `packages/ui`, root README, environment example, Docker Compose, CI, dev scripts, and smoke tests.

## Integration Gates

Run these after subagent work is merged:

```sh
pnpm install
pnpm lint
pnpm test
pnpm build
docker compose config
```

## Final Audit Checklist

- Shared types line up across apps and packages.
- API endpoints use the same contracts as the UI.
- Mock engine connects to room/game UI.
- Deck builder connects to card data and recommendations.
- README run instructions are accurate.
- No EDHREC scraping exists.
- No Wizards logos or official branding exist.
- Stubs and mocks are clearly labeled.
- Failing checks are fixed or documented with exact reasons.
