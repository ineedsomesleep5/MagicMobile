# iOS 0.1.1 build 19: play any deck from Deck Studio, Archidekt-style building

Apple reports build `2e985c85-6b8d-48b8-a7f2-81be660d04bd` as `VALID`, with Beta App Review `APPROVED`, in the Internal (all builds) and External (added) groups, on September 27, 2026 UTC. The External invitation remains https://testflight.apple.com/join/2mSHE8rZ. None of this proves a completed game on a physical phone or a live iPhone–Android match.

## Changes

- **Play this deck ([#65](https://github.com/ineedsomesleep5/MagicMobile/pull/65)).**
  - Choose the playing deck from inside Deck Studio: a deck's ⋯ menu, long press, or the Play button in the workspace header.
  - XMage checks the deck against the Commander rules on the phone, automatically, and the result is stored.
  - Decks show a Playing badge and Ready / Needs fixes / Not checked. A "Now playing" strip opens the playing deck.
  - Fix deck filters the list to the cards XMage named.
  - The setup deck card shows the card count, colors and check status.
  - Sideboard and maybeboard stay out of every game start, including Game Center and Online tables. The old "— Playtest" copies are no longer made.
- **Builder (#65):**
  - a quick-check bar (count toward 100, missing commander, off-color, duplicates, unresolved)
  - Quick Add ("2x Sol Ring", Undo) and commander-first new decks
  - edit as text with a reviewed diff, and Copy list
  - group by role
  - select mode (move, set quantity, remove)
  - a card grid with a long-press preview and actions
  - a sample hand (draw 7, London mulligan)
  - search syntax: `t:`, `o:`, `mv<=`, `mv>=`, `mv=`, `id:`
- **Parity:** the strings and rules match Android build 10 and are pinned for both platforms in `apps/android/core/src/test/resources/parity/deck-studio-cases.json`.
- **Accessibility and a hang fix ([#69](https://github.com/ineedsomesleep5/MagicMobile/pull/69)):**
  - The Deck Studio header is an accessibility container, so the Play button and quick check keep their own identifiers.
  - Scrolling to the end of the portrait Playtest history no longer hangs in a SwiftUI layout loop.
- **Resume, app side ([#63](https://github.com/ineedsomesleep5/MagicMobile/pull/63)), inactive.** The Resume/Abandon flow ships but stays off: this engine doesn't report `saveResume`. What is active:
  - image caches and audio buffers are released in the background
  - "Your last game ended when the app closed." appears after a game dies with the app
- **Online tables ([#48](https://github.com/ineedsomesleep5/MagicMobile/pull/48)):**
  - a host can remove a joiner while the table fills ("At the table")
  - credentials are sent as WebSocket subprotocols instead of URL parameters
  - the relay limits table creation (relay version `c75c7092-0aa1-495b-a421-970a4cb6f95f`)
- **"1 card" ([#56](https://github.com/ineedsomesleep5/MagicMobile/pull/56)):** singular counts, and the unreachable NativeDeckLibraryView removed.
- **Not included:** the save/resume engine ([#64](https://github.com/ineedsomesleep5/MagicMobile/pull/64)). Its first native build failed on GraalVM 22.1's serializable-lambda handling, and the fix (#68) is still being iterated in native CI.
- **Versions:** marketing 0.1.1, build 19, identity `com.calebfeliciano.magicmobile`, XMage `4825513287ba6c42c32fd205d227f4a5fc44c2f3` (unchanged).

## Verification

- **Signed source:** `4c8a933d2f04d515de87baf8b2d0712758413e5e` (`codex/release-build19`). This is `main` at #69 (`511e797`), plus the revert of #64 (`6e6dcda`) and the build-19 number bump.
  - The same bump and the upload ledger reached `main` by cherry-pick; the release branch itself does not merge into `main`.
  - The ledger commit on the release branch is `b0eac93`.
- **`ios-fast` preflight on that source:** passed, 11/11 checks.
- **Native engine:** the build 17 and 18 engine is reused (artifact `10838134036`, engine commit `fb0ea18`).
  - The native decision against `fb0ea18` is `equivalent-source`, with input tree `800b1d52…`, identical to the artifact's receipt.
  - Staged `libmmengine.a` SHA-256: `7216a2129011914ef224bac2772662c22cc87cbb261a545c969b633e8c4a892e`.
- **Simulator (iPhone 17 Pro, iOS 26.5):** 30 UI tests after #69, 0 failures:
  - the Deck Studio release, readability and pinned-tab suites
  - OnDeviceSetup (19 tests)
  - the 4 BoardPolish presentation-smoke tests
- **`swift test`:**
  - `apps/ios`: 566 tests, 5 skipped
  - `packages/ondevice-engine/swift`: 21 XCTest and 43 Swift Testing tests
- **CI:** green on #63, #65 and #69.
- **Not verified:**
  - a game on a physical iPhone
  - a live iPhone–Android match
  - the real XMage deck check running on a phone (the simulator can't run the real engine)

## Signed artifact and Apple distribution

- **Release controller:** run `ios-0.1.1-19`, fingerprint `0ce1c8babd4b987cee1ea90c94e4ea1f7ff786920f3432b10e3e04139bbdc525`, state `completed`.
- **Toolchain:** Xcode 27.0 with its Metal Toolchain, SDK `iphoneos27.0`, minimum iOS 17.0.
- **IPA SHA-256:** `04ad5ceef7b866c9105c6b17577cc69b1b8c03dc24f0e95031d86142a528207d`.
- **Delivery:** UUID `2e985c85-6b8d-48b8-a7f2-81be660d04bd`, uploaded 2026-09-27 06:13 UTC. Apple processing `VALID`; the build expires 2026-12-25.
- **Groups:** Internal `dd37d7bb-26d8-4a0c-b8a3-7811d648a699` (all builds) and External `72b71a7a-bf62-43b5-8eda-b12a62e5c3eb` (added).
- **Beta App Review:** `APPROVED`.

## Same day

- **Android build 10** (versionCode `2026092701`) is published at https://github.com/ineedsomesleep5/MagicMobile/releases/tag/android-v0.1.1-build.10.
  - APK SHA-256: `516746b68a3ddde0c61c8eaa78c2841a7add2c2c40cd958b2e50f5a85129cd33`, with signer `b10ca2cd…d4bb` unchanged.
  - It updated build 9 in place and passed its 6 packaged-engine device tests.
- **The download site** links both builds.
