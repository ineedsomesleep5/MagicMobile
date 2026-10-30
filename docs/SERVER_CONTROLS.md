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
| `ai_decks` | A newer AI deck file for each card catalogue, so decks and their Power change without a build. Apps from TestFlight 73 / Android 51 read it. See below. `{}` sends every app back to its own decks. | `{"<catalogue hash>": {"revision": 2, "url": "https://...", "sha256": "..."}}` |
| `switches` | Turns newer features off without a build. A switch that isn't named is on, except `voiceChat`. `leaveVote`: the vote to go on without a player who is away (a player who leaves is still conceded). `stackAutoTuck`: the stack card tucking itself while you pick a target. `voiceChat`: the mic at online tables (docs/VOICE_CHAT.md), off unless named on. | `{"leaveVote": true, "stackAutoTuck": true, "voiceChat": true}` (voice on since 2026-10-27) |

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

## AI decks and their Power

Change the decks with `scripts/ranked/build_ai_decks.py` or the ratings with `deck_power.py rate --write`, then:

```bash
python3 scripts/ranked/publish_ai_decks.py --upload
```

It checks the file (every card in the catalogue, every shipped deck still there), raises `revision`, puts the file on a
GitHub release and prints the SQL to run. Commit the raised revision and redeploy the web, which bundles the file.

A phone downloads the file at launch once the profile is ready, checks its SHA-256 and shape, and plays with it from the
next launch. It ignores a bad file and keeps the decks it has. It drops its copy when the server names none, or when an
app update ships the same revision or a newer one. To undo a publish, set `ai_decks` to `{}`. A deck can't be removed
once shipped, because saved games name it: drop its Power instead and Ranked and Quick Match stop picking it.

`power.rankedClosest` in the file sets how many decks each tier picks among (Mythic 5, the rest 3; `closest` in each
tier of `deck-power-weights.json`). A new card catalogue needs its own entry, so an engine release still ships its own
file.

## Awards

Medals on a player's profile (tables `awards`, `player_awards`; apps from TestFlight 73 / Android 51 and the web). An award
is a row and its art a URL, so a new one needs no build. An unseen award opens with a ceremony on the menu, once across a
player's devices, then sits on their profile. A profile that can't be opened doesn't show its awards.

| Column | What it does |
| --- | --- |
| `id` | Lowercase letters, numbers, dashes. Don't reuse one. |
| `name`, `description` | What the medal says (40 and 160 characters). |
| `image_url` | https only: a square transparent PNG, about 512 px. Without it, or if it can't load, a star medal in `tint`. |
| `tint` | `#RRGGBB`: the glow, the name's colour and the star medal. |
| `rarity` | 1 plain, 2 a soft glow, 3 a strong glow and a gold ring. |
| `title` | Optional. The player's title, shown everywhere titles show, even on old apps. It replaces the title they picked; the highest rarity wins, then the oldest. |
| `rule` | Optional. Hands it out by itself as ranked standings move: `{"kind": "peak_step", "step": 20}`, `{"kind": "season_wins", "count": 100}` or `{"kind": "win_streak", "count": 10}`; add `"first": 1` to stop after that many players. Steps: Diamond 16, Mythic 20. Another kind needs a migration. |
| `active` | `false` hides it everywhere and keeps who earned it. |

Art goes in `design/awards/` on `main`, then `https://raw.githubusercontent.com/ineedsomesleep5/MagicMobile/main/design/awards/<name>.png`.

```sql
-- A new award with a rule, then give it to everyone who has already earned it, in the order they did.
insert into public.awards (id, name, description, tint, rarity, rule)
values ('first-gold', 'First to Gold', 'The first player ever to reach Gold.', '#FFCC5C', 2, '{"kind": "peak_step", "step": 8, "first": 1}');
select public.mm_awards_backfill('first-gold');
-- By hand. The note shows under the description.
select public.mm_award_give('PlayerName', 'season-1-champion', 'October 2026');
-- New art, a new word: every app has it on its next read.
update public.awards set image_url = 'https://...', description = '...' where id = 'first-mythic';
-- Take one back. A title it gave stays until the player's app next publishes, so clear it.
delete from public.player_awards where award_id = 'mythic' and user_id = (select id from public.profiles where username = 'PlayerName');
update public.ranked_profiles set title = null where user_id = (select id from public.profiles where username = 'PlayerName');
```

## Voice chat

The `agora-token` edge function mints voice tokens; it needs the Supabase secret `AGORA_APP_CERTIFICATE` (Caleb sets it in
Edge Functions → Secrets). Then `voiceChat: true` in the switches turns the mic on for builds that have it
(docs/VOICE_CHAT.md).

## Ranked

- **AI difficulty per tier**: `ranked_ai_tuning` (deck Power band, mistake % by division, and `ai_skill`: null keeps the
  ladder's skill, Diamond is 6 since 2026-10-29); docs/DECK_POWER.md has the SQL.
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
play ship inside the apps: they need a build (and the engine its own release).
The web app and the website deploy any time (Vercel).
