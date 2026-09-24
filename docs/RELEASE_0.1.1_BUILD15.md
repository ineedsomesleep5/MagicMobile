# iOS 0.1.1 build 15 — board FX builds 15–17

Apple reports build `6abc846d-105b-42c1-a8c3-b420ae57372f` as `VALID`, with Beta App Review `APPROVED`, on September 24, 2026 UTC. The build is in the Internal group (all builds) and was added to the External group. The External invitation remains https://testflight.apple.com/join/2mSHE8rZ. These states do not prove that a game has been completed on a physical phone.

## Changes

Changes come from [PR #31](https://github.com/ineedsomesleep5/MagicMobile/pull/31) and follow Caleb's device notes on builds 15–16. Builds 15–16 had only been installed directly on his phone.

- **Build 15:**
  - An ability chosen in the app answers XMage's follow-up "choose ability" prompt, so the player is not asked twice.
  - Ability labels are shown in full.
  - The Skip button is steadier.
  - The card inspector shows more detail.
  - Keyword icons appear even when the engine does not send them.
  - The turn bar and life-orb glow were updated.
- **Build 16:**
  - Solo rematch.
  - Quiet Game Center sign-in.
  - Game Center match room.
- **Build 17:**
  - Multi-select choices (discard N, sacrifice N) are answered from one Confirm, and the selection labels were fixed.
  - Play and cast offers carry their ability ID, so modal double-faced, split and adventure cards are asked once.
  - The victory and defeat screen covers the whole screen.
  - Hand and battlefield glows are no longer clipped.
  - The portrait board has a stack tray that groups repeated triggers.
  - Downloaded token art is used when offline.
  - The Downloads check is faster.
  - Idle polling is lighter.
  - The dock's Skip button is a circle.
- **Engine:**
  - The MAD AI passes without a search when it can only pass.
  - While a stack is waiting to resolve, its think time is capped at 2 s (`MobileAICancellation`).
- Marketing version stays `0.1.1`. Build `15` was prepared with `scripts/ios/testflight-build-number.mjs` after build 14. Android is unchanged.

## Verification

- Signed source: `feee7da0dcbaf06ac3dc92f57afdd14ec76a0381`, which is `main` at `9149e9d` plus the build 15 number bump.
- Checks on the build 17 source:
  - `ios-fast` preflight passed 11/11.
  - MagicMobileTests ran 710 tests. One landscape dock-height assertion fails, and it was already failing before this work.
  - UI tests passed: presentation-smoke 5/5 and CardChoiceDraft 5/5.
  - PR #31 CI passed (app, checks, swift, real-jvm, boundary).
- Simulator: the DEBUG previews for the stack tray, victory screen and normal battlefield were checked on an iPhone 17 Pro.
- New native engine:
  - Non-simulator run [36010976739](https://github.com/ineedsomesleep5/MagicMobile/actions/runs/36010976739) passed, including real-jvm.
  - ARM64 native run [36014055598](https://github.com/ineedsomesleep5/MagicMobile/actions/runs/36014055598) passed on attempt 2. Attempt 1 failed because of a transient DNS failure on the runner.
  - Artifact `10818031401` (engine commit `5d2cb18817261c988073dbeb9668a60d5592b765`, ZIP digest `sha256:cb9d797ad35cd9015261ebdb067f22cf5a3cf6f619bef7a8fe12dfeff9f3328a`) was downloaded, hash-checked, provenance-verified and staged.
  - Staged `libmmengine.a` SHA-256: `5a170286e42d693bd3ee3de2a8a7e746fc578005eca8b03ca55158b134ffd076`.
- Not yet verified:
  - The new engine running on a physical phone.
  - The AI's speed on device.
  - A real-engine multi-card discard.

## Signed artifact and Apple distribution

- Release controller run `ios-0.1.1-15`, fingerprint `130ad8aa4e9b1532e940e544dd800c261106f4bd0445099c69185d963f7b9ec8`, state `completed`.
- IPA SHA-256 `2d36d359517d17e6aae605f9ed5f9f4ac5d1e202c7305503ce04d042e38584f3`. Apple processing state is `VALID`.
- Build ID `6abc846d-105b-42c1-a8c3-b420ae57372f`.
- Groups: Internal `dd37d7bb-26d8-4a0c-b8a3-7811d648a699` (all builds) and External `72b71a7a-bf62-43b5-8eda-b12a62e5c3eb` (added).
- Beta App Review `APPROVED`.
