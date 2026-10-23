# iOS 0.1.1 build 59: deck sync (internal + external)

Apple reports build `4a3d8511-c85b-4b71-960d-b38f5059c17a` as `VALID` on October 23, 2026. It went to the Internal and
External groups and both read `IN_BETA_TESTING` (Beta App Review approved it at once). Same native engine as builds 48–58
(release C, `21a82eb7`). Android build 36 shipped the same change the same day.

## Changes since build 58
- **Deck sync** (docs/DECK_SYNC.md): your saved decks follow your profile to every phone and to the web app. The phone
  syncs after sign-in, a few seconds after a change, every five minutes while open and on returning to the app. If two
  devices changed the same deck, the server's copy keeps the deck and this phone's edit is kept as "<name> (this
  device)"; a deck deleted on one device leaves the others. Server: `supabase/migrations/20261023120000_deck_sync.sql`,
  applied to the live project the same day.
- The source also carries the web app's phases 1–5 (PR #230); none of that changes the iPhone app beyond deck sync.

## Release
- **Source:** `codex/ios-build-59` at `5f4c9106`: `claude/web-arena-v2` (`18efd9dc`, main `2162a55e` plus PR #230) and
  the build-number prepare. Preflight `ios-fast` 14/14, native decision `equivalent-source`
  (`prepare_ios_app_native.py --verify-installed` exit 0), in the `MagicMobile-release-40` worktree. Xcode 27.1.
- **Run:** `ios-0.1.1-59`, fingerprint `7a55f73b…`, delivery `4a3d8511…`, IPA `f37992e8…`. VALID within a few minutes of
  the upload; the second resume added the groups.

## Verification
- **Deck sync logic:** `swift test --package-path apps/ios --filter DeckSyncTests` (all 12 cases of
  parity/deck-sync-cases.json plus 8), the whole package (775 tests), and `build-for-testing` for the simulator SDK.
- **Server functions:** exercised as a signed-in player in rolled-back transactions; the web client synced two browsers
  signed in to the same profile both ways on the live server.
- **Not verified:** deck sync on a physical iPhone, the full iOS UI suite (not run locally) and a simulator run of this
  build.
