# iOS 0.1.1 build 47: a cooler board

Apple reports build `6de1933e-5d40-42cd-8052-3f6fddea0881` as `VALID`, with Internal and External both
`IN_BETA_TESTING` and Beta App Review `APPROVED`, on October 18, 2026. The External invitation remains
https://testflight.apple.com/join/2mSHE8rZ. Same native engine as builds 40–46 (main `160e250`), together with Android
build 30 (`release/RELEASE_ANDROID_0.1.1_BUILD30.md`).

## Changes (#201, from the Instruments traces in docs/LIGHTER_ENGINE_PLAN.md step 1)
- Ambient glows share one 30 Hz clock (15 Hz while hot) and rest lit after 15 s with no touch or game change, so the
  board stops redrawing every frame while nothing happens.
- The AI thinking ring turns in Core Animation; the tavern medallion no longer draws the ring it clips away.
- Battlefield row layout and ribbon banner fitting are computed once per change instead of on every read or frame.
- Byte-identical poll replies are not decoded again, and the Deck Studio recorder skips them.

## Release
- **Source:** `codex/ios-build-47` at `9cd3f5ff` (main `3c916f21` + build number 47). Engine staged from build 40;
  preflight native decision `equivalent-source`. Xcode 27.1 (27A9275).
- **Run:** `ios-0.1.1-47`, fingerprint `e60cb891…`, delivery `6de1933e-5d40-42cd-8052-3f6fddea0881`, IPA `2f30675b…`.
  Internal first; External added by the same run's distribution after Caleb said make it public.

## Verification
- Preflight `ios-fast`: 14/14 on the final source. PR #201's CI (swift, real-jvm, Android app, boundary tests) green.
- Simulator before/after (#201): board CPU 14–22% → about 5%, 0.6% once the board rests.
- **Caleb's iPhone (TestFlight 47, Game Performance):** a 15-minute, 15-turn token-heavy game stayed `nominal` with a
  713 MB peak, against 978–1,127 MB peaks and up to `serious` heat in his earlier games on builds 43–46.
- **Not run:** the full UI test suites.
