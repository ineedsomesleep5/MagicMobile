# iOS 0.1.1 build 39: fair, friendlier ranked and smart pass v2 (Release 1 of the improvement program)

Apple reports build `bf686669-ac08-4bb8-b050-74a5a7219ae0` as `VALID`, with Internal and External both `IN_BETA_TESTING`
and Beta App Review `APPROVED`, on October 15, 2026. The External invitation remains
https://testflight.apple.com/join/2mSHE8rZ. The engine and catalogue are the same XMage `dac400b` build as builds 34–38,
so tables still seat Android build 23. Caleb chose to test from TestFlight instead of a direct install.

## Changes (docs/GAME_IMPROVEMENT_PROGRAM.md, Phases 0 and 1)
- #153 smart pass v2: long-press Pass for full control this turn, and auto-pass lines in the game log.
- #152 the server keeps ranked score; #165 and #168 ladder option B (Arena steps and tier floors) and server-side rank
  history; #169 Bronze faces the three gentlest precons.
- #155 privacy manifest reasons, #156 and #158 size trims, #159 photo import removed, #157 audit report.
- Live on the server before or with this build: `ranked_referee`, `ranked_record_points`, `ladder_option_b`.

## Release
- **Source:** `codex/ios-build-39` at `08c93d2` (main `c89bafc` + build number 39). Engine unchanged and staged from
  `verified-native-11516701556`; preflight native decision `equivalent-source`. Xcode 27.0 (27A266a).
- **Run:** `ios-0.1.1-39`, fingerprint `cc3a9dcb…`, delivery `bf686669-ac08-4bb8-b050-74a5a7219ae0`, IPA `77f9bd37…`.

## Verification
- Preflight `ios-fast`: 14/14 on the final source.
- `swift test --package-path apps/ios`: 685 tests, 0 failures, on main before the release. Every feature PR passed CI.
- **Not run for this build:** the UI test suites and a physical iPhone. Caleb tests from TestFlight.
