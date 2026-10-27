# Server controls

What changes on the server (Supabase project `pbspondpyvrjcnvwhtim`) without an app build, and how. Every change here is
live for iOS, Android and the web at once. Run the SQL in the Supabase SQL editor or through the Supabase connector.

## The app config (`mm_app_config`, 2026-10-27)

Every app reads it at launch once the profile is ready and keeps the last copy, so it applies offline too. Apps from
before TestFlight 64 / Android 42 don't read it.

| Key | What it does | Example |
| --- | --- | --- |
| `notice` | A banner on the main menu, shown once per `id` until the player closes it. `platforms` limits it to `ios`, `android`, `web`; `maxBuild` shows it only to builds at or below a number (to ask older builds to update). `null` shows nothing. | below |
| `name_fixes` | Deck-import name fixes: the name a deck site sends → the app's card name. Used only when that card is in the app's catalogue, after the app's own matching (exact name, plain letters, front of a two-part name). | `{"Some Archidekt Name": "Engine Name"}` |
| `switches` | Turns newer features off without a build. A switch that isn't named is on. `leaveVote`: the vote to go on without a player who is away (a player who leaves is still conceded). `stackAutoTuck`: the stack card tucking itself while you pick a target. | `{"leaveVote": true, "stackAutoTuck": true}` |

```sql
-- A notice for iPhones on build 63 or older and Android on 41 or older.
update public.app_settings set value = '{"id": "update-64", "text": "Update to the newest build for the new table rules.",
  "platforms": ["ios", "android"], "maxBuild": {"ios": 63, "android": 41}}', updated_at = now() where key = 'notice';
-- No notice.
update public.app_settings set value = 'null', updated_at = now() where key = 'notice';
-- A name fix (merge into what is there).
update public.app_settings set value = value || '{"Name A Site Sends": "App Card Name"}', updated_at = now() where key = 'name_fixes';
-- Turn the table vote off.
update public.app_settings set value = value || '{"leaveVote": false}', updated_at = now() where key = 'switches';
-- What an app sees.
select public.mm_app_config('ios', 63);
```

A notice's `id` decides whether players who closed it see it again: give a new notice a new id.

## Ranked

- **AI difficulty per tier**: `ranked_ai_tuning` (deck Power band and mistake % by division); docs/DECK_POWER.md has the SQL.
  Apps from TestFlight 63 / Android 41 and the web follow it.
- **Ladder rules** (pips per win and loss, the crushing-loss threshold, tier floors), **seasons** (`mm_season_for`), the
  **ranked AI win check** (turn minimums) and **rate limits** are SQL functions: a migration changes them for everyone.
- **Fixing a game by hand** (crediting a win the server held back, backfilling a missing game in `player_games`): SQL, as
  on 2026-10-26 for 254DADDY's wins and the Kudo games.
- **Leaderboard** contents and order (`mm_ranked_leaderboard`): streaks, the season's end and last season's champions
  come from the server.

## Social

Profiles, friends, friend challenges, messages, blocks and reports, profile privacy and game history are Supabase RPCs
(docs/RANKED.md, the social migrations).

## Not on the server

Anything on a screen's layout, the card catalogue (which cards exist and their names), the XMage engine and the AI's
play, and the AI decks with their Power ratings ship inside the apps: they need a build (and the engine its own release).
The web app and the website deploy any time (Vercel).
