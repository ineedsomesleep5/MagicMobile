# XMage Bridge Status

MagicMobile uses a thin gateway and Java bridge to run XMage server-side while iOS and web render a mobile Commander client. XMage remains the source of truth for rules, priority, stack, prompts, combat, Commander choices, and state transitions.

## Current Scope

- **Primary Target**: 1v1 Commander vs XMage AI.
- **Future Targets**: Human-vs-human Commander, 3-4 player digital Commander pods.
- **Out of Scope**: Non-Commander formats, tournaments, draft/sealed, webcam play, hybrid paper/digital play.

## Current Strengths

- **Healthy Dockerized Java Bridge**: Starts upstream XMage and exposes HTTP endpoints behind `apps/xmage-gateway`.
- **Green Live Smoke Test**: The live smoke play loop (`pnpm smoke:xmage`) consistently runs to turn 4, validating hand keeping, land play, mana generation, cost payments, spell casting, stack resolution, and priority passing.
- **BridgeRevision and Cycle Rejection**: Fully enforced at both gateway (`server.mjs`) and client levels (Swift/Next.js), preventing stale updates or websocket snap-backs.
- **Strict Command Mapping**: The bridge throws an `IllegalArgumentException` for unknown command types rather than silently mapping to random UUID sends.
- **Parsed Commander Tax**: Real casting counts are extracted from commander card rules text (e.g. `"played from the command zone"`) and parsed to calculate commander tax:
  $$\text{Tax} = \text{Casts} \times 2$$
- **Parsed Commander Damage Matrix**: Real combat damage is parsed from commander rules (e.g. `"did X combat damage to player Y"`) and mapped to the correct players in the snapshot.
- **Clean Dev/Simulator Separation**: Web `/play` requires a healthy XMage gateway; `/dev/play-simulator` is labeled preview-only.

## Gaps & Next Steps

| Area | Status | Gaps & Next Step |
|---|---|---|
| **Human Multiplayer** | Modeled but unproven | Viewer-scoped snapshot routing is required to hide hands and library cards before human-vs-human or 3-4 player pods. |
| **Webcam / Hybrid paper** | Out of scope | Postponed until after the digital mobile alpha playtest. |

## Bridge Invariants

- The bridge must stay thin. It translates between MagicMobile contracts and XMage calls; it must not implement a second Magic rules engine.
- Missing or stale prompt ids must fail closed.
- Missing required choices must fail closed.
- Missing required boolean answers must fail closed.
- Client optimistic UI is temporary only; actual zones, tapping, stack, combat, and game result come from XMage snapshots.
- Simulator behavior must stay dev-only and never be presented as real `/play` success.
