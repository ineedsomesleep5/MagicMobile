# MagicMobile download site

<!-- impeccable:product-schema 1 -->

## Platform
web

## Users
Commander players opening a shared link on a phone or computer to discover MagicMobile and install it.

## Product Purpose
Showcase the native apps and provide Android APK and iOS TestFlight downloads. Browser gameplay is a future possibility, not a currently available feature.

## Stack
Delegated implementation choice: standalone React/Vite site with Three.js, deployed to Vercel. The existing web game remains separate.

## Capabilities and Constraints
Native local Commander against AI, Deck Studio, deck imports and analysis. Android is an alpha with physical-phone acceptance pending and no process-death live-game resume. iOS build 9 includes Game Center multiplayer for 2–4 human players. Mixed human/bot games, a shared D20 starting roll and cancellable skip are planned for a future build, not available in build 9.

## Brand Commitments
MagicMobile's existing identity and imagery. User requests a minimal, polished interactive site, motion design, and a floating 3D Magic card such as Black Lotus.

## Evidence on Hand
Signed Android GitHub prerelease and acceptance receipt. iOS build 9 distribution evidence is recorded in `../../docs/RELEASE_0.1.1_BUILD9.md`. Actual application screenshots will be labeled by platform.

## Verified distribution
On September 22, 2026 UTC, App Store Connect confirmed iOS version 0.1.1 build 9 as VALID, with Beta App Review APPROVED and both Internal and External groups IN_BETA_TESTING. The External group uses public invitation https://testflight.apple.com/join/2mSHE8rZ. This confirms distribution, not physical-iPhone gameplay acceptance; see `../../docs/RELEASE_0.1.1_BUILD9.md`.

Android uses the public GitHub release `android-v0.2.0-alpha.1`, with the signed `MagicMobile-Android-0.2.0-alpha.1.apk` asset. Links were checked against their public destinations; no sign-in is required for the APK.

## Open Decisions
None for the download destinations. Production is published at https://magicmobile-downloads.vercel.app. Release version and build metadata are maintained with the download URLs in `src/releases.ts`.
