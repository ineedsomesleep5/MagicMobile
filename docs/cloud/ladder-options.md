# Ladder options (C1, 2026-10-15)

Three concrete ways to tune the 1v1 ranked ladder, compared with MTG Arena and Hearthstone, with the exact rule changes
for both apps and the server, and a simulation of how fast each one climbs. **Recommendation: option B** (Arena's
steps per tier, with a floor at each tier). Caleb chooses; see NEEDS CALEB at the end. Nothing here changes the apps.
B's server SQL is written and tested but kept outside `supabase/migrations` until Caleb has chosen.

## The short version

| | Today | A: tier floors | **B: Arena steps + floors** | C: Hearthstone reset + climb bonus |
|---|---|---|---|---|
| Win | +1 (+1 for a 3rd straight win below Gold) | same as today | **+2 in Bronze to Gold, +1 from Platinum** | +1 × climb bonus, doubled from the 3rd straight win below Diamond |
| Loss | −1 | −1 | **0 in Bronze, −1 elsewhere** | −1 |
| Can a bad night cost a whole tier? | yes | no | **no** | no |
| Season reset | one tier down | one tier down | **one tier down** | everyone to Bronze IV, with a climb bonus from last season |
| Fresh player at 50%: games to Platinum | 540 | 392 | **71** | 243 |
| Fresh player at 60%: games to Mythic | 301 | 275 | **183** | 207 |
| Size of the change | | 1 line per platform + SQL | **2 small properties + 3 lines per platform + 1 SQL function** | new stored state on both platforms and the server |

## Today's ladder

`RankLadder.swift`, `Ranked.kt`, `ranked-cases.json`, and on the server `mm_ranked_apply` / `mm_ranked_current` in
`20261015120000_ranked_referee.sql`:

- Bronze, Silver, Gold, Platinum, Diamond, each in divisions IV to I, then Mythic. Four pips win a division. One number
  holds it all: points = step × 4 + pips (Bronze IV 0 is 0, each tier is 16 points, Mythic starts at 80).
- A win is +1. A loss is −1, and with no pips left you drop a division or a tier. Only Bronze IV 0 is a floor.
- Bonuses: +1 for a third straight win below Gold (streak), +1 for a win with a deck below the tier's opponent brackets
  (underdog). Draws change nothing and end the streak.
- A new UTC month records the season and drops everyone one tier, keeping the division (Mythic restarts at Diamond IV).

So above Silver it is a pure +1/−1 coin flip: a 50% player goes nowhere on average, and a bad night (say six losses)
can drop a whole tier. Below Gold the streak bonus gives a slow lift.

## Arena and Hearthstone (docs/research/ARENA_HEARTHSTONE_NOTES.md, section D)

| | MTG Arena (Constructed Bo1) | Hearthstone |
|---|---|---|
| Structure | Bronze to Diamond, 4 tiers each, then Mythic (a rating) | 5 leagues of 10 ranks, 3 stars each, then Legend |
| Steps per tier | 6 | 3 stars per rank |
| Win / loss | Bronze +2/0, Silver and Gold +2/−1, Platinum and Diamond +1/−1 | +1 star (× the star bonus) / −1 star |
| Streak | none | from the 3rd straight win, stars double (not at Diamond 5 and above) |
| Protection | you never fall out of a rank class (Bronze, Silver, …), only lose tiers within it; Mythic can fall to Diamond | floors every 5 ranks: you can't drop below one for the rest of the season |
| Season reset | partial table: about one class down (Gold 4 to Bronze 1, Diamond 1 to Gold 1, Mythic to Platinum 4) | everyone to Bronze 10, with a star bonus (2× to 11×) from last season's rank that drops by 1 at each floor crossed |
| Rating | hidden MMR for pairing; Mythic is Elo-like | hidden MMR for pairing, not reset |

Our tiers are a third shorter than Arena's (4 pips per division against 6 steps), and our reset (one tier down,
keeping the division) is already close to Arena's table. What we lack from both games is protection, and Arena's
cheaper low tiers.

## What every option keeps

- Six tiers, four divisions, **four pips per division, and the points encoding** (step × 4 + pips, Mythic from 80).
  Arena's 6 steps per tier is tempting, but the encoding is in the server's standings, its rank history
  (`player_games.rank_points`), the public cards (`rank_step`/`pips`), the queue and challenge tier checks, the seed
  cap, the CHECK constraints, both apps' `RankPosition` and the parity file. Changing it means converting every stored
  standing and history point for no feel that the win/loss steps can't give. Not proposed.
- The underdog bonus, draws, the AI and pair caps, the tickets and the referee flow.
- The opponent brackets and AI skill per tier, and the queue's "within one tier" rule.

## Option A: tier floors

**Rule:** a loss never takes you below division IV of the tier you are in. Mythic can fall back to Diamond, but never
below Diamond IV. Everything else is today's ladder. You can't fall out of a tier, so this is also the start of the
highest tier reached this season, and it needs no new stored state (it reads only the current points, so standings
imported or seeded with a peak above their points are safe).

**RankLadder.swift**, in `RankLadder.apply`, replace `next.position = RankPosition(points: state.position.points + delta)`:

```swift
// A loss never takes you out of your tier (Mythic can fall back to Diamond, never below Diamond IV).
let floor = RankPosition.atStep(min(state.position.tier, .diamond).rawValue * RankPosition.divisions).points
next.position = RankPosition(points: max(state.position.points + delta, floor))
```

**Ranked.kt**, in `RankLadder.apply`, replace `val position = RankPosition.ofPoints(state.position.points + delta)`:

```kotlin
// A loss never takes you out of your tier (Mythic can fall back to Diamond, never below Diamond IV).
val floor = minOf(state.position.tier, RankTier.DIAMOND).ordinal * RankPosition.DIVISIONS * RankPosition.PIPS_PER_DIVISION
val position = RankPosition.ofPoints(maxOf(state.position.points + delta, floor))
```

**ranked-cases.json** (`ladder`): change one case and add one.

```json
{"name": "a loss at the bottom of a tier holds at the floor", "before": {"tier": "gold", "division": 4, "pips": 0}, "streak": 0, "outcome": "loss", "deckBracket": 2, "after": {"tier": "gold", "division": 4, "pips": 0}, "streakAfter": 0, "delta": 0, "bonuses": [], "kind": "none"},
{"name": "Diamond IV with no pips holds at the floor", "before": {"tier": "diamond", "division": 4, "pips": 0}, "streak": 0, "outcome": "loss", "deckBracket": 4, "after": {"tier": "diamond", "division": 4, "pips": 0}, "streakAfter": 0, "delta": 0, "bonuses": [], "kind": "none"}
```

The first replaces "a loss at the bottom of a tier drops the tier". "a loss at Mythic 0 falls to Diamond I" stays as it
is, and so do the rollover cases.

**Referee SQL**, in `mm_ranked_apply`, replace the `v_after` line:

```sql
v_after := least(greatest(s.points + v_delta, least(public.mm_rank_points_step(s.points) / 4, 4) * 16), 100080);
```

The rollover in `mm_ranked_current` is unchanged.

**Elsewhere:** the ranked rules text (`PlayModeViews.swift` line 401, `RankedViews.kt` line 498) becomes "… with none
left a loss drops you a division, but never out of your tier." `docs/RANKED.md` (The ladder) gets the same sentence.

## Option B: Arena steps and floors (recommended)

**Rule:**

- A win earns 2 pips in Bronze, Silver and Gold and 1 in Platinum, Diamond and Mythic. A loss costs nothing in Bronze
  and 1 pip elsewhere (Arena's Bo1 steps).
- Option A's floor: a loss never takes you below division IV of your tier; Mythic can fall back to Diamond (never
  below Diamond IV).
- The underdog bonus stays (+1 per win). The streak bonus ends, because two-pip wins replace it (Arena has no streak
  bonus). The win streak still counts for the profile and achievements.
- The season reset stays one tier down, which is close to Arena's table.

**RankLadder.swift**, add to `RankTier`:

```swift
/// Pips a ranked win earns here (Arena's Bo1 steps): two up to Gold, one from Platinum.
var winPips: Int { self <= .gold ? 2 : 1 }
/// Pips a ranked loss costs here: none in Bronze.
var lossPips: Int { self == .bronze ? 0 : 1 }
```

and in `RankLadder.apply`:

```swift
case .win:
    next.wins += 1
    next.winStreak += 1
    delta = state.position.tier.winPips
    if deckBracket < state.position.tier.opponentBrackets.lowerBound { delta += 1; bonuses.append(.underdog) }
case .loss:
    next.losses += 1
    next.winStreak = 0
    delta = -state.position.tier.lossPips
...
// A loss never takes you out of your tier (Mythic can fall back to Diamond, never below Diamond IV).
let floor = RankPosition.atStep(min(state.position.tier, .diamond).rawValue * RankPosition.divisions).points
next.position = RankPosition(points: max(state.position.points + delta, floor))
```

Keep `RankChange.Bonus.streak` so saved match records that carry it still decode; it is just never awarded again.

**Ranked.kt**, add to `RankTier`:

```kotlin
/** Pips a ranked win earns here (Arena's Bo1 steps): two up to Gold, one from Platinum. */
val winPips: Int get() = if (this <= GOLD) 2 else 1
/** Pips a ranked loss costs here: none in Bronze. */
val lossPips: Int get() = if (this == BRONZE) 0 else 1
```

and in `RankLadder.apply`:

```kotlin
RankOutcome.WIN -> {
    wins++; streak++; delta = state.position.tier.winPips
    if (deckBracket < state.position.tier.opponentBrackets.first) { delta++; bonuses += RankBonus.UNDERDOG }
}
RankOutcome.LOSS -> { losses++; streak = 0; delta = -state.position.tier.lossPips }
...
// A loss never takes you out of your tier (Mythic can fall back to Diamond, never below Diamond IV).
val floor = minOf(state.position.tier, RankTier.DIAMOND).ordinal * RankPosition.DIVISIONS * RankPosition.PIPS_PER_DIVISION
val position = RankPosition.ofPoints(maxOf(state.position.points + delta, floor))
```

Keep `RankBonus.STREAK` for the same reason.

**ranked-cases.json** (`ladder`): replace the whole array with these 16 cases. They are the same rows as the server's
pending test (`supabase/tests/ladder_option_b.sql`), and an independent Python model of the rules produced them, so
the apps, the server and the simulation agree. The rollover cases are unchanged.

```json
[
  {"name": "a Bronze win earns two pips", "before": {"tier": "bronze", "division": 4, "pips": 0}, "streak": 0, "outcome": "win", "deckBracket": 2, "after": {"tier": "bronze", "division": 4, "pips": 2}, "streakAfter": 1, "delta": 2, "bonuses": [], "kind": "pipUp"},
  {"name": "no streak bonus: the third straight win is +2", "before": {"tier": "bronze", "division": 4, "pips": 2}, "streak": 2, "outcome": "win", "deckBracket": 2, "after": {"tier": "bronze", "division": 3, "pips": 0}, "streakAfter": 3, "delta": 2, "bonuses": [], "kind": "divisionUp"},
  {"name": "a Bronze loss costs nothing", "before": {"tier": "bronze", "division": 3, "pips": 2}, "streak": 1, "outcome": "loss", "deckBracket": 2, "after": {"tier": "bronze", "division": 3, "pips": 2}, "streakAfter": 0, "delta": 0, "bonuses": [], "kind": "none"},
  {"name": "Bronze IV with no pips can't fall", "before": {"tier": "bronze", "division": 4, "pips": 0}, "streak": 1, "outcome": "loss", "deckBracket": 2, "after": {"tier": "bronze", "division": 4, "pips": 0}, "streakAfter": 0, "delta": 0, "bonuses": [], "kind": "none"},
  {"name": "a Silver win can carry into the next division", "before": {"tier": "silver", "division": 2, "pips": 3}, "streak": 0, "outcome": "win", "deckBracket": 2, "after": {"tier": "silver", "division": 1, "pips": 1}, "streakAfter": 1, "delta": 2, "bonuses": [], "kind": "divisionUp"},
  {"name": "Silver I's last pip carries into Gold", "before": {"tier": "silver", "division": 1, "pips": 3}, "streak": 0, "outcome": "win", "deckBracket": 2, "after": {"tier": "gold", "division": 4, "pips": 1}, "streakAfter": 1, "delta": 2, "bonuses": [], "kind": "tierUp"},
  {"name": "a Gold loss empties a pip", "before": {"tier": "gold", "division": 3, "pips": 2}, "streak": 4, "outcome": "loss", "deckBracket": 3, "after": {"tier": "gold", "division": 3, "pips": 1}, "streakAfter": 0, "delta": -1, "bonuses": [], "kind": "pipDown"},
  {"name": "Gold IV with no pips holds at the floor", "before": {"tier": "gold", "division": 4, "pips": 0}, "streak": 0, "outcome": "loss", "deckBracket": 2, "after": {"tier": "gold", "division": 4, "pips": 0}, "streakAfter": 0, "delta": 0, "bonuses": [], "kind": "none"},
  {"name": "Silver underdog win: +2 and +1", "before": {"tier": "silver", "division": 4, "pips": 0}, "streak": 2, "outcome": "win", "deckBracket": 1, "after": {"tier": "silver", "division": 4, "pips": 3}, "streakAfter": 3, "delta": 3, "bonuses": ["underdog"], "kind": "pipUp"},
  {"name": "Platinum win is one pip, underdog one more", "before": {"tier": "platinum", "division": 4, "pips": 1}, "streak": 5, "outcome": "win", "deckBracket": 2, "after": {"tier": "platinum", "division": 4, "pips": 3}, "streakAfter": 6, "delta": 2, "bonuses": ["underdog"], "kind": "pipUp"},
  {"name": "a Platinum loss drops a division within the tier", "before": {"tier": "platinum", "division": 3, "pips": 0}, "streak": 0, "outcome": "loss", "deckBracket": 3, "after": {"tier": "platinum", "division": 4, "pips": 3}, "streakAfter": 0, "delta": -1, "bonuses": [], "kind": "divisionDown"},
  {"name": "Diamond I's fourth pip reaches Mythic", "before": {"tier": "diamond", "division": 1, "pips": 3}, "streak": 0, "outcome": "win", "deckBracket": 4, "after": {"tier": "mythic", "division": 0, "pips": 0}, "streakAfter": 1, "delta": 1, "bonuses": [], "kind": "tierUp"},
  {"name": "Diamond IV with no pips holds at the floor", "before": {"tier": "diamond", "division": 4, "pips": 0}, "streak": 0, "outcome": "loss", "deckBracket": 4, "after": {"tier": "diamond", "division": 4, "pips": 0}, "streakAfter": 0, "delta": 0, "bonuses": [], "kind": "none"},
  {"name": "Mythic counts up", "before": {"tier": "mythic", "division": 0, "pips": 5}, "streak": 0, "outcome": "win", "deckBracket": 3, "after": {"tier": "mythic", "division": 0, "pips": 7}, "streakAfter": 1, "delta": 2, "bonuses": ["underdog"], "kind": "pipUp"},
  {"name": "a loss at Mythic 0 falls to Diamond I", "before": {"tier": "mythic", "division": 0, "pips": 0}, "streak": 0, "outcome": "loss", "deckBracket": 4, "after": {"tier": "diamond", "division": 1, "pips": 3}, "streakAfter": 0, "delta": -1, "bonuses": [], "kind": "tierDown"},
  {"name": "a draw changes nothing and ends the streak", "before": {"tier": "silver", "division": 3, "pips": 1}, "streak": 2, "outcome": "draw", "deckBracket": 2, "after": {"tier": "silver", "division": 3, "pips": 1}, "streakAfter": 0, "delta": 0, "bonuses": [], "kind": "none"}
]
```

Optionally add `"winPips"` and `"lossPips"` to each `tiers` row (2/0, 2/1, 2/1, 1/1, 1/1, 1/1) and check them in both
parity tests, next to `aiSkill`.

**Two app test expectations change** (a first ranked win from Bronze IV now lands on 2 pips, not 1):
`RankedParityTest.kt` line 167 (`recordStoreRanksAndRollsOver`) and `RankedParityTests.swift` line 195
(`testRankedMovesTheLadderAndQuickDoesNot`) become `BRONZE, 4, 2` / `.bronze, division: 4, pips: 2`. Nothing else in
either test suite depends on the steps.

**Checked in the cloud (Android JVM core only):** a scratch copy of the repo with exactly the Kotlin above, the
`ladder` array above and that one expectation changed passed the whole `:core:test` run (250 tests in 32 classes,
0 failures, Gradle 8.11.1, JDK 21, from a throwaway root that includes only `apps/android/core`). Without the
expectation change only `recordStoreRanksAndRollsOver` fails. Nothing from that copy is committed. The Swift half
has not been compiled (there is no Swift toolchain in the cloud).

**Referee SQL:** only `mm_ranked_apply` changes. Its full replacement is in `supabase/pending/ladder_option_b.sql`
(pending Caleb's choice, tested by `npm run test:ranked-pending --prefix supabase/tests`). The core:

```sql
v_tier integer := least(public.mm_rank_points_step(s.points) / 4, 5);   -- 0 Bronze … 5 Mythic
...
if p_outcome = 'win' then
  v_delta := (array[2, 2, 2, 1, 1, 1])[v_tier + 1];          -- no streak bonus
  ... underdog as today ...
elsif p_outcome = 'loss' then
  v_delta := -(array[0, 1, 1, 1, 1, 1])[v_tier + 1];
...
v_after := least(greatest(s.points + v_delta, least(v_tier, 4) * 16), 100080);   -- the tier floor
```

The rollover in `mm_ranked_current` is unchanged, and so are the friend-challenge tier checks.

**Elsewhere:**

- Ranked rules text (`PlayModeViews.swift` lines 400–402, `RankedViews.kt` lines 497–499): "Wins earn two pips up to
  Gold and one from Platinum. Losses cost nothing in Bronze and one pip above it. Four pips win a division, and a loss
  never drops you out of your tier." Remove the "Three wins in a row below Gold" line.
- The result screen and ceremony already show "+2 pips" (`RankCeremonyView.swift` line 54); the "Win streak +1" tag
  (`RankCeremonyView.swift` line 35, `RankedViews.kt` line 601) simply stops appearing.
- `docs/RANKED.md` (The ladder) and the server note in the referee migration's header comment describe the new steps.

## Option C: Hearthstone reset and climb bonus

**Rule:**

- Losses −1 and option A's floor, except that Mythic is a floor too (like Legend: you can't drop out of Mythic).
- Every season starts everyone at Bronze IV with a climb bonus of 1 + last season's best tier (Bronze 1 up to Mythic 6).
  A win earns the climb bonus in pips, doubled from the third straight win below Diamond, plus the underdog pip. The
  climb bonus drops by 1 at each new tier reached (never below 1).

**Stored state on all three:** a climb bonus per standing.

- `RankState.climbBonus` (Swift needs a custom `init(from:)` with `decodeIfPresent` so saved records without it load;
  Kotlin `val climbBonus: Int = 1` is enough). `RankLadder.rollover` sets `position = .start`, `peak = .start` and
  `climbBonus = 1 + min(state.peak.tier, .mythic).rawValue`. `RankLadder.apply` computes the win as
  `climbBonus * (tier < .diamond && winStreak >= 3 ? 2 : 1)` (+1 underdog), floors losses at the start of the current
  tier (Mythic included) and lowers `climbBonus` by the number of tiers crossed. `RankChange.Bonus.streak` now means
  "doubled".
- `RankedStanding` gets `climbBonus`; `PlayerRecordStore.adopt` / `PlayerRecordFile.adopting` take it.
- **ranked-cases.json:** every `ladder` case gets `climbBonus` and `climbBonusAfter` (1 when absent), with new cases
  for a bonus of 5, a bonus dropping at a tier, the doubled streak and the Mythic floor; every `rollover` case's
  `after` becomes Bronze IV 0 plus an expected `climbBonus` (Gold peak 3, Mythic 6, unplayed 1). Both parity tests
  read the new fields.
- **SQL:** `alter table ranked_standings add column climb_bonus integer not null default 1 check (climb_bonus between 1 and 6)`.
  `mm_ranked_current`'s rollover sets `points = 0`, `peak_points = 0` and
  `climb_bonus = 1 + least(mm_rank_points_step(s.peak_points) / 4, 5)`. `mm_ranked_apply` uses the new win and floor
  rules and lowers `climb_bonus`. `mm_ranked_standing` returns `climbBonus`. The friend challenges'
  `mm_current_rank_step` must read a stale season as 0 (Bronze IV) instead of `rank_step - 4`, and so must both apps'
  `FriendChallenges` "rolled over one tier" rule.
- **Matchmaking:** for the first days of a season, returning Diamond players meet new players in Bronze, because the
  queue pairs within one tier and we have no hidden rating (Hearthstone pairs on a hidden MMR for exactly this reason).

## Simulation

`python3 scripts/ranked/simulate_ladder.py` (seeded, 20,000 seasons per row, up to 3,000 games each). Each season plays
at a fixed win rate with no draws and no underdog decks. It is a model: in real ranked play the AI gets harder by tier,
so a player's win rate falls as they climb, and the server allows at most 12 counted AI wins per UTC day.

### Fresh player, from Bronze IV: median games to reach each tier (share who reach it by game 100)

At a 50% win rate:

| Ladder | Silver | Gold | Platinum | Diamond | Mythic |
|---|---|---|---|---|---|
| Today | 72 (68%) | 181 (16%) | 540 (0%) | 1274 (0%) | 2405 (0%) |
| A: tier floors | 71 (68%) | 157 (21%) | 392 (0%) | 655 (0%) | 926 (0%) |
| **B: Arena steps + floors** | **16 (100%)** | **42 (99%)** | **71 (89%)** | **280 (1%)** | **550 (0%)** |
| C: Hearthstone reset + climb bonus | 71 (68%) | 157 (20%) | 243 (2%) | 329 (0%) | 571 (0%) |

At a 60% win rate:

| Ladder | Silver | Gold | Platinum | Diamond | Mythic |
|---|---|---|---|---|---|
| Today | 33 (99%) | 71 (81%) | 144 (14%) | 222 (0%) | 301 (0%) |
| A: tier floors | 34 (99%) | 69 (84%) | 136 (16%) | 205 (0%) | 275 (0%) |
| **B: Arena steps + floors** | **13 (100%)** | **31 (100%)** | **50 (100%)** | **114 (32%)** | **183 (0%)** |
| C: Hearthstone reset + climb bonus | 33 (99%) | 69 (84%) | 104 (45%) | 140 (12%) | 207 (0%) |

### Median games spent in each tier

| Ladder | Bronze 50% | Silver 50% | Gold 50% | Platinum 50% | Diamond 50% | Bronze 60% | Silver 60% | Gold 60% | Platinum 60% | Diamond 60% |
|---|---|---|---|---|---|---|---|---|---|---|
| Today | 72 | 86 | 313 | 428 | 302 | 33 | 33 | 66 | 70 | 70 |
| A | 71 | 69 | 207 | 207 | 209 | 34 | 31 | 61 | 62 | 62 |
| **B** | **16** | **26** | **26** | **205** | **208** | **13** | **18** | **18** | **61** | **62** |
| C (fresh) | 71 | 69 | 68 | 69 | 206 | 33 | 31 | 31 | 31 | 61 |

### Returning player whose last season ended at Diamond IV: median games back to Diamond IV

| Ladder | Starts the season at | 50% | 60% |
|---|---|---|---|
| Today | Platinum IV | 546 (11%) | 70 (76%) |
| A | Platinum IV | 207 (20%) | 62 (84%) |
| B | Platinum IV | 207 (20%) | 62 (84%) |
| C | Bronze IV, climb bonus 5 | 43 (99%) | 30 (100%) |

What the numbers say:

- **Today**, a 50% player takes about 180 games to leave Silver and about 540 to reach Platinum, so most players spend
  the month in Bronze and Silver. Above Silver the walk is +1/−1 with nothing to hold you, so that is all variance.
- **A** only removes the downside: Gold to Diamond drop from about 300–430 games per tier to about 207 at 50%. A 50%
  player still never sees Platinum in a month.
- **B** makes Bronze to Gold the "everyone climbs" part: a 50% player reaches Platinum in about 71 games (89% within
  100). From Platinum up it is +1/−1 with a floor, so Diamond and Mythic still need a winning record (about 61 games
  per tier at 60%, about 205 at 50%). A 60% player reaches Mythic in about 183 games, against 301 today.
- **C** makes returning players fast (back to Diamond in 30–43 games) and fresh players at 60% faster up to Diamond
  than today, but a fresh 50% player gets little: the doubled streak only helps a winning record.

## Recommendation: B

1. **It fixes what players feel.** Bronze can't be lost. Caleb's sense is that even Bronze is hard, and C2 will make
   the Bronze AI easier in R2, but the ladder shouldn't punish a new player meanwhile. A bad night can no longer cost a
   tier. A 50% player sees Platinum within a month instead of never.
2. **The top still means something.** Platinum and up stay +1/−1, so Diamond and Mythic need a winning record, as on
   Arena. That matters more here because AI skill and deck brackets rise with the tier.
3. **It is the smallest real change.** One SQL function, two small `RankTier` properties and a few lines of `apply` on
   each platform, and a new `ladder` array in the parity file. There is no new stored state, no schema change and no
   change to the points encoding, the rank history, the rollover, the friend challenges or the queue. The server SQL
   is already written and tested (`supabase/pending/ladder_option_b.sql`).
4. **It matches the game the app is modelled on.** The tiers, divisions, monthly seasons and one-tier reset already
   follow Arena; B takes Arena's steps and protection too.

The trade-off: the "Win streak +1" moment goes, because two-pip wins up to Gold replace it.

A is the fallback if Caleb wants the lightest touch: it is safe and tiny, but a 50% player still sits in Silver and Gold.
C is the most different, needs new stored state on all three sides and a friend-challenge change, and without a hidden
rating it mixes returning Diamond players into Bronze at the start of each month.

## Rolling it out (any option)

- Ship the app rules and the server SQL in the same release (R1: TestFlight 39 / Android 23). The phones show their own
  result at once and then adopt the server's standing, so if the two disagree, the phone's pip corrects itself after
  the sync. That is harmless, but it looks like a flicker.
- Applying the SQL at the start of a season (1 November 00:00 UTC) means nobody's month mixes two rule sets. Applying
  it mid-season is also safe for A and B: their floors read only the current points, so no standing needs converting.
- The Mac session moves `supabase/pending/ladder_option_b.sql` into `supabase/migrations/` with a new timestamp, moves
  its test from the `--pending` run into the main `verify-ranked.mjs` order, and applies it live with Caleb's OK.

## NEEDS CALEB

- **Which ladder: A, B (recommended) or C?** Or today's ladder unchanged.
- **When:** with R1, or on 1 November at the season change.
