# Brackets, Quick Match, Ranked and profiles

Caleb asked for this on 2026-10-04: Commander brackets for decks, a Quick Match against an AI at your
deck's bracket, a 1v1 ranked ladder from Bronze to Mythic with monthly seasons (wins and losses both
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
- Win +1 pip. Loss −1 pip; with none left you drop a division or tier. Bronze IV with no pips can't fall.
- Bonuses: a third straight win below Gold (+1), and a win with a deck below the tier's opponent brackets
  (+1, "underdog"). Draws change nothing and end the streak.
- Seasons are calendar months (UTC). A new month records the season and drops everyone one tier, keeping
  the division (Mythic restarts at Diamond IV).

| Tier | Opponent decks | Your deck up to | AI skill |
|---|---|---|---|
| Bronze | Official precons only (Core) | 2 | 1 |
| Silver | 2 | 2 | 2 |
| Gold | 2–3 | 3 | 3 |
| Platinum | 3 | 3 | 4 |
| Diamond | 3–4 | 4 | 5 |
| Mythic | 4 | 4 | 6 |

In tiers with two opponent brackets, divisions IV–III face the lower one and II–I the upper.

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
317 decided games (95% CI 57–67%); before, it was 53% (docs/cloud/reports/c4.md).

## Play modes

- **Quick Match**: one AI. Defaults to an AI deck at your deck's bracket (a precon when that is Core or
  below) and skill 3; the player can set the
  opponent's bracket, pick the exact deck and set the skill (1–10). No rank change.
- **Ranked**: searches the queue for a person within one tier and one bracket for 40 s, then an AI from your
  tier's pool takes the seat ("Play the AI now" skips the wait). Leaving a ranked game early is a loss.
- **Custom Table**: the existing setup (up to three AIs, or an online table). Recorded in the profile only.

## AI decks

`apps/ios/MagicMobile/Resources/ai-decks.json`, built by `scripts/ranked/build_ai_decks.py` from EDHREC's
average decks per bracket (fetched 2026-10-04), limited to this XMage catalogue and swapped down so each
deck's list check is at most its bracket. Six commanders the XMage AI plays well (proactive creature
decks): Krenko, Gishath, Lathril (brackets 1–4), Edgar Markov, The Ur-Dragon, Wilhelt (2–4). With the five
precons (Core) that is 26 AI decks. Players may pick the bracket decks too ("Included · Bracket N").

All 26 passed XMage's Commander deck validation on the desktop JVM engine, and all resolve through the
iOS app's resolver (`AIDeckPoolTests`).

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
  as `RankLadder.swift` / `Ranked.kt`: bonuses, Bronze IV floor, monthly rollover into `ranked_season_history`.
  `ranked_results` records every change and why. `ranked_profiles` stays the public card; the server writes its
  rank fields and `mm_ranked_publish` now only sets the title and favourite commander (older builds keep working).
- **Person vs person:** `mm_ranked_report` settles a match when both sides agree (win/loss or draw/draw).
  Disagreements change nothing. A lone report settles after an hour (the side that never reported left: a loss). The
  same two players count at most three matches a day (win trading with spare accounts).
- **Against the AI** (the phone runs the game, so the server can only bound it): `mm_ranked_ai_start` hands out a
  ticket (at most ten an hour) and `mm_ranked_ai_result` takes one result for it. A win needs four minutes since the
  ticket, at most twelve AI wins count per UTC day, and a ticket not answered within twelve hours becomes a loss.
- `mm_ranked_standing` returns the caller's standing (settling anything stale first) plus `unsettled`, the matches
  they reported that the other side hasn't yet. `mm_ranked_seed` lets a player with no server standing bring their
  phone's earlier progress once, capped at Gold IV. Standings published before the migration carried over as they were.
- **Apps:** the phone still counts each result at once (result screen, ceremony), sends AI results with their
  ticket (queued and retried, `PlayerRecordStore.pendingRankedResults`), then adopts the server's standing
  (`RankedStanding`, `PlayerRecordStore.adopt` / `PlayerRecordFile.adopting`). While a result is still on its way
  the phone keeps its own number, so a pip never flickers away. Without a profile name, ranked stays on the phone.
- **Limits:** a modified app can still claim AI wins within the caps, and two colluding accounts can trade wins
  within the pair cap. The host phone runs online games and so holds hidden information (PROTOCOL.md).
- Tests: `supabase/tests/ranked_referee.sql` (run by `verify-ranked.mjs` after the older suites, which test the
  functions as they were before this migration), `RankedStandingTests.swift`, `RankedStandingTest.kt`.
- **Status: applied to the live project on 2026-10-15 UTC** (migration `ranked_referee`, file SHA-256 `a87d4431…a9ea`,
  with Caleb's go-ahead). Checked afterwards: the four new public functions plus `mm_ranked_report`/`publish` are
  callable by signed-in players and not anonymous callers; `mm_ranked_mirror/current/apply/settle` by neither; the four
  new tables have RLS on with no grants; all 3 published standings were carried over as `imported`; the security
  advisor shows only the usual RPC-only notices. No live game has been played against it yet.

## Tests

- Shared: `ranked-cases.json` (ladder, positions, tiers, seasons, rollovers, brackets, pools, colors) via
  `RankedParityTests.swift` and `RankedParityTest.kt`.
- iOS: `AIDeckPoolTests`, `PlayerRecordStoreTests`, `RankedMatchmakerTests`; UI `RankedUITests` (mode
  chooser, Quick Match, Ranked lobby, bracket sheet, profile, the four rank moments via
  `MAGICMOBILE_UI_TEST_CEREMONY`; `MAGICMOBILE_UI_TEST_RANK` / `_MATCHES` seed a profile).
- Android: `RankedParityTest` (also the record store and matchmaker), `FriendChallengesTest`.
- iOS `FriendChallengeTests` (in `RankedParityTests.swift`): same-tier rule, accept, decline, failure,
  withdraw-after-accept, answered challenges not shown again.
