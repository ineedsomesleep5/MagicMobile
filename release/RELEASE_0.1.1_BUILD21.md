# iOS 0.1.1 build 21: save on exit, smaller engine, How to play

Apple reports build `3a054b54-2773-46e2-893a-e3f3424d4e69` as `VALID`, with Beta App Review `APPROVED`, in the Internal (all builds) and External (added) groups, on September 28, 2026 UTC. The External invitation remains https://testflight.apple.com/join/2mSHE8rZ. None of this proves anything on a physical iPhone.

## Changes
- **Save only when leaving** ([#78](https://github.com/ineedsomesleep5/MagicMobile/pull/78), [#76](https://github.com/ineedsomesleep5/MagicMobile/pull/76), via [#83](https://github.com/ineedsomesleep5/MagicMobile/pull/83)).
  - The engine no longer writes a checkpoint before every priority decision. Those writes were the pauses Caleb noticed on build 20.
  - It saves on request: when the app goes inactive or to the background.
  - Returning deletes the save. A crash while the app is open reports that the game ended, and an older save is never offered.
- **Smaller engine** (#78):
  - 99,186 `.class` files are no longer embedded as resources.
  - Duplicate jars and test-scope libraries are dropped from the native classpath.
  - A build guard fails if `.class` resources come back.
  - `libmmengine.a` is 428 MB, down from 668 MB; the IPA is 137.9 MB, down from 195–202 MB.
- **Playtest fixes:**
  - Victory top-attacker token art ([#79](https://github.com/ineedsomesleep5/MagicMobile/pull/79)).
  - The D20 roll hides the starting-player choice (#79).
  - Offline token art for the tokens your decks make, common tokens and opponents' tokens ([#77](https://github.com/ineedsomesleep5/MagicMobile/pull/77)).
  - Deck Studio Ideas and Analysis scroll with the header and reset to the top ([#82](https://github.com/ineedsomesleep5/MagicMobile/pull/82)).
- **How to play** ([#88](https://github.com/ineedsomesleep5/MagicMobile/pull/88)): a 10-page walkthrough. It opens once and is also on the main menu and in the game menu.
- **Smaller backgrounds** ([#80](https://github.com/ineedsomesleep5/MagicMobile/pull/80)): `Assets.car` is 7.7 MB, down from 23.5 MB.
- **Legacy removal** ([#86](https://github.com/ineedsomesleep5/MagicMobile/pull/86)): the retired hosted-server and online clients are gone (−7,013 lines of Swift).
- **Repo and CI:** content archive ([#84](https://github.com/ineedsomesleep5/MagicMobile/pull/84)) and CI guardrails ([#81](https://github.com/ineedsomesleep5/MagicMobile/pull/81)).
- **Versions:** marketing 0.1.1, build 21, identity `com.calebfeliciano.magicmobile`, XMage `4825513287ba6c42c32fd205d227f4a5fc44c2f3`.

## Verification
- **Signed source:** `05ea801` (`codex/ios-build-21`, tag `ios-v0.1.1-build.21`). This is `main` at #88 (`67c9005`) plus the build-21 bump.
- **`ios-fast` preflight:** passed. The native decision against `ad2e8c3` is `equivalent-source`.
- **Native engine:**
  - Built by far-calls run [36355475313](https://github.com/ineedsomesleep5/MagicMobile/actions/runs/36355475313). The first attempt failed a synthetic builder-heap probe on the runner; the rerun passed.
  - Staged with the new `controller.py stage-native` step; `libmmengine.a` SHA-256 `466597b2ac83acec751f3dba5d0d83d4c691325c54a6519b7a51abfa7b7b9753`.
  - The unsigned product linked against it in product-device run [36362219474](https://github.com/ineedsomesleep5/MagicMobile/actions/runs/36362219474).
- **Tests:**
  - `swift test` for `apps/ios`: 585 tests.
  - Simulator UI tests on the integration and feature branches: Deck Studio, OnDeviceSetup, the starting roll, presentation-smoke and How to play.
  - The real-engine JVM suite, including the on-request checkpoint cases.
- **The same engine code on Android** (build 12, emulator):
  - The native save-on-request test passes.
  - In the app: Home, force-stop, relaunch, and Resume restored the board.
  - The first save in a process took 5.3 s on the emulator. The planned follow-up is to warm the serialization descriptors when a game starts.
- **Not verified:** anything on a physical iPhone, including resume timing. The iOS engine never ran in this session because the simulator can't run it.

## Signed artifact and Apple distribution
- **Release controller:** run `ios-0.1.1-21`, fingerprint `ccfd06d07103c8e5bf3321f5e5ff9bc296c3c709acc0c7c4a4d8f6b421cacfd1`, state `completed`.
- **Toolchain:** Xcode 27.0, SDK `iphoneos27.0`, minimum iOS 17.0.
- **IPA SHA-256:** `b2bd69d948a44f4a2dd200b141e1eb5d24a2730965925e8d8d3f7fc1578febad` (137,927,133 bytes).
- **Delivery:** `3a054b54-2773-46e2-893a-e3f3424d4e69`. Apple processing `VALID`; the build expires 2026-12-26.
- **Groups:** Internal `dd37d7bb-26d8-4a0c-b8a3-7811d648a699` and External `72b71a7a-bf62-43b5-8eda-b12a62e5c3eb`.
- **Beta App Review:** `APPROVED`.

## Same day
Android build 12 (versionCode `2026092703`) is published at https://github.com/ineedsomesleep5/MagicMobile/releases/tag/android-v0.1.1-build.12.
- APK SHA-256 `248890c07eb3977ed04306f2fb41d1c4b1983d5d29eeedb7cb660c430385c6da` (138.7 MB, down from 228.5 MB).
- Signer `b10ca2cd…d4bb` is unchanged.
