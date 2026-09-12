# Build and acceptance sequence

Run from the repository root unless stated otherwise. Use JDK 21 and the reviewed
Xcode 26.6 installation (`DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`
on the continuation Mac). Do not boot simulators or dispatch UI-test workflows.

## 1. Portable and real-engine regressions

```sh
bash packages/ondevice-engine/scripts/test_tooling.sh
bash packages/ondevice-engine/scripts/test_native_boundary.sh
bash packages/ondevice-engine/scripts/test_swift_close.sh
swift test --package-path packages/ondevice-engine/swift --jobs 2
swift test --package-path apps/ios --jobs 2
node --test scripts/ios/testflight-build-number.test.mjs
bash packages/ondevice-engine/scripts/build_jvm.sh
bash packages/ondevice-engine/scripts/test_real_engine.sh
```

Also export the exact bundled decks with the portable app exporter and run
`test_ios_precons.py` as wired in `magicmobile-issue4-nonsimulator.yml`. Inspect the workflow
before dispatch. These tests validate real JVM rules separately from C/Swift
fixtures; none executes native phone gameplay.

## 2. Preserve and verify the native candidate

Full ARM64 XMage+MAD build **34673638060** passed at engine source
`220647689c76cc95de941d279faafd85e63792c3`. Artifact **10292778783** ZIP SHA-256:
`24ba46f4836251861d32d8a51b2a5a0ff6da52901a6ef86742c99526750b5331`.

Use `download_issue4_native.py`, `verify_native_candidate.py` and
`prepare_ios_app_native.py` (see their `--help`) to verify and stage the paired
archive, generated headers, static dependencies and manifests. Never mix artifacts.
The preserved local candidate is `packages/ondevice-engine/build/verified-native-10292778783`.
Source equivalence conservatively guards production/compiler/build inputs and
all engine source directories, including tests.

Rebuild native inputs only when required by provenance or a reviewed engine change;
see [UPSTREAM_MAINTENANCE.md](UPSTREAM_MAINTENANCE.md). No card pruning or fallback.

## 3. Actual product link

Commit reviewed source before producing the receipt:

```sh
bash packages/ondevice-engine/scripts/build_issue4_unsigned_app.sh
```

This generates the Xcode project from `apps/ios/native-engine.yml`, selects generic iphoneos Release,
links the full library and inspects the actual product. It checks ARM64/iOS,
embedded startup, source/artifact hashes, native exports, paired dependencies and
absence of conflicting entrypoints. The Graal-first order and seven far-call
veneers preserve the entire 196,854,848-byte native code image. The verifier checks
922 relocated instructions/targets and every veneer. Do not atomize or patch
prelinked internal Graal branches without a separate correctness proof.

Local product source `62789b0` passed at
`packages/ondevice-engine/build/issue4-device-link.wacchh/product-receipt.json`.
The maintained unsigned verifier uses unstripped native symbols; do not pass a
stripped distribution binary and assume missing symbols imply missing engine.
For a stripped exported app, use the same layout verifier with the actual paired
DWARF file (not just the dSYM directory):

```sh
python3 packages/ondevice-engine/scripts/verify_graal_product_layout.py \
  --archive /absolute/verified-candidate/libmmengine.a \
  --executable /absolute/exported/Payload/MagicMobile.app/MagicMobile \
  --dsym /absolute/MagicMobile.xcarchive/dSYMs/MagicMobile.app.dSYM/Contents/Resources/DWARF/MagicMobile
```

It requires matching nonzero UUIDs, exact section bounds and defined symbols;
existing app symbols must agree. It still checks the actual executable's code,
relocations and veneers, never the dSYM's placeholder text. Neither path executes
the native runtime.

## 4. Authorized internal TestFlight

Use existing app **6784735182**, bundle **com.calebfeliciano.magicmobile**. Check
live ASC build numbers, then use the reviewed `scripts/ios/deploy-testflight.sh`
workflow. Verify archive identity/orientations, distribution provisioning and
Game Center in both profile and signed app, export, signature, Apple validation
and upload. Do not submit an App Store release.

**0.1.0 (2026091201)**, source `62789b0`, was successfully uploaded internal-only.
Artifacts: `build_output/testflight/issue4-2026091201-62789b0/`.
Upload ID: `86361630-995a-4029-9ca0-67da4fffa789`.
Processing reached **VALID**, internal state **MISSING_EXPORT_COMPLIANCE**.
This candidate is superseded by the opening-cancellation fix; new native run
**34723517045** builds source `a34fb08`. Inspect live state before claiming final
tester availability. Do not upload the same number again.

Replacement **2026091202** is prepared after confirming the number is unused in
ASC. The app plist declares no non-exempt encryption: inspected app/XMage sources
have no custom encryption calls; network transport uses Apple's URLSession/GameKit.
Apple's [export-compliance guidance](https://developer.apple.com/documentation/security/complying-with-encryption-export-regulations)
distinguishes OS-provided encryption from non-exempt encryption. Reassess this
declaration if dependencies or encryption functionality change.

## 5. Physical acceptance — separate gate

Use [TESTFLIGHT_ACCEPTANCE.md](TESTFLIGHT_ACCEPTANCE.md). No USB is required.
Native launch, complete offline games, AI/mobile resource behavior, complex UI
prompts, repeated cleanup and 2–4 real phones remain unexecuted. No durable restore,
host migration or guaranteed reconnect is implemented.
