# iOS 0.1.1 build 35: keep your profile with Sign in with Apple or Google

Apple reports build `cb47771b-d88d-4010-85f7-13d75678e086` as `VALID` and assigned to the Internal and External groups,
with Beta App Review `APPROVED`, on October 8, 2026. The External invitation remains
https://testflight.apple.com/join/2mSHE8rZ. It shipped together with Android build 20, on the same XMage `dac400b` engine
and catalogue as build 34, so tables still seat both platforms. None of this proves anything on a physical iPhone or iPad.

## Changes ([#129](https://github.com/ineedsomesleep5/MagicMobile/pull/129))
- **Keep your profile** card on the Profile screen (Walnut Tavern leather card):
  - Continue with Apple (`ASAuthorizationController`).
  - Continue with Google (`ASWebAuthenticationSession`, PKCE, the iOS OAuth client, no Google SDK).
  - Signed in, the card shows the provider and email, with Sign Out.
- **Server:** Supabase ID-token sign-in with a hashed nonce.
  - The first sign-in links the identity to the phone's anonymous account, so the name, friends and rank stay.
  - `identity_already_exists` switches the phone to the profile that identity already has.
  - Sign out starts a fresh anonymous profile.
- **Entitlement:** `com.apple.developer.applesignin` (App Store guideline 4.8). Automatic signing added the capability,
  and the signed IPA carries it.
- **Backend (October 8):**
  - Supabase Auth: Google enabled with MagicMobile's web, iOS and Android client IDs; Apple enabled with the bundle ID.
    Manual linking and anonymous sign-ins are on.
  - The Google consent screen was published to production by Caleb.
- **CI:** the page-curl shader is left out of the SwiftPM checks, because the Xcode 27 runner has no Metal toolchain.
- **Data:** at Caleb's request, the anonymous profiles `Bebo` and `254DADDY` were deleted so those names can be claimed
  again. A backup is in `~/Documents/MagicMobile-releases/backups/profiles-reset-2026-10-08.json`. `Caleb` was kept.

## Verification
- **Signed source:** `codex/ios-build-35` at `6e20ea6`, which is `codex/account-sign-in` at `1a35978` plus the build-35
  bump. The base is main `21ae85e`, with the build-34 records.
- **Engine:** unchanged from build 34. The staged dac400b engine was reused in the same worktree, and
  `prepare_ios_app_native.py --verify-installed` passed.
- **`ios-fast` preflight:** passed, 14 checks.
- **Tests:**
  - SwiftPM `TableChatTests` 7/7, including identity parsing and the shared message codes.
  - New UI test `testAccountCardOffersAppleAndGoogleThenShowsTheAccount` passed, signed out and signed in, plus
    `testPrivacySettingOnTheOwnProfile`.
  - The iOS simulator build passed.
- **Run:** `ios-0.1.1-35`, fingerprint `ac0752ad…e081`, IPA SHA-256 `a5904fc3…6bfb5`, delivery `cb47771b…`, Xcode 27.0.
- **Not verified:**
  - a real Apple or Google sign-in on a physical iPhone;
  - linking the existing `Caleb` profile to Google.
