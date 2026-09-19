# MagicMobile for Android

Android parity work continues on `codex/android-ios-parity`, which merges the Android
native XMage work with the iOS Deck Studio source shipped as build 5000000000. Android
remains a separate native Compose client; it consumes the same pinned engine and data.

## Architecture and scope

- Native Kotlin / Jetpack Compose UI, with the approved cream-and-charcoal deck workspace.
- The same pinned full XMage rules/cards and MagicMobile Java adapter, compiled for
  Android ARM64 and called in-process through JNI and the existing C lifetime boundary.
- No desktop computer, localhost server, Java installation, cloud rules service,
  downloaded executable engine, or substitute rules implementation in the consumer path.
- Reuse exact prompt IDs, revisions, response kinds, seat ownership and private
  viewer snapshots. Preserve Commander legality checks in the actual engine.
- First Android milestone: local Commander against actual MAD AI, local deck
  management and user-controlled external card reference. Cross-platform multiplayer
  is a separate transport project; Game Center is not available on Android.

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

## Building and testing

```sh
# full engine + native-linked APK (Linux x86_64 only; use the CI workflow)
gh workflow run magicmobile-android.yml --ref codex/android-ios-parity

# everything that does run on macOS
gradle -p apps/android :core:contractChecks :core:deckStudioChecks :app:assembleDebug :app:lintDebug
python3 -m unittest discover -s scripts/android/tests
```

`build_native.sh` requires Linux x86_64, so the engine itself cannot be built on
a Mac; only the diagnostic (engine-less) APK can. `-PwithNative=true` additionally
requires `apps/android/native-artifact/`, which only the workflow produces.

## Delivery boundary

A JVM test, an ARM64 library, an APK build and an Android-phone gameplay result
are separate evidence categories. Neither the iOS binary nor an empty Android
screen establishes Android engine execution. No store upload or production
signing is authorized by this development PR.

The earlier Android branch was manually exercised on an Android 15 ARM64 emulator
through engine load, isolate creation, a Commander prompt and an AI turn. That
artifact predates the merged Deck Studio engine and is not release evidence for
this branch. A fresh Linux ARM64 native build, completed emulator game and separate
physical-phone pass remain required.

Reference documentation:
- https://docs.gluonhq.com/#_android
- https://developer.android.com/training/articles/perf-jni
- https://developer.android.com/guide/practices/page-sizes
