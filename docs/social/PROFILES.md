# Profiles, friend search and privacy

Status: built on `codex/polish-social` (from `codex/spellbook`). The server half is a migration that has **not been applied to the
live Supabase project**; both apps work without it and light up the new parts when it is there.

What Caleb asked for (2026-10-06):

- The player's own profile is the home of the game history and analytics: visual first (rings, charts, art), details on tap.
  Deck Studio's Playtest chapter no longer holds the history.
- Friends: type a name and see players as you type, add them easily, open anyone's profile (rank, rank history, games with the
  opponents' names), and let a player choose who can see theirs.
- Profiles are **public by default**; public profiles show **opponents' player names** in the game history.

## Data model

`supabase/migrations/20261007120000_public_profiles.sql` (additive, re-runnable; the three functions it replaces keep their signatures).

| Thing | What |
| --- | --- |
| `profiles.visibility` | `text not null default 'public'` check in `public`, `friends`, `private`. Existing rows become public. |
| `profiles_username_prefix_idx` | `(lower(username) text_pattern_ops) where username is not null`: serves `LIKE 'da%'` (the unique index on `lower(username)` cannot). |
| `player_games` | One row per finished game, as the phone reported it: `user_id`, `client_id` (the phone's `MatchRecord.id`; unique per user, so a game is stored once), `played_at`, `mode` (`quick`/`ranked`/`casual`), `result`, `deck_name`, `commanders` (up to 4), `colors` (W U B R G), `opponents` jsonb (up to 3 of `{name, commander, ai}`), `turns`, `duration_seconds`, `rank_points`. RLS on, no grants. Cascades with the account. |
| rank history | The `rank_points` of a player's ranked games (`ladder step * 4 + pips` after the game), oldest first. There is no separate table: the same row carries the game and the point on the line, and a phone can backfill both. |

Game rows are **self-reported**, like the ranked cards already are. They are for show, not for anything that needs trust.

## RPCs (all `security definer`, `search_path = ''`, revoked from `public` and `anon`, granted to `authenticated`)

| Function | Does |
| --- | --- |
| `mm_set_visibility(p_visibility)` | Sets `public`/`friends`/`private` (needs a username). Error `invalid_visibility`. |
| `mm_profile()` (replaced) | Same as before, plus `visibility`. |
| `mm_search_players(p_prefix)` | Needs a username. Two to twenty letters, digits or underscores, trimmed and case-insensitive, matched at the **start** of the name (an underscore is a letter, not a wildcard); anything else returns nothing. At most 12 rows: the exact name first, then friends, then alphabetical. Never the caller, anyone blocked either way, or a `private` profile. A `friends` profile is found (so a request can be sent) but shows no rank or commander. Columns: `username, favorite_commander, season, rank_step, pips, visibility, relation (friend/outgoing/incoming/none), online` (online for friends only). |
| `mm_record_game(...)` | Called by the phone after a finished game (and for games it could not send before). Validates sizes and ranges, rebuilds `opponents` from known fields only, stores each `(user, client_id)` once (returns `true`; `false` if it was there), allows 100 new games an hour (`too_many_games`) and keeps the newest 500 per player. Errors `invalid_game`, `no_username`. |
| `mm_public_profile(p_username)` | Another player's profile, or the caller's own (`relation: self`). See the wire format below. `not_found` when either side blocked the other. |
| `mm_profile_card`, `mm_friend_ranks` (replaced) | Same results as before, but a profile the caller may not open shows no standing (the card has just the name; the friends' ranks leave out a `private` friend). |
| `mm_can_view_profile(viewer, target)` | Internal (not callable by `authenticated`): the one rule below. |

### Who may open a profile

| Visibility | Owner | Friend | Other signed-in player | Blocked either way |
| --- | --- | --- | --- | --- |
| `public` (default) | yes | yes | yes | not found |
| `friends` | yes | yes | stub: `{username, restricted: true, visibility, relation}` | not found |
| `private` | yes | stub | stub | not found |

Friends still see each other's presence (online, hosted table) whatever the profile setting: that is the friends feature, not the
profile. Block or unfriend to hide it. A stub still lets the viewer send a friend request. Blocking after viewing closes the profile
at once. A human opponent in someone's game history whom the viewer blocked (or who blocked the viewer) reads "Hidden player" and
does not link.

### `mm_public_profile` wire format

```
{ username, restricted, visibility, relation, online (friends only, else null), title, favoriteCommander,
  rank: {season, step, pips, peakStep, wins, losses} | null,
  stats: {games, wins, losses, draws, avgTurns, bestStreak, currentStreak},
  rankHistory: [{at, points}]   -- last 60 ranked games, oldest first
  commanders: [{name, games, wins}]   -- top 6
  colors: [{color, games, wins}]      -- W U B R G order
  weekly: [{week: "YYYY-MM-DD" (Monday, UTC), games, wins}]   -- the last 8 weeks, empty weeks included
  games: [{id, playedAt, mode, result, deckName, commanders, colors, turns, durationSeconds,
           opponents: [{name, commander, ai, hidden?}]}]   -- 30 latest, newest first }
```

The numbers are computed over all (up to 500) stored games; a draw ends a streak.

## Client flows (iOS and Android match screen for screen)

- **Own profile** (`PlayerProfileView` / `PlayerProfileScreen`): rank badge and rank-history line, deck chips (all decks / one deck narrows the
  totals, charts and games; rank history stays whole), win-rate ring with wins/losses/draws/average turns and flame streaks, games per
  week for eight weeks, the most played commanders as art tiles, a color-identity ring, a trophy shelf for the achievements (tap a
  coin to read what it is for), recent games as cards (result chips filter them), "Who can see your profile" (our own segmented
  control: Public / Friends only / Private) with "See it as others do", and "History settings & privacy".
- **Match dashboard**: a recent-game card opens the existing `MatchHistoryDashboard` when a detailed record exists. `MatchRecord.engineMatchID`
  (the engine's match id, new, optional) finds the Deck Studio `DeckStudioRecordedGame` it belongs to; games from earlier builds have none and open in
  place instead. The two opt-in choices (save AI game summaries, save detailed public game history) and refresh/clear moved to the profile.
  `DeckStudioPlaytestInsightsView` is untouched except for sharing its development fixture.
- **Friends** (`FriendsView` / `FriendsSheet`): a search field at the top. Results appear as you type (250 ms after the last key; a newer key
  cancels the older request) as player rows (art, name, rank badge, relation) with Profile and Add friend (or Accept / Requested / Friends).
  Requests, accept/decline, remove, block, challenge and join all still work. Every name opens a profile.
- **Public profile** (`PublicProfileView` / `PublicProfileScreen`): the shared visuals, rank history, recent games with opponents' names (human
  names open their profiles; back returns along the chain), Add friend / Accept / Challenge, and Report / Block in a menu.
- **Game upload** (`GameUploader`): after each finished game the phone sends a summary (`mm_record_game`). The phone's record is the source: a
  game counts as sent once the server confirmed it, and any of the newest 60 games not yet confirmed is retried whenever the app is open
  and online (every 45 s with the presence heartbeat). That covers offline play, rate limits and the games played before a profile name
  existed (the first pass after the migration backfills the recent history). Without a profile name nothing is sent. It never blocks play.
- **Without the migration**: PostgREST answers a missing function with `PGRST202`; the apps read that as `feature_unavailable`. Search turns
  into the old "add by exact name" field with a note, public profiles say they arrive with the next server update, the privacy control is
  disabled with the same note, and game upload waits. Nothing crashes and no old behaviour is lost.

## Signing in with Google or Apple (keeping a profile across phones)

Every profile starts as an anonymous Supabase user. The profile screen's **Keep your profile** card lets the player sign
in so the same profile (name, friends, rank, history) opens on any phone:

- **iPhone:** Continue with Apple (`ASAuthorizationController`) and Continue with Google (`ASWebAuthenticationSession`,
  authorization code with PKCE, iOS OAuth client, no Google SDK). Apple is required next to Google by App Store
  guideline 4.8, and the app has the `com.apple.developer.applesignin` entitlement.
- **Android:** Continue with Google through Credential Manager (`GetSignInWithGoogleOption`, Web client ID as the
  server client ID). Apple on Android would need a web flow with a Services ID and a rotating secret, so it's not offered.
- **Server call:** `POST /auth/v1/token?grant_type=id_token` with `{provider, id_token, nonce}`. The provider receives
  the SHA-256 of a one-time nonce; Supabase gets the raw value.
  - First sign-in adds `link_identity: true` with the anonymous session's bearer token, so the identity joins the
    existing user and nothing moves.
  - `identity_already_exists` means that Google or Apple account already has a profile (another phone). The phone
    then signs in without linking and switches to that profile. The anonymous profile it leaves stays on the server.
- **Sign out** forgets the session; the phone starts a new anonymous profile until the player signs in again.
- Signed-in state comes from `GET /auth/v1/user` `identities`, minus `anonymous` (`LinkedIdentity` on both platforms,
  tested against `chat-cases.json` `linkedIdentities`).

Configuration (October 8, 2026):

- **Google Cloud** project `magicmobile` (917754280625) has Web, iOS and Android OAuth clients. The Android client
  carries the release signing certificate, so Google sign-in works only in release-signed builds.
  - The consent screen stays in Testing (test users only) until Caleb publishes it.
- **Supabase** Auth:
  - Google enabled. "Client IDs" lists a pre-existing client first (kept, with its secret, for whatever already uses it),
    then MagicMobile's Web, iOS and Android client IDs. Native ID-token sign-in needs no secret, and nonce checks stay on.
  - Apple enabled with client ID `com.calebfeliciano.magicmobile`, and users without an email allowed.
  - Manual linking and anonymous sign-ins are on.

## Files

| | iOS (`apps/ios/MagicMobile`) | Android (`apps/android`) |
| --- | --- | --- |
| Numbers and wire parsing | `Ranked/ProfileAnalytics.swift` | `core/.../game/ProfileAnalytics.kt` |
| Pictures | `Ranked/ProfileVisuals.swift` | `app/.../ranked/ProfileVisuals.kt` |
| Own profile | `Ranked/ProfileView.swift`, `Ranked/ProfileHistory.swift` | `app/.../ranked/RankedViews.kt` (`PlayerProfileScreen`), `ranked/ProfileHistory.kt` |
| Public profile | `Ranked/PublicProfileView.swift` | `app/.../ranked/PublicProfileScreen.kt` |
| Friends | `FriendsView.swift`, `Ranked/SocialComponents.swift` | `app/.../social/FriendsSheet.kt`, `ranked/SocialComponents.kt` |
| Account and RPCs | `PlayerAccount.swift` | `app/.../social/PlayerAccount.kt`, `core/.../game/PlayerAccountRules.kt` |
| Game upload | `Ranked/GameUploader.swift`, `OnDeviceRootView.swift` | `core/.../game/GameUploader.kt`, `ondevice/OnDeviceRootView.kt` |
| Development fixtures | `Ranked/SocialFixtures.swift` | `app/.../ranked/SocialFixtures.kt` |
| Tests | `MagicMobileTests/ProfileAnalyticsTests.swift`, `GameUploaderTests.swift`, `MagicMobileUITests/ProfileHistoryUITests.swift` | `core/src/test/.../ProfileAnalyticsTest.kt`, `GameUploaderTest.kt` |

Shared: `apps/android/core/src/test/resources/parity/profile-cases.json` (summaries, public-profile parsing, search results, search prefixes) and the
new error messages in `chat-cases.json` are checked by both platforms. Server: `supabase/migrations/20261007120000_public_profiles.sql`,
`supabase/tests/public_profiles.sql` (run by `verify-ranked.mjs`).

### Development fixtures (debug builds only)

`MAGICMOBILE_UI_TEST_SOCIAL=1` seeds a 36-game history for the own profile and swaps the server for a fixture account (friends, a request in each direction, searchable players,
public profiles, a friends-only and a private one). `MAGICMOBILE_UI_TEST_OPEN=profile|friends|public:<name>|search:<text>` opens that screen at launch. On iOS pass them
with `SIMCTL_CHILD_`; on Android as debug intent extras. `--deck-history-layout-ui-test` (iOS UI tests) shows the eighteen Deck Studio history development games on the profile.

## Applying the migration (needs Caleb's approval; nothing here has touched the live project)

1. Read `supabase/migrations/20261007120000_public_profiles.sql`. It adds a column with a default (metadata only), one index, one table, new functions, and replaces `mm_profile`,
   `mm_profile_card` and `mm_friend_ranks` with the same signatures. It is safe to run twice.
2. Run the suite locally first: `npm ci --prefix supabase/tests --ignore-scripts && npm run test:ranked --prefix supabase/tests` (PGlite, no Docker).
3. Apply to a branch or the project (`supabase db push`, or the dashboard's SQL editor). It ends with `notify pgrst, 'reload schema'`.
4. Check: `select mm_set_visibility('public')` as a signed-in player returns `public`; `select * from mm_search_players('da')` returns rows; a phone's next foreground pass
   uploads its recent games (`select count(*) from player_games`).
5. Roll back (if ever needed): the old clients ignore everything new. To remove it: drop the new functions and `player_games`, `alter table profiles drop column visibility`, and re-create the three replaced functions from `20260928120000` / `20261004120000`.

## Known limits

- Search has no per-player rate limiter beyond the two-letter minimum, 12-row cap and Supabase's own request limits; a loop over every two-letter prefix can still list public names, 12 at a time.
- Game rows are self-reported and unauthenticated like ranked cards; there is no moderation view except the existing reports.
- A profile has no achievements on the server (trophies are the phone's own); other players see rank, record, commanders, colors and games.
- Presence and hosted tables stay visible to friends of a `private` profile.
