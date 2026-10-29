# TestFlight 0.1.1 (72): every player picks a name first

Uploaded October 29, 2026 and distributed to Internal and External testers (both `IN_BETA_TESTING`). Released with
Android build 50 (`release/RELEASE_ANDROID_0.1.1_BUILD50.md`) and the web deploy `dpl_AtDBL1vsH5YPVLZ619nuX6wL1JYn`, from
PR #267.

## What changed (PR #267)
- **Choose your name:** a profile that is reachable but has no name gets the name screen over the app before the menus,
  new and existing players alike, with Apple and Google sign-in for a profile that already has a name. Offline or with
  the profile server down it never shows. Before, 716 of 720 profiles had no name and showed nowhere.

## Release
- **Source:** `codex/ios-build-72` in `~/Documents/MagicMobile-release-40` = `codex/ios-build-71` + merge of PR #267's
  head, engine package as candidate `a98b4b63` (engine release D, unchanged), `prepare`. Never merge that branch.
- **Run:** `ios-0.1.1-72`, delivery `225e011c…`, VALID about 6 minutes after upload, distributed to both groups.
  Preflight `ios-fast` passed, `equivalent-source`.

## Verification
- iOS app build for the simulator; the web gate in the browser (shows for a fresh guest; a taken name is refused).
- **Not verified on a phone:** the gate itself and a sign-in from it.
