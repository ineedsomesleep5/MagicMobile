# Pinned deck-analysis input

`role-tags.json` is the reviewed Scryfall oracle-tag snapshot used by the iOS
catalogue exporter. Its source queries, provider and retrieval date are embedded
in the file; `ROLE_TAGS_SHA256` in `scripts/export_ios_catalogue.py` checks its
exact bytes. It is kept in version control so offline and clean-checkout builds
use the same data.

To propose an update, run `scripts/fetch_role_tags.py` (its default destination is
the ignored `build/generated/role-tags.json`). Review the changed roles, copy the
reviewed snapshot here, update the hash, regenerate the catalogue and run the
role tests. Fetching new data is never part of a normal release build.

Source: https://tagger.scryfall.com/ and https://scryfall.com/docs/api
The original snapshot identifies its provider as Scryfall oracle tags, CC-BY.
Roles are advisory; Commander legality and game rules come from pinned XMage.
