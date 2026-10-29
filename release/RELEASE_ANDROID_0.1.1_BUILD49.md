# Android 0.1.1 build 49: engine release D (pay for Propaganda), full screen on 3-button phones

Published October 28, 2026 as the latest public release,
[android-v0.1.1-build.49](https://github.com/ineedsomesleep5/MagicMobile/releases/tag/android-v0.1.1-build.49), from
PR #264 (engine release D) and PR #265 (TestFlight 71 from the same engine on `codex/ios-build-71`).

## Signed artifact
- **Source:** `codex/android-build-49` (`6161edba`) = PR #263's head (card art) merged with `codex/android-build-48`, the
  engine package set to candidate `1674f060` (= `a98b4b63`'s), the system-bars change from PR #265, versionCode
  `2026102804`, `RELEASE_BUILD` 49.
- **Native engine:** release D from `magicmobile-android.yml` run 40792593247 on `1674f060` (artifact
  `~/Documents/MagicMobile-releases/engines/android-build49-engine-1674f060/artifact`), engine identity
  `sha256:7c241814528f8ff01504ea277204144913ed700ec103c43a68f9ccdfe0ef1394`, registered in `ranked_engine_builds`.
- **APK SHA-256:** `aa2b8b432d2d498ebbe9687abffec4e8a5fb24fc1a3b6781e36a2b517041dba7` (144236591 bytes), with a copy in
  `~/Documents/MagicMobile-releases/android-49/`. The public download was re-hashed and matches.

## What changed
- **Engine release D (PR #264):** a mana payment asked while someone else holds priority (Propaganda and Ghostly Prison's
  attack tax, Rhystic Study, ward, Mana Leak) offers the payer's mana sources; before, nothing could be tapped and Auto
  Pay was dimmed (a TestFlight report on October 28). Also `ccd1365a`: an AI simulation's ended game copy no longer closes
  the live player's input channel.
- **3-button phones (PR #265):** the navigation bar hides during a game with the status bar; the board fills the screen.
- Saves from older builds are refused (new engine identity).

## Verification
- **Engine:** `RealStackResponseTests attack-tax` and the suite on a local JVM build; replay of an attack into
  Propaganda before and after; CI on #264 (real-jvm, swift, app).
- **`build_release.sh`:** native guard (engine package == artifact source), contracts, release lint, alignment and apksigner.
- **Emulator (API 35, headless):** in-place update over the first build 49 (`2026102804`), 6/6 packaged-engine device
  tests (16-turn native Commander game, game record on engine `7c241814…`). The system bars hide and the hand's slide,
  hold and spread work with the 3-button overlay at 420 and 480 dpi in the design preview.
- **Not verified on a phone:** a Propaganda payment in a live game; the Galaxy S23 Ultra report's hand gesture (not
  reproduced on the emulator).
