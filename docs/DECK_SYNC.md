# Deck sync

Your saved decks on every phone and browser signed in to the same profile. iOS, Android and the web follow these rules
exactly; `apps/android/core/src/test/resources/parity/deck-sync-cases.json` holds the shared cases.

## Server (`supabase/migrations/20261023120000_deck_sync.sql`)

A deck travels as one document in the phones' `decks.json` record shape: `{format, commander?, entries, source}` with
rows `{cardName, quantity, section, setCode?, collectorNumber?}` and `source: {kind, url?}`. The name travels beside it.
The server keeps a revision per deck (1 on creation, +1 on every change), a tombstone for deletions (the id stays) and a
change sequence for pulling.

| Function | Answer |
|---|---|
| `mm_decks_since(p_cursor)` | `{decks: [view], cursor, more}`: every change after `cursor` (0 for all), oldest first, at most 200; ask again while `more` |
| `mm_deck_save(p_id, p_name, p_deck, p_base)` | `{status: "saved" \| "conflict", deck: view}`. `p_base` null creates `p_id`; otherwise it must equal the server's revision. A stale base, an existing id with a null base, or a deleted deck is a `conflict` with the server's copy |
| `mm_deck_delete(p_id, p_base)` | `{status: "deleted" \| "conflict", deck?: view}`. Gone already is `deleted`; a stale base is a `conflict` |

A view is `{id, name, revision, changeSeq, updatedAt, deleted, deck}` (`deck` null when deleted). Errors:
`invalid_deck` (the phones' validateDraft limits: name 1–512 bytes, rows with a name and section of at most 2,000 bytes
and 1–2,000 copies, at most 2,000 cards, at most 1 MiB), `not_found`, `too_many_decks` (1,000 live decks).

## Client

Each device keeps, beside its library, a sync record: the profile it synced with (`account`), the pull `cursor`, per
deck id (compared case-insensitively; the server answers lower case) the server revision it last saw (`serverRevision`)
and the local revision that matched it (`syncedLocalRevision`), and tombstones for decks deleted here that the server
still has (`{id, serverRevision}`).

A local deck is **dirty** when it has no sync entry or its revision differs from `syncedLocalRevision`.

One sync, run after sign-in, when the library changes (a few seconds after the last change) and every few minutes while
the app is open:

1. **Another profile.** If `account` isn't the signed-in profile, the record starts over (cursor 0, no entries, no
   tombstones), so every deck on this device is dirty and joins the profile. Nothing local is deleted.
2. **Pull** every change since the cursor (repeat while `more`), applying each server deck `s` in order:
   - a tombstone for that id: if `s` is deleted, drop the tombstone; if `s.revision` equals the tombstone's, skip (this
     device's delete follows); otherwise drop the tombstone and apply `s` as below (someone changed it meanwhile: it
     comes back).
   - a local deck whose name and document already equal `s`'s: record the entry (it is clean; a save whose answer was
     lost ends here).
   - no local deck with that id: if `s` is live, add it (its local revision is whatever the library gives a new or
     updated record) and record `{serverRevision: s.revision, syncedLocalRevision: local.revision}`; if deleted, skip.
   - a clean local deck: if `s` is deleted, remove it locally and drop its entry (no tombstone). If live and its name or
     document differs, replace the local deck with it; then record the entry.
   - a dirty local deck whose entry already has `serverRevision == s.revision`: nothing (this device's push follows).
   - otherwise a dirty local deck that the server changed or deleted meanwhile: **fork** it (below), then apply `s` as for
     a clean deck.
   Then store the returned cursor.
3. **Push deletions.** For each tombstone, `mm_deck_delete(id, serverRevision)`: `deleted` drops it; `conflict` drops it
   and applies the server's copy as a pull would (the deck comes back: someone changed it meanwhile).
4. **Push changes.** For each dirty local deck, `mm_deck_save(id, name, document, entry?.serverRevision ?? null)`:
   `saved` records `{serverRevision: deck.revision, syncedLocalRevision: local.revision}`; `conflict` with a copy equal to
   the local deck records the entry; any other `conflict` forks the local deck and applies the server's copy. A fork is itself dirty and is pushed in the same pass. At most 3 passes.
5. **Pull** once more, so the cursor moves past this device's own changes (each is clean and identical, so nothing
   changes locally).

**Fork:** the local deck's content is saved as a new local deck with a new id, named `<name> (this device)` (cut to
512 bytes), with no sync entry, so it is pushed as new. The original id then takes the server's copy, or is removed
when the server's copy is deleted. No edit is ever lost; the player sees both and deletes the one they don't want.

**Deleting a deck here:** when it has a sync entry, add a tombstone `{id, serverRevision}` and drop the entry; a deck
never synced needs none.

**Signing out** keeps the library and the sync record; signing in to the same profile again resumes from the cursor.

The chosen deck (`local:<id>`), favourites and remembered colours follow the id, which never changes for a deck that
syncs; a fork is a new deck.

Errors other than `conflict` stop the sync quietly and it runs again later; a deck the server refuses as `invalid_deck`
stays local and is skipped until it changes.
