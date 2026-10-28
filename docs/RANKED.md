# Brackets, Quick Match, Ranked and profiles

Caleb asked for this on 2026-10-04: Commander brackets for decks, a Quick Match against an AI at your
deck's bracket, a 1v1 ranked ladder from Bronze to Mythic with quarterly seasons (wins and losses both
count, AI wins count, you can rank down), a full player profile, rank-up and rank-down animations, and
better AI decks. iOS and Android match each other; `apps/android/core/src/test/resources/parity/ranked-cases.json`
checks the shared rules on both.

## Commander brackets

`apps/ios/MagicMobile/Resources/commander-brackets.json`, built by `scripts/ranked/build_bracket_rules.py`
from Wizards' Commander Brackets beta (brackets last changed 2025-10-21; Game Changers list of 2026-02-09,
53 cards). Every card name is checked against the bundled XMage catalogue.

| Bracket | What the list may contain |
|---|---|
| 1 Exhibition, 2 Core | no Game Changers, no mass land denial, no chained extra turns, no two-card combos |
| 3 Upgraded | up to 3 Game Changers, no mass land denial, no chained extra turns, no early two-card combos |
| 4 Optimized, 5 cEDH | anything legal |

The list check gives the lowest bracket a deck can be in (Core at least). Bracket 1 vs 2 and 4 vs 5 are
intent, so the player may label their own deck higher, or call a Core list Exhibition (Deck bracket sheet,
`DeckBracketPreference`). Included decks have a fixed bracket. Heuristics, stated plainly:

- Extra turns come from the catalogue's rules text ("takes an extra turn"); three or more read as chaining.
- Two-card combos are a curated list of 49 well-known pairs, not Commander Spellbook's full database. A pair
  whose total mana value is 6 or less counts as early (Bracket 4).
- Mass land denial is a curated list (Armageddon, Blood Moon, Winter Orb, …).

## The ladder (`RankLadder.swift`, `Ranked.kt`)

- Bronze, Silver, Gold, Platinum, Diamond in divisions IV–I, then Mythic. Four pips win a division.
- Ladder option B (Caleb, 2026-10-15; docs/cloud/ladder-options.md): a win earns 2 pips in Bronze, Silver and Gold
  and 1 from Platinum; a loss costs nothing in Bronze and 1 pip elsewhere. A crushing loss against the AI (it still
  had 30 of its 40 life, read from the game record) costs 2 (Caleb, 2026-10-26), except in Platinum, where a win earns 1 and so does every loss cost (2026-10-28). A loss never takes you out of your
  tier (Mythic can fall back to Diamond, never below Diamond IV).
- Bonus: +1 for a win with a deck below the tier's opponent brackets ("underdog"). The old third-win streak bonus is
  gone (two-pip wins replace it). Draws change nothing and end the streak.
- Seasons (UTC): October 2026 was a month; from November 2026 each season is three months, named by its first
  ("2026-11" runs November to January; `mm_season_for`, `RankLadder.season`). A new season records the last one and drops everyone one tier, keeping
  the division (Mythic restarts at Diamond IV).

| Tier | AI deck Power (by division IV → I) | AI deck and your deck up to | AI skill |
|---|---|---|---|
| Bronze | 3–4 | 2 | 1 |
| Silver | 4–5 | 2 | 2 |
| Gold | 6–7 | 3 | 3 |
| Platinum | 6.75–7.75 | 3 | 4 |
| Diamond | 7.5–8.5 | 4 | 5 |
| Mythic | 8.5 | 4 | 6 |

Since 2026-10-25 (docs/DECK_POWER.md) the AI brings the deck whose hidden Power is nearest the division's target, at
random among the three nearest, from the tier's bracket or lower, never your commander and not one you faced recently.
Each deck's Power comes from its own AI-vs-AI games (`scripts/ranked/deck_power.py rate`), shipped as the `power` block
of `ai-decks.json`. A deck without a Power falls back to the old rule: the tier's opponent bracket (Bronze the three
gentlest precons).

Why this curve (2026-10-11): the XMage AI searches `max(4, skill)` moves deep and thinks `skill × 3` s,
so skills 1–4 differ only in thinking time and depth grows from Diamond. Ranked never asks for Bracket 1:
the Exhibition AI decks are tuned tribal lists (the bracket check only screens Game Changers, land
denial, extra turns and combos), so Bronze faces the precons instead. Skill 7 would mean 21 s AI turns
on a phone, so Mythic stops at 6.

Engine release A (2026-10-15, cloud session C2): skills 1 and 2 now search depth 2 and 3 (one and two
actions ahead; upstream depth 1 never casts a spell), skill 3 keeps depth 4, and skills 1–3 make a
deliberate mistake at 15%, 10% and 5% of their decisions (a weaker play or a pass, a held-back attack,
a skipped block, each with a safety guard). Skill 4 and up are unchanged. The numbers live in
`AIDifficulty.java` and each seat can override them (`aiSearchDepth`, `aiMistakePercent`, `aiSeed`;
packages/ondevice-engine/docs/PROTOCOL.md) for the C3 calibration, which decides the final values.

Expert tier (2026-10-15, cloud session C4): C3 found that skill made no measurable difference, because
XMage's search runs out of time long before its node cap, and attacks and blocks are fixed rules it never
searches. From skill 5 (Diamond) up the AI now plans its attacks against the defender's likely blocks and
the swing back, chooses all its blocks together (double blocks, chumps only when they matter), scores
life on Commander's 40-life scale (XMage's scores assume 20), and keeps a quick search's move when its
full search runs out of time. Think time is unchanged. On the Core pool, skill 6 beat skill 3 in 62% of
318 decided games (95% CI 57–67%) and skill 4 in 59% of 160 (52–67%); before, 53% and 50%. Skill 5
against 4 is 53% (45–60%), not yet a measurable step (docs/cloud/reports/c4.md).

## Play modes

- **Quick Match**: one AI. Easy (an AI deck near Power 3.5, skill 2), Medium (5.5, skill 3, the default) or Hard
  (7.5, skill 5). Advanced keeps the old controls: the opponent's bracket (by default your deck's, a precon at Core
  or below), the exact deck and the skill (1–10). No rank change.
- **Ranked**: searches the queue for a person within one tier and one bracket for 40 s, then an AI from your
  tier's pool takes the seat ("Play the AI now" skips the wait). Leaving a ranked game early is a loss.
- **Custom Table**: the existing setup (up to three AIs, or an online table). Recorded in the profile only.

## AI decks

`apps/ios/MagicMobile/Resources/ai-decks.json`, built by `scripts/ranked/build_ai_decks.py` from EDHREC's
average decks per bracket (fetched 2026-10-04), limited to this XMage catalogue and swapped down so each
deck's list check is at most its bracket. Six commanders the XMage AI plays well (proactive creature
decks): Krenko, Gishath, Lathril (brackets 1–4), Edgar Markov, The Ur-Dragon, Wilhelt (2–4). On 2026-10-24
seven more widened the Power range (docs/DECK_POWER.md), one bracket each: Kaalia of the Vast, Winota, The
First Sliver, Miirym (4), Marisi, Kynaios and Tiro (1), Tormod (2). On 2026-10-25 eight more for about five decks per rank: Tiamat, Lathliss, Old Gnawbone, Phelddagrif, Zedruu,
Karador, Meren and Marisi (2). With the five precons (Core) that is 41 AI decks. Players may pick the bracket decks too ("Included · Bracket N").

The first 26 passed XMage's Commander deck validation on the desktop JVM engine, and all resolve through the
iOS app's resolver (`AIDeckPoolTests`). The seven new decks are validated by their calibration games.

### Calibration (desktop JVM, AI vs AI, 2026-10-04)

The engine needs one human seat, so a watcher seat concedes at once and the two AIs play on.

- One bracket up (B3 vs B2, B4 vs B3, 6 matchups each, 2 games): the higher bracket won 11 of 24.
- Two brackets up (B4 vs B2, 2 matchups, 6 games each): the higher bracket won 5 of 12.
- Skill 6 vs skill 2 with the same decks, both seatings: 6–6.
- Games took 15–140 s on the Mac at skills 2–7.

So in AI-vs-AI play neither the deck bracket nor XMage's skill setting reliably made the AI stronger.
Stronger decks matter more against a person, who sees and plays around fast mana, tutors and combos, but
the XMage AI makes little use of them. The ladder still raises both, and the numbers should be revisited
from real games: the profile records each AI game's opponent bracket and skill. Script:
`calibrate.py` in the session scratchpad (resolves decks against `MagicMobile-ondevice`'s desktop build).

## Profile

`PlayerRecordStore` (iOS `Application Support/Profile/player-record.json`, Android `files/Profile/`): rank
and season history, the last 300 games, title, favorite commander. Stats (games, wins, win rate, streaks,
average turns, colors, decks), 13 achievements that unlock titles, and match history. Friends see each
other's badge in the friends list and can open a ranked card.

The profile picture is the favorite commander's illustration alone (`CommanderArtMedallion`, art-only
crop in the table's brass ring), chosen from commanders played or any of the player's decks (saved and
included); "Most played" is the default. Friends' cards show the same picture.

Since 2026-10-27 the profile also reads `ProfileInsights` from the player's own games (parity/profile-cases.json
"insights"): the last ten results, records by mode and by the tier a ranked game was played at, the five commanders faced
most, the fastest win, average turns in wins and losses, the average game length (games send `p_duration_seconds` from
then on) and the best deck (three games or more). Game cards show the turn and length, and "Crushing loss" for a two-pip loss.

## Leaderboard

`mm_ranked_leaderboard` (everyone or friends) gives each row the player's commander, rank, record, online dot and current
win streak, the season's end (`seasonEnds`) and last season's top three (`champions`, from `ranked_season_history` and
standings not yet rolled over). The screens show commander portraits with the rank's emblem, tier dividers, a flame for
three straight wins or more, "ends in N days" on the live strip, and a Champions tab.

## Friend challenges

From the friends list an online friend can be challenged to a **Quick Match** (friendly, profile history
only) or a **Ranked** game (only in the same tier, Gold with Gold; it counts for both, like any ranked
game). The challenger opens a two-seat relay table and sends its code (`mm_challenge_send`); the friend's
menu checks every 5 s while open (`mm_challenge_incoming`) and shows a banner to Accept or Decline. Accepting
(`mm_challenge_accept`) rechecks both tiers with the friend's current step, makes the `ranked_matches` row
for a ranked game and hands over the code; the friend joins and both ready by themselves. A challenge lasts
two minutes; the challenger may withdraw it; a table that never starts closes after 75 s with nothing
recorded. A friend without a standing this season counts as Bronze IV; a standing from an earlier season has
rolled over one tier, as on the phones. Code: `FriendChallenges.swift` / `FriendChallenges.kt` (rules and
coordinator), `FriendChallengeViews.swift` / `.kt` (waiting overlay, invite banner).

## Badges and animations

The six badges were painted as one Codex sheet, cut apart, turned into textured 3D models with Meshy
image-to-3D (meshy-cli, 30 credits each, task IDs in
`~/Movies/motion-assets/magicmobile-brand/rank-badges/meshy/`), and rendered in Blender:
`scripts/brand/rank_badges.py` (a still and a 32-frame turn per tier, 2026-10-04; it was 16) then
`scripts/brand/install_rank_badges.sh` (pngquant into `Assets.xcassets/tavern-rank-*`; Android gets them as
`tavern_rank_*` drawables). The spin decodes each tier's frames once off the main thread
(`RankSpinFrames`, `RankArt.spinFrames`) and crossfades neighbouring frames, so the slow end of a turn
glides instead of stepping.

- Result screen: the rank strip fills or empties each pip in turn and names any bonus.
- Division or tier change: a full-screen moment. Up: the old badge charges and spins, bursts into embers, and
  the new one spins in three turns under rotating light. Down: the badge cracks and falls, and the lower one
  turns in backwards, dimmed. Only Continue closes it. Reduce Motion shows the result without movement.
- The ranked lobby badge turns once on arrival; the search overlay's badge turns while searching.

## Server (Supabase)

`supabase/migrations/20261004120000_ranked_ladder.sql`: `ranked_queue`, `ranked_matches`, `ranked_profiles`
(RLS on, no grants) and `mm_ranked_enqueue/poll/cancel/set_table/report/publish`, `mm_profile_card`,
`mm_friend_ranks`. The host opens a two-seat relay table and shares its code; the guest joins; both ready
up by themselves. `supabase/tests/verify-ranked.mjs` runs the social and ranked migrations in PGlite and
checks pairing, blocks, the table hand-off, late cancels, cards and account deletion
(`npm run test:ranked --prefix supabase/tests`).

`supabase/migrations/20261004180000_friend_challenges.sql`: `friend_challenges` (RLS on, no grants) and
`mm_challenge_send/incoming/status/accept/decline/cancel`, with internal `mm_rank_tier`,
`mm_current_rank_step` and `mm_challenge_view`. Tested in the same PGlite run (`friend_challenges.sql`). **Applied to the live
project on 2026-10-04** (migration `friend_challenges`, file SHA-256 `620338a3…4373`): the six public
functions are callable by signed-in players and none by anonymous callers, the two internal helpers by
neither, the table has RLS on with no grants, and the advisor shows only the usual RPC-only notices. No test
accounts were made; a live two-phone challenge has not been played.

**Status: applied to the live project on 2026-10-04** (migration `ranked_ladder`, file SHA-256
`884e10c8…93ee`). Checked afterwards: the nine functions exist, signed-in players may call the eight public
ones and anonymous callers none (a signed-out REST call gets `permission denied`), the three tables have RLS
on with no grants, and the security advisor shows only the same RPC-only notices as the social tables. No
test accounts were made on the live project. A live two-phone ranked match has not been played.

### The server keeps score (2026-10-14)

`supabase/migrations/20261015120000_ranked_referee.sql`. Before it, each phone computed its own rank and
`mm_ranked_publish` stored whatever it was sent, so a modified app (or a direct REST call with the app's public key)
could publish any rank. Now the server is the referee, using the existing database (no new server, no game simulation):

- `ranked_standings` is the source of truth (points = step × 4 + pips, Mythic past 80), with the same ladder rules
  as `RankLadder.swift` / `Ranked.kt`: bonuses, Bronze IV floor, season rollover into `ranked_season_history`.
  `ranked_results` records every change and why. `ranked_profiles` stays the public card; the server writes its
  rank fields and `mm_ranked_publish` now only sets the title and favourite commander (older builds keep working).
- **Person vs person:** `mm_ranked_report` settles a match when both sides agree (win/loss or draw/draw).
  Disagreements change nothing. A lone report settles after an hour (the side that never reported left: a loss). The
  same two players count at most three matches a day (win trading with spare accounts).
- **Against the AI** (the phone runs the game, so the server can only bound it): `mm_ranked_ai_start` hands out a
  ticket (at most ten an hour) and `mm_ranked_ai_result` takes one result for it. A seeded win is judged by its game
  record's turns, not the clock (Caleb, 2026-10-26: fast decks win in a minute); only an older unseeded ticket keeps a
  two-minute floor. There is no daily cap on AI wins (removed 2026-10-26), and a ticket not answered within twelve
  hours becomes a loss. The ticket also carries the AI's tuning (`ranked_ai_tuning`, docs/DECK_POWER.md). The answer carries `settlement`, the server's `change` and, for an unverified win, `check`: the apps show the
  reason on the result screen and in Recent games instead of a win quietly adding nothing.
- `mm_ranked_standing` returns the caller's standing (settling anything stale first) plus `unsettled`, the matches
  they reported that the other side hasn't yet. `mm_ranked_seed` lets a player with no server standing bring their
  phone's earlier progress once, capped at Gold IV. Standings published before the migration carried over as they were.
- **Apps:** the phone still counts each result at once (result screen, ceremony), sends AI results with their
  ticket (queued and retried, `PlayerRecordStore.pendingRankedResults`), then adopts the server's standing
  (`RankedStanding`, `PlayerRecordStore.adopt` / `PlayerRecordFile.adopting`). While a result is still on its way
  the phone keeps its own number, so a pip never flickers away. Without a profile name, ranked stays on the phone.
- **Limits:** a modified app can still claim AI wins it forges a record for, or withhold a crushing loss's record, and two colluding accounts can trade wins
  within the pair cap. The host phone runs online games and so holds hidden information (PROTOCOL.md).
- Tests: `supabase/tests/ranked_referee.sql` (run by `verify-ranked.mjs` after the older suites, which test the
  functions as they were before this migration), `RankedStandingTests.swift`, `RankedStandingTest.kt`.

- **Status: applied to the live project on 2026-10-15 UTC** (migration `ranked_referee`, file SHA-256 `a87d4431…a9ea`,
  with Caleb's go-ahead). Checked afterwards: the four new public functions plus `mm_ranked_report`/`publish` are
  callable by signed-in players and not anonymous callers; `mm_ranked_mirror/current/apply/settle` by neither; the four
  new tables have RLS on with no grants; all 3 published standings were carried over as `imported`; the security
  advisor shows only the usual RPC-only notices. No live game has been played against it yet.

### AI wins backed by the game record (R3, migration `20261016120000_ranked_ai_records.sql`)

- `mm_ranked_ai_start2` hands out the same ticket plus a server seed (text, 64-bit) and remembers the tier's AI
  skill. The app waits up to four seconds for it before starting the game and passes the seed to the engine's `create`
  (only on engines advertising `gameRecord`), so one seed is one game.
- When a solo game ends the app fetches the engine's `record` before saving the result, keeps it on the phone
  (`Profile/GameRecords`, the last 50, no backups) and sends it with the result: `mm_ranked_ai_result2(game, result,
  record)`. Only seeded tickets use it; older builds keep `mm_ranked_ai_start` / `mm_ranked_ai_result` unchanged.
- Before a win on a seeded ticket counts, `mm_ranked_ai_record_check` runs the cheap checks of
  docs/cloud/game-record.md: hash chain equals `head`, the ticket's seed, an engine build listed in
  `ranked_engine_builds`, one human and one AI seat, an AI skill no more than one tier below the ticket's with the
  engine's depth and mistake chance for that skill (`mm_ai_engine_depth` / `mm_ai_engine_mistakes`, keep them in step
  with `AIDifficulty.java`), an end where the human alone won and the AI lost, increasing turn marks, the entry
  grammar with no concede, a final turn of 5 or later (3 for a bracket 5 deck: XMage counts each player's turn, so a
  win inside the first two rounds is suspect) and four seconds a turn since the ticket. A failed check settles the win
  as `unverified` (no rank change, `ranked_ai_games.record_check` says why). Every win's record is kept in
  `ranked_ai_records` for review and can be replayed with `scripts/dev/replay_record.sh`.
- **Release step:** every release whose engine records games registers its engine build before it goes out, or its
  ranked AI wins settle as `unverified`:
  `insert into public.ranked_engine_builds (engine_build, label) values ('<sha256:… from python3
  packages/ondevice-engine/scripts/engine_build_identity.py>', 'TestFlight NN / Android NN');` The identity is a hash
  of the engine sources, the same on both platforms (print it with `python3 -c 'import sys; sys.path.insert(0,
  "packages/ondevice-engine/scripts"); import engine_build_identity as e; print(e.identity())'`).
- **Limits:** the checks prove a record is well formed, unaltered, made for this ticket and consistent with the claimed
  win; a modified app can still write a consistent record by hand, and the AI's choices are recorded, not recomputed.
  The older entry points stay open for older builds until they are retired.
- Tests: `supabase/tests/ranked_ai_records.sql` (records built by `verify-ranked.mjs` with node's SHA-256),
  `RankedStandingTests.swift`, `RankedStandingTest.kt`, the guest-refusal tests in `SafetyTests.swift` and
  `HostRouterPrivacyTest.kt`.

## Tests

- Shared: `ranked-cases.json` (ladder, positions, tiers, seasons, rollovers, brackets, pools, colors) via
  `RankedParityTests.swift` and `RankedParityTest.kt`.
- iOS: `AIDeckPoolTests`, `PlayerRecordStoreTests`, `RankedMatchmakerTests`; UI `RankedUITests` (mode
  chooser, Quick Match, Ranked lobby, bracket sheet, profile, the four rank moments via
  `MAGICMOBILE_UI_TEST_CEREMONY`; `MAGICMOBILE_UI_TEST_RANK` / `_MATCHES` seed a profile).
- Android: `RankedParityTest` (also the record store and matchmaker), `FriendChallengesTest`.
- iOS `FriendChallengeTests` (in `RankedParityTests.swift`): same-tier rule, accept, decline, failure,
  withdraw-after-accept, answered challenges not shown again.
