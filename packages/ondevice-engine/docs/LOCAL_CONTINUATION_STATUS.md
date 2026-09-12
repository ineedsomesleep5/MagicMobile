# Local continuation status — 2026-09-11

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
device ARM64 artifact; simulator compilation/execution remains outstanding.
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

The next diagnostic keeps the same standard Intel runner, 10 GiB heap, two build
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
then validate offline and two-/four-device play before the existing TestFlight
release is updated.

The separate unsigned [repository preflight](https://github.com/ineedsomesleep5/MagicMobile/actions/runs/34661344897)
passed at `fe12ee1`: 65 retained-gateway tests, repository typecheck, and the
existing bridge Docker image build on a Linux runner. No image was run or
published, no local Docker daemon was started, and no app was signed or uploaded.
These compatibility checks are not a remote rules-engine fallback or iOS proof.
