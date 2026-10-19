# Android 0.1.1 build 31: engine release C (lighter engine)

Published October 18, 2026 as
[android-v0.1.1-build.31](https://github.com/ineedsomesleep5/MagicMobile/releases/tag/android-v0.1.1-build.31), first as a
test prerelease and then as the latest release, together with iPhone build 48 (`release/RELEASE_0.1.1_BUILD48.md`). The
public download re-hashes to the APK below.

## Signed artifact
- **Source:** `db33aa9e` (`codex/android-build-31`): candidate `codex/native-build-c` `21a82eb7` plus versionCode
  `2026101802` and `RELEASE_BUILD` 31.
- **Native engine:** `magicmobile-android.yml` run 39148290469 on `21a82eb7` (18 minutes), saved in
  `~/Documents/MagicMobile-releases/engines/android-build31-engine-21a82eb/artifact`. `libmmengine.so` 316.0 MB (was 354.0).
- **APK SHA-256:** `9a199b20f86fa7c2eac431d44457b537b2a46dd61a6055a2f10986ffa4ebb87e` (133912316 bytes; build 30 was
  143263544).
- **Signer:** unchanged, so it updates in place.

## Verification
- **`build_release.sh`:** the native guard (`verify_native` against `21a82eb7`), contract assertions, release lint,
  alignment and apksigner.
- **Emulator (API 35, headless):** in-place update `2026101801` → `2026101802`; 6/6 packaged-engine device tests,
  including an 18-turn native Commander game and a seeded game record (60 entries by turn 3, engine build
  `sha256:9f06efbe…906f`, registered in `ranked_engine_builds`).
- Size report `magicmobile-native-code-sizes.yml` run 39150431210: code 162.4 MB, set classes 11.5 MB.
- **Not verified:** a physical Android phone (free-memory reading from `/proc/meminfo`).
