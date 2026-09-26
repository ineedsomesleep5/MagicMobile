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
| 0 Merge #37, #38 | Waiting on Caleb | #37, #38 | Both green and conflict-free |
| 0 Branch cleanup | Done | | 14 remote branches deleted; 5 stale ones kept as `archive/*` tags |
| 0 Legacy removal, CI triggers, docs | Done | #40 (draft) | Reviewed. Before merging, Caleb disconnects or deletes the Vercel project `magicmobile` (old web game, Root Directory `apps/web`) |
| 1 Web engine spike | No-go on CheerpJ Java 17; Java 11 follow-up running | #44 (draft) | Engine ready in 17–26 s, tab 1.1 GB, but 0/15 games reached a prompt (missing Unsafe routines break `Watcher.copy` and Gson). PRs 3–6 wait on this |
| 2 Playtest focus | Done | #41 (draft) | Reviewed. Android and portable Swift tests pass, iOS simulator build OK. 2 pre-existing iOS 27 UI-test failures (library search focus) |
| 2 Playtest cards | Done | #43 (draft) | Reviewed. Swift 29 + Xcode 10 tests, Android core 69 / app 47 pass |
| 2b.1 Relay backlog + CI | Done, not deployed | #39 (draft) | Reviewed. 6/6 tests locally and in the new `Table relay` CI. Deploying needs Caleb: `cd services/table-relay && npx wrangler deploy` |
| 2b.2–4 Guest retry, notices, crash reports | Done, cross-play check pending | #42 (draft) | Reviewed. iOS swift 79 tests, Android core 60 / app 62 pass. The live Android-host/iPhone-guest run could not complete on the loaded Mac; the integration owner reruns it |
| 3–6 Web client | Blocked on PR 1 | | |
| Integration for build 18 / 9 | In progress | `codex/build18-integration` | #39–#43 and this doc merged; one conflict resolved (Android preview enum and tests, both kept). Android: core 73 / app 62 tests and 283 contract assertions pass, assembleDebug OK. Next: iOS 27 fixes, full iOS checks, live cross-play |
| iOS 27 UI-test triage | In progress | `codex/ios27-ui-fixes` | Delegate. Library search focus, hand inspection, attachment and history tests fail on iOS 27 (also on base); plus a full build with Metal |
| Release: iOS build 18, Android build 9 | Not started | | Needs Caleb's go-ahead |

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
