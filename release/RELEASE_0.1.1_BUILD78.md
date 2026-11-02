# TestFlight 0.1.1 (78): painted coins for the older trophies

Uploaded November 1, 2026 and distributed to Internal and External testers, from PR #284. Released with Android build 55
(`release/RELEASE_ANDROID_0.1.1_BUILD55.md`) and web deploy `dpl_DMg1PSFcebdknzpb3kxyTKnzD3BJ`.

## What changed
- **Trophies:** the 13 built-in coins load painted art from `design/awards/classic-<id>.png` on `main`, in colour when earned and dark when not. The brass coin shows until the art loads, or if it can't. Replacing a file changes the art with no build (`docs/SERVER_CONTROLS.md`).

## Release
- **Source:** `codex/ios-build-78` in `~/Documents/MagicMobile-release-40` = PR head `5475f449` + `prepare` + xcodegen. No engine change: build 74's engine stays staged.
- **Run:** `ios-0.1.1-78`, fingerprint `95653570…`, delivery `48ce119b…`, VALID about 6 minutes after the upload finished. Preflight `ios-fast` passed, equivalent-source.
- **Built with:** Xcode 27.2, iOS 27.2 SDK.

## Verification
- iOS: `swift test` (825) and the UI harness build. CI on #284 passed.
- All 13 art URLs answered 200 after the merge.
- **Seen on the simulator:** the shelf with the fixture account, all 13 painted coins loaded from `main`, earned ones in colour and locked ones dark, beside the server trophies.
- **Seen on the live web app:** all 13 coins loaded, on a page with no profile, so all dark.
- **Not verified on a phone**, and an earned coin hasn't been seen on Android or the web.
