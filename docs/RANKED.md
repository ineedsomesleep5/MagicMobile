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
| Bronze | Bracket 1–2 | 2 | 2 |
| Silver | 2 | 2 | 3 |
| Gold | 2–3 | 3 | 4 |
| Platinum | 3 | 3 | 5 |
| Diamond | 3–4 | 4 | 6 |
| Mythic | 4 | 4 | 7 |

In tiers with two opponent brackets, divisions IV–III face the lower one and II–I the upper.

## Play modes

- **Quick Match**: one AI. Defaults to an AI deck at your deck's bracket and skill 3; the player can set the
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

## Badges and animations

The six badges were painted as one Codex sheet, cut apart, turned into textured 3D models with Meshy
image-to-3D (meshy-cli, 30 credits each, task IDs in
`~/Movies/motion-assets/magicmobile-brand/rank-badges/meshy/`), and rendered in Blender:
`scripts/brand/rank_badges.py` (a still and a 16-frame turn per tier) then
`scripts/brand/install_rank_badges.sh` (pngquant into `Assets.xcassets/tavern-rank-*`; Android gets them as
`tavern_rank_*` drawables). About 4.9 MB for all 102 images.

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

**Status (2026-10-04): not applied to the live project.** Until it is, the apps treat the queue as
unavailable and every ranked game is against the AI (ranks still count), and friends' badges stay hidden.
A live two-phone ranked match has not been played.

## Tests

- Shared: `ranked-cases.json` (ladder, positions, tiers, seasons, rollovers, brackets, pools, colors) via
  `RankedParityTests.swift` and `RankedParityTest.kt`.
- iOS: `AIDeckPoolTests`, `PlayerRecordStoreTests`, `RankedMatchmakerTests`; UI `RankedUITests` (mode
  chooser, Quick Match, Ranked lobby, bracket sheet, profile, the four rank moments via
  `MAGICMOBILE_UI_TEST_CEREMONY`; `MAGICMOBILE_UI_TEST_RANK` / `_MATCHES` seed a profile).
- Android: `RankedParityTest` (also the record store and matchmaker).
