# Maintaining the pinned XMage port

XMage remains the rules authority. Maintain the upstream Java implementation and narrow mobile/build adapters; do not replace card rules with a second handwritten engine. New rules and cards reach players only in a tested, signed app update. GitHub source/toolchain/artifact downloads are developer/CI operations, **never an in-app executable update mechanism**. Do not download or load replacement JARs, native libraries, or executable card implementations on a phone.

This is a maintenance procedure, not release acceptance. Current evidence and outstanding gates belong in [LOCAL_CONTINUATION_STATUS.md](LOCAL_CONTINUATION_STATUS.md) and [NATIVE_BLOCKERS.md](NATIVE_BLOCKERS.md).

## 1. Select and review an exact upstream revision

Start in the explicitly selected MagicMobile checkout; record its root, branch, commit and diff. Use a fresh maintenance checkout/build tree for a new upstream candidate so stale classes, generated registries and patched sources cannot enter it. Preserve existing work and evidence; do not reset an occupied checkout.

Commands below run from `packages/ondevice-engine` in that checkout and are instructions for an authorized maintenance run, not automatic actions.

```sh
python3 scripts/check_upstream.py
```

This queries upstream `master` and writes `evidence/upstream-status.json`; it does not approve or install the update. [upstream.lock.json](../upstream.lock.json) currently pins `magefree/mage` at `8aea65ae9ae3c89970fe865e1316105539e097ca`. `magicmobileBase` identifies the original integration baseline, not the latest upstream revision.

Review the chosen upstream diff, rules/card changes, dependencies and notices. Update `commit` and the three `sourceBlobs` only after reviewing the corresponding original files. Obtain each Git blob ID with `git -C <reviewed-mage-checkout> rev-parse <exact-commit>:<path>`; these are Git blob IDs, not plain-file SHA-256 hashes. Review the `CardImpl`, `Sets` and `HumanPlayer` transformations in [prepare_upstream.py](../scripts/prepare_upstream.py) against those originals. Keep changes limited to static factories/registration and the response hook.

Update the explicit upstream identities together: `XmageEngine.UPSTREAM`, `engine/tools/CommanderSetExporter.java`, and `scripts/export_ios_catalogue.py:UPSTREAM`. Do not merely change the lock and leave runtime/catalogue identities on the old revision.

## 2. Rebuild the real registry and JVM adapter

```sh
bash scripts/build_jvm.sh
bash scripts/test_real_engine.sh
```

`build_jvm.sh` invokes `bootstrap.sh`, which fetches the exact commit only into an uninitialized upstream checkout and refuses an existing different HEAD. It does not advance an old checkout automatically. `prepare_upstream.py` checks reviewed input blobs on first application and stamped output hashes on reuse; a changed patch implementation therefore needs a fresh upstream tree, not reuse of an old stamp.

The Maven build selects real Sets/Common, Human/AI/AI.MAD, Constructed and Commander modules plus dependencies. It skips upstream Maven tests; the second command runs the port's real-JVM regressions and bounded match drivers, not the entire upstream test suite. `RegistryExporter` generates direct factories, the catalogue, registry report and reflection metadata; `CommanderSetExporter` generates set eligibility. Investigate any failure before proceeding. JVM success is not iOS execution or full-card parity.

Review new generated contents and their exclusions, then update the exporter's `CATALOGUE_SHA256`, `REPORT_SHA256`, `REGISTRY_HASH` and `SET_ELIGIBILITY_SHA256` from those exact reviewed outputs. Never copy hashes just to silence a failure.

```sh
python3 scripts/export_ios_catalogue.py --self-test
python3 scripts/export_ios_catalogue.py
python3 scripts/export_ios_catalogue.py --check
```

The export writes `apps/ios/MagicMobile/Resources/ondevice-catalogue.json`. It retains exact printing identities, rejects ambiguous collector addresses and filters to Commander-eligible sets. Review unavailable names and deck regressions. The registry fingerprint describes inventory, not every byte of rules code.

## 3. Rebuild with the reviewed native compiler

The full-engine reference is [.github/workflows/magicmobile-far-calls.yml](../../../.github/workflows/magicmobile-far-calls.yml): an Intel macOS builder using a private patched Gluon 22.1.0.1 / Java 17.0.3 compiler, GluonFX 1.0.29 and static JDK `18-ea+prep18-9`. Its configured Xcode path and builder resources must exist on the selected authorized host. Do not substitute the desktop diagnostic or an unpatched default compiler and call it the same candidate.

On that compatible builder, with new result filenames:

```sh
bash scripts/test_far_call_planner.sh
bash scripts/setup_gluon_intel.sh
python3 scripts/prepare_gluon_far_calls.py --result-file build/maintenance-compiler-home.txt
export MM_GRAALVM_HOME="$(<build/maintenance-compiler-home.txt)"
JAVA_TOOL_OPTIONS=-Dmagicmobile.farCallLimit=256 bash scripts/test_ios_toolchain.sh
MM_NATIVE_REFLECTION_PROFILE=targeted MM_NATIVE_INIT_PROFILE=reviewed-enums \
MM_NATIVE_ORM_PROFILE=runtime-defaults MM_NATIVE_NEW_RATIO=7 MM_NATIVE_MAX_HEAP=10g \
MM_NATIVE_RESULT_FILE=build/maintenance-native-build.txt bash scripts/build_native_ios.sh
```

The 10g setting is the hosted profile and requires at least 12 GiB physical RAM; never use it on the 8 GB development Mac. A resource/profile change needs its own recorded evidence. The forced-distance toolchain probe is not XMage execution; its option must not leak into the full build. `build_native_desktop.sh` is a separate desktop diagnostic, not an iOS artifact.

Compiler preparation verifies the official archive hash and [upstream compiler source manifest](../native/gluon/compiler-patches/upstream-sources.json), applies `far-calls.patch` with zero fuzz, checks patched-source hashes, and alters only a private SDK copy. Preserve `compiler-patch-manifest.json`: archive, original/patched JAR, patch, source manifest, planner and replacement-class hashes. A compiler upgrade requires reviewing/rebasing these pins and rerunning compiler and full-engine gates, not bypassing them.

Freeze inputs during AOT. `build_native_ios.sh` snapshots `build/core` and `build/engine` and records `class-snapshot.sha256`; upstream class directories and dependency JARs remain referenced by the classpath rather than copied into that snapshot. Preserve the exact classpath, dependency/toolchain versions, profiles, generated metadata and build logs alongside the artifact.

## 4. Preserve and verify candidate provenance

Use the workflow's packaging step to retain the same build's archive, generated headers, Gluon/JDK static libraries, class snapshot, reflection config, registry report, source commit, compiler manifest and `SHA256SUMS`. Select the exact successful same-repository run and artifact ID/digest; developer-side download helpers validate that identity and bytes. Do not mix libraries or headers from other builds.

[verify_native_candidate.py](../scripts/verify_native_candidate.py) checks those files and compares engine inputs between the engine source and app source. Broad engine directories, including their tests, remain conservatively guarded. A changed adapter or engine test requires a new native candidate, even when a test is outside the native runtime classpath. Dirty tracked work fails the guard. Provenance is not execution evidence; untracked inputs must not enter a release build.

Stage only the verified candidate using `prepare_ios_app_native.py` with its explicit archive/header/clib/JDK inputs: dry run first, then authorized `--apply`, then `--verify-installed`. It refuses a different existing destination; preserve the prior candidate and use a fresh release checkout rather than overwriting it. Record generated-project provenance and run `verify_issue4_unsigned_product.py` on the resulting actual app. Its Graal layout check must retain code bytes except verified relocation immediates and decode the long-call targets correctly. Neither staging nor unsigned linkage is signed-app acceptance.

## 5. Keep multiplayer on exact build identity

[BuildIdentity / HostRouter](../swift/Sources/MagicMobileOnDevice/HostRouter.swift) requires an exact `hello` identity before accepting player operations: protocol version, upstream commit, catalogue hash and adapter version. The actual app supplies `ondevice-0.1/app-<marketing-version>/build-<build-number>` as adapter version in [OnDeviceRootView.swift](../../../apps/ios/MagicMobile/OnDeviceRootView.swift). Thus different app builds must not silently join, even with identical card inventory. Preserve the mismatch refusal; do not broaden compatibility based on catalogue hash alone. A new executable requires a new release build identity and verification that bundled catalogue and native capabilities agree.

## 6. Release only after separate acceptance gates

Record each result against the exact source/artifact, with failures and unrun checks explicit: source/patch review; tooling and real-JVM regressions; iOS archive and product linkage; signed app launch and real-engine gameplay on supported phones; AI/lifecycle cancellation and shutdown; hidden-information/prompt handling; actual multi-device Game Center matching and incompatible-build rejection; interruption/reconnect behavior for supported flows. Retest affected rules/cards and representative long games; inventory size is not full-card coverage.

After source/build/signing gates pass, the authorized release owner may distribute an internal TestFlight candidate for physical acceptance, including when no USB device is available. A public release remains a separate approval and acceptance gate. Verify app identity `com.calebfeliciano.magicmobile`, unique resolved version/build metadata, signing, privacy and applicable release checks. Upload/processing, tester availability, installation and phone acceptance are distinct states. Preserve the previous known-good signed release and provenance; recover via the approved app distribution path, never by fetching executable replacements inside the app.
