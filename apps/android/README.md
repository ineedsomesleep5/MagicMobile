# MagicMobile for Android

Android development is isolated in `codex/android-native-xmage`, based on main
`1f7bd7213875f181d35bac5d88b97b2cb2f76634`. The iOS app and Deck Studio PR #10 are not
modified or merged by this work.

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

## Delivery boundary

This is an implementation-in-progress checkpoint, not a working APK claim.
The Linux Graal distribution is being inventoried before its checksum is pinned
and executable build steps are enabled. Subsequent commits add the Android app,
JNI binding, full-engine build, test and packaging evidence.

A JVM test, an ARM64 library, an APK build and an Android-phone gameplay result
are separate evidence categories. Neither the iOS binary nor an empty Android
screen establishes Android engine execution. No store upload or production
signing is authorized by this development PR.

Reference documentation:
- https://docs.gluonhq.com/#_android
- https://developer.android.com/training/articles/perf-jni
- https://developer.android.com/guide/practices/page-sizes
