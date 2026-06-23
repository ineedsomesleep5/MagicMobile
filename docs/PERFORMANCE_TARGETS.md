# MagicMobile Performance Targets

MagicMobile should feel like a smooth mobile Commander client powered by XMage, not a slow remote-control wrapper around a Java desktop game.

## Current Scope

- Format: Commander only.
- Gameplay target: 1v1 Commander vs XMage AI first.
- Later targets: human-vs-human Commander, then 3-4 player digital Commander pods.
- Out of current scope: webcam play, hybrid paper/digital play, draft, sealed, tournaments, and non-Commander formats.

## Responsiveness Targets

- Local touch feedback: immediate, ideally under 100 ms.
- Simple command accepted response: under 250-500 ms when the gateway can acknowledge without waiting on a full XMage transition.
- Authoritative XMage update: usually under 1 second for simple human actions when XMage is not waiting on AI or a complex prompt.
- Board update after a normal action: under 3 seconds p95.
- AI thinking: may take longer, but the UI must show a specific AI thinking or waiting state.
- Game startup: may be slower, but the user should enter the battlefield/progress state immediately and see clear status.

These are alpha targets. Live smoke tests should report actual timings so we can separate UI latency from Next.js, gateway, Java bridge, XMage, AI, WebSocket, and image-loading delays. Generated smoke reports belong under `build_output/smoke/*.json` and should be kept as local/CI artifacts, not committed proof.

## Client Behavior

- The client may show optimistic feedback for safe UI-level interactions: selecting a card, focusing a permanent, choosing a target, choosing yes/no, selecting a prompt option, and passing priority.
- Optimistic feedback is temporary. XMage remains the source of truth for hand, battlefield, stack, tapping, costs, combat, commander replacement, and game outcome.
- If XMage rejects an action, or if the prompt is stale, the client should show a clear message and refresh from the latest snapshot.
- Repeated taps for the same in-flight command should be ignored or disabled until a new snapshot arrives.
- Missing card art must not block gameplay. Show a placeholder immediately and load cached/local art when available.

## Server Behavior

- Commands should return quickly with an authoritative snapshot when available.
- If the bridge accepted the command but XMage has not produced a new snapshot yet, return a snapshot with `pendingStatus: "waiting_for_xmage"` instead of blocking the phone for a long time.
- Use `pendingStatus: "accepted"`, `"waiting_for_xmage"`, or `"stalled"` where the bridge/gateway can distinguish those states.
- WebSocket snapshots are the primary live update path. Polling is a backup for recovery and stale connections.
- Every snapshot from XMage must carry `bridgeRevision` and, when available, `xmageCycle`. Clients and gateways must ignore stale revisions.

## Timing Logs

Add or preserve timing logs around the real XMage path:

- mobile/web command submitted
- API route started
- gateway forwarded command
- Java bridge received command
- bridge sent XMage action
- XMage callback received
- snapshot translated
- snapshot broadcast over WebSocket
- client applied snapshot

Each command should carry a request or correlation id where practical. Logs should make it possible to tell whether slowness is in UI rendering, Next.js, gateway routing, Java bridge waiting, XMage engine processing, AI thinking, WebSocket delivery, or card image loading.

## Snapshot Path

Full snapshots are acceptable for alpha. Start measuring:

- snapshot JSON byte size
- command response time
- bridge wait time
- XMage callback time
- time from command submission to client-applied snapshot

Future optimization path:

1. Initial full snapshot when joining or reconnecting.
2. Ordered snapshot revisions for alpha gameplay.
3. Later smaller delta/event updates if measured snapshot size or WebSocket latency becomes a real bottleneck.

Do not implement a complicated delta system until measurement shows it is needed.
