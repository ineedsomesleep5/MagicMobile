# iOS 0.1.1 build 37: smart auto-pass, the online turn timer, a guided first game and Cormorant SC titles

Apple reports build `5390eee2-1f17-4d1d-9b7d-1da37d36181f` as `VALID`, with Internal and External both in TestFlight and
Beta App Review `APPROVED`, on October 14, 2026 (UTC).
The External invitation remains https://testflight.apple.com/join/2mSHE8rZ. The engine and catalogue are the same XMage
`dac400b` build as builds 34–36, so tables still seat Android build 21. None of this proves anything on a physical
iPhone or iPad.

## Changes
- [#138](https://github.com/ineedsomesleep5/MagicMobile/pull/138): Arena-style smart auto-pass with phase stops.
- [#139](https://github.com/ineedsomesleep5/MagicMobile/pull/139): an online turn timer with a burning rope.
- [#140](https://github.com/ineedsomesleep5/MagicMobile/pull/140): a guided first game with a coach.
- [#144](https://github.com/ineedsomesleep5/MagicMobile/pull/144): the turn timer became a ring around the pass button
  and the opponent's medallion.
- [#137](https://github.com/ineedsomesleep5/MagicMobile/pull/137): the stale Bronze underdog test fix.
- [#145](https://github.com/ineedsomesleep5/MagicMobile/pull/145): Cormorant SC for titles and brand plaques.
- Release branch only: the Xcode project regenerated with XcodeGen. The hand-added entries from #138–#145 listed the
  same files but failed preflight's `generated-project` check.

## Release
- **Source:** `codex/ios-build-37` at `e762568` (main `0d6c5b0` + build number 37 + the regenerated project). The
  engine is unchanged (`packages/ondevice-engine` differs from build 36 only in `docs/PROTOCOL.md`), staged from
  `verified-native-11516701556`. Xcode 27.0 (27A266a).
- **Run:** `ios-0.1.1-37`, fingerprint `ecff1532…`, delivery `5390eee2-1f17-4d1d-9b7d-1da37d36181f`, IPA `7b885dee…`.

## Verification
- Preflight `ios-fast`: 14/14 on the final source.
- The signed IPA contains `CormorantSC-Bold.ttf` (763,124 bytes) and its OFL licence; `UIAppFonts` lists it.
- **Not run for this build:** the full unit and UI test suites locally (each feature PR passed CI), and a physical
  iPhone or iPad.
