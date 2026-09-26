# Handoff: web version, playtest fixes, cleanup

Started 2026-09-25 from a read-only plan written in a Cowork session. The fuller plan is at
https://claude.ai/code/artifact/1ad663a0-fdcf-45c7-af93-edca306a1193. This file is the shared
status: whoever works on these steps updates **Status** and **Log** before stopping, like
`docs/BOARD_FX_ROADMAP.md`.

1. Read `AGENTS.md` first; this file does not override it.
2. Each step is its own branch and PR (`codex/<topic>`).
3. Ask Caleb before anything AGENTS.md reserves for him: uploads, TestFlight, deleting
   branches, production or provider changes, spending money.

## Decisions

Settled with Caleb on 2026-09-25:

- **Spectator seat:** when you're out, the next living player after you in turn order takes the
  bottom seat.
- **Branch cleanup:** approved (done, see Log).
- **Legacy web stack:** archive under a tag and remove from main.
- **Relay fixes:** deploy once tests pass, if backward compatible with shipped clients.

Still open (ask before the step that needs them):

- By "syncing", does Caleb mean cross-play, decks following you across devices, or both? The plan
  assumes both, cross-play first.
- Who gets the web version: a private link for friends, or anyone? See Card IP below.
- Is a small monthly hosting cost OK if the Cloudflare or Vercel free plans run out?
- Deck sync sign-in: Apple, Google, email link, or all?

## Step 0: merge and tidy

1. Caleb merges #37 (flaky `NativeAssetDownloadsTests`, AGENTS.md "Android resumed"), then #38
   (Android parity, build 8, relay).
2. Delete the branches already in main, and tag the stale unmerged ones as `archive/<name>`
   before deleting them.
3. CI: drop push triggers for branches that no longer exist. Run
   `node --test services/table-relay/test/relay.test.mjs` on PRs that touch the relay.
4. Docs:
   - Move the release records into `release/`.
   - Move the web-era docs (`XMAGE_*`, `REMOTE_DOCKER_WORKFLOW`, …) into `docs/archive/`.
   - Fix the links.
5. Remove the legacy web stack (`apps/web`, `apps/mobile`, `apps/xmage-gateway`,
   `apps/engine-worker`, old TS `packages/*`). It is archived at the tag `archive/legacy-web`.

## PR 1: web engine spike (`codex/web-engine-spike`, draft)

Goal: prove or rule out the real XMage engine in a browser via CheerpJ, with numbers. It ships
nothing to players.

- The engine sits behind `EngineService.request(String json) -> String`
  (`packages/ondevice-engine/engine/core`).
- The web entry point and build script live in `packages/web-engine/`, not in
  `packages/ondevice-engine/`. That path is the guarded native input, so editing it forces a
  multi-hour native rebuild.
- The bench app is `apps/web-play/` (Vite + TypeScript, CheerpJ in a Web Worker, a Playwright
  metrics run).
- Results go in `docs/WEB_ENGINE_SPIKE.md`.

Pass targets:
- Engine ready in ≤ 45 s on the first visit, ≤ 10 s cached.
- 4-player game start in ≤ 10 s.
- Board update in ≤ 1 s typical, ≤ 3 s p95.
- AI turn median ≤ 5 s, p95 ≤ 15 s.
- 10/10 seeded games finish.
- No main-thread stall over 100 ms, and the tab stays under 2 GB.

If it misses:
- Slow but correct: web solo uses the hosted engine (`apps/multiplayer-server`).
- Broken: try GraalVM Web Image, or hosted play.

## PR 2: playtest fixes, iOS and Android together

These come from Caleb's 4-player game (2 AI and him). The same change lands on both platforms.
They are split into two PRs:

**`codex/playtest-focus`:**
- **Follow the turn:** at turn start, the top of the board shows the active player. A tapped
  opponent sticks until the next turn. The switch never happens mid-prompt, and a "Follow turns"
  setting (default on) controls it.
- **Spectator seat:** when you're out, the next living player after you takes the bottom seat. It
  is presentation-only: hidden information, permissions and "You" labels are unchanged.
- **Top bar:** no more "Waiting on Waiting" before the first turn.
- **Tests:** shared `focus-cases.json` and `spectator-cases.json`, read by both platforms.

**`codex/playtest-cards`:**
- **Token copies:** render as a full card frame with the source art, the token's own name, type
  and P/T, and a "Token copy" tag.
- **Inspector:** rules text fits without scrolling, the image shrinks instead, and the backdrop
  is solid.
- **Ability banner:** placed below the ability card and labelled "<source> · ability".

Ships in iOS TestFlight build 18 (with the relay client from #38) and Android build 9, only when
Caleb authorizes.

## PR 2b: multiplayer hardening

1. **Relay backlog (`codex/relay-backlog`):** store one storage key per queued packet instead of
   one oversized key; drop answers older than the 15 s guest timeout; send a backlog notice instead
   of losing packets; add relay CI.
2. **Guest timeout:** a lost host answer times out after 15 s and stops polling ("Updates
   interrupted"). Retry a few times with "Waiting for <host>…". Both platforms.
3. **Polling keeps relay tables awake:** the host pushes a small "new revision" notice, and guests
   poll on the notice plus a slow heartbeat.
4. **Crash and hang reports:** MetricKit (iOS) and `ApplicationExitInfo` (Android) in the
   diagnostics export.

## PR 3–6: web client (only if PR 1 passes)

- Shared logic: convert `apps/android/core` to Kotlin Multiplatform (JVM + JS) as its own step.
  Android tests and parity goldens are the gate.
- PR 3, solo web play: React UI, PixiJS battlefield, desktop layout, Web Audio.
- PR 4, web Deck Studio: IndexedDB, engine `validateDeck`.
- PR 5, cross-play via the relay: web can host; iPhones need build 18.
- PR 6, accounts and deck sync: Supabase `profiles`, `decks` and `deck_entries` (RLS per owner),
  migrations in `supabase/`.

## Engine and catalogue updates without app builds

- iPhone engine code cannot change without a build (native AOT, App Review 2.5.2). Android uses
  the same `libmmengine.so`. The web updates on deploy.
- Data can update everywhere. Split `ondevice-catalogue.json` into:
  - the engine-bound card list
  - a signed downloadable data pack (metadata, role tags, name aliases, precons)
- Let the host decide: relax the exact build handshake to the same protocol version plus feature
  negotiation.
- Ship engine releases from one commit on the same day for TestFlight, the APK and the web bundle.

## Other findings (lower priority)

- Combat clarity: show gained keywords, play first-strike damage as its own beat, and add a
  one-line log reason.
- Save and resume research.
- Split `ContentView.swift` along Android's `board/` file names, after PR 2 merges.
- Relay: let the host see and remove joiners, rate-limit `POST /v1/tables`, and move the host key
  out of the URL.
- Fade the edges of clipped rows and show a "+N" marker.
- Card IP: Wizards' Fan Content Policy does not cover games. Keep it free and on private links,
  add a notice in every app, and be ready to take it down. This is not legal advice.
- Skip board FX phase 5 (RealityKit 3D) for now.

## Status

| Step | State | Branch / PR | Notes |
|---|---|---|---|
| 0 Merge #37, #38 | Done | #37, #38 | Merged 2026-09-26 |
| 0 Branch cleanup | Done | | 14 remote branches deleted; 5 stale ones kept as `archive/*` tags |
| 0 Legacy removal, CI triggers, docs | Done | #40 via #51 | Tag `archive/legacy-web`. The old Vercel project `magicmobile` is disconnected from Git; magicmobile.vercel.app stays up |
| 1 Web engine spike | Done: no-go | #44 (draft) | CheerpJ can't run the engine on Java 17 or 11. Next route (hosted solo or a GraalVM Web Image spike) is Caleb's decision |
| 2 Playtest focus | Done | #41 via #51 | Follow Turns, spectator seat, "Starting the game" |
| 2 Playtest cards | Done | #43 via #51 | Token-copy frames, fitted inspector, ability banner |
| 2b.1 Relay backlog + CI | Done, deployed | #39 via #51 | Relay version `905960a4-16ae-4f18-b978-e6e0567f9f6f`; 6/6 tests pass against the live Worker |
| 2b.2–4 Guest retry, notices, crash reports | Done | #42 via #51 | Live iPhone–Android check pending on real phones |
| Polish: fan-content notice, row "+N" | Done | #45 via #51 | |
| Combat clarity | Done | #46 via #51 | Keyword badges, first-strike beat, log reasons |
| Save/resume research | Done | #47 via #51 | Plan in `docs/SAVE_RESUME_SPIKE.md`; Phase 1 and later need Caleb |
| iOS 27 fixes | Done | #49 via #51, #53 | Card-choice accessibility; board and setup UI tests updated for Xcode 27 |
| Build 7 Android UI removal | Done | #50 via #51 | |
| Integration | Done | #51 | Merged at `1a62733` |
| Relay extras: joiner removal, create limit, key out of URL | Ready for next build | #48 | Deploy the relay first (new apps need it), then ship the apps |
| Release: iOS build 18 | Done | `codex/ios-build-18` | TestFlight `VALID`, Beta App Review `APPROVED`, Internal and External (`release/RELEASE_0.1.1_BUILD18.md`) |
| Release: Android build 9 | Done | `android-v0.1.1-build.9` | Published; download site updated |
| 3–6 Web client | Blocked on Caleb | | Needs a route (hosted solo or a GraalVM spike) plus the open questions: audience, hosting cost, sign-in, meaning of "syncing" |

## Log

- 2026-09-25 (Claude, Cowork): Plan written from a read-only review.
- 2026-09-25 (Claude Code): Started. Xcode 27.0 (27A266a) is installed on macOS 27. Caleb
  settled the spectator seat, branch cleanup, legacy removal and relay deploys.
  - Deleted 14 remote branches after tagging the 5 unmerged stale ones as `archive/*`. Nothing
    else in `codex/android-native-xmage` was unmerged: its PR #11 was squash-merged.
  - Kept the local worktrees `MagicMobile-android` and `MagicMobile-ondevice`, because both
    have untracked files. The web spike reuses the ondevice engine build.
  - Tagged `archive/legacy-web`.
  - Five delegates are running, on the branches listed in Status.
- 2026-09-25 (Claude Code): Relay backlog fixed in #39.
  - Held messages are stored one entry each, in pieces of at most 524,288 characters. This
    fixes the silent loss past Cloudflare's 2 MB SQLite key+value limit.
  - Overflow or a refused write sends `peer_backlog`. Host `reply` packets held over 15 s are
    dropped. The wire protocol is unchanged.
  - New `table-relay.yml` CI runs the tests with the 2 MB limit enforced locally.
  - The deploy was refused by Claude Code's auto-mode safety check, so it waits for Caleb.
- 2026-09-25 (Claude Code): Repo tidy in #40 (215 files, -38.5k lines).
  - Removed the legacy apps and TS packages (tag `archive/legacy-web`), `docker-compose.yml`
    and the pnpm workspace. Also removed two scripts for the offline Hostinger stack.
  - `ci.yml` now builds the download site. The TestFlight repository preflight runs the release
    tooling checks, and its dispatched run passed.
  - Dead branch triggers are gone.
  - Release records moved to `release/`, and web-era docs to `docs/archive/`, with links fixed.
  - Vercel `magicmobile` (magicmobile.vercel.app) will fail once `apps/web` is gone, and no kept
    code uses that URL.
- 2026-09-25 (Claude Code): Four delegates stopped mid-work at the account usage limit, with no
  failures. After the reset, continuation delegates resumed playtest focus, playtest cards and
  multiplayer hardening in their existing worktrees. The web spike resumes next.
- 2026-09-25 (Claude Code): Playtest focus done in #41 (`codex/playtest-focus`).
  - The board follows the active player at each turn start. A tapped opponent sticks until the
    next turn, and a pending prompt defers the switch. The Follow Turns setting
    (`magicmobile.followTurns`, default on) controls it.
  - A spectator sees the next living player after them in the bottom seat, with the hand shown
    as a count. This is presentation only.
  - The pre-game top bar reads "Starting the game".
  - Shared cases: `parity/focus-cases.json` and `parity/spectator-cases.json`. Preview:
    `four-player-spectating`.
  - This Mac lacked Xcode 27's Metal Toolchain, so simulator builds skipped
    `BoardFXShaders.metal`. It is being installed (`xcodebuild -downloadComponent MetalToolchain`).
- 2026-09-26 (Claude Code): Playtest cards done in #43. Copy tokens draw as their own card frame
  with a "Token copy" tag. The inspector gives rules full height without scrolling, over a solid
  backdrop. The ability banner sits below the card. New previews: `token-copy-inspection` and
  `ability-showcase`.
  - Integration branch `codex/build18-integration` created.
  - The Metal Toolchain 27A266a is installed.
  - The emulator's /data was full (INSTALL_FAILED_INSUFFICIENT_STORAGE); a cleanup is queued.
- 2026-09-26 (Claude Code): Web spike #44 is a no-go on CheerpJ 4.3's Java 17 runtime.
  - The real engine starts in the browser (16.7–26.0 s first visit, 13–17 s cached against a
    10 s target) and the tab stays at 1.1 GB, but no game reached its first prompt.
  - Cause: CheerpJ lacks the `jdk.internal.misc.Unsafe` routines behind reflective reads of final
    fields. XMage's `Watcher.copy` (shadowed for the web) and Gson's snapshot serialization both
    need them, and JavaScript stand-ins could not call back into Java.
  - Running now: a follow-up on CheerpJ's Java 11 runtime, with the six Java 16+ lines patched in
    build-folder copies only.
  - If that also fails, the options are hosted web solo (`apps/multiplayer-server`, a hosting-cost
    decision for Caleb) or a GraalVM Web Image spike.
  - #44 edits `pnpm-workspace.yaml`, which #40 deletes. Drop that edit if #40 merges first.
- 2026-09-26 (Claude Code): Multiplayer hardening done in #42.
  - A guest retries a lost poll or `hello` 3 times (1/2/4 s) and shows "Waiting for <host>…". A
    relay `gone` still ends the table at once.
  - Host revision notices (`{"type":"revision"}`) drive guest polls: promptly for 10 s after an
    action, otherwise on a 15 s heartbeat.
  - Crash and hang summaries from MetricKit and ApplicationExitInfo are kept locally in the
    diagnostics export. This also added Android's `OnDeviceDiagnostics.kt`.
  - Finding: relay tables check only the relay identity, not the app build, so mixed builds
    (Android build 8 with a newer iPhone) can share a table. The notices are negotiated, so older
    clients keep polling. Decision: keep it negotiated rather than block mixed builds, so build 8
    Android players can play with build 18 iPhones.
- 2026-09-26 (Claude Code): Web spike, Java 11 follow-up. The six Java 16+ lines were patched in
  build-folder copies only (`build_web.sh --java 11`, `cheerpjInit({version: 11})`).
  - The engine boots in 17.1 s, but the first snapshot fails with
    `UnsatisfiedLinkError: Java_jdk_internal_misc_Unsafe_getBooleanVolatile` (Gson →
    `GameView.toJson`). The JavaScript stand-in natives hang the Java thread, as on Java 17.
  - Final verdict: CheerpJ 4.3 cannot run the engine.
  - Next options for web play:
    - hosted solo on `apps/multiplayer-server`, which costs hosting money
    - a GraalVM Web Image spike, which needs CI runners because a Wasm image build of XMage does
      not fit this 8 GB Mac
  - Caleb decides. `packages/ondevice-engine` is unchanged and no native rebuild is needed.
- 2026-09-26 (Claude Code): Polish #45 merged into the integration branch.
  - Both apps' Updates sheet has an About section with the site's fan-content notice and a
    Scryfall credit.
  - Scrolling battlefield rows fade at clipped edges and show "+N" hidden-card badges. The logic
    is `BattlefieldRowOverflow`, with mirrored tests.
  - Fixed `apps/android/.gitignore`: `native-artifact/` did not match the symlinks worktrees use.
  - Pre-existing and noted:
    - `testLandscapeLandsAndPermanentsScrollFromArtwork` fails on the base, because two landscape
      resource rows share the `board.battlefield.Your lands` identifier.
    - `testLandscapeRocksUse…ScrollIndependently` is flaky on the base.
- 2026-09-26 (Claude Code): Combat clarity #46 merged into the integration branch.
  - Attacking and blocking cards show combat keyword badges from the live engine view, so gained
    double strike shows. Printed and gained can't be told apart.
  - XMage's `FIRST_COMBAT_DAMAGE` step plays as a labelled "First strike" beat before regular
    damage.
  - The log adds one-line first-strike and deathtouch reasons.
  - Preview: `first-strike`. Shared cases: `parity/combat-cases.json`.
  - Started delegates for relay extras and save/resume research.
- 2026-09-26 (Claude Code): Save/resume research done in #47 (`docs/SAVE_RESUME_SPIKE.md`).
  - JVM experiments on the old build: 11 of 11 fresh-process restores matched the saved game
    exactly (including library order) and played to legal ends.
  - Saves are 135–287 KB without AI search trees, take 10–12 ms (0.2 s cold), and load in
    0.5–0.8 s.
  - Blockers found:
    - the human player object isn't serializable
    - the engine's copy function zeroes AI limits
    - XMage's load hook leaves a null field
    - the exile zone is keyed per process (re-keying fixed it)
  - Seeded replay diverged at turns 8 and 11, so replay is not the path.
  - Plan phases:
    - 0: app-only mitigations, 1–2 days
    - 1: engine checkpoint on the JVM, 5–7 days, forces a native rebuild
    - 2: native probe, 3–5 days, needs CI
    - 3: iOS, 4–6 days
    - 4: Android, 2–4 days
    - 5: relay multiplayer, optional, 6–10 days
  - Caleb decides:
    - Phase 1/2 approval
    - upstream patches or adapter workarounds
    - resume UX: auto or ask, force-quit behavior, saving RNG state
    - accepting that the AI may play differently after a restore
    - relay multiplayer scope
    - Android foreground-service policy
- 2026-09-26 (Claude Code): Paused and reassessed after the Mac overloaded.
  - Running the Android emulator and an iOS simulator together (plus macOS 27's post-update
    indexing) drove the load average past 900, and swap reached 8.2 of 9.2 GB. Both were shut
    down; free memory recovered to 52% and swap fell to 3.5 GB.
  - From now on only one device runs at a time. The live Android-host / iPhone-guest check moves
    to Caleb's phones after install.
  - Merged #50 (the build 7 UI removal, from a separate session) and #47 into the integration
    branch, and opened integration PR #51.
  - Caleb confirmed that Game Center stays for iPhone-only games; Online table codes are for
    iPhone plus Android.
- 2026-09-26 (Claude Code): Shipped.
  - Caleb approved the steps that needed him. #37, #38 and #51 were merged, the relay fix was
    deployed, and the old Vercel `magicmobile` project was disconnected.
  - Android build 9 published: versionCode 2026092601, APK `5b9320f2…`, signer unchanged.
    It updated build 8 in place on the emulator and passed its 5 packaged-engine device tests.
  - iOS build 18 uploaded from `8672b23` with Xcode 27 and the iOS 27 SDK, reusing build 17's
    engine. Apple reports it `VALID`, and Beta App Review `APPROVED`, in Internal and External.
  - The download site now shows iPhone build 18 and Android build 9.
  - Still open:
    - a live iPhone–Android game on real phones
    - #48 in the next build, after a relay deploy
    - the web route and save/resume decisions
