# iOS 0.1.1 build 22: friends, table chat, invite links

Apple reports build `859dbb22-9801-45b3-a4f7-93fe9cf82e58` as `VALID`, with Beta App Review `APPROVED`, in the Internal (all builds) and External (added) groups, on September 28, 2026 UTC. The External invitation remains https://testflight.apple.com/join/2mSHE8rZ. None of this proves anything on a physical iPhone.

## Changes ([#90](https://github.com/ineedsomesleep5/MagicMobile/pull/90))
- **Starting roll and starting player online:**
  - Attaching the session to a table's match no longer resets the roll's "seen" flag. The reset replayed a finished roll.
  - The host's automatic starting-player answer now retries until XMage takes it. Before, it could be dropped while the session was busy, which left "Select a starting player" for the player.
  - The prompt stays hidden while the answer is on its way.
- **Versus intro online:** every seat's name and commander come from the lobby.
- **Table chat:**
  - Typed messages and quick chat in one panel, with an unread badge beside the stack.
  - Mute, block and report.
  - Strong language is masked on display.
  - The relay identity adds `chat-1`, so build 21 and Android build 12 can't sit at these tables.
- **Invite links:**
  - `https://magicmobile-downloads.vercel.app/join/CODE` (Associated Domains) and `magicmobile://join/CODE` join with the chosen deck.
  - The site serves `/join/*` and the AASA file.
- **Instant profiles:**
  - An anonymous Supabase account and a unique player name used at every table.
  - Friends with presence, and one-tap join to a friend's open table.
  - Block, report and account deletion.
  - Migration `social_profiles_friends`; access only through `mm_*` functions.
- **Scryfall live art** is on by default (registered in the app delegate), with a one-time offer to save art for offline play.
- **Privacy manifest** declares User ID and Other User Content (app functionality, linked, no tracking).

## Verification
- **Signed source:** `7076f34` (`codex/ios-build-22`, tag `ios-v0.1.1-build.22`), which is `main` at #90 (`de70d46`) plus the build-22 bump.
- **`ios-fast` preflight:** passed. The native decision is `equivalent-source` with `ad2e8c3`.
- **Engine:** the build 21 engine, re-staged with `prepare_ios_app_native.py` from `verified-native-10945664948`; `libmmengine.a` SHA-256 is `466597b2…9753`, unchanged.
- **Tests:**
  - `swift test` for `apps/ios`: 591 tests, including `TableChatTests` against `chat-cases.json`.
  - Simulator UI tests, 19: the presentation-smoke preset plus the setup, Updates, How to play, Downloads and Build 19 board suites.
    - They caught a launch crash, fixed before release: registering the art default inside the preferences initializer re-entered it through the defaults observer.
- **Android split-screen run** of the same code on the live relay:
  - invite links joined the table;
  - one D20 round, and the roll's winner started with no manual prompt;
  - chat was delivered with masked language.
- **Not verified:**
  - anything on a physical iPhone;
  - universal links on a device;
  - profiles live: anonymous sign-ins are not yet enabled in the Supabase project, and Friends shows "Profiles aren't available right now".

## Signed artifact and Apple distribution
- **Release controller:** run `ios-0.1.1-22-r2`, fingerprint `a90c6a05…71a5`, state `completed`.
  - The first run, `ios-0.1.1-22`, stopped in the TestFlight guard before building: the copied engine manifest pointed at a removed worktree. Nothing was uploaded; that run stays `uncertain`.
- **IPA SHA-256:** `dded0b15284dd1e054425788347c193f711f8106509269764272a2a07453c737` (138,253,815 bytes).
- **Entitlements:** `applinks:magicmobile-downloads.vercel.app` and Game Center.
- **Delivery:** `859dbb22-9801-45b3-a4f7-93fe9cf82e58`, Apple processing `VALID`; the build expires 2026-12-26.
- **Groups:** Internal `dd37d7bb-26d8-4a0c-b8a3-7811d648a699` and External `72b71a7a-bf62-43b5-8eda-b12a62e5c3eb`.
- **Beta App Review:** `APPROVED`.

## Same day
Android build 13 (versionCode `2026092801`) is published at https://github.com/ineedsomesleep5/MagicMobile/releases/tag/android-v0.1.1-build.13.
