# Player-Scoped Snapshots Design Plan

This document describes the planned player-scoped snapshot obfuscation system for human multiplayer Commander games (2-4 players).

> [!IMPORTANT]
> This is the **primary blocker** before enabling human-vs-human multiplayer pods.

---

## Problem

In 1v1 vs AI, exposing all zones to the human player is acceptable since the AI opponent's hand/library are not strategically secret. In human multiplayer, each player must only see:

- Their own hand and library contents
- Other players' **public zones**: battlefield, command zone, graveyard, exile, stack
- Other players' hand **count** (not contents)
- Other players' library **count** (not contents)
- No looked-at or revealed cards from private zones unless XMage explicitly marks them as revealed

## Current Implementation (Alpha)

The gateway now has `obfuscateSnapshotForPlayer(snapshot, targetPlayerId)` in [server.mjs](file:///Users/calebfeliciano/Documents/MagicMobile/apps/xmage-gateway/server.mjs) and the Java bridge in [MagicMobileBridge.java](file:///Users/calebfeliciano/Documents/MagicMobile/apps/xmage-gateway/bridge/MagicMobileBridge.java).

**What it does today:**
- Replaces opponent hand card details with `{ name: "Hidden card" }` placeholders
- Replaces **all** library card details with placeholders (including the viewer's own library)
- Preserves hand and library **count** for UI display
- Activated via `?playerId=<id>` query parameter on GET `/games/:id`

**What's missing for full multiplayer:**
1. WebSocket broadcasts must be player-scoped (send different snapshots to different connections)
2. Legal actions must be filtered per-player (currently returns all legal actions for the active player)
3. XMage "revealed" card state needs to be forwarded (e.g., when a card is revealed from hand)
4. Sideboard/outside-game zones need obfuscation rules
5. Spectator mode needs its own obfuscation profile

## Proposed Contract

```typescript
interface PlayerScopedSnapshot extends GameSnapshot {
  /** The player this snapshot was generated for */
  viewerPlayerId: string;
  
  /** Each opponent's hand shows count but hidden cards */
  // player.zones.hand = [{ instanceId: "hidden-0", card: { name: "Hidden card" } }, ...]
  
  /** All libraries show count but hidden cards */
  // player.zones.library = [{ instanceId: "hidden-0", card: { name: "Hidden card" } }, ...]
  
  /** Legal actions only for the viewer */
  legalActions: LegalAction[];  // filtered to viewerPlayerId only
}
```

## Next Steps

1. Add `viewerPlayerId` field to snapshot contract
2. Implement per-connection WebSocket filtering in the gateway
3. Add integration tests with 2+ human players
4. Test with XMage's reveal/look-at mechanics
