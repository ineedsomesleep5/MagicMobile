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
Native local Commander against AI, Deck Studio, deck imports and analysis. Android is an alpha with physical-phone acceptance pending and no process-death live-game resume. iOS build 11 fixes the solo AI D20 startup flow and includes Game Center multiplayer for 2–4 seats with human players and AI opponents, a shared animated D20 starting roll, and cancellable skip actions. Physical two-device acceptance remains pending.

## Brand Commitments
MagicMobile's existing identity and imagery. User requests a minimal, polished interactive site, motion design, and a floating 3D Magic card such as Black Lotus.

## Evidence on Hand
Signed Android GitHub prerelease and acceptance receipt. iOS build 11 distribution evidence is recorded in `../../release/RELEASE_0.1.1_BUILD11.md`. Actual application screenshots will be labeled by platform.

## Verified distribution
On September 23, 2026 UTC, App Store Connect confirmed iOS version 0.1.1 build 11 as VALID, with Beta App Review APPROVED and both Internal and External groups IN_BETA_TESTING. The External group uses public invitation https://testflight.apple.com/join/2mSHE8rZ. This confirms distribution, not physical-iPhone gameplay acceptance; see `../../release/RELEASE_0.1.1_BUILD11.md`.

Android uses the public GitHub release `android-v0.2.0-alpha.1`, with the signed `MagicMobile-Android-0.2.0-alpha.1.apk` asset. Links were checked against their public destinations; no sign-in is required for the APK.

## Open Decisions
None for the download destinations. Production is published at https://magicmobile-downloads.vercel.app. Release version and build metadata are maintained with the download URLs in `src/releases.ts`.
