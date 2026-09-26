# XMage Mobile Next Steps

This roadmap keeps MagicMobile Commander-only and XMage-backed. It intentionally does not expand into draft, sealed, tournaments, webcam, hybrid, or non-Commander formats.

## Priority 1: Make 1v1 Commander vs XMage AI Playable

1. Keep `/play` XMage-only and `/dev/play-simulator` dev-only.
2. Make live smoke green against Dockerized XMage:
   - health ready
   - create Commander table
   - keep/mulligan
   - play land
   - make mana
   - cast spell
   - pass priority
   - resolve stack where possible
   - AI turn visibly progresses or shows stalled recovery
3. Fix pass-priority semantics against real XMage.
4. Improve AI waiting/stalled UI and gateway telemetry.
5. Ensure played lands/permanents, stack, command zone, graveyard, exile, mana pool, phase, active player, priority player, and log are visible on iOS and web.

## Priority 2: Complete Prompt Fidelity

1. Keep extending PromptEnvelopeV2 instead of adding one-off prompt patches.
2. Require prompt id/message id for prompt responses where available.
3. Validate min/max selections on clients and bridge.
4. Remove silent first-choice/default-answer paths.
5. Add real UI for:
   - target selection
   - card selection
   - player selection
   - mode selection
   - ability selection
   - amount and multi-amount selection
   - mana selection
   - pay cost
   - yes/no prompts
   - trigger/replacement ordering
   - search/select
   - commander replacement
   - declare attackers/blockers
6. Add prompt-family smoke fixtures so missing prompt types fail tests.

## Priority 3: Commander Deck Import And Validation

1. Prefer server-side parser/validator parity for iOS and web imports.
2. Support pasted Commander text, Moxfield-style text export, and Archidekt-style text export.
3. Validate:
   - exactly 100 cards including commander
   - singleton except basic lands
   - color identity
   - Commander legality/banned status where data exists
   - XMage card compatibility before table start
4. Surface exact deck-loading errors from XMage.
5. Do not scrape EDHREC. Keep recommendation providers separate from gameplay.

## Priority 4: Make It Feel Fast

1. Show local touch feedback immediately.
2. Show pending state for sent commands.
3. Return `waiting_for_xmage` instead of blocking when the bridge has accepted a command but XMage has not produced a new snapshot.
4. Use WebSockets as the main update path and polling only as backup.
5. Ignore stale `bridgeRevision` updates everywhere.
6. Measure command response time, bridge wait time, callback time, snapshot size, WebSocket delivery time, and client-apply time.

## Priority 5: Human Commander Later

Before human-vs-human or 3-4 player pods:

1. Add viewer-scoped snapshots and WebSocket subscriptions.
2. Ensure hidden hands/libraries are never sent to the wrong client.
3. Add reconnect-per-player.
4. Add per-player legal actions and prompts.
5. Keep the same prompt/action bridge; do not fork rules into clients.

## Current Shortest Path

1. Run and fix live Docker smoke until it passes through at least land, mana, spell, pass, and one AI progression point.
2. Add bridge truth for commander tax/damage.
3. Add prompt fixtures for target, mana, yes/no, commander replacement, and search/select.
4. Device-test iOS against the same live gateway with card images cached locally.
