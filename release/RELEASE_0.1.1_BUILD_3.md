# MagicMobile 0.1.1 — build 3

Marketing version remains **0.1.1**. Shared visible build is **3**; Android installation versionCode is **2026091904**. Native engines are reused, not rebuilt.

## Changes

- Equal-height deck tiles reserve two title lines and use mana-color symbols.
- Scryfall live images is available in settings and the lobby: saved artwork first, higher-quality online artwork when enabled. Bulk-download quality remains independent.
- Commander availability uses current engine-authorized actions. Casting closes the zone inspector.
- Floating mana has clearer payment controls and availability cues.
- iOS portrait reclaims duplicated safe-area spacing and removes the lower rectangular gradient.
- iOS landscape uses a wider, single-line action button and a shorter right-side dock. The hand reaches the safe-area bottom without the extra artificial gutter; the populated stack retains its width.

## Verification

- iOS artwork: 12 portable tests passed. Release helpers: 10 Node and 20 Python tests passed.
- iOS simulator: gameplay affordances, deck layout, viewport metrics and 17 portrait-polish checks passed. UI checks cover crowded boards, stack layout, commander dismissal, floating mana and the shared artwork preference.
- Empty metadata initially failed tile-height checks and was fixed. A landscape payment tap missed once; the unchanged isolated rerun passed. This is not evidence of physical-phone acceptance or a diagnosed automation root cause.
- Simulator fixtures are explicitly labeled development fixtures without an engine. They do not establish real-engine gameplay.
- Android: eight focused JVM tests, release compilation, contract/deck/provider/insight checks, lint, native provenance, signing and 16 KiB alignment passed.
- Android: nine exact signed-APK tests passed, including a completed native Commander game (14 turns, 71 responses), three independent AI decks, ten lifecycle cycles, isolated persistence, OCR and playtest privacy.
- Android installed over build 2 without clearing data. Normal main-menu startup was separately confirmed after a data-preserving cold boot; allocation/garbage-collection waits made initialization slow on the constrained emulator. No startup fix or physical-phone performance claim is implied.
- Exact-APK screenshots confirm equal-height one/two-line deck tiles, real mana symbols and the visible Settings live-image toggle. Consent remained off; offline artwork placeholders were expected.
- Repository CI passed on release source `bfb95ceb4dc03ea9e4b526b3e8e809da388d0ef8`.
- Website production build passed. Local rendered checks at 390×844 and 1440×1000 passed page identity, meaningful content, error-overlay absence, console health, platform switching, exact version/download links and horizontal overflow. Browser plugin was not available; existing Playwright and installed Chromium were used without new dependencies.

## Artifacts and distribution

Both artifacts were built from `bfb95ceb4dc03ea9e4b526b3e8e809da388d0ef8`.

iOS:

- IPA: `build_output/testflight/parity-0.1.1-build3/native-release.sWHmnL/export/MagicMobile.ipa`.
- Size: 181,790,287 bytes. SHA-256: `33b2c642532a4bb099b80ad46d70698188673784b7c824a22bcc3a96af6e3411`.
- Delivery UUID: `6dd55a71-706d-430a-8a5b-cb6275a8be31`.
- Archive, export, signed/native guards, Apple validation and upload passed September 19, 2026. Apple processing and tester availability are pending confirmation.
- Public TestFlight link remains https://testflight.apple.com/join/2mSHE8rZ. Upload alone does not make build 3 publicly available.

Android: https://github.com/ineedsomesleep5/MagicMobile/releases/tag/android-v0.1.1-build.3

- APK: `build_output/android-release/0.1.1-build3/MagicMobile-Android-0.1.1-build3.apk`, 191,888,423 bytes.
- SHA-256: `951a1eb949cb840b5cc9113698f234ccbcd7c0d992459c29449d3bfcf64f10c4`.
- Original certificate SHA-256: `b10ca2cdf5d184c2b264b56dae888d950f3ab52a40551b7f8eb634de0316d4bb`.
- Native runtime evidence: `build_output/android-acceptance/instrumentation-eGahRn`.
- Public HTTP 200, GitHub asset size and SHA-256 digest verified.

Physical-phone acceptance remains separate. Android multiplayer is excluded. Existing process-death resume and foreground-download limitations remain unchanged. Shared numbering does not claim pixel-identical platform layouts.
