STATUS: ready-for-review

# Power 2: the same decks with no AI mistakes and at skill 5

Cloud session for docs/cloud/power-skill-test.md (approved by Caleb, 2026-10-25). Branch `claude/deck-power-design`.
Measurement only: no weights, formula, `ai-decks.json`, app or engine changes; nothing merged, released or uploaded.

## Answer

**Not the misplays.** With mistakes off (C), the four weak Optimized decks win 33% against the references, against 30%
with mistakes; The First Sliver goes from 15% to 11%. The Optimized-minus-Core gap narrows only because the Core decks
fall (52% to 44%, inside noise).

**Partly the AI's limits, for two decks.** At skill 5 (D), Lathril Optimized (33% to 51%) and Gishath Optimized (44% to
63%) catch up with their Core decks, and the four weak Optimized decks together rise from 30% to 40% (+11%, +0% to
+21%) while the three Core decks stay at 51–52%.

**Wilhelt Optimized and The First Sliver look overrated by the formula, not misplayed.** Wilhelt Optimized plays 25–31%
at every setting, at or below its Core deck. The First Sliver is the weakest deck at every setting (15%, 11%, 23%); a
stronger AI moves it a little but nowhere near its formula Power (6.8 in v1, 6.5 in v2). These games cannot tell a
formula miss from an AI weakness deeper than skill 5 (power-1's hypothesis about Sliver activated abilities is still
unchecked), but neither removing mistakes nor the expert AI makes it play strong.

**Krenko** is an ordinary deck at every setting: Optimized 66%, 61%, 53% and Core 64%, 47%, 56%. It does not stand out
once the mistakes go, and its Optimized edge over Core (+2%, +14%, −3%) is inside noise each time.

## What ran

- **Engine.** Branch HEAD `0062d807` when the runs began. `engine/`, `platform/`, `tools/`, `scripts/` (engine
  package) and `upstream.lock.json` are identical to power-1.md's `37226f4` (empty diff). Upstream XMage
  `dac400ba1380f17492c9ad6a65ab60f12f28cd97`. 4 CPUs, 15 GB, JDK 21.0.12, Maven 3.9.11. `bash scripts/build_jvm.sh`:
  BUILD SUCCESS, "Adapter compilation completed". `ai_calibration.py decks`: exits 0, all decks resolve.
- **Settings.** Phone budget, default heap, 4 workers, default seed. Both seats always on the same settings. Skill 5
  is depth 5, 0% mistakes, expert (`AIDifficulty`).
- **Smoke.** 4 games of batch D (The First Sliver against Grave Danger): all ended normally, 15–24 turns, 35–118 s,
  0 mistakes in either seat (one real draw). Deleted afterwards.
- **Batch C**, 324 games, 15:09–16:11 UTC (59 min), skill 3 with mistakes off (depth 4, 0%):

  ```
  python3 scripts/ai_calibration.py run --skill-a 3 --skill-b 3 --mistake-a 0 --mistake-b 0 --against $REFS \
    --pool $POOL --games 324 --out "$R/docs/cloud/skill-results/batch-c"
  ```

- **Batch D**, 324 games, 16:11–17:49 UTC (97 min), skill 5:

  ```
  python3 scripts/ai_calibration.py run --skill-a 5 --skill-b 5 --against $REFS \
    --pool $POOL --games 324 --out "$R/docs/cloud/skill-results/batch-d"
  ```

`POOL` and `REFS` as in the brief. Data: `docs/cloud/skill-results/batch-c/` and `batch-d/`, outside `power-results/`,
so `deck_power.py check` and `rate` do not read them. Baseline: these nine decks' 372 games in `power-results/batch-a`
and `batch-b` (skill 3, 10% mistakes), not replayed.

While D ran, Caleb's session pushed Deck Power v2 (`8796007`, weights refit, `deck-power-ratings.json`) and eight new
decks (`1ec9392`) to this branch; my commits were rebased on top. Neither touches the engine or these nine decks' lists.
The tables below give v1 Power (the brief's, power-1.md's) and v2's formula and game-based Power for reference.

## Games

| Setting | Games | Ended normally | Draws | Replayed | Mistakes per seat per game (A, B) |
|---|---|---|---|---|---|
| Baseline (skill 3, 10%) | 372 | 372 | 2 | 0 | 2.10, 2.26 |
| C (skill 3, 0%) | 324 | 324 | 2 | 0 | 0.00, 0.00 |
| D (skill 5) | 324 | 324 | 4 | 0 | 0.00, 0.00 |

Every draw ended normally (both players lost at once); no game hit the turn or 30-minute limit. No harness failures.

## Each deck against the three references

Wins–losses, win rate and Wilson 95% interval; draws left out. 36 games per deck per setting (48 for the Optimized
decks in batch A's baseline).

| Deck | Power v1 | v2 formula / v2 rated | Baseline (skill 3, 10%) | C (skill 3, 0%) | D (skill 5) |
|---|---|---|---|---|---|
| ai-the-first-sliver-optimized | 6.8 | 6.5 / 2.2 | 7–40, 15% (7–28) | 4–31, 11% (5–26) | 8–27, 23% (12–39) |
| ai-lathril-blade-of-the-elves-optimized | 5.7 | 5.2 / 3.8 | 16–32, 33% (22–47) | 11–25, 31% (18–47) | 18–17, 51% (36–67) |
| ai-lathril-blade-of-the-elves-core | 5.3 | 5.7 / 5.2 | 19–17, 53% (37–68) | 15–21, 42% (27–58) | 20–16, 56% (40–70) |
| ai-wilhelt-the-rotcleaver-optimized | 6.1 | 6.0 / 3.6 | 14–34, 29% (18–43) | 11–24, 31% (19–48) | 9–27, 25% (14–41) |
| ai-wilhelt-the-rotcleaver-core | 4.7 | 5.0 / 4.4 | 14–22, 39% (25–55) | 10–26, 28% (16–44) | 14–22, 39% (25–55) |
| ai-gishath-suns-avatar-optimized | 7.1 | 7.3 / 5.9 | 16–20, 44% (30–60) | 21–15, 58% (42–73) | 22–13, 63% (46–77) |
| ai-gishath-suns-avatar-core | 6.7 | 7.4 / 7.9 | 23–13, 64% (48–78) | 23–13, 64% (48–78) | 21–14, 60% (44–74) |
| ai-krenko-mob-boss-optimized | 5.6 | 6.0 / 7.9 | 31–16, 66% (52–78) | 22–14, 61% (45–75) | 19–17, 53% (37–68) |
| ai-krenko-mob-boss-core | 5.3 | 5.9 / 6.4 | 23–13, 64% (48–78) | 17–19, 47% (32–63) | 20–16, 56% (40–70) |

Pooled: the four weak Optimized decks (Sliver, Lathril, Wilhelt, Gishath) 30% (23–37), 33% (26–41), 40% (33–49); the
three Core decks 52% (43–61), 44% (35–54), 51% (42–61); all nine 44%, 42%, 47%. The references play at the same
setting as the deck, so these are strengths relative to the references under each AI, not absolute.

By reference:

| Deck | Setting | vs First Flight | vs Token Triumph | vs Grave Danger |
|---|---|---|---|---|
| ai-the-first-sliver-optimized | Baseline | 2–13 | 4–12 | 1–15 |
| | C | 0–11 | 1–11 | 3–9 |
| | D | 3–9 | 1–11 | 4–7 |
| ai-lathril-blade-of-the-elves-optimized | Baseline | 5–11 | 6–10 | 5–11 |
| | C | 3–9 | 5–7 | 3–9 |
| | D | 7–5 | 6–5 | 5–7 |
| ai-lathril-blade-of-the-elves-core | Baseline | 5–7 | 7–5 | 7–5 |
| | C | 5–7 | 5–7 | 5–7 |
| | D | 7–5 | 6–6 | 7–5 |
| ai-wilhelt-the-rotcleaver-optimized | Baseline | 6–10 | 2–14 | 6–10 |
| | C | 4–8 | 1–11 | 6–5 |
| | D | 5–7 | 1–11 | 3–9 |
| ai-wilhelt-the-rotcleaver-core | Baseline | 6–6 | 3–9 | 5–7 |
| | C | 5–7 | 3–9 | 2–10 |
| | D | 5–7 | 6–6 | 3–9 |
| ai-gishath-suns-avatar-optimized | Baseline | 5–7 | 7–5 | 4–8 |
| | C | 6–6 | 6–6 | 9–3 |
| | D | 6–6 | 6–6 | 10–1 |
| ai-gishath-suns-avatar-core | Baseline | 9–3 | 7–5 | 7–5 |
| | C | 8–4 | 8–4 | 7–5 |
| | D | 6–6 | 7–4 | 8–4 |
| ai-krenko-mob-boss-optimized | Baseline | 6–10 | 12–3 | 13–3 |
| | C | 9–3 | 5–7 | 8–4 |
| | D | 8–4 | 5–7 | 6–6 |
| ai-krenko-mob-boss-core | Baseline | 7–5 | 8–4 | 8–4 |
| | C | 5–7 | 7–5 | 5–7 |
| | D | 7–5 | 8–4 | 5–7 |

Wilhelt Optimized goes 4–33 against Token Triumph over the three settings.

## Optimized minus Core

Win-rate difference against the references, normal 95% interval; pooled is precision-weighted over the first three.

| Commander | Baseline | C (no mistakes) | D (skill 5) |
|---|---|---|---|
| Lathril | −19% (−41% to +2%) | −11% (−33% to +11%) | −4% (−27% to +19%) |
| Wilhelt | −10% (−30% to +11%) | +4% (−18% to +25%) | −14% (−35% to +7%) |
| Gishath | −19% (−42% to +3%) | −6% (−28% to +17%) | +3% (−20% to +26%) |
| Lathril + Wilhelt + Gishath | **−16% (−28% to −4%)** | −4% (−17% to +9%) | −5% (−18% to +7%) |
| Krenko (control) | +2% (−19% to +23%) | +14% (−9% to +37%) | −3% (−26% to +20%) |

Only the baseline's pooled gap is clearly below zero. In C it closes because the Core decks drop (Lathril Core −11%,
Wilhelt Core −11%, Krenko Core −17%, each inside noise), not because the Optimized decks rise. In D it closes because
Lathril and Gishath Optimized rise (+18% each, intervals −3% to +39% and −4% to +41%); Wilhelt Optimized does not.

Change from the baseline, per deck: The First Sliver C −3% (−18 to +11), D +8% (−9 to +25); Lathril Optimized −3%,
+18%; Lathril Core −11%, +3%; Wilhelt Optimized +2%, −4%; Wilhelt Core −11%, +0%; Gishath Optimized +14%, +18%;
Gishath Core +0%, −4%; Krenko Optimized −5%, −13%; Krenko Core −17%, −8%. No single deck's change is outside its
interval.

## What the data cannot tell

- AI against AI only, on the JVM engine in the cloud; nothing about how these decks play for a person or on a phone.
- 36 games per deck per setting: a single deck's interval is about ±16 points, so only pooled or large moves are
  clear. Searches stop on a clock, so reruns agree statistically, not move for move.
- Both seats change together, so a setting that helps the references as much as a deck shows no change for it.
- Whether The First Sliver and Wilhelt Optimized are weak decks or decks the AI can't pilot even at skill 5. No game was
  replayed move by move.
- None of these games enter `check`, `rate` or v2's ratings (they are outside `power-results/`). v2's rated Power for
  these decks comes from skill-3-with-mistakes games; at skill 5 Lathril and Gishath Optimized play above it.

## How long games took

| Setting | Wall time (4 workers) | Play time | Mean s/game | Median | Longest | Turns | Going first won |
|---|---|---|---|---|---|---|---|
| Baseline | (part of power-1's batches) | 3.8 h | 36 | 20 | 367 | 16.8 | 61% |
| C | 59 min | 3.9 h | 44 | 28 | 255 | 16.8 | 61% |
| D | 97 min | 6.5 h | 72 | 42 | 503 | 17.3 | 59% |

Skill 5 took about 1.6 times as long per game as C. Slowest decks in D: Krenko Core 112 s, Lathril Core 97 s,
Wilhelt Optimized 92 s; fastest Gishath Core 34 s.

## What did not run

- No runs beyond batches C and D; no reruns (nothing failed). No weights, formula, `ai-decks.json`, app or engine
  change; no `check`/`rate` over these games (retuning is another session's). No unit tests (no code changed).
- No native, iOS, Android or phone runs; no move-by-move replay of any game.

## Outputs

### `ai_calibration.py summarize --by-deck`, batch C

| Deck | Games | Wins | Losses | Draws | Win rate (95% CI) | In seat A: wins | In seat B: wins |
|---|---|---|---|---|---|---|---|
| ai-gishath-suns-avatar-core | 36 | 23 | 13 | 0 | 64% (48–78) | 12/18 | 11/18 |
| token-triumph | 108 | 67 | 41 | 0 | 62% (53–71) | 33/54 | 34/54 |
| ai-krenko-mob-boss-optimized | 36 | 22 | 14 | 0 | 61% (45–75) | 12/18 | 10/18 |
| ai-gishath-suns-avatar-optimized | 36 | 21 | 15 | 0 | 58% (42–73) | 12/18 | 9/18 |
| first-flight | 108 | 62 | 45 | 1 | 58% (48–67) | 35/54 | 27/53 |
| grave-danger | 108 | 59 | 48 | 1 | 55% (46–64) | 30/53 | 29/54 |
| ai-krenko-mob-boss-core | 36 | 17 | 19 | 0 | 47% (32–63) | 8/18 | 9/18 |
| ai-lathril-blade-of-the-elves-core | 36 | 15 | 21 | 0 | 42% (27–58) | 8/18 | 7/18 |
| ai-wilhelt-the-rotcleaver-optimized | 36 | 11 | 24 | 1 | 31% (19–48) | 6/18 | 5/17 |
| ai-lathril-blade-of-the-elves-optimized | 36 | 11 | 25 | 0 | 31% (18–47) | 7/18 | 4/18 |
| ai-wilhelt-the-rotcleaver-core | 36 | 10 | 26 | 0 | 28% (16–44) | 4/18 | 6/18 |
| ai-the-first-sliver-optimized | 36 | 4 | 31 | 1 | 11% (5–26) | 2/17 | 2/18 |

### `ai_calibration.py summarize --by-deck`, batch D

| Deck | Games | Wins | Losses | Draws | Win rate (95% CI) | In seat A: wins | In seat B: wins |
|---|---|---|---|---|---|---|---|
| ai-gishath-suns-avatar-optimized | 36 | 22 | 13 | 1 | 63% (46–77) | 12/17 | 10/18 |
| ai-gishath-suns-avatar-core | 36 | 21 | 14 | 1 | 60% (44–74) | 11/17 | 10/18 |
| token-triumph | 108 | 60 | 46 | 2 | 57% (47–66) | 33/53 | 27/53 |
| ai-lathril-blade-of-the-elves-core | 36 | 20 | 16 | 0 | 56% (40–70) | 9/18 | 11/18 |
| ai-krenko-mob-boss-core | 36 | 20 | 16 | 0 | 56% (40–70) | 12/18 | 8/18 |
| ai-krenko-mob-boss-optimized | 36 | 19 | 17 | 0 | 53% (37–68) | 9/18 | 10/18 |
| grave-danger | 108 | 55 | 51 | 2 | 52% (42–61) | 26/54 | 29/52 |
| ai-lathril-blade-of-the-elves-optimized | 36 | 18 | 17 | 1 | 51% (36–67) | 9/18 | 9/17 |
| first-flight | 108 | 54 | 54 | 0 | 50% (41–59) | 27/54 | 27/54 |
| ai-wilhelt-the-rotcleaver-core | 36 | 14 | 22 | 0 | 39% (25–55) | 6/18 | 8/18 |
| ai-wilhelt-the-rotcleaver-optimized | 36 | 9 | 27 | 0 | 25% (14–41) | 4/18 | 5/18 |
| ai-the-first-sliver-optimized | 36 | 8 | 27 | 1 | 23% (12–39) | 4/17 | 4/18 |

Both seats play the same skill here, so the seat A/B columns are just the two seatings.
