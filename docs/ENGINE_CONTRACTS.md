# Engine Contracts

MagicMobile talks to rules engines through shared contracts. Production Commander play uses XMage through the gateway and Java bridge. The simulator is for dev-only UI work.

## Snapshot Contract

`GameSnapshot` is the authoritative view rendered by iOS and web. For real XMage games it should include:

- `source: "xmage-java-bridge"` when produced by the Java bridge.
- `bridgeRevision` as the ordered bridge truth source.
- `xmageCycle` when XMage exposes a cycle value.
- `pendingStatus` for accepted/waiting/stalled states.
- active player, priority player, waiting player, phase, step, turn.
- players with life, poison, mana pool, commander tax, commander damage, and zones.
- stack, command zone, graveyard, exile, revealed/looked-at/search surfaces where available.
- `promptEnvelopeV2` when XMage is waiting for a user response.
- legal actions that are valid for the viewing player.

Future human multiplayer must use viewer-scoped snapshots so hidden hands and libraries are never sent to the wrong player.

## Legal Action Invariants

For XMage-backed actions, `LegalAction` should carry enough metadata to submit without client guessing:

- stable `id`
- action `type`
- `playerId`
- label and short label
- source zone
- card/source/ability ids where available
- prompt id and message id where prompt-derived
- min/max/required metadata where prompt-derived
- candidate target/card/player/mode/mana/amount/order ids
- `commandTemplate` when the bridge can provide an exact command shape

Unknown or stale actions should fail closed.

## Prompt Envelope Invariants

`PromptEnvelopeV2` is the canonical mobile/web prompt model. It should preserve:

- prompt id and message id
- method/callback family
- player id
- response kind
- message/title
- required/optional
- min/max selections
- choices/cards/targets/players/modes/abilities/amounts/mana/piles/ordered items
- confirmation labels and explicit yes/no command templates
- response command template

Clients should render unknown prompt kinds honestly with message and debug metadata rather than guessing.

## Command Lifecycle

Preferred command flow:

1. Client sends a `GameCommand` with request id and prompt/action metadata.
2. API route logs command start and forwards to the engine adapter.
3. Gateway forwards to Java bridge.
4. Bridge validates current prompt/legal state and sends the exact XMage response.
5. If XMage produces a new snapshot quickly, return it.
6. If XMage accepted the action but no snapshot is ready, return a snapshot with `pendingStatus: "waiting_for_xmage"`.
7. WebSocket broadcasts the authoritative snapshot when it arrives.
8. Client reconciles pending UI against the latest `bridgeRevision`.

Future work should add typed command results with `accepted`, `applied`, `waiting_for_xmage`, `rejected`, and `stalled` states. Full snapshots are acceptable for alpha; deltas can wait until measurements prove they are needed.

## Simulator Boundary

- Simulator state may mutate locally for UI development.
- Simulator success is not product gameplay success.
- Production `/play` must not silently fall back to simulator.
- Simulator routes and labels should remain explicit, e.g. `/dev/play-simulator`.
