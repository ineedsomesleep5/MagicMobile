# MagicMobile 0.1.1 — build 2

Keep marketing version **0.1.1**. Shared visible build is **2**; Android installation versionCode is **2026091903**.

## Fixes

- iOS deck-library illustrations are explicitly constrained to each grid cell. Wide artwork cannot expand across column gutters; tile footer labels compress while preserving touch targets.
- Both platforms provide a separate included-deck selector for each of up to three AI opponents. Each selected deck is resolved separately and mapped to the correct engine seat.
- iOS visibly labels AI seats and persists selections across relaunch. Both lobbies preserve hidden selections when lowering and raising the opponent count while setup remains open.
- Existing engine artifacts are reused. No engine rebuild or rules change.

## Verification

- iOS: 9 configuration tests and the loaded-bitmap grid regression passed. The latter checks wide/tall illustrations across compact, wide and single-column layouts, including clear gutters.
- iOS UI: three distinct selections, 3→1→3 count changes, relaunch persistence and visible AI captions passed. An initial final-label run missed the main-menu transition; screenshot and hierarchy showed the unchanged menu. An unchanged warm rerun passed. Result: `build_output/presentation-review/build2-ai-labels-rerun.xcresult`.
- Android: release compilation, contract/deck/provider/analysis checks, lint, original signing certificate and 16 KiB alignment passed.
- Android: all 9 exact signed-APK tests passed on Android 15 ARM64, including three distinct AI commanders in an actual four-seat game, ten native lifecycle cycles, persistence, OCR and history.
- Android: actual Commander game completed at turn 17 with 83 responses, exercising ASK, PICK_TARGET and SELECT. Runtime report: `build_output/android-acceptance/instrumentation-esoJzM`.
- Installed Android build 2 over build 1 with original first-install timestamp preserved. Initial emulator framework/installer failures occurred under host memory pressure; a data-preserving cold boot recovered. No uninstall, app-data clear or AVD wipe.
- Website local mobile/desktop checks passed for both platform tabs, exact build 2 links, version labels, review notice, overflow and browser errors.

## Artifacts

Release source: `cc66de9a87666edfb9867120d86b6cd13fb9eb08`. Android tree equals build-start source `1d6c810024794863ee90d6f4d62f27f765db9caa`.

Android: https://github.com/ineedsomesleep5/MagicMobile/releases/tag/android-v0.1.1-build.2

- APK: `MagicMobile-Android-0.1.1-build2.apk`, 191,883,067 bytes.
- SHA-256: `b9590243bf78d7d6cbc26b7e88d124923188d993d93090f4e14b7a029492d159`.
- Public HTTP 200, file size and GitHub digest verified.
- Certificate SHA-256: `b10ca2cdf5d184c2b264b56dae888d950f3ab52a40551b7f8eb634de0316d4bb`.

iOS: https://testflight.apple.com/join/2mSHE8rZ

- IPA: `build_output/testflight/parity-0.1.1-build2/native-release.ax6gAz/export/MagicMobile.ipa`, 181,759,283 bytes.
- SHA-256: `de7b37ace592a534a4a235816284256390918ea10ae05c309051eedfe5a7104e`.
- Delivery UUID: `da469fda-b337-41ff-91fe-63d08fc8eaae`.
- Archive/export, signed/native guards, Apple validation and upload passed September 19, 2026 at 18:13 CDT.
- Apple processing: VALID. Adding tester groups succeeded, but the review submission failed because build 1 in the same version is already awaiting review. Build 2 has not been submitted for public review. No build was expired or review cancelled. Distribution must be retried after the existing review completes; the website explicitly states this pending gate.

Physical-phone acceptance remains pending. Android multiplayer remains excluded. Existing build 1 limitations on process-death game resume and foreground artwork downloads remain unchanged; matching release labels do not imply pixel-identical native UIs.
