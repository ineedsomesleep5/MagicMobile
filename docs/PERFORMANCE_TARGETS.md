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

## On-device battery, memory and size (October 2026)

The phone apps run the engine on the device, so these rules replace the gateway ones above for iOS and Android.
They were measured on the iPhone 17 Pro Max simulator and the API 35 emulator, not on a phone.

- **Engine polls.** A local game polls every 0.3 s while the engine works, 0.6 s after three unchanged
  answers, and every 2 s once the engine has waited on the player for eight (`OnDeviceLocalPollSchedule` on
  both platforms). A tap returns to 0.3 s at once. Online tables keep their own schedule.
- **No idle redraws.** A poll whose answer is unchanged publishes nothing: the iOS session sends
  `objectWillChange` only when the snapshot, status or error changed.
- **Ambient motion.** Slow glows step on the wall clock instead of at the display's rate (iOS `BoardBreath`,
  30 a second; Android `rememberBoardBreath`, 20 a second), and brief glints draw only while they show
  (`BurstTimelineSchedule`). A custom
  `TimelineSchedule` must return a fixed grid of dates: the latest one at or before the date asked for, then
  strictly later ones. Returning "now" first makes the view update forever.
- **Shared data.** The card catalogue and deck resolver decode once, off the main thread, and are shared
  (`BundledResourceCache`); both are dropped when the app goes to the background. Decoded card art is kept in a
  64 MB `NSCache` and decoded off the main thread.
- **Quiet network.** Friend-challenge polling stops with no friends and slows to 20 s when none is online.
- **Size.** iOS ships the catalogue LZFSE-compressed (12.9 MB to 2.2 MB, written by a build phase). Android
  release code goes through R8 without renaming (dex 49.2 MB to 12.9 MB; the APK 156.9 MB to 147.3 MB).
  `proguard-rules.pro` keeps the app's own packages whole and the libraries the instrumentation runner shares
  with the app; a new library the tests call needs the same keep. Debug builds are not shrunk.
- **Engine.** Left as it is. It already uses the targeted reflection profile and went from 795 MB to 381 MB in
  September; what remains is the compiled rules for 31,881 cards (201 MB) and the image heap (167 MB). Any
  further cut is a compiler experiment that needs an ARM64 build per platform and a phone to judge AI speed,
  and ships as its own release (see the release sequencing rule).
