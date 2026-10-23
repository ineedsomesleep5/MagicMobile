# iOS 0.1.1 build 58: Arena is the default board (internal + external)

Apple reports build `615c78c6-f961-4194-b788-16034d660781` as `VALID` on October 23, 2026. It went to the Internal and
External groups, and Beta App Review approved it at once. Same native engine as builds 48–57 (release C, `21a82eb7`).
The source is main after PR #228. Android build 35 shipped the same change the same day.

## Changes since build 57
- **Arena is the default board** (Caleb: "arena should be the default across all", in and out of game). The menus were
  already Arena. Now a game opens on the Arena board unless the player picked Hearth, and Arena is listed first in the
  Table picker. Hearth stays as the classic mode in Options.
- **Landscape gear:** moved 3 pt down so its 44 pt touch target stays on screen on a 402 pt tall phone.
- **Tests:** UI tests written against the Hearth board now pin `-magicmobile.boardMode hearth`;
  `testTheArenaBoardIsTheDefault` checks the default.

## Release
- **Source:** `codex/ios-build-58` at `d30f9c71`: main `02c4d79d` plus the build-number prepare. Preflight
  `ios-fast` passed, native decision `equivalent-source` (`prepare_ios_app_native.py --verify-installed` exit 0).
  Xcode 27.1.
- **Run:** `ios-0.1.1-58`, fingerprint `ab024a14…`, delivery `615c78c6…`. VALID about 8 minutes after the upload;
  the second resume added the External group.

## Verification
- **Simulator (iPhone 17 Pro):** `presentation-smoke` 5/5 (the ProfileHistory test needed a rerun, a known flake),
  `testTheArenaBoardIsTheDefault`, `testArenaBoardKeepsItsControlsInBothOrientations`, `ArenaBoardModelTests` 34/34.
- **PR #228 CI:** swift, real-jvm, boundary-tests and app all passed.
- **Not verified:** the full iOS UI suite, which isn't run locally, and a physical phone.
