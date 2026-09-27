# iOS 0.1.1 build 20: resume solo games

Apple reports build `dce0cd1c-463f-4b50-801f-dfd210c1825c` as `VALID`, with Beta App Review `APPROVED`, in the Internal (all builds) and External (added) groups, on September 27, 2026 UTC. The External invitation remains https://testflight.apple.com/join/2mSHE8rZ. None of this proves a completed game, or a resume, on a physical iPhone.

## Changes

- **Resume solo games.**
  - The engine checkpoints a game against the AI at each human priority decision.
  - After iOS terminates the app, or after a force-quit, a relaunch within 10 minutes offers "Resume your game?" with Resume and Abandon. Resume returns to the last decision with the same board, hands and library order. The RNG state is restored; AI play after the restore may differ.
  - The app side ([#63](https://github.com/ineedsomesleep5/MagicMobile/pull/63)) shipped inactive in build 19. It turns on because this engine reports `saveResume`, but only after the engine's runtime serialization self-test passes on the device. If the self-test fails on a phone, resume stays off, and games behave as in build 19.
- **Engine:** [#64](https://github.com/ineedsomesleep5/MagicMobile/pull/64) (checkpoints), [#68](https://github.com/ineedsomesleep5/MagicMobile/pull/68) (native metadata without serializable lambdas), [#72](https://github.com/ineedsomesleep5/MagicMobile/pull/72) (token test accepts the reviewed RandomUtil patch) and [#73](https://github.com/ineedsomesleep5/MagicMobile/pull/73) (the complete native metadata, with a JVM check that every checkpoint class is listed).
- Everything else matches build 19 (`release/RELEASE_0.1.1_BUILD19.md`). Android build 11 ships the same resume behavior.
- **Versions:** marketing 0.1.1, build 20, identity `com.calebfeliciano.magicmobile`, XMage `4825513287ba6c42c32fd205d227f4a5fc44c2f3` with the reviewed checkpoint patches.

## Verification

- **Signed source:** `9afc38b468d06e904b96bdf6dbd8c68791af048b` (`codex/ios-build-20`). This is `main` at #74 (`d030b72`) plus the build-20 bump.
- **`ios-fast` preflight on that source:** passed. The native decision against `79de39c` is `equivalent-source` (input tree `2bd5a469…`).
- **Native engine (new):**
  - Built by `magicmobile-far-calls.yml` run [36311846082](https://github.com/ineedsomesleep5/MagicMobile/actions/runs/36311846082), artifact `10931357619` (`sha256:f25f6662…`), engine commit `79de39c1ee847176afa8f325c43b77294d61240a`.
  - Checked with `download_issue4_native.py` and `verify_native_candidate.py`, then staged with `prepare_ios_app_native.py --apply`.
  - Staged `libmmengine.a` SHA-256: `dd6b742065f445d9d7b667fd4dcdbcd7b99ef3a3d333a800ec79b5e9032d2cf3`.
- **Linking:** the unsigned product linked against that exact artifact in `magicmobile-product-device.yml` run [36318481419](https://github.com/ineedsomesleep5/MagicMobile/actions/runs/36318481419).
- **The same engine code on Android** (build 11, run 36310535888):
  - The packaged engine reported `saveResume: true` on the emulator. `NativeCheckpointTest` checkpointed a priority decision and restored it.
  - The app resumed a force-stopped game, with a spell still on the stack.
  - The JVM suite checks that every class a checkpoint uses is listed in the native metadata.
- **Not verified:**
  - the iOS native engine running at all in this session (the simulator can't run the device engine)
  - resume on a physical iPhone, including the background task, file protection and the 10-minute window

## Signed artifact and Apple distribution

- **Release controller:** run `ios-0.1.1-20`, fingerprint `6556d95cc89959156eaa8cb08d6dc6a61cd564ee152af00fe4090de27506377b`, state `completed`.
- **Toolchain:** Xcode 27.0 with its Metal Toolchain, SDK `iphoneos27.0`, minimum iOS 17.0.
- **IPA SHA-256:** `d5072738c2ebb1981279ed9992220e637e134063259ae8c2c0849cb5b4aeb7cf`.
- **Delivery:** UUID `dce0cd1c-463f-4b50-801f-dfd210c1825c`. Apple processing `VALID`; the build expires 2026-12-26.
- **Groups:** Internal `dd37d7bb-26d8-4a0c-b8a3-7811d648a699` (all builds) and External `72b71a7a-bf62-43b5-8eda-b12a62e5c3eb` (added).
- **Beta App Review:** `APPROVED`.

## Acceptance for Caleb (on the iPhone)

1. Start a game against the AI and play until it's your turn to act.
2. Swipe the app away in the app switcher, then reopen it within 10 minutes. Expect "Resume your game?", and Resume should return you to the same decision.
3. Repeat, but wait more than 10 minutes. Expect "Your unfinished game expired after 10 minutes."
