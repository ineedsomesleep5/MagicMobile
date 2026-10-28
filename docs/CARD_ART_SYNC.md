# Your own card pictures

"Use my own picture" (Deck Studio's artwork picker on iOS and Android, the card inspect on the web) gives a card a
picture of the player's choosing. The picture is the **whole card face** wherever the card shows: board, hand, deck
pages, inspect. It is usually a card of its own, with name, cost, rules and power drawn on it, so nothing of the printed
card shows through. Places that show only a card's art (the art crop) take the picture's art box, the same window
(8% / 14.5% / 84% × 38.5%) a printed card's art crop comes from. A picture that isn't card-shaped keeps its middle.
Opponents always see the card's usual art.

Pictures follow the profile: a picture set on one phone or browser appears on every phone and browser signed in to the
same profile. iOS, Android and the web follow these rules exactly; `apps/android/core/src/test/resources/parity/card-art-sync-cases.json`
holds the shared cases.

Code: iOS `CustomCardArt.swift` and `DeckStudio/Services/CardArtSync.swift`; Android `CustomCardArt.kt` and
`core/.../studio/CardArtSync.kt`; web `ui/customArt.ts` and `core/cardArtSync.ts` (the reference).

## Card key

One picture per card, keyed by the front face's name, trimmed, in lower case (`Delver of Secrets // Insectile
Aberration` → `delver of secrets`). Every platform uses that key with the server.

## Server (`supabase/migrations/20261028180000_card_art_sync.sql`, live 2026-10-28)

- Files: the private Storage bucket `custom-card-art`, at `<user id>/<sha-256 of the JPEG>.jpg`. A changed picture is a
  new file, so no device keeps a stale copy. Only the owner can read, write or delete their folder (four storage
  policies). JPEG only, 2 MiB at most (the apps save at most 1200 px on the long edge, about 150–300 KB).
- `card_art (user_id, card_key, picture, change_seq, updated_at)`: which picture each card wears; `picture` null is a
  removed one (a tombstone). Deleting the account deletes the rows. Its files are not removed with it yet.

| Function | Answer |
|---|---|
| `mm_card_art_since(p_cursor)` | `{arts: [{cardKey, picture, changeSeq}], cursor, more}`: every change after `cursor` (0 for all), oldest first, at most 200; ask again while `more` |
| `mm_card_art_set(p_card_key, p_picture)` | the row as `{cardKey, picture, changeSeq}`. `p_picture` null removes the card's picture. Errors: `invalid_card_art`, `picture_missing` (not uploaded yet), `too_many_pictures` (500 cards) |

Files go up and down through Storage's own API (`storage/v1/object/custom-card-art/<user id>/<hash>.jpg`: PUT with
`x-upsert`, GET, DELETE) with the player's token.

## Client

Each device keeps its pictures (by card key, with an index of keys beside the hashed file names on the phones) and a
sync record: the profile it synced with (`account`), the pull `cursor`, per card the picture the server had when this
device last matched it (`synced`), and removals made here that the server still has (`removed: [{cardKey, picture}]`).

A local picture is **changed here** when its hash differs from `synced[card]`.

One sync, run with deck sync (after sign-in, on coming back to the app, every 5 minutes) and a few seconds after a
picture is set or removed here:

1. **Another profile.** If `account` isn't the signed-in profile, the record starts over, so every picture here joins
   the profile. Nothing local is deleted.
2. **Pull** every change since the cursor (repeat while `more`):
   - a card removed here: if the server's picture is the one removed, skip (the removal follows). Otherwise drop the
     removal; if the server's picture is null, stop; else apply it as below (someone set a new one meanwhile: it comes back).
   - the server's picture is null: remove the local picture unless it changed here; forget `synced[card]`.
   - the local picture is the server's: record it.
   - the local picture changed here: record the server's picture in `synced` and keep the local one (it goes up in 4 and wins).
   - otherwise download the server's picture, store it (not a change made here) and record it.
3. **Push removals:** `mm_card_art_set(card, null)`, drop the removal, and delete its file when no card still points at it.
4. **Push pictures changed here:** upload the file, `mm_card_art_set(card, hash)`, record it, and delete the previous
   file when no card still points at it. A card the server refuses (`invalid_card_art`, `too_many_pictures`, a file too
   large or not a JPEG) stays on this device, its upload is deleted, and it isn't offered again this session unless its
   picture changes. Any other error stops the sync quietly; it runs again later.
5. **Pull** once more, so the cursor moves past this device's own changes.

**Removing a picture here:** delete it locally; if `synced` has the card, move it to `removed`.

**Signing out** keeps the pictures and the record; signing in to the same profile again resumes from the cursor.

Pictures saved by the first builds (TestFlight 67–69, Android 45–47) before the index existed stay on that phone but
don't sync until they are chosen again.
