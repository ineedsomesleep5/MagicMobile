# TestFlight 0.1.1 (73): more high-rank decks, awards, updates from the server

Uploaded October 30, 2026 and distributed to Internal and External testers. Released with Android build 51
(`release/RELEASE_ANDROID_0.1.1_BUILD51.md`) and the web deploy `dpl_3CJVv4ErW9UbFukf8hHndMz7MF4Q`, from PRs #270 and #271.

## What changed
- **AI decks (#270):** 14 new decks at Platinum, Diamond and Mythic. Mythic picks among the 5 closest decks, the rest among 3.
- **AI decks from the server (#270):** a newer deck file is downloaded and used from the next launch, so decks and ratings change without a build (`docs/SERVER_CONTROLS.md`).
- **Awards (#271):** medals on your profile and on public profiles, a ceremony for a new one, art by URL. Awards and their rules live on the server.

## Release
- **Source:** `codex/ios-build-73` in `~/Documents/MagicMobile-release-40` = #271's head `304c83bb` + merge of `codex/ios-build-72`, `prepare`, xcodegen. Engine package identical to candidate `a98b4b63` (engine release D, unchanged).
- **Run:** `ios-0.1.1-73b`, fingerprint `3e2208be…`, delivery `e140e5b6…`, VALID about 9 minutes after upload. Preflight `ios-fast` passed, `equivalent-source`. Run `ios-0.1.1-73` failed before reaching Apple: Xcode had updated to 27.2 that morning, which needs the Metal Toolchain installed again.
- **Built with:** Xcode 27.2, iOS 27.2 SDK.

## Verification
- CI on #270 and #271 (`swift` 820 tests, `app`, `real-jvm`, web). A rolled-back dry run of the awards migration on the live database.
- The award card and ceremony seen on the web build; iOS covered by type-checks and unit tests.
- **Not verified on a phone:** the award ceremony, the medals loading, and a deck file downloading (the first publish is revision 2).
