# Android 0.1.1 build 10

## Scope

The same app changes as iPhone build 19 (`release/RELEASE_0.1.1_BUILD19.md`), on the current engine:

- **Deck Studio "Play this deck" ([#65](https://github.com/ineedsomesleep5/MagicMobile/pull/65)).**
  - Choose the playing deck from a deck's ⋯ menu, long press or the workspace header.
  - The deck is checked automatically with XMage on the phone, and the result is stored.
  - Decks show a Playing badge and Ready / Needs fixes / Not checked.
  - The setup deck card shows the card count, colors and check status.
  - Fix deck filters the list to the cards XMage named.
- **Deck Studio builder (#65):**
  - quick check
  - Quick Add and commander-first new decks
  - edit as text with a reviewed diff, and Copy list
  - group by role
  - select mode
  - card grid with a long-press preview and actions
  - sample hand
  - search syntax (`t:`, `o:`, `mv`, `id:`)
- **Parity fixture:** strings and rules are pinned for both platforms in `parity/deck-studio-cases.json`.
- **Resume, app side ([#63](https://github.com/ineedsomesleep5/MagicMobile/pull/63)), inactive.** The Resume/Abandon flow ships, but it stays off because this engine doesn't report `saveResume`. What is active:
  - the background memory release and music stop
  - the "Your last game ended when the app closed." notice
- **Online tables ([#48](https://github.com/ineedsomesleep5/MagicMobile/pull/48)):**
  - a host can remove a joiner while the table fills
  - credentials are sent as WebSocket subprotocols instead of URL parameters
  - the relay (version `c75c7092…`) limits table creation
- **Singular counts ([#56](https://github.com/ineedsomesleep5/MagicMobile/pull/56)):** "1 card".
- **Not included:** the save/resume engine ([#64](https://github.com/ineedsomesleep5/MagicMobile/pull/64)). Its native build is still being fixed (#68), so the release source reverts it.

## Signed artifact

- **Source:** `07e2bc54f27886df14e39e4fdf17fefe1460f408` (`codex/release-android10`). This is `main` at #67 (`7958793`), plus:
  - the revert of #64 (`6e6dcda`)
  - the engine package and native build scripts restored to the bundled library's source `2c32482` (the only files that differed were the iOS-only Swift wrapper and two iOS test scripts)
  - versionCode `2026092701` and `RELEASE_BUILD` 10
- **Version:** `0.1.1`, versionCode `2026092701`, unchanged package `com.calebfeliciano.magicmobile.android`.
- **APK SHA-256:** `516746b68a3ddde0c61c8eaa78c2841a7add2c2c40cd958b2e50f5a85129cd33` (222,541,642 bytes).
- **Instrumentation APK SHA-256:** `16f74a12d159511a6c0b30f10692d15e7f19f0d9011df26babbc0d5ae8439c5f`.
- **Signer SHA-256:** `b10ca2cdf5d184c2b264b56dae888d950f3ab52a40551b7f8eb634de0316d4bb`, unchanged (APK Signature Scheme v2).
- **Native engine:** the same as builds 8 and 9. `libmmengine.so` comes from `2c324825a8f6cff1a0a40ac38055dfe93683b960`, and XMage is at `4825513287ba6c42c32fd205d227f4a5fc44c2f3`. `scripts/android/verify_native.py` verified the exact native files and equivalent guarded source.

## Verification

- **`scripts/android/build_release.sh` passed:**
  - the native guard
  - 283 core contract assertions (136 protocol/deck/privacy, 42 auto-yield, 71 Deck Studio, 14 provider and 20 role)
  - `:app:assembleRelease`, `:app:assembleReleaseAndroidTest` and `:app:lintRelease`
  - 16 KiB zipalign and apksigner
- **JVM tests on main:** `:core:test` (143) and `:app:testDebugUnitTest` (55), including the Deck Studio and resume parity fixtures (#65).
- **Emulator (API 35, arm64):**
  - The APK updated build 9 in place. The first install time (2026-09-19) is unchanged, so data was kept.
  - All 6 packaged-engine instrumentation tests passed: completed Commander play, repeated engine reopen, and the device feature checks. The new `NativeCheckpointTest` skips because this engine lacks `saveResume`.
  - The first three device runs failed from emulator starvation, not the app: the emulator ran with software graphics while the host was swapping 4+ GB, and Android's watchdog killed `system_server` ("GOODBYE", `DeadObjectException`). Relaunched with `-gpu host`, the emulator idled at 3% CPU and the suite passed.
  - A manual launch afterwards hit an ANR while Android itself showed "Process system isn't responding". The launch path loads the printing index on `Dispatchers.IO` and runs the resume check on its own executor, as in build 9, so this is recorded as inconclusive, not as an app failure.
- **Not verified:**
  - a physical Android phone
  - a visual check of the new Deck Studio screens on Android (compile and JVM tests only)
  - a live Android–iPhone match on phones

## Release

- [android-v0.1.1-build.10](https://github.com/ineedsomesleep5/MagicMobile/releases/tag/android-v0.1.1-build.10) targets `07e2bc5`, with `SHA256SUMS`, and is marked latest.
- The public download was streamed without authentication and hashed. It matches the tested APK.
- The download site links build 10 via #70; iOS build 19 follows in the records PR.
