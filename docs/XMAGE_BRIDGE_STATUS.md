# XMage Bridge Status

MagicMobile currently uses a thin gateway and Java bridge to run XMage server-side while iOS and web render a mobile Commander client. XMage remains the source of truth for rules, priority, stack, prompts, combat, Commander choices, and state transitions.

## Current Scope

- Current product target: 1v1 Commander vs XMage AI.
- Future compatible targets: human-vs-human Commander, then 3-4 player digital Commander pods.
- Not current targets: non-Commander formats, tournaments, draft/sealed, webcam play, hybrid paper/digital play.

## Current Strengths

- Dockerized Java bridge starts upstream XMage and exposes HTTP endpoints behind `apps/xmage-gateway`.
- Gateway health, Java bridge health, command forwarding, WebSocket broadcast, and stale `bridgeRevision` rejection are covered by gateway tests.
- The bridge creates a Commander table, loads human and AI decks, joins a human plus XMage AI, and translates `GameView` into shared snapshots.
- `bridgeRevision` and `xmageCycle` are present in bridge snapshots.
- PromptEnvelopeV2 covers many callback families: target, card, player, mode, ability, pile, amount, multi-amount, mana, ordering, search, confirmation, commander replacement, and pay-cost-like responses.
- `play_land` and normal `cast_spell` send the playable source UUID. `activate_ability` sends the playable ability UUID.
- Production web `/play` uses the XMage adapter path; `/dev/play-simulator` is separate and explicitly dev-only.

## Known Gaps

| Area | Status | Risk | Next step |
|---|---|---|---|
| Live Docker/XMage smoke | Unit and mocked bridge tests pass, but live smoke is not consistently green. | Product may look correct in tests while real XMage pass/AI/prompt behavior fails. | Keep running `XMAGE_GATEWAY_URL=http://localhost:17171 pnpm smoke:xmage` and record exact failing step. |
| Pass priority | Bridge currently submits a boolean response for `pass_priority`; live behavior still needs proof. | UI can appear to do nothing after a pass. | Inspect XMage client/server expected callback for priority pass and add a live regression. |
| AI waiting | Gateway has a watchdog, but live AI-start games can expose only `Concede` while waiting. | Phone feels frozen even though XMage/AI is thinking or stalled. | Show explicit AI thinking/stalled state and improve AI progress detection. |
| Boolean prompt defaults | The bridge now fails closed for `answer_yes_no`, `pay_cost`, and `commander_replacement` when explicit booleans are missing. | Older clients that omit explicit booleans will get rejected instead of auto-answering. | Keep iOS/web using command templates or explicit boolean fields. |
| Make mana | `make_mana` uses source UUID and `play_mana` uses mana type, but mana ability identity is still not fully proven for all sources. | Mana rocks/multicolor sources can ask follow-up prompts or misroute. | Add live tests for lands, rocks, and multicolor mana choices. |
| Combat selections | Attack/block transport exists, but empty declarations and defender/blocker pairing need stricter client UX and tests. | Dropped ids can look like intentional no-attacks/no-blocks. | Require explicit empty combat choices in UI and add combat smoke. |
| Commander tax/damage | Shared types and UI fields exist; Java bridge currently reports placeholder values. | Commander games are not fully truthful. | Map real XMage commander tax/cast count/damage data or expose a documented bridge TODO until found. |
| Player-specific snapshots | Opponent hand/library are hidden placeholders in current 1v1 AI flow, but APIs/WebSockets are not viewer-scoped. | Future human games could leak or misroute hidden info. | Add `viewerPlayerId`/player-scoped snapshot contract before human multiplayer. |
| Prompt coverage proof | Prompt model is broad, but live tests do not force each callback family. | Missing prompt types can appear mid-game and block play. | Build prompt fixture decks and add prompt-family smoke scenarios. |

## Bridge Invariants

- The bridge must stay thin. It translates between MagicMobile contracts and XMage calls; it must not implement a second Magic rules engine.
- Missing or stale prompt ids must fail closed.
- Missing required choices must fail closed.
- Missing required boolean answers must fail closed.
- Client optimistic UI is temporary only; actual zones, tapping, stack, combat, and game result come from XMage snapshots.
- Simulator behavior must stay dev-only and never be presented as real `/play` success.

## Current Verification Status

Local unit and integration-style tests cover gateway behavior, mocked bridge forwarding, stale snapshot rejection, simulator separation, and prompt rendering. The remaining milestone proof is live XMage smoke through opening hand, land, mana, spell, stack/pass, prompt response, and AI turn progression.
