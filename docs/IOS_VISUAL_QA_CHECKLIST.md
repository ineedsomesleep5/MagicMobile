# iOS Visual QA Checklist

Use this checklist for the native iOS Commander gameplay surface. It separates simulator layout evidence from physical iPhone play QA so a clean screenshot pass does not get mistaken for product release readiness.

## Current Evidence - June 24, 2026

- Target device for the milestone: iPhone 16 Pro Max landscape.
- Simulator actually used: iPhone 17 Pro Max Simulator on iOS 26.5 because iPhone 16 Pro Max Simulator was unavailable.
- Local simulator API override: launch the app with `MAGICMOBILE_SERVER_URL=http://127.0.0.1:<web-port>` when using a local Next web API port such as `3001`.
- Orientation note: the app declares landscape-only orientations. This CoreSimulator runtime did not expose `simctl ui ... orientation`, rejected `screenConfig` landscape geometry, and saved a portrait framebuffer containing the landscape UI rotated sideways. Keep both the raw capture and the readable rotated copy.
- Simulator result: layout/build evidence only. It does not prove real iPhone install, local-network setup, touch ergonomics, WebSocket behavior, or sustained gameplay.
- Generic iPhoneOS build result: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project apps/ios/MagicMobileiOS.xcodeproj -scheme MagicMobile -configuration Debug -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build` passed. This proves arm64 compile only.
- Real iPhone result: pending. The June 24 device check showed Caleb's iPhone 16 Pro Max as `unavailable` and a separate physical iPhone (`Ruthie's iPhone 16`, reported as iPhone 16 Pro Max-class hardware) as `connected`; the app was not installed or launched on that device without explicit permission. Product release is blocked until physical iPhone QA passes against the same fixture-ready gateway.

## Simulator Screenshots To Keep

Keep captures under `build_output/ios-screenshots/` and treat them as local artifacts, not release proof.

- `iphone-17-pro-max-setup-local-api.jpg`: setup state with local web API URL and ready bridge health.
- `iphone-17-pro-max-setup-local-api-landscape-readable.jpg`: readable rotated setup evidence.
- `iphone-17-pro-max-fixture-board-rustic.jpg`: raw fixture board capture from the local XMage fixture.
- `iphone-17-pro-max-fixture-board-rustic-landscape-readable.jpg`: readable rotated fixture board proof currently cited by readiness docs.
- `iphone-17-pro-max-fixture-board-zone-buttons-landscape-readable.jpg`: refreshed fixture board proof with Stack, Command, Grave, and Exile exposed as tappable zone buttons.
- `iphone-17-pro-max-fixture-board-final-metrics-landscape-readable.jpg`: final board proof after layout metric minimum-size guards were added and satisfied.
- `iphone-17-pro-max-zone-sheet-rustic-landscape-readable.jpg`: command-zone sheet proof.
- `build_output/screenshots/ios-layout-after.png`: current readable board checkpoint requested by the layout milestone.
- `build_output/screenshots/ios-prompt-active.png`: current active-prompt checkpoint; the current fixture prompt is the priority/pass prompt.
- `build_output/screenshots/ios-zone-sheet.png`: current zone-sheet checkpoint.
- Historical troubleshooting captures may remain in the same directory, but do not use older timeout/deck-validation captures as current layout proof.

Next simulator run should recapture the same states after any layout edit and include the visible `source`, `bridgeRevision`, `xmageCycle`, priority player, pending state, phase/step, stack count, command zone access, graveyard access, exile access, and missing-art placeholders where present.

## Simulator Pass Criteria

- The app builds, launches, and renders the gameplay surface with the landscape-oriented board layout on the selected Pro Max simulator.
- The setup screen scrolls; the local API URL, deck/setup controls, health status, and fixture start control are reachable without rotation or hidden debug gestures.
- The fixture board loads from `source: xmage-java-bridge`; no simulator/mock gameplay source is shown on the production play path.
- `bridgeRevision` and `xmageCycle` are visible and numeric on the play screen or in reachable diagnostics.
- Top HUD, opponent board, player board, player lands, hand, right prompt/action dock, phase/status rail, stack surface, command zone, graveyard, exile, and pending/waiting UI do not overlap in a way that hides controls.
- Primary prompt/action controls remain tappable before secondary zone surfaces when a human response is required.
- Stack, command, graveyard, exile, commander tax, commander damage, and missing card art are reachable without debug JSON.
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
- Dense combat states still need physical-device checks for attacker/blocker assignment and damage allocation.
- Commander tax and commander damage decode, but their visual prominence still needs real iPhone confirmation.
- Prompt variety controls are deterministic-fixture proven, but amount, multi-amount, pile, ordering, and damage-assignment controls still need touch QA on hardware.
- Missing art placeholders are visually stable in simulator evidence, but slow or failed image loading needs a real phone network check.
- Hand-selected and missing-art screenshots were not recaptured in the latest automated simulator pass because the current runtime accessibility snapshot did not expose individual hand cards as reusable tap targets. This needs either manual Simulator interaction or a future card-accessibility polish pass.
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
- Fixture-ready health visible from the app.
- A Commander game or debug fixture started through the local web API.
- Gauntlet-style actions played through the native UI: keep hand, play land, make mana, cast/pay, pass priority, respond to prompts, open stack, open command zone, inspect graveyard/exile, observe commander tax and commander damage, handle missing art, and wait through at least one AI action.
- Screenshots captured on the real iPhone for setup health, fixture/game board, active prompt, stack/zone sheet, missing-art placeholder, AI waiting state, and any failure state.
- Evidence note with game id if visible, `source`, `bridgeRevision`, `xmageCycle`, WebSocket state, pending status, and the local gateway/web terminal logs for failures.

Product release remains blocked until this physical iPhone pass is complete.
