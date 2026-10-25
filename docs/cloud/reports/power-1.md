STATUS: ready-for-review

# Power 1: deck Power gauntlet

Cloud session for docs/cloud/power-gauntlet.md (approved by Caleb, 2026-10-24). Branch `claude/deck-power-design`.
Measurement only: no weights, formula, `ai-decks.json`, app or engine changes; nothing merged, released or uploaded.

## What ran

- **Engine.** Branch HEAD `37226f4`. Its `engine/`, `platform/`, `tools/` and upstream pin are identical to main
  `bc3f029`; only `scripts/ai_calibration.py` (the `--against` option) and its test differ. Upstream XMage
  `dac400ba1380f17492c9ad6a65ab60f12f28cd97`. 4 CPUs, 15 GB, JDK 21.0.12, Maven 3.9.11.
  `bash scripts/build_jvm.sh`: BUILD SUCCESS, "Adapter compilation completed". `ai_calibration.py decks`: all 33 decks
  resolve (99 cards and a commander each).
- **Settings.** Skill 3 against 3 (on today's engine: search depth 4, 10% mistakes, 2.2–2.4 mistakes per seat per
  game), phone budget, default heap (2560m), 4 workers, seed 20261015.
- **Smoke.** 4 games of batch A (Edgar Optimized against First Flight): all ended normally in 11–31 turns, 14–60 s.
  Deleted afterwards.
- **Batch A**, 624 games, 01:31–03:23 UTC (111 min):

  ```
  python3 scripts/ai_calibration.py run --skill-a 3 --skill-b 3 --against first-flight,token-triumph,grave-danger \
    --pool ai-the-ur-dragon-optimized,ai-gishath-suns-avatar-exhibition,ai-krenko-mob-boss-optimized,ai-edgar-markov-optimized,ai-lathril-blade-of-the-elves-optimized,ai-wilhelt-the-rotcleaver-optimized,ai-kaalia-of-the-vast-optimized,ai-winota-joiner-of-forces-optimized,ai-the-first-sliver-optimized,ai-miirym-sentinel-wyrm-optimized,ai-marisi-breaker-of-the-coil-exhibition,ai-kynaios-and-tiro-of-meletis-exhibition,ai-tormod-the-desecrator-core \
    --games 624 --out "$R/docs/cloud/power-results/batch-a"
  ```

- **Batch B**, 612 games, 03:23–04:37 UTC (73 min):

  ```
  python3 scripts/ai_calibration.py run --skill-a 3 --skill-b 3 --against first-flight,token-triumph,grave-danger \
    --pool draconic-destruction,chaos-incarnate,ai-krenko-mob-boss-exhibition,ai-krenko-mob-boss-core,ai-krenko-mob-boss-upgraded,ai-gishath-suns-avatar-core,ai-gishath-suns-avatar-upgraded,ai-gishath-suns-avatar-optimized,ai-lathril-blade-of-the-elves-exhibition,ai-lathril-blade-of-the-elves-core,ai-lathril-blade-of-the-elves-upgraded,ai-edgar-markov-core,ai-edgar-markov-upgraded,ai-the-ur-dragon-core,ai-the-ur-dragon-upgraded,ai-wilhelt-the-rotcleaver-core,ai-wilhelt-the-rotcleaver-upgraded \
    --games 612 --out "$R/docs/cloud/power-results/batch-b"
  ```

- **Games.** 1,236 played, 1,234 ended normally. One hit the time limit (Kynaios and Tiro against Grave Danger, 30
  turns in 30 min) and one the turn limit (Draconic Destruction against First Flight, 41 turns). Four more were real
  draws (both players lost at once). No harness failures, so nothing was replayed; no deck failed validation, so no
  `batch-a2`. Data: `docs/cloud/power-results/batch-a/` and `batch-b/`.

## Every pool deck against the references

Power is `deck_power.py table` (weights unchanged, the same numbers as docs/DECK_POWER.md). Each cell is wins–losses,
win rate and Wilson 95% interval; draws are left out of the rate. Each deck met each reference 16 times (batch A) or 12
(batch B), both seatings equally.

| Deck | Power | Games | vs First Flight | vs Token Triumph | vs Grave Danger | Overall |
|---|---|---|---|---|---|---|
| ai-kaalia-of-the-vast-optimized | 7.9 | 48 | 7–9, 44% (23%–67%) | 11–5, 69% (44%–86%) | 13–3, 81% (57%–93%) | **31–17, 65% (50%–77%)** |
| ai-the-ur-dragon-optimized | 7.8 | 48 | 11–5, 69% (44%–86%) | 6–10, 38% (18%–61%) | 11–5, 69% (44%–86%) | **28–20, 58% (44%–71%)** |
| ai-the-ur-dragon-upgraded | 7.5 | 36 | 7–5, 58% (32%–81%) | 8–4, 67% (39%–86%) | 5–7, 42% (19%–68%) | **20–16, 56% (40%–70%)** |
| ai-gishath-suns-avatar-optimized | 7.1 | 36 | 5–7, 42% (19%–68%) | 7–5, 58% (32%–81%) | 4–8, 33% (14%–61%) | **16–20, 44% (30%–60%)** |
| ai-miirym-sentinel-wyrm-optimized | 7.0 | 48 | 9–7, 56% (33%–77%) | 9–7, 56% (33%–77%) | 13–3, 81% (57%–93%) | **31–17, 65% (50%–77%)** |
| ai-the-ur-dragon-core | 7.0 | 36 | 10–2, 83% (55%–95%) | 9–3, 75% (47%–91%) | 8–4, 67% (39%–86%) | **27–9, 75% (59%–86%)** |
| ai-gishath-suns-avatar-exhibition | 6.9 | 48 | 10–6, 62% (39%–82%) | 8–8, 50% (28%–72%) | 11–5, 69% (44%–86%) | **29–19, 60% (46%–73%)** |
| ai-gishath-suns-avatar-upgraded | 6.9 | 36 | 3–9, 25% (9%–53%) | 7–5, 58% (32%–81%) | 10–2, 83% (55%–95%) | **20–16, 56% (40%–70%)** |
| ai-edgar-markov-upgraded | 6.8 | 36 | 8–4, 67% (39%–86%) | 6–6, 50% (25%–75%) | 8–4, 67% (39%–86%) | **22–14, 61% (45%–75%)** |
| ai-the-first-sliver-optimized | 6.8 | 48 (1 draw) | 2–13, 13% (4%–38%) | 4–12, 25% (10%–49%) | 1–15, 6% (1%–28%) | **7–40, 15% (7%–28%)** |
| ai-gishath-suns-avatar-core | 6.7 | 36 | 9–3, 75% (47%–91%) | 7–5, 58% (32%–81%) | 7–5, 58% (32%–81%) | **23–13, 64% (48%–78%)** |
| ai-edgar-markov-optimized | 6.6 | 48 | 8–8, 50% (28%–72%) | 6–10, 38% (18%–61%) | 9–7, 56% (33%–77%) | **23–25, 48% (34%–62%)** |
| ai-winota-joiner-of-forces-optimized | 6.3 | 48 | 9–7, 56% (33%–77%) | 4–12, 25% (10%–49%) | 9–7, 56% (33%–77%) | **22–26, 46% (33%–60%)** |
| ai-wilhelt-the-rotcleaver-optimized | 6.1 | 48 | 6–10, 38% (18%–61%) | 2–14, 12% (3%–36%) | 6–10, 38% (18%–61%) | **14–34, 29% (18%–43%)** |
| ai-edgar-markov-core | 6.0 | 36 | 9–3, 75% (47%–91%) | 9–3, 75% (47%–91%) | 7–5, 58% (32%–81%) | **25–11, 69% (53%–82%)** |
| ai-lathril-blade-of-the-elves-optimized | 5.7 | 48 | 5–11, 31% (14%–56%) | 6–10, 38% (18%–61%) | 5–11, 31% (14%–56%) | **16–32, 33% (22%–47%)** |
| ai-krenko-mob-boss-optimized | 5.6 | 48 (1 draw) | 6–10, 38% (18%–61%) | 12–3, 80% (55%–93%) | 13–3, 81% (57%–93%) | **31–16, 66% (52%–78%)** |
| draconic-destruction | 5.5 | 36 (1 draw) | 8–3, 73% (43%–90%) | 7–5, 58% (32%–81%) | 7–5, 58% (32%–81%) | **22–13, 63% (46%–77%)** |
| ai-krenko-mob-boss-upgraded | 5.5 | 36 | 7–5, 58% (32%–81%) | 6–6, 50% (25%–75%) | 8–4, 67% (39%–86%) | **21–15, 58% (42%–73%)** |
| ai-lathril-blade-of-the-elves-exhibition | 5.5 | 36 | 6–6, 50% (25%–75%) | 8–4, 67% (39%–86%) | 6–6, 50% (25%–75%) | **20–16, 56% (40%–70%)** |
| ai-wilhelt-the-rotcleaver-upgraded | 5.4 | 36 | 4–8, 33% (14%–61%) | 6–6, 50% (25%–75%) | 6–6, 50% (25%–75%) | **16–20, 44% (30%–60%)** |
| ai-krenko-mob-boss-exhibition | 5.4 | 36 | 7–5, 58% (32%–81%) | 5–7, 42% (19%–68%) | 8–4, 67% (39%–86%) | **20–16, 56% (40%–70%)** |
| ai-lathril-blade-of-the-elves-upgraded | 5.3 | 36 (1 draw) | 6–6, 50% (25%–75%) | 5–6, 45% (21%–72%) | 8–4, 67% (39%–86%) | **19–16, 54% (38%–70%)** |
| ai-krenko-mob-boss-core | 5.3 | 36 | 7–5, 58% (32%–81%) | 8–4, 67% (39%–86%) | 8–4, 67% (39%–86%) | **23–13, 64% (48%–78%)** |
| ai-lathril-blade-of-the-elves-core | 5.3 | 36 | 5–7, 42% (19%–68%) | 7–5, 58% (32%–81%) | 7–5, 58% (32%–81%) | **19–17, 53% (37%–68%)** |
| ai-wilhelt-the-rotcleaver-core | 4.7 | 36 | 6–6, 50% (25%–75%) | 3–9, 25% (9%–53%) | 5–7, 42% (19%–68%) | **14–22, 39% (25%–55%)** |
| ai-tormod-the-desecrator-core | 4.4 | 48 | 3–13, 19% (7%–43%) | 6–10, 38% (18%–61%) | 6–10, 38% (18%–61%) | **15–33, 31% (20%–45%)** |
| ai-kynaios-and-tiro-of-meletis-exhibition | 4.3 | 48 (2 draws) | 6–10, 38% (18%–61%) | 3–13, 19% (7%–43%) | 2–12, 14% (4%–40%) | **11–35, 24% (14%–38%)** |
| ai-marisi-breaker-of-the-coil-exhibition | 4.0 | 48 | 4–12, 25% (10%–49%) | 9–7, 56% (33%–77%) | 3–13, 19% (7%–43%) | **16–32, 33% (22%–47%)** |
| chaos-incarnate | 4.0 | 36 | 5–7, 42% (19%–68%) | 2–10, 17% (5%–45%) | 1–11, 8% (1%–35%) | **8–28, 22% (12%–38%)** |

The references against the 30 pool decks: First Flight 212–198 (52%, 47–57), Token Triumph 214–196 (52%, 47–57),
Grave Danger 195–215 (48%, 43–52).

## Decks that play far from their Power

`check` fits one strength per deck over all 4,216 decided games (C3, C4 and these), with going first worth +0.45
log-odds. Its line from Power to strength now has a slope of **0.30 log-odds per Power point** (57% against a deck
one point lower; it was 0.37 on the 2,986 earlier games). "Plays like" below is the Power at which that line meets the
deck's measured strength, so "off by" is in Power points (negative: plays weaker). With 36–48 games a new deck's interval spans about ±2 Power
points, so only large misses are clear.

**Outside their interval:**

| Deck | Power | Plays like (95% CI) | Off by |
|---|---|---|---|
| ai-the-first-sliver-optimized | 6.8 | −0.7 (−3.4 to 2.0) | **−7.5** |
| ai-wilhelt-the-rotcleaver-optimized | 6.1 | 2.2 (0.1 to 4.3) | **−3.9** |
| ai-kynaios-and-tiro-of-meletis-exhibition | 4.3 | 1.3 (−1.0 to 3.6) | **−3.0** |
| ai-lathril-blade-of-the-elves-optimized | 5.7 | 2.9 (0.8 to 4.9) | **−2.8** |
| ai-gishath-suns-avatar-optimized | 7.1 | 4.5 (2.2 to 6.7) | **−2.6** |
| ai-edgar-markov-core | 6.0 | 7.0 (6.5 to 7.6) | +1.0 |
| ai-wilhelt-the-rotcleaver-core | 4.7 | 3.8 (3.3 to 4.3) | −1.0 |
| token-triumph | 4.4 | 5.4 (4.9 to 5.8) | +0.9 |
| ai-lathril-blade-of-the-elves-core | 5.3 | 4.5 (4.0 to 5.1) | −0.8 |
| first-flight | 5.3 | 5.8 (5.3 to 6.2) | +0.5 |

The last five are the Core misses DECK_POWER.md already lists, now with more games. **Large but inside their
interval:** Krenko Optimized +1.9 (5.6, plays like 7.5), Tormod −1.9, Edgar Optimized −1.6, Winota −1.6, Ur-Dragon
Optimized and Upgraded −1.4 each, Marisi −1.1. Every deck is in the full table under Outputs.

- **A higher bracket does not play stronger in the AI's hands.** Against the references: Ur-Dragon Core 75%,
  Upgraded 56%, Optimized 58%; Edgar Core 69%, Upgraded 61%, Optimized 48%; Gishath Core 64%, Exhibition 60%,
  Upgraded 56%, Optimized 44%; Lathril Exhibition, Core and Upgraded 53–56%, Optimized 33%; Wilhelt Core 39%,
  Upgraded 44%, Optimized 29%. Only Krenko's Optimized deck (66%) edges its Core (64%). The formula rates most
  Optimized decks above their Core.
- **The seven new decks.** Kaalia (65%) and Miirym (65%) play at the top, close to their Power. Winota is mid-pack
  (46%). The First Sliver is the weakest of all 33 decks (7–40, 15%), below every precon. Marisi (33%), Tormod (31%)
  and Kynaios and Tiro (24%) play at the bottom, as intended, and below their Power.
- **Fit over 33 decks:** Spearman +0.54 (+0.77 over the eleven Core decks before); 23 of 33 decks inside their
  interval; 161 of 212 clearly separated pairs in Power's order. C3's precon round robin still fits 5 of 5.
- **Hypothesis, not checked:** many of The First Sliver's Slivers give an activated ability to every Sliver (Crypt
  Sliver's regenerate, Hibernation Sliver's return to hand, Necrotic Sliver's destroy, Gemhide and Manaweft Sliver's
  mana), which multiplies the AI's choices for each creature. No game was replayed move by move.

## Core decks: today's engine against the older games

Each Core deck's games against the same three references: the older C3/C4 CSVs (older engines, several skill
pairings, each deck in both seats) against batch B (today's engine, skill 3 against 3).

| Deck | Older C3/C4 vs the three references | Today | Difference (95% CI) |
|---|---|---|---|
| ai-the-ur-dragon-core | 40–19, 68% (55%–78%) | 27–9, 75% (59%–86%) | +7% (-11% to +26%) |
| ai-gishath-suns-avatar-core | 106–60, 64% (56%–71%) | 23–13, 64% (48%–78%) | +0% (-17% to +17%) |
| ai-edgar-markov-core | 146–98, 60% (54%–66%) | 25–11, 69% (53%–82%) | +10% (-7% to +26%) |
| draconic-destruction | 111–89, 56% (49%–62%) | 22–13, 63% (46%–77%) | +7% (-10% to +25%) |
| ai-krenko-mob-boss-core | 29–31, 48% (36%–61%) | 23–13, 64% (48%–78%) | +16% (-5% to +36%) |
| ai-lathril-blade-of-the-elves-core | 97–150, 39% (33%–45%) | 19–17, 53% (37%–68%) | +14% (-4% to +31%) |
| ai-wilhelt-the-rotcleaver-core | 124–200, 38% (33%–44%) | 14–22, 39% (25%–55%) | +1% (-16% to +17%) |
| chaos-incarnate | 45–75, 38% (29%–46%) | 8–28, 22% (12%–38%) | -15% (-31% to +1%) |

**They agree.** Every interval contains zero. Pooled over the eight decks, today's win rate is +4% (−2% to +10%,
precision-weighted), and the eight differences together are consistent with none (χ² 10.7 on 8 df, p ≈ 0.2). The
largest moves, none significant: Chaos Incarnate −15%, Krenko Core +16%, Lathril Core +14%. The older games mix
engines and skill gaps (C3's baseline had no mistakes; skill 3 today makes 10%), so this checks the order and rough
level, not a like-for-like replay.

## How long games took

- Batch A: 111 min on 4 workers, 7.4 h of play. 43 s a game on average (median 20, longest 1,810), 17.1 turns.
  Kynaios and Tiro's games were the slowest by far: 181 s on average (median 86), including the 30-minute time limit.
- Batch B: 73 min, 4.8 h of play. 28 s a game (median 16, longest 259), 16.9 turns.
- Going first won 56% (A) and 58% (B) of decided games.

## What did not run

- No reruns and no `batch-a2` (nothing failed). No weight fit, and no formula, weights, `ai-decks.json`, app or engine
  change: retuning is another session's. No unit tests (no code changed).
- No native, iOS, Android or phone runs: JVM engine on the cloud CPU only, AI against AI, not against a person.
  Searches stop on a clock, so a rerun agrees statistically, not move for move.

## Outputs

### Every deck's distance from Power

From `check`'s fit. Negative: the deck plays weaker than its Power; "outside": outside its 95% interval.

| Deck | Power | Observed (95% CI) | From Power | Plays like Power | Off by (points) |
|---|---|---|---|---|---|
| ai-krenko-mob-boss-optimized | 5.6 | +0.73 (+0.11 to +1.35) | +0.16 | 7.5 (5.5 to 9.6) | +1.9 |
| ai-kaalia-of-the-vast-optimized | 7.9 | +0.68 (+0.07 to +1.28) | +0.84 | 7.4 (5.3 to 9.4) | -0.5 |
| ai-miirym-sentinel-wyrm-optimized | 7.0 | +0.68 (+0.07 to +1.28) | +0.57 | 7.4 (5.3 to 9.4) | +0.4 |
| ai-the-ur-dragon-core | 7.0 | +0.67 (+0.49 to +0.85) | +0.56 | 7.3 (6.7 to 7.9) | +0.4 |
| ai-edgar-markov-core | 6.0 | +0.58 (+0.42 to +0.74) | +0.27 | 7.0 (6.5 to 7.6) | +1.0 (outside) |
| ai-gishath-suns-avatar-core | 6.7 | +0.56 (+0.40 to +0.72) | +0.47 | 7.0 (6.4 to 7.5) | +0.3 |
| ai-edgar-markov-upgraded | 6.8 | +0.52 (-0.16 to +1.21) | +0.52 | 6.8 (4.6 to 9.1) | +0.0 |
| ai-gishath-suns-avatar-exhibition | 6.9 | +0.49 (-0.10 to +1.09) | +0.54 | 6.7 (4.8 to 8.7) | -0.1 |
| ai-krenko-mob-boss-upgraded | 5.5 | +0.40 (-0.28 to +1.08) | +0.12 | 6.4 (4.2 to 8.7) | +0.9 |
| ai-the-ur-dragon-optimized | 7.8 | +0.40 (-0.19 to +0.99) | +0.82 | 6.4 (4.5 to 8.4) | -1.4 |
| ai-lathril-blade-of-the-elves-exhibition | 5.5 | +0.29 (-0.39 to +0.96) | +0.12 | 6.0 (3.8 to 8.3) | +0.6 |
| ai-the-ur-dragon-upgraded | 7.5 | +0.29 (-0.39 to +0.96) | +0.72 | 6.0 (3.8 to 8.3) | -1.4 |
| ai-gishath-suns-avatar-upgraded | 6.9 | +0.29 (-0.39 to +0.96) | +0.54 | 6.0 (3.8 to 8.3) | -0.8 |
| ai-krenko-mob-boss-exhibition | 5.4 | +0.29 (-0.39 to +0.96) | +0.09 | 6.0 (3.8 to 8.3) | +0.7 |
| ai-lathril-blade-of-the-elves-upgraded | 5.3 | +0.25 (-0.44 to +0.93) | +0.07 | 5.9 (3.6 to 8.2) | +0.6 |
| first-flight | 5.3 | +0.20 (+0.07 to +0.33) | +0.06 | 5.8 (5.3 to 6.2) | +0.5 (outside) |
| ai-krenko-mob-boss-core | 5.3 | +0.17 (-0.07 to +0.41) | +0.07 | 5.7 (4.9 to 6.5) | +0.4 |
| token-triumph | 4.4 | +0.08 (-0.06 to +0.22) | -0.20 | 5.4 (4.9 to 5.8) | +0.9 (outside) |
| draconic-destruction | 5.5 | +0.06 (-0.12 to +0.24) | +0.14 | 5.3 (4.7 to 5.9) | -0.2 |
| ai-edgar-markov-optimized | 6.6 | -0.03 (-0.62 to +0.55) | +0.46 | 5.0 (3.0 to 6.9) | -1.6 |
| ai-winota-joiner-of-forces-optimized | 6.3 | -0.12 (-0.71 to +0.46) | +0.37 | 4.7 (2.7 to 6.6) | -1.6 |
| grave-danger | 4.6 | -0.13 (-0.25 to -0.00) | -0.15 | 4.7 (4.3 to 5.1) | +0.1 |
| ai-lathril-blade-of-the-elves-core | 5.3 | -0.18 (-0.34 to -0.01) | +0.06 | 4.5 (4.0 to 5.1) | -0.8 (outside) |
| ai-gishath-suns-avatar-optimized | 7.1 | -0.18 (-0.86 to +0.49) | +0.61 | 4.5 (2.2 to 6.7) | -2.6 (outside) |
| ai-wilhelt-the-rotcleaver-upgraded | 5.4 | -0.18 (-0.86 to +0.49) | +0.09 | 4.5 (2.2 to 6.7) | -0.9 |
| ai-wilhelt-the-rotcleaver-core | 4.7 | -0.40 (-0.55 to -0.24) | -0.11 | 3.8 (3.3 to 4.3) | -1.0 (outside) |
| chaos-incarnate | 4.0 | -0.55 (-0.78 to -0.32) | -0.34 | 3.3 (2.5 to 4.0) | -0.7 |
| ai-lathril-blade-of-the-elves-optimized | 5.7 | -0.67 (-1.28 to -0.06) | +0.18 | 2.9 (0.8 to 4.9) | -2.8 (outside) |
| ai-marisi-breaker-of-the-coil-exhibition | 4.0 | -0.67 (-1.28 to -0.06) | -0.34 | 2.9 (0.8 to 4.9) | -1.1 |
| ai-tormod-the-desecrator-core | 4.4 | -0.77 (-1.39 to -0.15) | -0.20 | 2.5 (0.5 to 4.6) | -1.9 |
| ai-wilhelt-the-rotcleaver-optimized | 6.1 | -0.87 (-1.51 to -0.24) | +0.31 | 2.2 (0.1 to 4.3) | -3.9 (outside) |
| ai-kynaios-and-tiro-of-meletis-exhibition | 4.3 | -1.14 (-1.83 to -0.45) | -0.24 | 1.3 (-1.0 to 3.6) | -3.0 (outside) |
| ai-the-first-sliver-optimized | 6.8 | -1.74 (-2.55 to -0.93) | +0.50 | -0.7 (-3.4 to 2.0) | -7.5 (outside) |

### `python3 scripts/ranked/deck_power.py check`

4216 decided games; going first is worth +0.45 log-odds.

| Deck | Power | Observed strength (95% CI) | From Power | Games | Fits |
|---|---|---|---|---|---|
| ai-krenko-mob-boss-optimized | 5.6 | +0.73 (+0.11 to +1.35) | +0.16 | 47 | yes |
| ai-kaalia-of-the-vast-optimized | 7.9 | +0.68 (+0.07 to +1.28) | +0.84 | 48 | yes |
| ai-miirym-sentinel-wyrm-optimized | 7.0 | +0.68 (+0.07 to +1.28) | +0.57 | 48 | yes |
| ai-the-ur-dragon-core | 7.0 | +0.67 (+0.49 to +0.85) | +0.56 | 537 | yes |
| ai-edgar-markov-core | 6.0 | +0.58 (+0.42 to +0.74) | +0.27 | 692 | **no** |
| ai-gishath-suns-avatar-core | 6.7 | +0.56 (+0.40 to +0.72) | +0.47 | 689 | yes |
| ai-edgar-markov-upgraded | 6.8 | +0.52 (-0.16 to +1.21) | +0.52 | 36 | yes |
| ai-gishath-suns-avatar-exhibition | 6.9 | +0.49 (-0.10 to +1.09) | +0.54 | 48 | yes |
| ai-krenko-mob-boss-upgraded | 5.5 | +0.40 (-0.28 to +1.08) | +0.12 | 36 | yes |
| ai-the-ur-dragon-optimized | 7.8 | +0.40 (-0.19 to +0.99) | +0.82 | 48 | yes |
| ai-lathril-blade-of-the-elves-exhibition | 5.5 | +0.29 (-0.39 to +0.96) | +0.12 | 36 | yes |
| ai-the-ur-dragon-upgraded | 7.5 | +0.29 (-0.39 to +0.96) | +0.72 | 36 | yes |
| ai-gishath-suns-avatar-upgraded | 6.9 | +0.29 (-0.39 to +0.96) | +0.54 | 36 | yes |
| ai-krenko-mob-boss-exhibition | 5.4 | +0.29 (-0.39 to +0.96) | +0.09 | 36 | yes |
| ai-lathril-blade-of-the-elves-upgraded | 5.3 | +0.25 (-0.44 to +0.93) | +0.07 | 35 | yes |
| first-flight | 5.3 | +0.20 (+0.07 to +0.33) | +0.06 | 1017 | **no** |
| ai-krenko-mob-boss-core | 5.3 | +0.17 (-0.07 to +0.41) | +0.07 | 300 | yes |
| token-triumph | 4.4 | +0.08 (-0.06 to +0.22) | -0.20 | 861 | **no** |
| draconic-destruction | 5.5 | +0.06 (-0.12 to +0.24) | +0.14 | 536 | yes |
| ai-edgar-markov-optimized | 6.6 | -0.03 (-0.62 to +0.55) | +0.46 | 48 | yes |
| ai-winota-joiner-of-forces-optimized | 6.3 | -0.12 (-0.71 to +0.46) | +0.37 | 48 | yes |
| grave-danger | 4.6 | -0.13 (-0.25 to -0.00) | -0.15 | 1124 | yes |
| ai-lathril-blade-of-the-elves-core | 5.3 | -0.18 (-0.34 to -0.01) | +0.06 | 648 | **no** |
| ai-gishath-suns-avatar-optimized | 7.1 | -0.18 (-0.86 to +0.49) | +0.61 | 36 | **no** |
| ai-wilhelt-the-rotcleaver-upgraded | 5.4 | -0.18 (-0.86 to +0.49) | +0.09 | 36 | yes |
| ai-wilhelt-the-rotcleaver-core | 4.7 | -0.40 (-0.55 to -0.24) | -0.11 | 726 | **no** |
| chaos-incarnate | 4.0 | -0.55 (-0.78 to -0.32) | -0.34 | 359 | yes |
| ai-lathril-blade-of-the-elves-optimized | 5.7 | -0.67 (-1.28 to -0.06) | +0.18 | 48 | **no** |
| ai-marisi-breaker-of-the-coil-exhibition | 4.0 | -0.67 (-1.28 to -0.06) | -0.34 | 48 | yes |
| ai-tormod-the-desecrator-core | 4.4 | -0.77 (-1.39 to -0.15) | -0.20 | 48 | yes |
| ai-wilhelt-the-rotcleaver-optimized | 6.1 | -0.87 (-1.51 to -0.24) | +0.31 | 48 | **no** |
| ai-kynaios-and-tiro-of-meletis-exhibition | 4.3 | -1.14 (-1.83 to -0.45) | -0.24 | 46 | **no** |
| ai-the-first-sliver-optimized | 6.8 | -1.74 (-2.55 to -0.93) | +0.50 | 47 | **no** |

Spearman +0.54; 23 of 33 decks inside their interval; 161 of 212 clearly separated pairs in Power's order. One Power point is +0.30 log-odds (57% against a deck one point lower).

| Precon | Power | Predicted | Measured (95% CI) | Fits |
|---|---|---|---|---|
| draconic-destruction | 5.5 | 57% | 62% (52%–72%) | yes |
| first-flight | 5.3 | 55% | 56% (45%–67%) | yes |
| grave-danger | 4.6 | 48% | 45% (35%–56%) | yes |
| token-triumph | 4.4 | 47% | 50% (39%–61%) | yes |
| chaos-incarnate | 4.0 | 42% | 36% (27%–47%) | yes |

5 of 5 precons inside their interval.

### `ai_calibration.py summarize --by-deck` (batch A and B CSVs)

| Deck | Games | Wins | Losses | Draws | Win rate (95% CI) | In seat A: wins | In seat B: wins |
|---|---|---|---|---|---|---|---|
| ai-the-ur-dragon-core | 36 | 27 | 9 | 0 | 75% (59–86) | 12/18 | 15/18 |
| ai-edgar-markov-core | 36 | 25 | 11 | 0 | 69% (53–82) | 12/18 | 13/18 |
| ai-krenko-mob-boss-optimized | 48 | 31 | 16 | 1 | 66% (52–78) | 15/24 | 16/23 |
| ai-miirym-sentinel-wyrm-optimized | 48 | 31 | 17 | 0 | 65% (50–77) | 13/24 | 18/24 |
| ai-kaalia-of-the-vast-optimized | 48 | 31 | 17 | 0 | 65% (50–77) | 16/24 | 15/24 |
| ai-gishath-suns-avatar-core | 36 | 23 | 13 | 0 | 64% (48–78) | 13/18 | 10/18 |
| ai-krenko-mob-boss-core | 36 | 23 | 13 | 0 | 64% (48–78) | 12/18 | 11/18 |
| draconic-destruction | 36 | 22 | 13 | 1 | 63% (46–77) | 10/17 | 12/18 |
| ai-edgar-markov-upgraded | 36 | 22 | 14 | 0 | 61% (45–75) | 10/18 | 12/18 |
| ai-gishath-suns-avatar-exhibition | 48 | 29 | 19 | 0 | 60% (46–73) | 17/24 | 12/24 |
| ai-the-ur-dragon-optimized | 48 | 28 | 20 | 0 | 58% (44–71) | 12/24 | 16/24 |
| ai-krenko-mob-boss-upgraded | 36 | 21 | 15 | 0 | 58% (42–73) | 12/18 | 9/18 |
| ai-krenko-mob-boss-exhibition | 36 | 20 | 16 | 0 | 56% (40–70) | 11/18 | 9/18 |
| ai-lathril-blade-of-the-elves-exhibition | 36 | 20 | 16 | 0 | 56% (40–70) | 12/18 | 8/18 |
| ai-gishath-suns-avatar-upgraded | 36 | 20 | 16 | 0 | 56% (40–70) | 10/18 | 10/18 |
| ai-the-ur-dragon-upgraded | 36 | 20 | 16 | 0 | 56% (40–70) | 10/18 | 10/18 |
| ai-lathril-blade-of-the-elves-upgraded | 36 | 19 | 16 | 1 | 54% (38–70) | 10/17 | 9/18 |
| ai-lathril-blade-of-the-elves-core | 36 | 19 | 17 | 0 | 53% (37–68) | 8/18 | 11/18 |
| token-triumph | 412 | 214 | 196 | 2 | 52% (47–57) | 114/205 | 100/205 |
| first-flight | 412 | 212 | 198 | 2 | 52% (47–57) | 110/206 | 102/204 |
| ai-edgar-markov-optimized | 48 | 23 | 25 | 0 | 48% (34–62) | 10/24 | 13/24 |
| grave-danger | 412 | 195 | 215 | 2 | 48% (43–52) | 95/206 | 100/204 |
| ai-winota-joiner-of-forces-optimized | 48 | 22 | 26 | 0 | 46% (33–60) | 11/24 | 11/24 |
| ai-gishath-suns-avatar-optimized | 36 | 16 | 20 | 0 | 44% (30–60) | 12/18 | 4/18 |
| ai-wilhelt-the-rotcleaver-upgraded | 36 | 16 | 20 | 0 | 44% (30–60) | 9/18 | 7/18 |
| ai-wilhelt-the-rotcleaver-core | 36 | 14 | 22 | 0 | 39% (25–55) | 6/18 | 8/18 |
| ai-lathril-blade-of-the-elves-optimized | 48 | 16 | 32 | 0 | 33% (22–47) | 9/24 | 7/24 |
| ai-marisi-breaker-of-the-coil-exhibition | 48 | 16 | 32 | 0 | 33% (22–47) | 11/24 | 5/24 |
| ai-tormod-the-desecrator-core | 48 | 15 | 33 | 0 | 31% (20–45) | 7/24 | 8/24 |
| ai-wilhelt-the-rotcleaver-optimized | 48 | 14 | 34 | 0 | 29% (18–43) | 6/24 | 8/24 |
| ai-kynaios-and-tiro-of-meletis-exhibition | 48 | 11 | 35 | 2 | 24% (14–38) | 9/22 | 2/24 |
| chaos-incarnate | 36 | 8 | 28 | 0 | 22% (12–38) | 4/18 | 4/18 |
| ai-the-first-sliver-optimized | 48 | 7 | 40 | 1 | 15% (7–28) | 2/23 | 5/24 |

Win rate counts decided games only. Interval: Wilson score, 95%. Seat A is the lower skill of each pairing, B the higher; with each skill on each deck equally often, a deck that wins far more than half is stronger, whoever plays it.
