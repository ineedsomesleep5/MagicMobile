# iOS 0.1.1 build 38: smart pass lets effects finish, and no waiting flash

Apple reports build `4e8512c4-4dd0-4c10-a64b-eea507422e4e` as `VALID`, with Internal and External both `IN_BETA_TESTING` and
Beta App Review `APPROVED`, on October 14, 2026 (CDT; October 15 UTC).
The External invitation remains https://testflight.apple.com/join/2mSHE8rZ. The engine and catalogue are the same XMage
`dac400b` build as builds 34–37, so tables still seat Android build 21. None of this proves anything on a physical
iPhone or iPad.

## Changes
- [#148](https://github.com/ineedsomesleep5/MagicMobile/pull/148): two smart auto-pass fixes from Caleb's playtest.
  - Smart pass now waits for the board to finish showing a spell showcase, a showcase arrival, a card leaving play or a
    combat hit before it passes, at most 4 s per prompt. Previously an opponent's Path to Exile resolved, and the turn moved on,
    before its showcase and the exile had played. Ability and trigger resolutions, life, damage and counters never
    hold, so a big trigger stack still resolves at full speed.
  - Automatic passes (smart pass, End Turn, Skip) no longer flash the "Waiting for the table…" pop-up.
  - Android carries the same code; it ships in the next Android build.

## Release
- **Source:** `codex/ios-build-38` at `7273a6b` (the #148 branch + build number 38; identical to main `d6d7a2d` apart
  from the build number). The engine is unchanged and still staged from `verified-native-11516701556`; preflight's
  native decision is `equivalent-source`. Xcode 27.0 (27A266a).
- **Run:** `ios-0.1.1-38`, fingerprint `5d06a96f…`, delivery `4e8512c4-4dd0-4c10-a64b-eea507422e4e`, IPA `6c9ebeba…`.

## Verification
- Preflight `ios-fast`: 14/14 on the final source.
- `swift test --package-path apps/ios`: 675 tests, 0 failures. Android `:core:test` 244 tests, 0 failures, and
  `:app:compileDebugKotlin`. PR CI (app, swift, real-jvm, boundary-tests, site) green.
- Physical iPhone: the first fix (smart pass waits for effects) was installed on Caleb's iPhone 16 Pro Max as a
  Release build, and his playtest found the pop-up flash. The second fix has not been run on a device.
- **Not run for this build:** the UI test suites.
