# iOS 0.1.1 build 48: engine release C (lighter engine)

Apple reports build `3227e75c-22e4-4dfd-919e-181529247b67` as `VALID` with Internal `IN_BETA_TESTING` on October 18,
2026. External not submitted yet (Caleb plays it first). New native engine from candidate `codex/native-build-c` =
`21a82eb7`, together with Android build 31 (`release/RELEASE_ANDROID_0.1.1_BUILD31.md`). Engine identity
`sha256:9f06efbe5487c5b29cf62e00f10a937eec06abb114540f1a08c060c0e5f0906f`, registered in `ranked_engine_builds` before
upload (the R2 engine stays listed for older builds). Tables seat only builds on this engine (Android 31).

## Changes (docs/LIGHTER_ENGINE_PLAN.md step 3)
- #199 size cuts: sets from a set catalogue instead of set classes; H2/ORMLite JDBC, protobuf and TLS out of the native
  image. Locale data kept (Caleb's decision: no formatting risk on non-English phones).
- #202 AI search memory: a live game-copy cap scaled to free memory, cards copied on first use, library searches one
  target at a time, copies freed after each decision.
- #205 abandoned or capped AI searches stop at their next copy; the cap counts every search and trigger fan-outs.
- #197 shorter AI thinking while the phone is hot (`devicePace`), unranked games the engine runs on this phone.
- #198 profiling tools (`profile_long_games.py`, `LongGameProfile.java`).

## Measured
- Android native (same engine source): `libmmengine.so` 354.0 → 316.0 MB, code 191.1 → 162.4 MB (set classes
  27.7 → 11.5 MB, H2 and protobuf gone), image heap 167.8 → 156.7 MB; APK 143.3 → 133.9 MB.
- JVM (PRs): AI CPU per search step about halved, one search copy 1.9 → 0.55 MB, peak search memory about 520 → 320 MB,
  0 of 640 calibration games out of memory (was 2), win rates unchanged (per skill and per deck).

## Release
- **Engine:** gate `magicmobile-issue4-nonsimulator.yml` run 39148288419; far-calls 39168216580 (run 39150395010 built
  but GitHub's runner hung after its uploads until the 3 h limit; its rerun left two artifacts, which stage-native refuses,
  so a fresh run was used). Staged with `controller.py stage-native`; the build-40 engine is kept in
  `packages/ondevice-engine/build/NativeEngine-build40-160e250` in the release worktree.
- **Source:** `codex/ios-build-48` at `7b226336`. Preflight native decision `equivalent-source` (`21a82eb7`). Xcode 27.1.
- **Run:** `ios-0.1.1-48`, fingerprint `46a429d5…`, delivery `3227e75c-22e4-4dfd-919e-181529247b67`, IPA `52d27dd4…`.

## Verification
- Preflight `ios-fast`: 14/14. Gate jobs (portable contracts, provenance, Apple source and SDK, compiler inspection,
  real JVM) passed; far-calls built and verified the ARM64 engine.
- Android 31 on the same engine source: 6/6 emulator device tests, game record engine identity `sha256:9f06efbe…`.
- **Still to check on Caleb's iPhone:** the engine reads free memory (`os_proc_available_memory`), a long AI game's
  Game Performance report against build 47, and that saves from older builds are refused (new engine identity).
