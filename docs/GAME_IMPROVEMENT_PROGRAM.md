# Game improvement program (October 2026)

Caleb approved this program on 2026-10-15. It aims for two releases on both platforms. The second one has everything,
working and verified. The Mac session ("Game smart skip changes") owns integration and releases. Cloud sessions do
isolated engine, Android and server work, and report through GitHub (the protocol is below). Update the checkboxes and
the log at the bottom as work lands, so any session can see where the program stands.

## Releases

| Release | Content | iOS | Android |
|---|---|---|---|
| R1 | Phases 0 and 1: app-only, on today's engine (XMage `dac400b`) | TestFlight 39 | build 23 |
| R2 | Phases 2 to 4: the engine release, plus the app pieces that use it | TestFlight 40 | build 24 |
| R3 | Phase 5: the engine game record, plus verified ranked AI wins | TestFlight 41 | build 25 |

Caleb chose the strongest path on 2026-10-15 and gave Phase 5 its own release (R3).
Builds installed directly on Caleb's phone between releases are test builds, not releases.

## Phase 0: ship what is already built (Mac)

- [ ] Caleb's phone test of ranked and smart pass v2 (the build is waiting in the Mac scratchpad)
- [ ] Merge #153 smart pass v2, #155 iOS privacy manifest, #156 and #158 size trims, #157 audit report, #159 photo
      import removed
- [ ] Privacy policy on the site: sign-in email and ranked records (ML Kit is gone with #159). Caleb approves the wording.
- [x] Gradle wrapper pinned to 8.14.3; CI workflows and `scripts/android/*` use `./gradlew`; the signed release APK is
      checked (signer, versionCode, size)

## Phase 1: app-only improvements, in R1

| Item | Owner |
|---|---|
| Bronze ranked AI picks from the gentlest precons until the engine difficulty lands | Mac |
| Ladder tuning: two or three concrete options (tier floors and similar) for Caleb to choose from, then implemented on both platforms and on the server ladder | C1 for options and server, Mac for apps |
| Rank history from the server: `mm_record_game` takes the ranked points from `ranked_standings`, not from the phone | C1 writes it; Mac applies it live with Caleb's OK |
| Rank-badge spin frames re-encoded or trimmed (about 7 MB per platform, see docs/audits/APP_AUDIT_2026-10.md) | Mac |
| Smart pass fixes from Caleb's phone test | Mac |

## Phase 2: engine release A, in R2

| Item | Owner |
|---|---|
| `stackControllers` in ViewProjector; the apps fill `controllerId`; smart pass passes on your own spells and triggers ("Stop for my own spells" setting) | C2 for the engine, Mac for the apps |
| A "real response" signal: per priority, whether a legal play actually responds to the stack (Arena's smart stops), so smart pass stops less | C2 for the engine, Mac for the apps |
| Real AI difficulty: shallower search and occasional deliberate mistakes at Bronze and Silver, full strength from Platinum up | C2 |
| AI-vs-AI calibration showing each tier is measurably easier than the next | C3, after C2 |
| Android startup: cut the about 4.5 M load-time relocations of `libmmengine.so` (linker and native-image flags), measured before and after | C2 researches, Mac runs native CI |
| The latest XMage upstream, if the weekly watch has one | Mac |

## Phase 3: smaller engine, in R2

- [ ] Read the GraalVM build report: what fills the 167 MB image heap and the 202 MB of code. Make only safe cuts. (C4)

## Phase 4: stronger AI at Diamond and Mythic, in R2

- [ ] Better attack, block, mulligan and response choices, measured with the C3 harness (C4 after Phase 3, or C2)

## Phase 5: engine game record, in R3

- [ ] A compact, deterministic action log from the engine, enough to replay a game, kept with each finished game (C5)
- [ ] A replay viewer for debugging (developer-facing first) (Mac)
- [ ] Ranked AI wins: the phone uploads the game record with the result, and the server checks it before counting
      the win (signature, length, consistency checks; the server does not run the engine) (C5 for the format, Mac and
      server for the check)

## Sessions, models and effort

| Session | Where | Model | Effort |
|---|---|---|---|
| Main ("Game smart skip changes") | Mac | Opus 5.5 | high (extra-high for engine reviews) |
| C1 ladder options and rank history | cloud | Opus 5.5 | high |
| C2 engine release A | cloud | Opus 5.5 | extra-high |
| C3 AI calibration | cloud | Sonnet 5.5 | medium |
| C4 engine size and high-tier AI | cloud, after C2 and C3 | Opus 5.5 | high |
| C5 game record | cloud, after C2 merges | Opus 5.5 | extra-high |
| Subagents | any | Sonnet 5.5 (Haiku 5.5 for mechanical sifting) | default |

Cloud sessions start on the account's default model, so Caleb sets each one's model and effort when it starts. At
most four sessions run at once (Main plus three cloud sessions).

## Approval gates (the Mac session asks Caleb)

- Live Supabase changes, each one
- Multi-hour native builds (far-calls, the Android native build): the first one of R2, then per change only if something new is risky
- The store upload and distribution of R1 and of R2
- The privacy policy wording and the ladder option

## Cloud protocol (every cloud session follows this)

Environment: **MagicMobile Cloud**. It has JDK 17 and 21, Maven 3.9, Gradle via the repo wrapper `apps/android/gradlew` (8.14.3; the image's `/opt/gradle` is only a fallback), Android SDK 35
(`$ANDROID_HOME=/opt/android-sdk`), Node 22 and Python 3.13, with 4 CPUs and 15 GB of memory. There is no macOS, so no
Xcode, no iOS builds and no simulators. There is no NDK and no native engine artifact. Maven Central can answer 429:
retry it.

1. **Branch:** `cloud/<id>-<topic>` (for example `cloud/c2-engine-a`), cut from origin/main. Never push to main. Never
   force-push someone else's branch.
2. **Report:** keep `docs/cloud/reports/<id>.md` up to date on that branch. Its first line is
   `STATUS: working | blocked | ready-for-review | done`. Then: what changed, what was verified (with exact commands
   and results), what was not, and a `NEEDS CALEB` section for decisions. Commit and push the report at each
   milestone, not only at the end. The Mac session reads it from GitHub.
3. **PR:** open a draft PR early with the same title as the report. Mark it ready for review when STATUS is
   `ready-for-review`. The Mac session reviews, integrates and merges.
4. **Never:** release, upload, sign, change the live Supabase project, dispatch multi-hour native workflows, or delete
   branches. Write `NEEDS CALEB` in the report instead.
5. **Engine work** follows packages/ondevice-engine/AGENTS.md. Real-engine tests run with
   `bash packages/ondevice-engine/scripts/build_jvm.sh` and `scripts/test_real_engine.sh`. Update PROTOCOL.md for any
   snapshot change.
6. **Android work** builds with `apps/android/gradlew -p apps/android :core:test :app:compileDebugKotlin`. Never split one feature
   between an iOS session and an Android session: the Mac does the iOS half of cloud engine features.
7. **Subagents:** a cloud session may use one or two Sonnet 5.5 subagents for research, test writing and analysis.
   Design and engine changes stay with the session itself.

## Cloud session briefs

### C1: ladder options and server-side rank history (Phase 1)
Read docs/RANKED.md, docs/research/ARENA_HEARTHSTONE_NOTES.md (section D) and
supabase/migrations/20261015120000_ranked_referee.sql.
1. Write `docs/cloud/ladder-options.md` with two or three concrete ladder options compared with Arena and Hearthstone
   (for example a floor at each tier, the steps per tier, a streak bonus, the season reset). For each option, list
   the exact rule changes for `RankLadder.swift`, `Ranked.kt` and the referee SQL, and the expected climb speed in
   games per tier at a 50% and a 60% win rate. Recommend one.
2. Write a new migration so that `mm_record_game` stores the caller's server points (`ranked_standings.points`) for
   `mode = 'ranked'` and ignores `p_rank_points`. Add PGlite tests in supabase/tests and run
   `npm run test:ranked --prefix supabase/tests`. Do not apply it live.

### C2: engine release A (Phase 2)
Read packages/ondevice-engine/AGENTS.md, docs/PROTOCOL.md, docs/RANKED.md (the AI skill notes) and
docs/research/ARENA_HEARTHSTONE_NOTES.md (A2 and A3).
1. `stackControllers` (stack object id to controller player id) in the per-seat projection, with a real-JVM test.
2. A per-priority "responds to the stack" flag on legal plays (spells and abilities that target or could affect what
   is on the stack, or that have flash and timing reasons). Define it conservatively: when unsure, true. Real-JVM tests.
3. AI difficulty: skill 1 and 2 search 1 and 2 plies (today the minimum is `max(4, skill)`). Add a small, seeded mistake
   chance at skill 1 to 3, configurable. Keep skill 4 and up unchanged. Unit and real-JVM tests.
4. Research only: which GraalVM native-image and linker options reduce load-time relocations for the Android shared
   library (`-H:` options, `-Wl,-z,pack-relative-relocs`, PIE and similar). Write the proposed change for
   scripts/android/build_native.sh with the expected effect. Do not dispatch native workflows.
Report the protocol and snapshot changes the apps must adopt, so the Mac can do the iOS and Android wiring.

### C3: AI calibration (Phase 2; build the harness now, run it after C2's AI changes are pushed)
The October calibration (docs/RANKED.md, "Calibration") used a throwaway script that is not in the repo. It found skill
6 against skill 2 went 6–6, which matches Caleb's sense that even Bronze is hard.
1. Build a committed, repeatable AI-vs-AI harness on the real JVM engine (for example
   `packages/ondevice-engine/tools/ai-calibration/` plus a script). It runs two AI seats with a watcher seat that
   concedes at once, seeded, on the ranked AI deck pools (apps/ios/MagicMobile/Resources and the AIDeckPool lists),
   and writes CSV results.
2. Baseline on today's engine. Then, on C2's branch, run enough games per pairing to tell the tiers apart: skill 1
   against 3, 2 against 4, 3 against 4, and every skill against skill 6. Report win rates with 95% intervals and
   recommend skill and mistake settings so each tier is measurably easier than the one above it. CPU-heavy: this is
   why it runs in the cloud.

### C4: engine size and high-tier AI (Phases 3 and 4)
1. Produce or read the GraalVM build report (the native-image `--emit build-report` or the dashboard) for the engine.
   Break down the image heap and code by package. Propose safe cuts with their estimated savings. Recommendations
   first; implement only the clearly safe ones.
2. Stronger AI at skill 5 and 6: improve attack, block, mulligan or response choices where calibration shows weak play.
   Measure with the C3 harness.

### C5: engine game record (Phase 5, after C2 is merged)
Design and build a compact, deterministic record of every engine decision (the seed, the decks, then each prompt
answer in order), enough to replay a finished game on the JVM engine to the same result. Add a replay entry point and
real-JVM tests that replay recorded games. Keep it small (kilobytes per game). Write `docs/cloud/game-record.md` with
the format and how the ranked server can check an uploaded record cheaply without running the engine (for example a
signed digest chain, turn and length bounds, and consistency with the reported result). Do not change the server or
the apps: the Mac does those.

## Log

- 2026-10-15: Caleb gave the go with the strongest model path and a third release for Phase 5.
- 2026-10-15: program approved in principle; cloud environment verified (tools, network, GitHub push and draft PR from
  the cloud, #160); plan written.
