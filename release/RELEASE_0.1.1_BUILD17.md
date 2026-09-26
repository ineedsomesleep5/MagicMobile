# iOS 0.1.1 build 17 — board FX build 19 (recorded audio, concede, next-level pass)

Apple reports build `1c01fc86-35b3-4b1b-95d2-b1090bdc7dab` as `VALID` with Beta App Review `APPROVED`, in the Internal (all builds) and External (added) groups, on September 25, 2026 UTC. The External invitation remains https://testflight.apple.com/join/2mSHE8rZ. These states do not prove a completed physical-phone game, the audio mix on device, or two-phone concede and quick chat.

## Changes

These come from [PR #35](https://github.com/ineedsomesleep5/MagicMobile/pull/35): Caleb's notes on build 16, plus the "next level" list he approved.

- **Audio:**
  - Every cue is now a professional recording: Sonniss GDC bundles (royalty-free) and Kenney CC0 card foley. The synthesized music and magic layers are gone.
  - Music is Kevin MacLeod (CC BY): four lobby and four table tracks, played whole as a playlist. Victory, defeat and the versus reveal use orchestral stingers.
  - Removed the chatty cues:
    - button clicks on ordinary presses
    - mana taps
    - stack resolves
    - the opponent's turn bell
    - the hand fan
  - Only your own abilities chime, and opponents' casts sit lower in the mix.
  - **Sound Lab** (Settings → Sound Lab):
    - auditions every cue
    - switches groups off
    - picks lobby and table tracks
    - shows the required credits
  - A music level of zero reads as off.
- **Concede:** from the game menu, with a confirmation.
  - The engine's new `concede` operation runs XMage's own concede. Game Center guests relay it through the host router.
  - In a pod, a player who concedes or is eliminated gets a spectator bar and can keep watching.
- **Attachments:**
  - Auras and Equipment tuck behind their creature with named tabs.
  - The held inspector lists each attachment's rules text and names what an Aura is attached to.
  - Trigger doublers such as Roaming Throne get a rules note.
- **Portraits:**
  - Opponents show commander art, with a gold ring on their turn and a spinning ring plus "… is thinking" while the AI decides.
  - A player who is out shows a skull.
  - This works in portrait and landscape.
- **Opening hand:** an Arena-style screen for XMage's mulligan question.
- **Result summary:** turns, combat damage from unblocked attackers, creatures destroyed and the top attacker.
- **Quick chat:** tap your life orb.
  - Fixed emotes only, never free text.
  - AI opponents sometimes reply.
  - Game Center relays them peer to peer, rate-limited.
- **Combat feel:** hits of 5 or more shake the board harder, flash a red edge and show a larger life number.
- **Deck Studio:** covers show the commander and deck colors when art isn't downloaded.
- **Fixes:**
  - The game menu's Done button is themed.
  - Disabled compact buttons look disabled.
  - The landscape priority help line no longer overflows the dock.
- **Versions:**
  - Marketing version stays `0.1.1`. Build `17` was prepared with `scripts/ios/testflight-build-number.mjs`. Android is unchanged.
  - Built with Xcode 26.6 (iOS 26.5 SDK) at Caleb's request, while this Mac waits for macOS 26.6+ to install Xcode 27. An iOS 27 SDK build follows once Xcode 27 is installed.

## Verification

- Signed source: `153fb826adfc9a037624d72d9074959941c1ad71`. That is PR #35's head `6c2522b` (CI green, not yet merged) plus the build-17 number bump.
- Real XMage (JVM):
  - `RealConcedeTests` covers a duel at the opening and mid-game, pod spectating, and a second human conceding while the first is asked.
  - All other real suites pass locally and in CI `real-jvm`.
- Core: 427 assertions and the failure-boundary tests. Swift package: 36 tests, including router and client concede.
- MagicMobileTests: 724 run.
  - The new Build19LogicTests pass, along with adapter departure and AI flags, remote concede, and the audio catalogue.
  - The landscape dock assertion that already failed before this build passes after the fix.
- UI tests: Build19FeatureUITests 6/6 (Sound Lab, deck covers, concede confirmation, spectating, opening hand, attachments) and presentation-smoke 5/5.
- `ios-fast` preflight: 11/11. Native decision: `equivalent-source`.
- Native engine (new):
  - Artifact `10838134036` from run [36066265586](https://github.com/ineedsomesleep5/MagicMobile/actions/runs/36066265586), engine commit `fb0ea18`.
  - Staged `libmmengine.a` SHA-256: `7216a2129011914ef224bac2772662c22cc87cbb261a545c969b633e8c4a892e`.
- Release device builds link with Xcode 26.6, and with the Xcode 27 beta as an early check. The Graal far-call layout verifier passes on both.
- Not verified: a native game on a phone, the audio mix on a phone speaker, Game Center concede and quick chat across two phones, and the iOS 27 simulator (it would not boot on this Mac).

## Signed artifact and Apple distribution

- Release controller run `ios-0.1.1-17`, fingerprint `9c275ccf4454e9faddf44084e36df2f27cee5a6dad3ca43d30765890d79505eb`, state `completed`.
- Toolchain: Xcode 26.6 (`17F113`), SDK `iphoneos26.5`, minimum iOS 17.0.
- IPA SHA-256 `c9899d276712529ea8d8d29697c12bb0cc3bb6286aff7b2be3fc9d9189a6b0ee` (194,839,164 bytes); Apple processing state `VALID` after 7m1s.
- Engine archive `7216a2129011914ef224bac2772662c22cc87cbb261a545c969b633e8c4a892e` from artifact `10838134036` (engine commit `fb0ea18`).
- Build ID `1c01fc86-35b3-4b1b-95d2-b1090bdc7dab`.
- Groups: Internal `dd37d7bb-26d8-4a0c-b8a3-7811d648a699` (all builds) and External `72b71a7a-bf62-43b5-8eda-b12a62e5c3eb` (added).
- Beta App Review: `APPROVED`.
