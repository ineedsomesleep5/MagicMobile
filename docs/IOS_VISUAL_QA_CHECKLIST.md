# iOS Visual QA Checklist

Use this checklist for the native iOS Commander gameplay surface. It separates simulator layout evidence from physical iPhone play QA so a clean screenshot pass does not get mistaken for product release readiness.

## Current Evidence - June 24, 2026, after `fed99977` plus local pass-7 polish

- Target device for the milestone: iPhone 16 Pro Max landscape.
- Simulator actually used: iPhone 17 Pro Max Simulator on iOS 26.5 because iPhone 16 Pro Max Simulator was unavailable.
- Reviewed commit: `fed99977 Refine iOS arena layout QA and prompt polish`, with the follow-up local pass that adds explicit native WebSocket gateway configuration and a simpler readable phase strip.
- Arena-style visual reference applied in the current native pass: the play surface now favors a broad tabletop center, centered player/opponent life anchors, a slimmer translucent right action dock, and edge/zone affordances instead of a dashboard-heavy board. This is inspired by observed MTG Arena layout patterns and official Arena mobile notes, but it does not copy Arena art, logos, or branded assets.
- Local simulator API override: launch the app with `MAGICMOBILE_SERVER_URL=http://127.0.0.1:<web-port>` when using a local Next web API port such as `3001`.
- Local simulator/gateway WebSocket override: launch with `MAGICMOBILE_XMAGE_WS_URL=http://127.0.0.1:17171` when HTTP uses the local Next web API. This keeps HTTP routed through the web API while native live updates connect to the real XMage gateway `/ws/games/:gameId` endpoint.
- Debug simulator fixture shortcut: launch a Debug build with `MAGICMOBILE_AUTO_START_FIXTURE=true` to skip the setup form and request the dev-only real XMage commander fixture immediately. This is for screenshot/layout QA only and does not change release behavior.
- Orientation note: older captures in this pass include portrait framebuffers containing the landscape UI rotated sideways. The latest `ios-17-pro-max-*` captures are readable 800x368 landscape files.
- Simulator result: layout/build evidence only. It does not prove real iPhone install, local-network setup, touch ergonomics, WebSocket behavior, or sustained gameplay. Do not describe these screenshots as real iPhone manual QA or gameplay proof.
- Generic iPhoneOS build result: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project apps/ios/MagicMobileiOS.xcodeproj -scheme MagicMobile -configuration Debug -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build` passed. This proves arm64 compile only.
- Real iPhone result: pending. The June 24 device check showed Caleb's iPhone 16 Pro Max as `unavailable` and a separate physical iPhone (`Ruthie's iPhone 16`, reported as iPhone 16 Pro Max-class hardware) as `connected`; the app was not installed or launched on that device without explicit permission. Product release is blocked until physical iPhone QA passes against the same fixture-ready gateway.

## Current Screenshot Inventory

Keep current captures under `build_output/screenshots/` and treat them as local simulator artifacts, not release proof.

- `build_output/screenshots/ios-17-pro-max-arena-pass-2.jpg`: after-`03c51aa7` iPhone 17 Pro Max simulator visual pass. Shows the arena-style battlefield, centered life/hand anchors, readable hand fan, opponent/player rows, visible mana rail, and right prompt dock with Done/Pass/Skip turn controls.
- `build_output/screenshots/ios-17-pro-max-arena-pass-3.jpg`: latest parent-orchestrated simulator visual pass after the dock/metrics/prompt polish. Shows the right prompt dock anchored to the trailing safe area, larger hand cards, compact phase/log/settings strip, and real fixture-backed board data.
- `build_output/screenshots/ios-17-pro-max-arena-pass-7-readable.jpg`: latest readable iPhone 17 Pro Max simulator visual pass after explicit gateway WebSocket configuration and compact phase strip polish. Shows `WS Live`, `source: xmage-java-bridge`, numeric `bridgeRevision`/`xmageCycle`, board-first layout, centered life anchors, hand fan, mana pool, and visible prompt/action dock.
- `build_output/screenshots/ios-17-pro-max-arena-pass-1-board-upright.jpg`: prior readable arena-board proof from the same polish sequence, useful for comparing the right dock and board density before pass 2.
- `build_output/screenshots/ios-17-pro-max-arena-pass-1-board.jpg`: prior pass-1 board proof.
- `build_output/screenshots/ios-17-pro-max-arena-pass-1.jpg`: prior pass-1 full arena proof.
- `build_output/screenshots/ios-17-pro-max-fixture-loading.jpg`: fixture-loading state proof.
- `build_output/screenshots/ios-17-pro-max-landscape-baseline.jpg`: landscape baseline before the final arena hierarchy pass.
- `build_output/screenshots/ios-17-pro-max-landscape-before-next-polish.jpg`: pre-polish landscape reference.
- `build_output/screenshots/ios-arena-inspired-launch-landscape.jpg`: arena-inspired launch/layout proof in readable landscape.
- `build_output/screenshots/ios-arena-inspired-launch.jpg`: raw portrait-oriented companion capture for the arena-inspired launch state.
- `build_output/screenshots/ios-right-dock-backdrop-landscape.jpg`: right-dock backdrop proof in readable landscape.
- `build_output/screenshots/ios-right-dock-backdrop.jpg`: raw portrait-oriented companion capture for the right-dock backdrop state.
- `build_output/screenshots/ios-layout-after.png` and `build_output/screenshots/ios-layout-after.jpg`: earlier readable board checkpoints requested by the layout milestone.
- `build_output/screenshots/ios-prompt-active.png` and `build_output/screenshots/ios-prompt-active.jpg`: active priority/pass prompt checkpoints.
- `build_output/screenshots/ios-hand-selected.png`: hand-selection checkpoint using the `card-hand-sol-ring-<id>` accessibility target.
- `build_output/screenshots/ios-action-dock.png`: right-dock checkpoint showing prompt/pass controls before secondary surfaces.
- `build_output/screenshots/ios-missing-art.png`: missing-art checkpoint using a real XMage fixture board and the simulator-only forced-placeholder image toggle.
- `build_output/screenshots/ios-zone-sheet.png`: command-zone sheet checkpoint.
- `build_output/screenshots/ios-setup-local-api.png` and `build_output/screenshots/ios-setup-local-api.jpg`: setup/local API evidence.
- Historical troubleshooting captures may remain elsewhere, but do not use older timeout/deck-validation captures as current layout proof.

Next simulator run should recapture the same states after any layout edit and include the visible `source`, `bridgeRevision`, `xmageCycle`, priority player, pending state, phase/step, stack count, command zone access, graveyard access, exile access, and missing-art placeholders where present. If the image is captured from Simulator, label it as simulator evidence even when it uses a real XMage fixture snapshot.

## Simulator Pass Criteria

- The app builds, launches, and renders the gameplay surface with the landscape-oriented board layout on the selected Pro Max simulator.
- The setup screen scrolls; the local API URL, deck/setup controls, health status, and fixture start control are reachable without rotation or hidden debug gestures.
- The fixture board loads from `source: xmage-java-bridge`; no simulator/mock gameplay source is shown on the production play path.
- `bridgeRevision` and `xmageCycle` are visible and numeric on the play screen or in reachable diagnostics.
- Top HUD, opponent board, player board, player lands, hand, right prompt/action dock, phase/status rail, stack surface, command zone, graveyard, exile, and pending/waiting UI do not overlap in a way that hides controls.
- Primary prompt/action controls remain tappable before secondary zone surfaces when a human response is required.
- Stack, command, graveyard, exile, library count, revealed/looked-at zones when XMage exposes them, commander tax, commander damage, and missing card art are reachable without debug JSON.
- The right dock shows the current prompt, selected-card action, and pass/action controls before secondary zone surfaces.
- Missing art renders a stable placeholder with card text and does not collapse rows or push controls off-screen.
- AI waiting and XMage pending states appear as status, not as a frozen board.
- Long prompt text truncates or scrolls inside its owned region instead of covering battlefield cards.

## Simulator Fail Criteria

- Any simulator-only route, mock source, or `/dev/play-simulator` state is used as proof for the production `/play` path.
- Startup or fixture creation hangs without a visible status or retry/debug clue.
- Prompt, stack, pending toast, or diagnostics overlays cover hand actions, mana controls, or battlefield card midpoints.
- Primary actions are hidden below zone previews while XMage waits on the human player.
- Unknown prompts auto-select yes, colorless mana, zero, pile 1, first choice, or command-zone replacement.
- Card movement appears locally without a later authoritative XMage snapshot.
- Missing art leaves blank collapsed cards or shifts layout enough to hide actions.

## Known Visual Issues To Watch

- iPhone 16 Pro Max simulator was not installed for the current pass, so actual 16 Pro Max simulator safe-area behavior remains unverified.
- Real iPhone safe-area, Dynamic Island, home indicator, touch target feel, and local-network latency remain unverified.
- The earlier `ios-17-pro-max-arena-pass-3.jpg` capture showed connection/reconnection status text because iOS was deriving `/ws/games/:gameId` from the local Next API port. Pass 7 uses `MAGICMOBILE_XMAGE_WS_URL=http://127.0.0.1:17171` and shows `WS Live`; keep this override in simulator/phone fixture QA unless the web API grows a real WebSocket proxy.
- The latest pass-2 screenshot improves the arena hierarchy, but the right dock, status pill, phase/prompt controls, and phone cutout still need real-device checks for tap comfort and safe-area clearance.
- Dense combat states still need physical-device checks for attacker/blocker assignment and damage allocation.
- Commander tax and commander damage decode, but their visual prominence still needs real iPhone confirmation.
- Prompt variety controls are deterministic-fixture proven, but amount, multi-amount, pile, ordering, and damage-assignment controls still need touch QA on hardware.
- The right dock now orders prompt/action controls before zone chips and exposes count-only Library plus Revealed/Looked sheets when real XMage data is present; keep recapturing active-prompt screenshots after dock edits to verify the dock still reads cleanly.
- The right prompt/action dock now has its own rustic backdrop and named `rightActionPanelRect`; the bottom strip is reserved for compact pending/waiting state instead of covering the center battlefield.
- The latest live fixture screenshots verify the new arena-inspired tabletop background, centered life medallions, and narrower right dock on iPhone 17 Pro Max Simulator, but they still need real iPhone confirmation against an active local web API.
- The latest action-dock simulator recapture shows the prompt/pass controls first and keeps the battlefield, hand, mana HUD, and phase rail readable on iPhone 17 Pro Max Simulator.
- Missing art placeholders are visually stable in simulator evidence through the explicit Debug-only `MAGICMOBILE_FORCE_CARD_PLACEHOLDERS=true` visual-QA launch, but slow or failed image loading still needs a real phone network check.
- Hand, battlefield, stack, prompt, zone-sheet, and inspector card tiles now expose zone-scoped accessibility labels and stable identifiers such as `card-hand-sol-ring-<id>`. Automated simulator QA used that target to recapture a hand-selected Sol Ring screenshot, then relaunched with forced placeholders to recapture the missing-art board state without changing XMage gameplay data.
- Layout metric tests now cover Pro Max landscape and compact landscape named-region containment, non-overlap, and minimum readable card/action sizes.

## Physical iPhone QA Separation

Run physical QA only after the backend route gate and local web API are ready:

```sh
ENABLE_XMAGE_FIXTURES=true NODE_ENV=test docker compose up -d --build xmage-bridge xmage-gateway
curl -fsS http://localhost:17171/health
ENGINE_MODE=xmage XMAGE_GATEWAY_URL=http://localhost:17171 ENABLE_XMAGE_FIXTURES=true NODE_ENV=development pnpm --filter @magicmobile/web exec next dev --hostname 0.0.0.0
```

Manual phone pass requires:

- iPhone and Mac on the same Wi-Fi.
- App server URL set to `http://<Mac-LAN-IP>:<web-port>`, not `localhost` and not the raw `:17171` gateway.
- Native WebSocket URL set to `http://<Mac-LAN-IP>:17171` through `MAGICMOBILE_XMAGE_WS_URL` for Debug launches until a phone-facing settings field or web WebSocket proxy exists.
- Fixture-ready health visible from the app.
- A Commander game or debug fixture started through the local web API.
- Gauntlet-style actions played through the native UI: keep hand, play land, make mana, cast/pay, pass priority, respond to prompts, open stack, open command zone, inspect graveyard/exile, observe commander tax and commander damage, handle missing art, and wait through at least one AI action.
- Screenshots captured on the real iPhone for setup health, fixture/game board, active prompt, stack/zone sheet, missing-art placeholder, AI waiting state, and any failure state.
- Evidence note with game id if visible, `source`, `bridgeRevision`, `xmageCycle`, WebSocket state, pending status, and the local gateway/web terminal logs for failures.

Product release remains blocked until this physical iPhone pass is complete. Simulator screenshots, including `build_output/screenshots/ios-17-pro-max-arena-pass-3.jpg`, are useful visual layout evidence but are not real iPhone manual QA and are not gameplay acceptance proof.
## Magic Path Handoff

For Magic Path visual editing, use the current file at https://www.magicpath.ai/files/420728834988597248 and the import package in [design/magic-path/README.md](../design/magic-path/README.md). The package includes named `MM.*` layers, a 956 x 440 point iPhone Pro Max landscape SVG blueprint, design tokens, a layer-to-SwiftUI binding map, and decorative placeholder assets.

Current handoff frames: Normal Battlefield, Selected Card, Stack Response Prompt, Dragging Card / Drop Zones Visible, Search Library Prompt, Mana Payment Prompt, Commander Replacement Prompt, Damage Assignment Prompt, AI Thinking / Waiting, and Bridge Unavailable / Reconnect.

The DEBUG-only SwiftUI design preview is launched with `MAGICMOBILE_DESIGN_PREVIEW=<state>`. It is for layout review only and is not gameplay proof.
