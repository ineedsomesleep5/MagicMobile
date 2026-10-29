# TestFlight 0.1.1 (70): your own card art is the whole card and follows you to every device

Uploaded October 28, 2026 and distributed to Internal and External testers (both `IN_BETA_TESTING`). Released with
Android build 48 (`release/RELEASE_ANDROID_0.1.1_BUILD48.md`) and the web deploy `dpl_GSZWY2db6RJecifRGAnZ8ffFR5sA`, from
PR #263 (`claude/card-art-full-sync`).

## What changed (PR #263)
- **Whole card:** "Use my own picture" now makes the picture the card's whole face everywhere (board, hand, deck pages,
  inspect), so a picture that is itself a card (Caleb's Gojo version of Zur the Enchanter) shows as itself instead of
  inside the printed card's art box. The art crop comes from the picture's art box. Opponents see the usual art.
- **Sync:** pictures follow the profile to every phone and browser signed in to it (docs/CARD_ART_SYNC.md): a private
  Supabase Storage folder per player plus the `card_art` change list (`mm_card_art_since` / `mm_card_art_set`, migration
  `20261028180000_card_art_sync.sql`, live since October 28). One card key everywhere: the front face, lower case.
- **News:** the "Your own card art" entry says the picture becomes the whole card and follows you to every device.
- Pictures chosen in builds 67–69 stay on the phone but don't sync until chosen again (those builds kept no index).

## Release
- **Source:** `codex/ios-build-70` in `~/Documents/MagicMobile-release-40` = `codex/ios-build-69` + merge of PR #263's
  head + `prepare`, project generated from `native-engine.yml`. Never merge that branch.
- **Engine:** release C, unchanged; preflight `ios-fast` passed, `equivalent-source`.
- **Run:** `ios-0.1.1-70`, fingerprint `5ea316cf…`, delivery `88af0b72…`, VALID about 10 minutes after upload, then
  distributed to both groups. Uploaded from PR #263's head before its merge (CI green).

## Verification
- Shared sync cases (`parity/card-art-sync-cases.json`, 11) on iOS (`CardArtSyncTests`), Android (`CardArtSyncTest`) and
  the web; iOS `CardArtChoicesTests` checks the picture covers the whole card; CI on #263.
- Live server with two throwaway anonymous users: upload, set, list, download, the other player refused, removal.
- Web app on localhost: a full-card test picture covered the whole card, uploaded, came back after the browser's copy
  was wiped, and its removal synced and deleted the file.
- **Not verified on a phone:** a picture syncing between a phone and the web.
