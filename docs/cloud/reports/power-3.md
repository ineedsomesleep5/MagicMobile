STATUS: ready-for-review

# Power 3: the eight new decks and a top-up

Cloud session for docs/cloud/power-new-decks.md (approved by Caleb, 2026-10-25). Branch `claude/deck-power-design`.
Measurement only: no weights, formula, app or engine changes; nothing merged, released or uploaded. The only
non-result files changed are the ratings `deck_power.py rate --write` writes (`scripts/ranked/deck-power-ratings.json`
and the `power` block of `apps/ios/MagicMobile/Resources/ai-decks.json`).

## Answer

- **The formula over-rates the gentle new decks, as expected, and by more than it seemed.** Zedruu (formula 4.8) won
  3 of 47 decided games and now rates **1.0**; Karador (5.5) **3.4**; Marisi Core (5.4) **3.6**; Meren (6.7) **5.5**.
  Phelddagrif (4.8) plays as rated (**4.9**).
- **The strong end splits.** Lathliss won 77% and rates **9.9**, the highest of all 40 decks, above Mythic's 8.5
  target. Tiamat (**7.5**, formula 7.8) and Old Gnawbone (**7.4**, formula 7.2) play mid-Diamond.
- **Top-up:** Kaalia and Miirym hold (64% over 96 games each, 8.2 and 8.1). Krenko Optimized falls from 7.9 to
  **7.1** (50% this time, 58% over 96). Kynaios and Tiro falls to **1.2** (0–16 against First Flight this time).
- **Ranks short of five decks within 0.5 of their target:** Bronze IV (3), Silver IV (3), Silver III (1), Silver II
  (2), Silver I (3), Gold I (4), Mythic (4). Bronze II–III went from 3 to 5; Silver went from 2–5 to 1–3, because
  Zedruu, Karador and Marisi Core all landed in Bronze or below instead of Silver.

## What ran

- **Engine.** Branch HEAD `d127b9a` when the runs began. Its `engine/`, `platform/`, `tools/` and `upstream.lock.json`
  are identical to power-1.md's `37226f4` (empty diff). Upstream XMage `dac400ba1380f17492c9ad6a65ab60f12f28cd97`.
  4 CPUs, 15 GB, JDK 21.0.12, Maven 3.9.11. `bash scripts/build_jvm.sh`: BUILD SUCCESS, "Adapter compilation
  completed". Stale `build/ai-calibration/decks` deleted first; `ai_calibration.py decks` exits 0 and resolves all
  40 decks (35 AI decks, 5 precons; 99 cards and a commander each). The First Sliver is gone, as of `d127b9a`.
- **Settings.** Skill 3 against 3, phone budget, default heap, 4 workers.
- **Smoke.** 4 games of batch E (Lathliss against First Flight): all ended normally, 17–24 turns, 30–48 s. Deleted.
- **Batch E**, 384 games, 18:12–20:03 UTC (111 min), plus a 4-minute rerun:

  ```
  python3 scripts/ai_calibration.py run --skill-a 3 --skill-b 3 --seed 20261025 --against first-flight,token-triumph,grave-danger \
    --pool ai-tiamat-core,ai-lathliss-dragon-queen-core,ai-old-gnawbone-core,ai-phelddagrif-core,ai-zedruu-the-greathearted-core,ai-karador-ghost-chieftain-core,ai-meren-of-clan-nel-toth-core,ai-marisi-breaker-of-the-coil-core \
    --games 384 --out "$R/docs/cloud/power-results/batch-e"
  ```

- **Batch F**, 288 games, 20:07–21:31 UTC (84 min):

  ```
  python3 scripts/ai_calibration.py run --skill-a 3 --skill-b 3 --seed 20261026 --against first-flight,token-triumph,grave-danger \
    --pool ai-kaalia-of-the-vast-optimized,ai-miirym-sentinel-wyrm-optimized,ai-krenko-mob-boss-optimized,ai-tormod-the-desecrator-core,ai-marisi-breaker-of-the-coil-exhibition,ai-kynaios-and-tiro-of-meletis-exhibition \
    --games 288 --out "$R/docs/cloud/power-results/batch-f"
  ```

- **Games.** 672 played; after the replay, 669 ended normally. Three hit the 41-turn limit (Phelddagrif against Token Triumph and First
  Flight, Zedruu against Grave Danger). Two more Phelddagrif games against Token Triumph (119 and 213) ended
  normally as real draws. **One replay:** batch E game 226 (First Flight against Marisi Core)
  first ended `engine-stopped` after 12 turns in 3 s. The harness counts that as a failure; rerunning E with the
  same arguments replayed it (Marisi Core won in 32 turns). The only exception in the worker logs is one
  `StackOverflowError` inside an AI search (`FilterImpl.match` ← `Battlefield.getActivePermanents`) on worker 3
  at about that time, next to a "thinks too long" warning in a Meren game. Hypothesis, not checked: that overflow
  stopped game 226. No deck failed validation, so no `batch-e2`. Data: `docs/cloud/power-results/batch-e/` and
  `batch-f/`. (Several "batch F checkpoint" commits are mid-run snapshots of F's CSV; the last commit has all 288.)

## The eight new decks (batch E)

Each cell is wins–losses, win rate and Wilson 95% interval; draws are left out of the rate. Each deck met each
reference 16 times, both seatings equally. Power is `deck_power.py rate` before and after this run.

| Deck | Formula | Power before → after | Games | vs First Flight | vs Token Triumph | vs Grave Danger | Overall |
|---|---|---|---|---|---|---|---|
| ai-lathliss-dragon-queen-core | 7.7 | 8.1 → **9.9** (7.8–10.0) | 48 | 13–3, 81% (57%–93%) | 12–4, 75% (51%–90%) | 12–4, 75% (51%–90%) | **37–11, 77% (63%–87%)** |
| ai-tiamat-core | 7.8 | 8.2 → **7.5** (5.6–9.4) | 48 | 9–7, 56% (33%–77%) | 11–5, 69% (44%–86%) | 8–8, 50% (28%–72%) | **28–20, 58% (44%–71%)** |
| ai-old-gnawbone-core | 7.2 | 7.6 → **7.4** (5.5–9.3) | 48 | 9–7, 56% (33%–77%) | 10–6, 62% (39%–82%) | 9–7, 56% (33%–77%) | **28–20, 58% (44%–71%)** |
| ai-meren-of-clan-nel-toth-core | 6.7 | 7.0 → **5.5** (3.6–7.4) | 48 | 5–11, 31% (14%–56%) | 10–6, 62% (39%–82%) | 6–10, 38% (18%–61%) | **21–27, 44% (31%–58%)** |
| ai-phelddagrif-core | 4.8 | 4.9 → **4.9** (3.0–6.9) | 48 (4 draws) | 9–6, 60% (36%–80%) | 4–9, 31% (13%–58%) | 6–10, 38% (18%–61%) | **19–25, 43% (30%–58%)** |
| ai-marisi-breaker-of-the-coil-core | 5.4 | 5.5 → **3.6** (1.7–5.6) | 48 | 6–10, 38% (18%–61%) | 4–12, 25% (10%–49%) | 5–11, 31% (14%–56%) | **15–33, 31% (20%–45%)** |
| ai-karador-ghost-chieftain-core | 5.5 | 5.6 → **3.4** (1.4–5.4) | 48 | 3–13, 19% (7%–43%) | 6–10, 38% (18%–61%) | 5–11, 31% (14%–56%) | **14–34, 29% (18%–43%)** |
| ai-zedruu-the-greathearted-core | 4.8 | 4.8 → **1.0** (1.0–3.7) | 48 (1 draw) | 1–15, 6% (1%–28%) | 1–15, 6% (1%–28%) | 1–14, 7% (1%–30%) | **3–44, 6% (2%–17%)** |

The references against these eight: First Flight 72–55 (57%, 48–65), Token Triumph 67–58 (54%, 45–62), Grave Danger
75–52 (59%, 50–67).

## The top-up (batch F, and batch A + F together)

| Deck | Power before → after | Batch F (48 games) | Batch A + F: vs First Flight | vs Token Triumph | vs Grave Danger | Overall (96 games) |
|---|---|---|---|---|---|---|
| ai-kaalia-of-the-vast-optimized | 8.4 → **8.2** (6.8–9.7) | 30–18, 62% (48%–75%) | 13–19, 41% (26%–58%) | 23–9, 72% (55%–84%) | 25–7, 78% (61%–89%) | **61–35, 64% (54%–72%)** |
| ai-miirym-sentinel-wyrm-optimized | 8.2 → **8.1** (6.7–9.6) | 30–18, 62% (48%–75%) | 19–13, 59% (42%–74%) | 22–10, 69% (51%–82%) | 20–12, 62% (45%–77%) | **61–35, 64% (54%–72%)** |
| ai-krenko-mob-boss-optimized | 7.9 → **7.1** (5.6–8.5) | 24–24, 50% (36%–64%) | 13–19, 41% (26%–58%) | 24–7, 77% (60%–89%) | 18–14, 56% (39%–72%) | **55–40, 58% (48%–67%)** (1 draw) |
| ai-tormod-the-desecrator-core | 3.2 → **3.6** (2.1–5.0) | 18–30, 38% (25%–52%) | 9–23, 28% (16%–45%) | 12–20, 38% (23%–55%) | 12–20, 38% (23%–55%) | **33–63, 34% (26%–44%)** |
| ai-marisi-breaker-of-the-coil-exhibition | 3.5 → **3.7** (2.2–5.2) | 18–30, 38% (25%–52%) | 6–26, 19% (9%–35%) | 18–14, 56% (39%–72%) | 10–22, 31% (18%–49%) | **34–62, 35% (27%–45%)** |
| ai-kynaios-and-tiro-of-meletis-exhibition | 2.4 → **1.2** (1.0–3.0) | 7–41, 15% (7%–27%) | 6–26, 19% (9%–35%) | 5–27, 16% (7%–32%) | 7–23, 23% (12%–41%) | **18–76, 19% (12%–28%)** (2 draws) |

Batch F's references: First Flight 65–31 (68%, 58–76), Token Triumph 42–54 (44%, 34–54), Grave Danger 54–42 (56%,
46–66). All six decks' batch F rates sit inside their batch A intervals.

Other ratings that moved only through the shared fit: Edgar Core 7.9 → 8.0, Token Triumph 6.1 → 5.9, Grave Danger
5.3 → 5.5. Every other deck is unchanged.

## Ladder

`python3 scripts/ranked/deck_power.py ladder` after `rate --write`. "Within 0.5" counts decks the division allows
(bracket at most its max) whose Power is within 0.5 of the target; before is the same count on the ratings this run
started from.

| Tier | Division | Target | Nearest allowed decks (Power) | Within 0.5: before → after |
|---|---|---|---|---|
| Bronze | IV | 3.12 | karador-ghost-chieftain-core 3.4, marisi-breaker-of-the-coil-core 3.6, tormod-the-desecrator-core 3.6 | 2 → **3** |
| Bronze | III | 3.38 | karador-ghost-chieftain-core 3.4, marisi-breaker-of-the-coil-core 3.6, tormod-the-desecrator-core 3.6 | 3 → 5 |
| Bronze | II | 3.62 | marisi-breaker-of-the-coil-core 3.6, tormod-the-desecrator-core 3.6, marisi-breaker-of-the-coil-exhibition 3.7 | 3 → 5 |
| Bronze | I | 3.88 | chaos-incarnate 3.8, marisi-breaker-of-the-coil-exhibition 3.7, marisi-breaker-of-the-coil-core 3.6 | 2 → 5 |
| Silver | IV | 4.12 | wilhelt-the-rotcleaver-core 4.4, chaos-incarnate 3.8, marisi-breaker-of-the-coil-exhibition 3.7 | 2 → **3** |
| Silver | III | 4.38 | wilhelt-the-rotcleaver-core 4.4, phelddagrif-core 4.9, chaos-incarnate 3.8 | 2 → **1** |
| Silver | II | 4.62 | wilhelt-the-rotcleaver-core 4.4, phelddagrif-core 4.9, lathril-blade-of-the-elves-core 5.2 | 3 → **2** |
| Silver | I | 4.88 | phelddagrif-core 4.9, lathril-blade-of-the-elves-core 5.2, wilhelt-the-rotcleaver-core 4.4 | 5 → **3** |
| Gold | IV | 5.12 | lathril-blade-of-the-elves-core 5.2, wilhelt-the-rotcleaver-upgraded 5.3, phelddagrif-core 4.9 | 7 → 5 |
| Gold | III | 5.38 | wilhelt-the-rotcleaver-upgraded 5.3, grave-danger 5.5, meren-of-clan-nel-toth-core 5.5 | 6 → 5 |
| Gold | II | 5.62 | grave-danger 5.5, meren-of-clan-nel-toth-core 5.5, token-triumph 5.9 | 7 → 6 |
| Gold | I | 5.88 | token-triumph 5.9, draconic-destruction 6.1, grave-danger 5.5 | 4 → **4** |
| Platinum | IV | 6.12 | draconic-destruction 6.1, token-triumph 5.9, krenko-mob-boss-core 6.4 | 6 → 6 |
| Platinum | III | 6.38 | krenko-mob-boss-core 6.4, lathril-blade-of-the-elves-upgraded 6.4, first-flight 6.6 | 7 → 7 |
| Platinum | II | 6.62 | first-flight 6.6, lathril-blade-of-the-elves-exhibition 6.6, krenko-mob-boss-exhibition 6.7 | 7 → 6 |
| Platinum | I | 6.88 | krenko-mob-boss-upgraded 7.0, krenko-mob-boss-exhibition 6.7, first-flight 6.6 | 8 → 7 |
| Diamond | IV | 7.12 | krenko-mob-boss-optimized 7.1, gishath-suns-avatar-upgraded 7.2, krenko-mob-boss-upgraded 7.0 | 8 → 9 |
| Diamond | III | 7.38 | the-ur-dragon-upgraded 7.4, old-gnawbone-core 7.4, edgar-markov-upgraded 7.5 | 8 → 9 |
| Diamond | II | 7.62 | the-ur-dragon-optimized 7.6, edgar-markov-upgraded 7.5, tiamat-core 7.5 | 10 → 10 |
| Diamond | I | 7.88 | gishath-suns-avatar-core 7.9, gishath-suns-avatar-exhibition 7.8, edgar-markov-core 8.0 | 12 → 11 |
| Mythic | | 8.50 | the-ur-dragon-core 8.3, kaalia-of-the-vast-optimized 8.2, miirym-sentinel-wyrm-optimized 8.1 | 5 → **4** |

**Fewer than five within 0.5:** Bronze IV, Silver IV, Silver III, Silver II, Silver I, Gold I and Mythic. Silver is
the thin tier now: Phelddagrif (4.9) is the only new deck that landed there. Mythic's four are The Ur-Dragon Core,
Kaalia, Miirym and Edgar Core; Lathliss (9.9) is 1.4 above the target, and no deck rates between 8.3 and 9.9.

| Quick Match | Power band | Decks in the band |
|---|---|---|
| Easy | 3–4 | 7: chaos-incarnate, lathril-blade-of-the-elves-optimized, marisi-breaker-of-the-coil-exhibition, wilhelt-the-rotcleaver-optimized, marisi-breaker-of-the-coil-core, tormod-the-desecrator-core, karador-ghost-chieftain-core |
| Medium | 5–6 | 8: token-triumph, gishath-suns-avatar-optimized, edgar-markov-optimized, winota-joiner-of-forces-optimized, grave-danger, meren-of-clan-nel-toth-core, wilhelt-the-rotcleaver-upgraded, lathril-blade-of-the-elves-core |
| Hard | 7–8 | 11: edgar-markov-core, gishath-suns-avatar-core, gishath-suns-avatar-exhibition, the-ur-dragon-optimized, edgar-markov-upgraded, tiamat-core, the-ur-dragon-upgraded, old-gnawbone-core, gishath-suns-avatar-upgraded, krenko-mob-boss-optimized, krenko-mob-boss-upgraded |

Zedruu (1.0), Kynaios and Tiro (1.2) and Lathliss (9.9) now sit outside every Quick Match band.

## How long games took

- Batch E: 111 min on 4 workers (plus 4 min for the replay), 7.4 h of play. 69 s a game on average (median 38,
  longest 1,088), 19.3 turns. The slowest decks: Phelddagrif 152 s on average (median 83), Zedruu 123 s, Karador
  94 s; Lathliss and Tiamat about 20 s.
- Batch F: 84 min, 5.4 h of play. 67 s a game (median 26, longest 1,343), 17.4 turns.
- Going first won 59% of decided games in both batches.

## What did not run

- No runs beyond the two batches and the smoke. No weight fit, and no formula, weights, app or engine change; no
  edit to `ai-decks.json` beyond what `rate --write` writes. No unit tests (no code changed). No `batch-e2`.
- The `StackOverflowError` behind game 226's stop is not diagnosed; no game was replayed move by move.
- No native, iOS, Android or phone runs: JVM engine on the cloud CPU only, AI against AI, not against a person.
  Searches stop on a clock, so a rerun agrees statistically, not move for move.
