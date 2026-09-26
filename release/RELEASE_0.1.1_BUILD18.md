# iOS 0.1.1 build 18: cross-play tables, playtest fixes, Xcode 27

Apple reports build `5c8c7de2-d217-4fdc-b5cf-f762f1fe7cfc` as `VALID`, with Beta App Review `APPROVED`, in the Internal (all builds) and External (added) groups, on September 26, 2026 UTC. It is the first build made with Xcode 27 and the iOS 27 SDK. The External invitation remains https://testflight.apple.com/join/2mSHE8rZ. None of this proves a completed game on a physical phone or a live iPhone–Android match.

## Changes

These come from [PR #51](https://github.com/ineedsomesleep5/MagicMobile/pull/51). It integrates Caleb's 4-player playtest fixes, the multiplayer work and the iOS 27 fixes. Android build 9 ships the same changes.

- **iPhone and Android at one table.** Online (a table code) lets iPhone and Android players host or join the same match through the relay. Game Center stays for iPhone-only games; the picker reads AI · Game Center · Online.
- **The board follows the game (#41).**
  - At each turn start the top of the board shows the active player.
  - A tapped opponent stays until the next turn.
  - A pending prompt defers the switch.
  - Follow Turns (in the game settings, on by default) controls it.
  - A spectator's bottom seat goes to the next living player, with their hand shown only as a count.
  - "Starting the game" replaces "Waiting on Waiting".
- **Cards (#43):**
  - Copy tokens draw as their own card frame, with a "Token copy" tag.
  - The held inspector fits all the rules text without scrolling.
  - The ability banner sits below the card.
- **Combat clarity (#46):**
  - Attackers and blockers show keyword badges, including gained keywords such as Atarka's double strike.
  - First-strike damage plays as its own beat.
  - The log explains deaths from first strike.
- **Crowded rows and About (#45):**
  - Clipped battlefield rows fade and show "+N".
  - Updates → About credits Scryfall and carries the fan-content notice.
- **Multiplayer (#42):**
  - Guests retry a slow host ("Waiting for <host>…").
  - Hosts send revision notices instead of guests polling every 300 ms.
  - MetricKit crash and hang summaries are kept locally in the diagnostics export.
- **iOS 27 (#49):** card choices are one accessibility element each, which fixes VoiceOver and taps on iOS 27.
- **Versions:**
  - marketing 0.1.1, build 18, identity `com.calebfeliciano.magicmobile`
  - XMage `4825513287ba6c42c32fd205d227f4a5fc44c2f3`, unchanged

## Verification

- Signed source: `8672b23508c60df77891fd5f835e82077af02050`, which is `main` at PR #51's merge (`1a62733`) plus the build-18 number bump.
- `ios-fast` preflight on that source: 11/11 checks. The native decision is `equivalent-source`.
- Native engine: the build 17 engine is reused (artifact `10838134036`, engine commit `fb0ea18`). Staged `libmmengine.a` SHA-256: `7216a2129011914ef224bac2772662c22cc87cbb261a545c969b633e8c4a892e`. The engine source is unchanged, so no rebuild was needed.
- Integration branch, on the iOS 27.0 simulator with Xcode 27:
  - `MagicMobileTests`: 774 run, 0 failures, 5 skipped
  - `swift test`: 505 tests
  - the Metal shaders compile into `default.metallib`
  - the board UI tests from #49 pass
- CI on #51 was green: app, swift, real-jvm, boundary tests, relay and the download site. The swift job's type-check timeout on an older toolchain was fixed in `e78fcf0`.
- The relay fix (#39) is deployed (version `905960a4-16ae-4f18-b978-e6e0567f9f6f`). All 6 relay tests pass against the live Worker.
- Not verified:
  - a game on a physical iPhone
  - a live iPhone–Android match: this 8 GB Mac can't run the emulator and a simulator together; it passed over the production relay during the #38 work
  - the setup UI-test updates in #53, which came after this build and are test-only apart from one identifier

## Signed artifact and Apple distribution

- Release controller run `ios-0.1.1-18`, fingerprint `a13f9376d41ad54dda33bd2af84e4b22aaa1037c0310040ce7829973c3e10e4e`, state `completed`.
- Toolchain: Xcode 27.0 (`27A266a`) with its Metal Toolchain, SDK `iphoneos27.0`, minimum iOS 17.0.
- IPA SHA-256 `b7da40512b4552f5f19f821a73a859eb5b1666825bebe9b63ff4ddb887faf6e5` (194,987,377 bytes).
- Delivery UUID `5c8c7de2-d217-4fdc-b5cf-f762f1fe7cfc`: "UPLOAD SUCCEEDED with no errors". Apple processing `VALID`; the build expires 2026-12-25.
- Groups: Internal `dd37d7bb-26d8-4a0c-b8a3-7811d648a699` (all builds) and External `72b71a7a-bf62-43b5-8eda-b12a62e5c3eb` (added).
- Beta App Review: `APPROVED`.

## Same day

- Android build 9 (versionCode `2026092601`) is published at https://github.com/ineedsomesleep5/MagicMobile/releases/tag/android-v0.1.1-build.9.
  - APK SHA-256 `5b9320f25ff1950bd01058b45c867bc65692b735ccc85aa07485d2539d1a10ab`, with signer `b10ca2cd…d4bb` unchanged.
  - On the emulator it updated build 8 in place and passed its 5 packaged-engine device tests.
- The download site links both builds.
