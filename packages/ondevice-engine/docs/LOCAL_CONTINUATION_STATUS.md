# Local continuation status — 2026-09-13 UTC

## Current result — corrected native engine built; TestFlight upload succeeded

Full native **34762171820** at `00b33cb` passed in 87m 47s. Both original
product **34762192464** and privacy-corrected app product **34775393085** passed.
App source `2bdbc8027f6bafb6dbd98d5c29bdf36481f78e49` passed the local native
Release and signed-layout checks. Internal-only **0.1.0 (2026091301)** validated
and uploaded successfully at 18:46 UTC, delivery
`4384ed1f-51ca-4df8-8a6e-ac41451d1133`. Apple processing is **VALID** and state
**IN_BETA_TESTING**, with existing Internal group access confirmed. Phone
acceptance remains separate and unverified.
See [the release handoff](TESTFLIGHT_2026091301.md) for exact artifact hashes,
preserved prior inputs, checks and the manual first test.

## Previous work — compiler heap and runtime catalogue fixes

Full native run **34740553245** timed out after 180 minutes; it did not produce
a replacement engine. Its builder log shows repeated full collections with
the Parallel collector's old generation essentially full. The product wait in
**34740596789** also expired. The candidate changes the compiler JVM to G1,
retaining the same guarded 10 GiB heap on the existing hosted runner; it does
not change the iOS runtime collector. A bounded retention probe fails under
the previous policy and passes with G1. The small actual ARM64/iOS ABI compile,
archive and independent link also pass. Full-engine run **34762171820** at
`00b33cb223f93caed6bc752f87d2384e146c9a1c` is running; the product workflow is
pinned to that exact source/run. Neither new native nor product gate has passed.

The conversion audit additionally reproduced missing token metadata in native
code and empty card-name choices from the desktop repository on a fresh JVM.
The token resource inclusion now passes a native/JVM comparison. The new
read-only catalogue exports original XMage/H2 metadata at build time: 92,166
printings, 92,738 rows including split halves, and 33,070 names. Runtime queries
use bundled data, not H2 or a desktop service. Real JVM lookup/factory/choice
and AI error-capture regressions pass. Full JVM compilation and the full real
regression suite pass, including completed two-/four-seat and token/mulligan
games. The metadata criteria oracle passes 326 checks against in-memory H2;
166 Python build-tool tests pass. The real catalogue host-native test passes
all nine naming categories, metadata decoding/reflection, filters and copies
(`build/card-catalogue-native-744Kt3`); full native engine/iOS execution is separate.

The user now requests **TestFlight updates**, because the phone will be away
from the Mac's Wi-Fi. Do not require USB or resume automated phone taps.
Build **2026091301** is prepared but **not uploaded**; its currently staged old
library cannot validate these changes. Verify a fresh matching native artifact,
product, signing and App Store Connect build-number availability before upload.
Phone startup, gameplay, performance and full-card parity remain unaccepted.

## Previous result — iOS Color policy conflict reproduced; revised patch validated locally

The user's 2026091203 report identifies `Color.<clinit>` loading the unavailable
desktop AWT library during `HumanPlayer.chooseMulligan`. A real small native
executable reproduces the exact `UnsatisfiedLinkError`. The first Color-only
build-time policy passed on the host but full iOS run **34737322860** failed:
Toolkit was initialized despite its required runtime policy. The strengthened
probe now reproduces that compiler conflict too. A source-pinned, generated
Color patch removes only its desktop JNI bootstrap, preserves all original
value methods, and keeps Color/Toolkit runtime initialization. Native/JVM value
comparisons and the explicit unsupported-Toolkit guard pass locally.
See [the compatibility analysis](NATIVE_COLOR_COMPATIBILITY.md).

The failed `017b9c5` run produced no accepted full engine artifact. The next run
**34740086280** at `1f5eadd` stopped in the shared compiler probe because that
caller lacked the new patch-directory argument. This caller wiring is corrected;
the small Color-exercising ARM64/iOS compile/archive/independent link passes
locally in `build/ios-abi-ueIYy7/`. Full engine run **34740553245** at source
`28185e5e3aea67a2b5a932a0cb213160e7b2c51b` subsequently timed out; the product gate
was pinned to that exact run and source and also timed out. App build
**2026091301** remains prepared for the revised artifact; it is not installed or
uploaded yet. The previous library cannot verify this fix.
Caleb's paired physical iPhone 16 Pro Max is connected and charging;
device details, installed build 2026091203, launch and a stopped-game screenshot
were obtained directly. The Mac is unlocked and both Device Hub and iPhone
Mirroring display the real app. iPhone Mirroring taps started Token Triumph
against one Grave Danger AI and selected the human starting player; old build
2026091203 then stopped before mulligans, confirming the before-fix failure.
The user now prefers to perform phone taps manually, following one specific
test instruction at a time. Do not resume automated phone controls; build,
install and inspect reported errors, then request the next manual test.
New native startup/gameplay acceptance remains pending.

## Previous diagnostic distribution — report captured successfully

The user confirmed installing **2026091202** and reported a stopped engine during
startup with default human **Token Triumph** and one AI opponent. **Grave Danger**
is the source default AI deck; the phone's saved AI selection was not confirmed.
This is a failed native play attempt, not successful full-game acceptance.
The same matchup reached turn one with seven cards in a desktop JVM replay;
that does not reproduce or fix the iPhone exception. The installed engine
discarded the underlying exception. App Store Connect had no crash/feedback
record at inspection; the engine catches this failure without crashing the app.

The user approved a local-only diagnostic TestFlight update. Engine revision
`c355eeea2277c6234207fe756eb757f86b58bde8` retains one bounded exception report,
separate from peer polls and ordinary error replies. Full native run
**34731298892**, using the validated far-call compiler pipeline at source
`76c18bfc76ca652cbd7a979cbb8910531ccb280e`, **passed**, artifact **10311165739**.
App source `7c27eaa20f10a7e05727f1e2fa17d1210d1932fd` passed actual product run
**34732453251** and the local Release/native-layout checks. Build **2026091203**
adds explicit review/share/delete and protected, backup-excluded latest-report
storage. Archive/export/signature/Apple validation/upload passed; processing is
**VALID**, internal state **IN_BETA_TESTING**, with verified existing **Internal**
group access. Delivery UUID: `92c6be87-4cbf-4708-ae0c-8421932e1395`.

See [the diagnostic handoff](DIAGNOSTIC_TESTFLIGHT_2026091203.md) for exact
hashes, passing checks and phone instructions. The next step is a known-deck
startup retest and, if it stops, an explicitly shared **private** error report.
Native diagnostic capture, successful gameplay and performance remain unverified.
No gameplay fix is claimed. PR #6 remains draft; issues #4 and #7 remain open.

The first diagnostic dispatch (**34730780807**) selected the older, unpatched
native workflow. The product provenance guard correctly rejected that workflow
identity (**34731246989**); the wrong run was cancelled before full AOT. The
replacement above uses `magicmobile-far-calls.yml` and its paired full-engine
artifact. The guard was not weakened and no incorrect artifact was packaged.

## Previous distribution — replacement native/product passed; internal TestFlight available

The release binary uses app source `55be4f417dded8c22b97987536dc6dc3cf825b4a`
and engine source `a34fb08abd7c4f32b643701349f99f0b59ee2771`. Later status/ledger
commits document this binary; they are not its compiled source revision.

- Full XMage+MAD ARM64 run **34723517045**, attempt 2, passed. Candidate
  **10308242189** ZIP SHA-256:
  `4f306aec6e6591bf576a337119e303120656fe46eda012048c12b1819cdc8c0c`.
  The paired archive/headers/static dependencies/compiler manifest/registry report
  are hash-verified and preserved in `packages/ondevice-engine/build/verified-native-10308242189`.
  Archive SHA-256: `897f55bceeb1f4b71156b9542edf9aabf47b7abacfbd94291e3afe81099800c6`.
- Actual generic-iPhone Release passed locally and in hosted run **34724909323**.
  Hosted product evidence: **10308617788**, ZIP SHA-256
  `129bde95d9f2db45e78c124a8fd83878db27c894bd0f42f29e2533426b2f508f`.
  Local receipt: `packages/ondevice-engine/build/issue4-device-link.XeypPM/product-receipt.json`.
  Both verify the full 196,881,504-byte Graal code image, 922 relocated instructions
  and targets, all seven far-call veneers, ARM64/iOS, native entrypoint and provenance.
- Signed archive/export, distribution signature, Game Center in both profile and
  signed app, Apple validation and internal-only upload passed for existing ASC app
  **6784735182**, **0.1.0 (2026091202)**. Upload ID:
  `ceccf78d-c836-4216-8df3-8f725f7aac31`; Apple processing **VALID**, internal state
  **IN_BETA_TESTING**, audience **INTERNAL_ONLY**. Membership in the existing
  **Internal** group (`dd37d7bb-26d8-4a0c-b8a3-7811d648a699`) is verified.
  Installation was later user-confirmed; startup failed as recorded above. Artifacts:
  `build_output/testflight/issue4-2026091202-55be4f4/`.
  IPA SHA-256: `5ce0fb7bb1db27b614c2bf178d35547ca7486e8d3c5f4780adc239e3df1a96d4`.
  Exported native layout passed with UUID-matched dSYM
  `CF9E4267-2AC5-3AB0-AF21-7FFED19FBAA1`; this is inspection, not execution.
- App-source **55be4f4** CI **34724759396**, package gates **34724759413** and
  full non-simulator verification **34724758131** passed. Evidence includes 108
  portable app tests, 32 Swift protocol tests, 153 tooling tests, 394 core assertions,
  9,000 C fixture requests/five shutdown scenarios, generic SDK/test compilation,
  real JVM rules/AI/lifecycle/completed games and all five exact bundled precons.
- Native startup later **FAILED** on 2026091202; complete gameplay, AI resource
  behavior, repeated native cleanup, rendered portrait/landscape accessibility
  and real 2–4-phone matches remain unverified in
  [issue #7](https://github.com/ineedsomesleep5/MagicMobile/issues/7).
  No simulator/UI workflow or public App Store release was run in this continuation.

## Resolved regression — opening-selection shutdown

After the initial upload, bounded teardown tests exposed an opening-selection
race: interrupting the GAME worker makes every upstream player unable to respond,
while `GameImpl.pickChoosingPlayer()` spins on `hasEnded()`. The mobile adapter's
existing cancellation hook covered `checkIfGameIsOver()` but not that end check.
The deterministic regression failed before the fix. `MobileCommanderGame` now
includes the same durable cancellation signal in `hasEnded()`, including copies.
Full real-engine regressions passed, including both MAD configurations and complete
two-/four-seat plus token/mulligan games. Commit `a34fb08abd7c4f32b643701349f99f0b59ee2771`
passed in ARM64 run **34723517045**. This changes production engine
source: the old archive/build below cannot validate or ship the new fix. The fresh
source-verified archive and replacement internal upload are recorded above.
Do not call build 2026091201 the final accepted candidate.

App source `c2f62e2e4acbfa01351d3ddee2a6569fbe983ab5` prepared replacement
`0.1.0 (2026091202)`. CI **34723993396**, on-device package gates **34723993392**
and full non-simulator verification **34723991713** passed, including SDK compile,
real JVM regressions and exact bundled precons. An additional 30 JVM immediate
start/destroy cycles across 1/2/3 AI passed with zero busy replies (maximum 75 ms).
These timings are not native mobile measurements.

Native run **34723517045** attempt 1 stopped on Maven repository DNS resolution
after module compilation, before AOT. Logs are retained; attempt 2 passed with the
same source/settings, followed by actual product linking and signing/upload.
Physical acceptance is tracked separately in [issue #7](https://github.com/ineedsomesleep5/MagicMobile/issues/7).

## Initial desktop result — native product linked; internal TestFlight uploaded

This block supersedes all chronological checkpoints below. Product source
`62789b0e2b8fd006135fd0ff1dac0b769c92717f` on PR #6 preserves `apps/ios` and
bundle `com.calebfeliciano.magicmobile`.

- Full XMage + MAD ARM64 compilation passed in run **34673638060**, engine source
  `220647689c76cc95de941d279faafd85e63792c3`, artifact **10292778783**. ZIP SHA-256:
  `24ba46f4836251861d32d8a51b2a5a0ff6da52901a6ef86742c99526750b5331`.
  Paired archive/headers/dependencies/manifests are preserved locally under
  `packages/ondevice-engine/build/verified-native-10292778783`.
- Apple's final `arm64_b26` link failure was reproduced. The fix places the intact
  196,854,848-byte Graal image first and uses seven ARM64 far-call veneers. No cards
  or AI were removed. Verification checks all 922 relocated instructions and their
  actual targets, loader mapping/alignment, intact code and every veneer.
- Actual unsigned generic-device Release passed; local receipt:
  `packages/ondevice-engine/build/issue4-device-link.wacchh/product-receipt.json`.
  Signed exported app layout also passed using UUID-matched dSYM
  `44AC3CD8-A28A-33FC-84A9-DDE221057D7C`. This is inspection, not native execution.
- Existing ASC app **6784735182** received internal-only **0.1.0 (2026091201)**.
  Archive/export/Apple validation/upload passed; upload ID
  `86361630-995a-4029-9ca0-67da4fffa789`, processing **VALID**, internal state
  **MISSING_EXPORT_COMPLIANCE**. This superseded candidate is not final tester
  availability. Signature verification passed; signed app
  and distribution profile both carry Game Center. No public release was submitted.
  Local artifacts: `build_output/testflight/issue4-2026091201-62789b0/`.
- 108 portable app tests, 32 Swift protocol tests, 9,000 ASan/UBSan C fixture
  requests and five shutdown scenarios passed. Real JVM query/control/privacy,
  Commander, portrait, lifecycle/cancellation and MAD play regressions passed.
  Two-/four-human games completed at turns 16/40; token/mulligan game at turn 16.
  All five exact bundled precons passed real validation and first-prompt tests.
- Final tooling now has 153 passing tests, including 31 native-layout/dSYM
  fixtures. The signed verifier was rerun against the initial exported app; its
  actual code/relocations/veneers passed with UUID-matched symbols.
- Final test cleanup retries only documented `engine_busy_shutdown`, bounded to
  20 seconds. Artifact equivalence remains conservative: all engine source
  directories, including tests, and production/compiler inputs are guarded.

See [source ledger](ISSUE4_SOURCE_CONTROL_LEDGER.md), [build gates](BUILD_AND_DEVICE_GATES.md),
[upstream maintenance](UPSTREAM_MAINTENANCE.md) and [physical acceptance](TESTFLIGHT_ACCEPTANCE.md).
No simulator/UI workflow was run in this continuation. Native phone gameplay,
AI memory/thermal measurements and real multi-phone matches remain **NOT RUN**.

## Historical checkpoints (superseded)

## Paused for Web Pro — 2026-09-12

Caleb requested a GitHub handoff with no further simulator work. Continue from
[issue #4](https://github.com/ineedsomesleep5/MagicMobile/issues/4), which defines
the source/build completion checklist and the later desktop release boundary.
The source checkpoint is published to `codex/ondevice-xmage` and `main`.

New concrete blocker: [ARM64 run 34664591026](https://github.com/ineedsomesleep5/MagicMobile/actions/runs/34664591026)
failed at image creation after method compilation, with
`GraalError: failed guarantee: value too large to fit into space` in
`AArch64Assembler$SingleInstructionAnnotation.patch` / `LIRNativeImageCodeCache.patchMethods`.
This was not another timeout or an observed out-of-memory exception. The newer
AI-inclusive ARM64 run 34669182960 was still compiling at pause; inspect its live
result before another build. No full native archive has been accepted.

The final small prompt patch preserves authoritative commander confirmation,
direct mana-source actions, native detail controls beside quick actions,
empty-special choices and exact special-payment labels/accessibility. All 76
portable presentation tests passed on macOS after these edits. SwiftUI syntax
parse and diff checks passed; the three new SDK-only board tests were added but
not executed. Prior unsigned build-for-testing predates this final small patch.

Simulator engine run 34670423198 and setup UI run 34669768265 were canceled at
the user's request, not passed. No simulator is required for Web Pro's handoff
phase. Native runtime, offline phone gameplay, AI performance and multi-phone
acceptance remain explicitly unverified; do not convert source/build success
into those claims. Signing and a new build in the existing TestFlight app are
reserved for the later desktop phase. No new TestFlight upload occurred.

## Latest update — 2026-09-12 03:14 UTC

Published portrait/setup integration `e116c42` preserves the existing bundle and
board, adds authenticated viewer identity, 2–4 human Game Center setup, 1–3 real
XMage AI opponents, exact local deck resolution, native prompt transport, named
public/authorized inspection zones, per-commander tax/damage, and retryable
session cleanup. Release entry remains unchanged until a real native library is
linked; only an explicit DEBUG argument opens the new setup for UI testing.

Local gates passed: 73 portable Swift presentation tests, 32 native-boundary/
network-package tests (including ordered ingress and suspension revisions),
unsigned iOS build-for-testing, 13 freshly exported real JVM two-/four-seat board
fixtures, and all five bundled precons through real Commander validation and an
initial prompt. The catalogue selects eternal-legal printings with the exact
upstream set predicate; no deck cards were changed to make validation pass.
Real AI JVM tests observed land, commander cast, combat and bounded shutdown;
they are not native AI or mobile-performance evidence.

Game Center capability is enabled for the existing bundle and its existing app
has a Game Center detail record. Entitlement source is wired; no newly signed
provisioning profile or actual multi-phone match has been validated.

Active hosted gates:

- [ARM64 full engine including AI, source 178f3f3](https://github.com/ineedsomesleep5/MagicMobile/actions/runs/34669182960).
- [Full XMage simulator lifecycle, source 10eec3a](https://github.com/ineedsomesleep5/MagicMobile/actions/runs/34669512748).
- [Actual setup UI plus unit/geometry checks, source e116c42](https://github.com/ineedsomesleep5/MagicMobile/actions/runs/34669768265).

The older ARM64 build 34664591026 remains running but predates the AI/projection
freeze and cannot serve as the current release library. No full native library,
native gameplay, new TestFlight build, or phone acceptance has been claimed.
Caleb explicitly chose testing on his phone **through the TestFlight update**;
USB availability must not become a release blocker. Native compilation/linkage,
runtime and app checks still precede upload, with remaining physical-device and
multi-phone acceptance reported honestly.

## Earlier toolchain update — 2026-09-12 02:22 UTC

[Non-XMage simulator probe 34666765499](https://github.com/ineedsomesleep5/MagicMobile/actions/runs/34666765499)
passed on the pinned Intel toolchain and an actual iOS 26.5 simulator. The
independent executable printed `TOOLCHAIN_ONLY entered_main`, `isolate_create=0`,
`result=42 isolate_teardown=0`, and exited zero. Artifact 10289777588 preserves
the evidence. This proves the simulator toolchain/runtime path, not XMage,
ARM64 device execution, the product UI, or a TestFlight release.

The full ARM64 engine run 34664591026 remains in progress. Portrait adapters,
real AI lifecycle integration, and offline deck resolution are now being
implemented in this worktree. The older chronological notes below describe
earlier snapshots; the portrait source is no longer unchanged.

## Earlier baseline

The real JVM engine baseline is working. The full on-device engine is **not**
release-ready: local native compiler heaps saturated, and the hosted 10 GiB
attempt reached inlining but exceeded its 75-minute limit. No simulator/phone
gameplay or TestFlight upload occurred.

Work is on `codex/ondevice-xmage`; source was published to that branch and `main`
at `b8b273f` without rewriting history. The original
portrait app under `apps/ios` remains unchanged; its existing
`com.calebfeliciano.magicmobile` release identity is preserved. The separate
`.ondevice` inspection harness is not the product interface or a replacement
TestFlight app. Portrait protocol integration and Game Center lobby work remain.

## Evidence by gate

| Category | Executed result | Evidence |
|---|---|---|
| Standalone protocol/tooling | 378 Java assertions; 24 Python cases; 29 macOS Swift tests | `evidence/macos-tooling-tests.txt`, `macos-swift-tests.txt` |
| Native C/Swift boundary fixtures | 9,000 echo requests; five C shutdown scenarios; Swift retry/idempotence/deinit checks | `evidence/native-boundary-tests.txt`, `native-shutdown-tests.txt`, `swift-close-tests.txt` |
| Actual JVM build | Pinned real XMage compiled; 32,275 factories, 587 sets, 92,166 printings; no unregistered printing reference | `evidence/macos-jvm-build.log` |
| Completed real JVM games | Two-human game at turn 16; four-human game at turn 39; token/mulligan game at turn 16 | `evidence/real-jvm-game.json`, `real-jvm-four-player-game.json`, `real-jvm-token-mulligan-game.json` |
| Real JVM regressions | 27 query/control/privacy groups; 10 seeded Commander rule groups; two injected-busy-worker groups; two real resolving-choice cancellation cases; seven deck rejection fixtures and 24 lifecycle checks | `evidence/Real*Tests.txt`, `real-commander-rules-tests.txt`, `real-busy-shutdown-tests.txt`, `real-jvm-deck-validation.json`, `real-jvm-lifecycle.json` |
| Full-engine AOT | No desktop or iOS XMage binary. Local 4/5 GiB builds saturated; hosted 10 GiB completed analysis, universe, parsing and inlining before its 75-minute timeout | `evidence/ormlite-check-55Hbub.log`, `ios-native-memory-diagnostic.txt`, `hosted-native-34659217140/evidence/ios-native-Cx8W0J.log` |
| iOS toolchain only | Separate non-engine ARM64 archive, generated-header caller compilation, and independent iOS executable link passed; no native execution | `evidence/ios-abi-H6FJa9.log`, `ios-abi-H6FJa9-link.log` |
| iOS inspection harness | Unsigned iOS SDK build passed after separating the app target name from its Swift package target; no native engine linked or app execution | `evidence/ios-harness-target-fixed.log`, `scripts/test_ios_harness.sh` |
| Simulator | Not built or played | No native engine XCFramework |
| Physical iPhone / airplane mode | Not installed or played | Not validated |
| Multi-device internet | Not run; lobby/correlation/reconnect implementation still needed | Portable host/packet tests are not network-device proof |
| TestFlight | No upload or app-record changes | Existing release untouched |

All game seats were driven by developer protocol fixtures, not human players on
phones. The Commander-rule fixtures directly set up real upstream state. The
busy-worker regression injects an uninterruptible query-listener stall; it does
not prove cancellation inside a genuine complex resolving card effect. Full
card catalogue compilation is not full playable-card/UI parity.

The separate resolving-choice regression seeds a real Fact or Fiction and mana
at an ordinary priority wait, then casts and resolves it through the unmodified
game worker. Destroy/close at its genuine 0/5 pile-choice prompt terminate the
worker before replacement. This is specific real-effect choice-wait evidence,
not cancellation of every complex or CPU-bound effect, nor native/device proof.

## Environment and reproducible commands

Local Apple Silicon M1 Mac with 8 GB RAM; macOS 26.5; JDK 21.0.11 and Maven
3.9.16 for the JVM baseline; Xcode 26.6 (17F113), Swift 6.3.3. Native diagnostic:
Gluon GraalVM 22.1.0.1 / Java 17.0.3 M1, GluonFX 1.0.29, Substrate 0.0.69,
static SDK 18-ea+prep18-9. The iOS C probe reported SDK 26.5 / minimum iOS 17.
Upstream commit: `8aea65ae9ae3c89970fe865e1316105539e097ca`.

From this package directory, these are the reproduction entrypoints. The complete
runner incorporates independently rerun tests; it was not a hosted CI execution.

```bash
export JAVA_HOME=/opt/homebrew/opt/openjdk@21/libexec/openjdk.jdk/Contents/Home
export PATH="$JAVA_HOME/bin:$PATH"
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
bash scripts/test_tooling.sh
bash scripts/test_native_boundary.sh
bash scripts/test_swift_close.sh
swift test --package-path swift
bash scripts/build_jvm.sh
bash scripts/test_real_engine.sh
bash scripts/test_ormlite_native.sh
bash scripts/test_ios_toolchain.sh
```

The full-engine diagnostic (do not run concurrently with another compiler) was:

```bash
MM_NATIVE_REFLECTION_PROFILE=targeted MM_NATIVE_INIT_PROFILE=reviewed-enums \
MM_NATIVE_ORM_PROFILE=runtime-defaults MM_NATIVE_NEW_RATIO=7 \
MM_NATIVE_MAX_HEAP=5g bash scripts/build_native_ios.sh
```

Its wrapper exited 1 after intentional compiler termination (143), not an
observed OOM. The earlier `ShThev` status 137 was an intentional KILL after TERM
did not exit, not an inferred OS OOM kill. See the measured collection counters
and exact snapshot hashes in the memory diagnostic. No card pruning, rule
substitution, or remote rules-engine fallback was used.

The toolchain-only archive is deliberately not an engine artifact: it contains
no `mm_engine_*` exports. It also contains Gluon's application delegate/main;
the independent caller link verified that ordinary archive linking with a
caller-owned `main` does not pull that delegate into the executable. The linked
executable reports platform iOS, minimum iOS 17, and exports the probe/isolate
symbols, not the engine. The Graal-produced object itself lacks a platform load
command, so Apple's linker still warns while assuming iOS for that member.
Native execution and full-engine linking remain unverified.

The fresh `H6FJa9` toolchain probe also verified bounded builder GC logs
(`builder-gc.log`, up to two 8 MB rotated files). Future hosted diagnostics retain
these logs to distinguish retained-heap pressure from compiler faults. This is
instrumentation, not a fix or a measurement of the already-running hosted build.
The pinned toolchain's simulator target is separately compiled x86_64, not the
device ARM64 artifact; full-engine simulator compilation/execution remains outstanding.
[Gluon simulator documentation](https://docs.gluonhq.com/#_ios_simulator)

## Hosted continuation authorized

At 23:40 UTC on 2026-09-11, Caleb authorized publishing to GitHub `main` and an
eventual TestFlight upload containing the new native game. The original `main`
history can be preserved by a fast-forward; local logs/device data are excluded.
A manually dispatched unsigned workflow now targets the standard 14 GB Intel
Mac runner with a checksum-pinned Intel compiler. This is not a proven native
engine build or an authorization for paid larger runners.
[GitHub runner specifications](https://docs.github.com/en/actions/reference/runners/github-hosted-runners)

The first hosted native diagnostic, [run 34659217140](https://github.com/ineedsomesleep5/MagicMobile/actions/runs/34659217140),
failed at its 75-minute step timeout. It completed analysis (66,479 reachable
classes; 366,507 methods), universe construction, parsing and inlining. The
universe stage reported 1,844.5 seconds in 13 collections, 92.24% of that stage;
its final heap reading was 9.26 GB. There was no reported Java out-of-memory
exception or native compatibility error before the timeout. No candidate library
was uploaded. Diagnostics are retained locally under
`evidence/hosted-native-34659217140/`; the frozen class-manifest hash matches the
local baseline (`5d81068e320c953e73beee92d9b0d4d8f945db75eec28e3fba91601b50384c7a`).

The [retry, run 34664591026](https://github.com/ineedsomesleep5/MagicMobile/actions/runs/34664591026),
was dispatched from `b76805d`. It keeps the same standard Intel runner, 10 GiB heap, two build
workers, NewRatio 7 and complete card registry, but permits 180 minutes for the
compile step (210 minutes for the job) and captures bounded GC logs. This tests
whether the proven compiler progress can finish; it does not claim success or
authorize a paid runner. TestFlight still requires the native/product gates.
Live App Store Connect lookup confirmed the
existing app `6784735182`, bundle `com.calebfeliciano.magicmobile`, and latest
uploaded build `2026062902` (valid, not expired) before any new upload.
Changing the build machine does not change the requirement that gameplay and
XMage run on the iPhone. After full native compilation: verify actual headers,
archive contents/slices and isolate behavior, integrate the portrait interface,
then integrate and test the product before updating the existing TestFlight
release. The later user instruction above makes TestFlight the delivery path
for physical-phone and multi-device acceptance, not a USB prerequisite.

The separate unsigned [repository preflight](https://github.com/ineedsomesleep5/MagicMobile/actions/runs/34661344897)
passed at `fe12ee1`: 65 retained-gateway tests, repository typecheck, and the
existing bridge Docker image build on a Linux runner. No image was run or
published, no local Docker daemon was started, and no app was signed or uploaded.
These compatibility checks are not a remote rules-engine fallback or iOS proof.

The separate non-XMage [simulator probe 34665324348](https://github.com/ineedsomesleep5/MagicMobile/actions/runs/34665324348)
compiled and linked x86_64 code with IOSSIMULATOR metadata, then booted a fresh
iOS 26.5 simulator. Its application launch timed out after 60 seconds without
the required isolate/result output. It is not an execution pass. The follow-up
uses `simctl spawn` for this C-only caller (which has no UIKit application entry)
and adds a flushed main-entry marker to separate process entry from isolate
startup. Runtime success, app lifecycle and full-engine gameplay remain unproven.

That [follow-up 34665870814](https://github.com/ineedsomesleep5/MagicMobile/actions/runs/34665870814)
stopped before compilation: the first `simctl list --json` exceeded its 30-second
deadline. It did not exercise direct process execution. The discovery bound is
now 120 seconds to test slow CoreSimulator initialization; no runtime/architecture
checks or execution-result assertions were relaxed.

[Run 34666118749](https://github.com/ineedsomesleep5/MagicMobile/actions/runs/34666118749)
passed discovery, compilation and linkage, then exceeded 180 seconds during a
fresh iOS 26.5 simulator's data migration. Migration advanced through distinct
system plugins; the probe executable was not reached. Cleanup of that owned,
ephemeral CI simulator also exceeded its bounds. The next check permits up to
600 seconds for first boot, retaining all platform and exact execution assertions.
