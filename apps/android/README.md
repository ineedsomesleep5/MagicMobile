# MagicMobile for Android

Android parity work continues on `codex/android-ios-parity`, which merges the Android
native XMage work with the current iOS Deck Studio product line. Android
remains a separate native Compose client; it consumes the same pinned engine and data.

The shared marketing version is **0.1.1** (release build 1). Android package code
**2026091902** remains a separate monotonic platform build number; the planned artifact
is `MagicMobile-Android-0.1.1-build1.apk` under tag `android-v0.1.1-build.1` after release verification.

## Architecture and scope

- Native Kotlin / Jetpack Compose UI, with the approved cream-and-charcoal deck workspace.
- The same pinned full XMage rules/cards and MagicMobile Java adapter, compiled for
  Android ARM64 and called in-process through JNI and the existing C lifetime boundary.
- Offline AI games require no desktop computer, localhost server, Java installation,
  cloud rules service, or downloaded executable engine.
- Reuse exact prompt IDs, revisions, response kinds, seat ownership and private
  viewer snapshots. Preserve Commander legality checks in the actual engine.
- First Android milestone: local Commander against actual MAD AI, local deck
  management and user-controlled external card reference. Online tables use the shared
  authenticated match service; Game Center is not used on Android.

### Online transport

`-PonlineServerUrl=https://…` sets the approved deployed match service at build time.
The default is empty, which presents an unavailable screen rather than claiming a live
service. `/v1/config` supplies the public Supabase authentication configuration and exact
engine identity. The client checks protocol, upstream, catalogue and app/build identity.
Email/password sessions use Android Keystore encrypted storage and are excluded from
backup. Lobby creation/join sends the selected resolved deck for server validation.

Online games reuse `PollState`, `GamePoll` and `GameScreen`; only poll/respond transport
changes to authenticated HTTPS. The server binds the signed-in user to their seat.
Backgrounding stops polling; foregrounding resumes with retry/backoff and a full snapshot
after interruption. The last lobby survives process restart. Explicitly leaving ends the
match for all players in this initial version, with confirmation in the UI.
The client also discovers `/v1/lobbies/current` after sign-in and an uncertain create/join
reply, so a lost response cannot cause repeated creation. Successful game/lobby polls
are at least one second apart; failures back off to a bounded 30-second interval.

Client compilation and contract tests do not establish cross-platform gameplay acceptance.
A configured deployment, matching engine build, and an iOS/Android live match are release gates.

## What one change has to touch for both platforms

Android reads the iOS app's committed data rather than keeping a second copy, so
most updates reach both platforms from a single edit:

| Shared input | Lives in | Reaches Android via |
|---|---|---|
| Card catalogue | `apps/ios/MagicMobile/Resources/ondevice-catalogue.json` | `scripts/android/prepare_assets.py` at build time |
| Included precons | `apps/ios/MagicMobile/PreconCatalog.swift` | the same script, parsed from the Swift source |
| Rules engine and adapter | `packages/ondevice-engine/` | `scripts/android/build_native.sh` cross-compiles it for ARM64 |
| Mana symbol artwork | `apps/ios/MagicMobile/Assets.xcassets/mana-*.svg` | converted to VectorDrawables; regenerate if the SVGs change |

So a catalogue regeneration or an engine change is picked up by the next Android
build with no Android-side edit. The two genuinely separate things are the UI
layer (SwiftUI vs Compose) and release: iOS ships through
`scripts/ios/deploy-testflight.sh` to TestFlight, Android produces an APK from
`.github/workflows/magicmobile-android.yml`.

Android consumes the merged type, mana value, printed color, color identity, set and
curated-role metadata. Catalogue facts remain distinct from XMage legality results.

The client includes local deck editing and per-deck drafts, text/JSON/file/public-link
imports, bundled on-device photo text recognition, retained import receipts, favorites,
tags/notes, grid/list browsing, card replacement and basic-land tools. Analysis includes
curve, printed mana symbols, roles with local overrides/targets, and explicitly bounded
draw probabilities. Scryfall search, Commander Spellbook and EDHREC are optional,
user-initiated services; they never replace the compiled card catalogue or rules engine.

Deck JSON interchanges with the current iOS DeckList format, while earlier Android
JSON remains readable. Plain-text export refuses a lossy conversion and offers JSON
instead. Commander replacement is one undoable operation; main, commander, companion,
sideboard and maybeboard destinations are available. Local search filters include
type, mana range, set and commander color identity before applying the result limit.

Gameplay uses the same protocol and per-viewer projections as iOS, including targeting,
payments, combat, multiple allocations, revealed zones and bounded auto-pass policies.
Playtest summaries are opt-in and exclude private hands and opponent decklists.
The editor shows and exports only history matching its exact playing cards and counts.

## Building and testing

```sh
# full engine + native-linked APK (Linux x86_64 only; use the CI workflow)
gh workflow run magicmobile-android.yml --ref codex/android-ios-parity

# everything that does run on macOS
gradle -p apps/android :core:contractChecks :core:deckStudioChecks :core:providerChecks :core:insightChecks :app:assembleDebug :app:lintDebug
python3 -m unittest discover -s scripts/android/tests
```

`build_native.sh` requires Linux x86_64, so the engine itself cannot be built on
a Mac; only the diagnostic (engine-less) APK can. `-PwithNative=true` additionally
requires `apps/android/native-artifact/`, which only the workflow produces.

## Signed downloads and subsequent updates

The downloadable build is a native-linked **Release APK**, application ID
`com.calebfeliciano.magicmobile.android`. Diagnostic builds have a different identity
and cannot play. Android 8 or later and an ARM64 device are required.

`scripts/android/build_release.sh` requires an equivalent verified native artifact,
JDK 17, Android SDK/NDK, an external private signing keystore/password file, and explicit
increasing version code/name. It runs the Kotlin checks, builds Release, runs lint,
and verifies APK signing and 16 KiB alignment. Do not commit signing keys/passwords.
Back up the release key securely: future installs need the same certificate and a
higher version code to update without uninstalling or losing local decks.

Set `MM_ANDROID_KEYSTORE`, `MM_ANDROID_PASSWORD_FILE`, `MM_ANDROID_VERSION_CODE`, and
`MM_ANDROID_VERSION_NAME`, then run `bash scripts/android/build_release.sh`. The signed
output is `app/build/outputs/apk/release/app-release.apk` under this Android directory.
The script does not publish automatically. Publish the verified APK and its source,
checksum and acceptance receipt as a GitHub prerelease when release is requested.
The script also builds a release-signed instrumentation APK under
`app/build/outputs/apk/androidTest/release/`. Install that test APK alongside the
release app and use `MM_ANDROID_TEST_PACKAGE=com.calebfeliciano.magicmobile.android.test`
with the device runner below to test the actual signed build. Do not distribute the
instrumentation APK as the game download.

For isolated emulator acceptance, use `-PandroidDebugSuffix=.paritytest` so an older
debug installation and its decks remain intact. Build with `-PwithNative=true` and run
`DeviceFeatureTest` and `NativeGameTest` through the Android instrumentation runner.
The latter validates, closes/reopens the native runtime, and requires a natural
completed Commander game against the actual packaged AI.

After installing the native debug app and its matching instrumentation APK, run:

```sh
ANDROID_SERIAL=emulator-5554 \
MM_ANDROID_TEST_PACKAGE=com.calebfeliciano.magicmobile.android.paritytest.test \
bash scripts/android/test_device.sh
```

Choose an already connected device explicitly and retain `ANDROID_HOME`. The runner
does not install, clear data, or boot an emulator. It rejects crashes even when adb
returns exit status zero; an engine-less diagnostic APK cannot pass. Lifecycle
acceptance includes ten open/close cycles in one process.

## Keeping iOS and Android together

Changes to shared engine/catalogue/precons/artwork now trigger Android app checks on
`main` as well as pull requests. UI changes still require implementation and review on
both platforms. Native engine changes require a new Android-native artifact; UI-only
updates may reuse one only after `verify_native.py` confirms guarded source equivalence.
Update both delivery receipts when releasing a feature to both platforms.

React Native/Expo would require porting the existing interfaces and retaining custom
native engine modules. Expo updates cannot replace changed native engine code. The
current route shares engine/data while preserving the working SwiftUI and Compose apps.

## Delivery boundary

A JVM test, an ARM64 library, an APK build and an Android-phone gameplay result
are separate evidence categories. Neither the iOS binary nor an empty Android
screen establishes Android engine execution. No store upload or production
signing or gameplay acceptance is established by a compilation check alone.

The signed `0.2.0-alpha.1` APK was verified on an Android 15 ARM64 emulator with all
eight instrumentation tests, including a completed real-engine Commander game and
ten native open/close cycles. The final UI pass covered validation through live play
and background/foreground continuation. Its exact source, checksum, test scope and
remaining limits are recorded in the
[release acceptance receipt](https://github.com/ineedsomesleep5/MagicMobile/releases/tag/android-v0.2.0-alpha.1).
Physical-phone acceptance remains pending. Live games do not survive process death;
decks and drafts persist. Android's native presentation is not pixel-for-pixel parity
with every iOS skin and animation. Multiplayer remains excluded.

Reference documentation:
- https://docs.gluonhq.com/#_android
- https://developer.android.com/training/articles/perf-jni
- https://developer.android.com/guide/practices/page-sizes
