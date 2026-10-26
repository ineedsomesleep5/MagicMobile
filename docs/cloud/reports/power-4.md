STATUS: ready-for-review

# Power 4: the Silver and Mythic decks

Cloud session for docs/cloud/power-silver-decks.md (approved by Caleb, 2026-10-25). Branch `claude/deck-power-design`.
Measurement only: no weights, formula, app, engine or deck-list changes; nothing merged, released or uploaded. The
only non-result files changed are the ratings `deck_power.py rate --write` writes (`scripts/ranked/deck-power-ratings.json`
and the `power` block of `apps/ios/MagicMobile/Resources/ai-decks.json`; everything outside `power` checked identical).

## Answer

- **Silver gained two decks.** Meren Exhibition (formula 7.1) won 38% and rates **4.9**; Syr Gwyn (6.0) **5.1**.
  Arahbo (6.0) rates **5.3**, Gold III.
- **The rest missed Silver.** Kumena (5.8) won 29% and falls to **3.5**; Marrow-Gnawer stays Bronze at **3.4**.
  Hakbal (5.3) won 58% and rises to **6.8**, Platinum I.
- **Mythic:** Kaalia Core won 65% and rates **8.4**, the nearest deck to the 8.5 target. Miirym Core (formula 7.5)
  won 48% and falls to **6.2**, Platinum.
- **Ranks still short of five decks within 0.5 of their target:** Silver IV (3), Silver III (1), Silver II (4).
  Silver I went 3 → 6, Bronze IV 3 → 5, Mythic 4 → 5 (counts against power-3.md's ratings). Silver III has only
  Wilhelt Core (4.4); the nearest others, Phelddagrif and Meren Exhibition (4.9), are 0.52 above.

## What ran

- **Engine.** Branch HEAD `9cbd831` when the runs began. Its `engine/`, `platform/`, `tools/` and `upstream.lock.json`
  are identical to power-3.md's `d127b9a` (empty diff). Upstream XMage `dac400ba1380f17492c9ad6a65ab60f12f28cd97`.
  4 CPUs, 15 GB, JDK 21.0.12, Maven 3.9.11. `bash scripts/build_jvm.sh`: BUILD SUCCESS, "Adapter compilation
  completed". Stale `build/ai-calibration/decks` deleted first; `ai_calibration.py decks` exits 0 and resolves all
  48 decks (43 AI decks, 5 precons; 99 cards and a commander each).
- **Settings.** Skill 3 against 3, phone budget, default heap, 4 workers.
- **Smoke.** 4 games of batch G (Miirym Core against First Flight): all ended normally, 16–28 turns, 18–127 s. Deleted.
- **Batch G**, 384 games, 22:13–23:17 UTC (64 min):

  ```
  python3 scripts/ai_calibration.py run --skill-a 3 --skill-b 3 --seed 20261027 --against first-flight,token-triumph,grave-danger \
    --pool ai-kumena-tyrant-of-orazca-core,ai-hakbal-of-the-surging-soul-core,ai-marrow-gnawer-core,ai-arahbo-roar-of-the-world-core,ai-syr-gwyn-hero-of-ashvale-core,ai-meren-of-clan-nel-toth-exhibition,ai-kaalia-of-the-vast-core,ai-miirym-sentinel-wyrm-core \
    --games 384 --out "$R/docs/cloud/power-results/batch-g"
  ```

- **Games.** 384 played, 384 ended normally; no draws, no turn-limit games, no replays, no exceptions in the worker
  logs. No deck failed validation, so no `batch-g2`. Data: `docs/cloud/power-results/batch-g/`. (The "batch G
  checkpoint" commits are mid-run snapshots; the last commit has all 384.)

## The eight decks

Each cell is wins–losses, win rate and Wilson 95% interval. Each deck met each reference 16 times, both seatings
equally. Power is `deck_power.py rate` before and after this run.

| Deck | Formula | Power before → after | Games | vs First Flight | vs Token Triumph | vs Grave Danger | Overall |
|---|---|---|---|---|---|---|---|
| ai-kaalia-of-the-vast-core | 8.4 | 8.9 → **8.4** (6.5–10.0) | 48 | 8–8, 50% (28%–72%) | 13–3, 81% (57%–93%) | 10–6, 62% (39%–82%) | **31–17, 65% (50%–77%)** |
| ai-hakbal-of-the-surging-soul-core | 5.3 | 5.4 → **6.8** (4.9–8.7) | 48 | 11–5, 69% (44%–86%) | 8–8, 50% (28%–72%) | 9–7, 56% (33%–77%) | **28–20, 58% (44%–71%)** |
| ai-miirym-sentinel-wyrm-core | 7.5 | 7.9 → **6.2** (4.3–8.1) | 48 | 7–9, 44% (23%–67%) | 5–11, 31% (14%–56%) | 11–5, 69% (44%–86%) | **23–25, 48% (34%–62%)** |
| ai-arahbo-roar-of-the-world-core | 6.0 | 6.3 → **5.3** (3.4–7.2) | 48 | 8–8, 50% (28%–72%) | 7–9, 44% (23%–67%) | 6–10, 38% (18%–61%) | **21–27, 44% (31%–58%)** |
| ai-syr-gwyn-hero-of-ashvale-core | 6.0 | 6.2 → **5.1** (3.2–6.9) | 48 | 2–14, 12% (3%–36%) | 8–8, 50% (28%–72%) | 10–6, 62% (39%–82%) | **20–28, 42% (29%–56%)** |
| ai-meren-of-clan-nel-toth-exhibition | 7.1 | 7.4 → **4.9** (2.9–6.8) | 48 | 5–11, 31% (14%–56%) | 6–10, 38% (18%–61%) | 7–9, 44% (23%–67%) | **18–30, 38% (25%–52%)** |
| ai-kumena-tyrant-of-orazca-core | 5.8 | 5.9 → **3.5** (1.5–5.5) | 48 | 2–14, 12% (3%–36%) | 6–10, 38% (18%–61%) | 6–10, 38% (18%–61%) | **14–34, 29% (18%–43%)** |
| ai-marrow-gnawer-core | 3.7 | 3.6 → **3.4** (1.5–5.4) | 48 | 7–9, 44% (23%–67%) | 4–12, 25% (10%–49%) | 5–11, 31% (14%–56%) | **16–32, 33% (22%–47%)** |

The references against these eight: First Flight 78–50 (61%, 52–69), Token Triumph 71–57 (55%, 47–64), Grave Danger
64–64 (50%, 41–59).

Other ratings that moved only through the shared fit: First Flight 6.6 → 6.7, Gishath Exhibition 7.8 → 7.7, Kynaios
and Tiro 1.2 → 1.3. Every other deck is unchanged.

## Ladder

`python3 scripts/ranked/deck_power.py ladder` after `rate --write`. "Within 0.5" counts decks the division allows
(bracket at most its max) whose Power is within 0.5 of the target. Before is the ratings this run started from (the
eight decks at their formula-based Power, so Bronze IV and Mythic already counted Marrow-Gnawer and Kaalia Core).

| Tier | Division | Target | Nearest allowed decks (Power) | Within 0.5: before → after |
|---|---|---|---|---|
| Bronze | IV | 3.12 | karador-ghost-chieftain-core 3.4, marrow-gnawer-core 3.4, kumena-tyrant-of-orazca-core 3.5 | 4 → 5 |
| Bronze | III | 3.38 | karador-ghost-chieftain-core 3.4, marrow-gnawer-core 3.4, kumena-tyrant-of-orazca-core 3.5 | 6 → 7 |
| Bronze | II | 3.62 | marisi-breaker-of-the-coil-core 3.6, tormod-the-desecrator-core 3.6, marisi-breaker-of-the-coil-exhibition 3.7 | 6 → 7 |
| Bronze | I | 3.88 | chaos-incarnate 3.8, marisi-breaker-of-the-coil-exhibition 3.7, marisi-breaker-of-the-coil-core 3.6 | 6 → 7 |
| Silver | IV | 4.12 | wilhelt-the-rotcleaver-core 4.4, chaos-incarnate 3.8, marisi-breaker-of-the-coil-exhibition 3.7 | 3 → **3** |
| Silver | III | 4.38 | wilhelt-the-rotcleaver-core 4.4, phelddagrif-core 4.9, meren-of-clan-nel-toth-exhibition 4.9 | 1 → **1** |
| Silver | II | 4.62 | wilhelt-the-rotcleaver-core 4.4, phelddagrif-core 4.9, meren-of-clan-nel-toth-exhibition 4.9 | 2 → **4** |
| Silver | I | 4.88 | phelddagrif-core 4.9, meren-of-clan-nel-toth-exhibition 4.9, syr-gwyn-hero-of-ashvale-core 5.1 | 3 → 6 |
| Gold | IV | 5.12 | syr-gwyn-hero-of-ashvale-core 5.1, lathril-blade-of-the-elves-core 5.2, wilhelt-the-rotcleaver-upgraded 5.3 | 6 → 8 |
| Gold | III | 5.38 | wilhelt-the-rotcleaver-upgraded 5.3, arahbo-roar-of-the-world-core 5.3, grave-danger 5.5 | 6 → 8 |
| Gold | II | 5.62 | grave-danger 5.5, meren-of-clan-nel-toth-core 5.5, token-triumph 5.9 | 8 → 7 |
| Gold | I | 5.88 | token-triumph 5.9, draconic-destruction 6.1, miirym-sentinel-wyrm-core 6.2 | 8 → 5 |
| Platinum | IV | 6.12 | draconic-destruction 6.1, miirym-sentinel-wyrm-core 6.2, token-triumph 5.9 | 9 → 6 |
| Platinum | III | 6.38 | krenko-mob-boss-core 6.4, lathril-blade-of-the-elves-upgraded 6.4, miirym-sentinel-wyrm-core 6.2 | 10 → 9 |
| Platinum | II | 6.62 | lathril-blade-of-the-elves-exhibition 6.6, first-flight 6.7, krenko-mob-boss-exhibition 6.7 | 8 → 8 |
| Platinum | I | 6.88 | hakbal-of-the-surging-soul-core 6.8, krenko-mob-boss-upgraded 7.0, first-flight 6.7 | 7 → 8 |
| Diamond | IV | 7.12 | krenko-mob-boss-optimized 7.1, gishath-suns-avatar-upgraded 7.2, krenko-mob-boss-upgraded 7.0 | 10 → 11 |
| Diamond | III | 7.38 | the-ur-dragon-upgraded 7.4, old-gnawbone-core 7.4, edgar-markov-upgraded 7.5 | 10 → 9 |
| Diamond | II | 7.62 | the-ur-dragon-optimized 7.6, gishath-suns-avatar-exhibition 7.7, edgar-markov-upgraded 7.5 | 12 → 10 |
| Diamond | I | 7.88 | gishath-suns-avatar-core 7.9, edgar-markov-core 8.0, gishath-suns-avatar-exhibition 7.7 | 13 → 11 |
| Mythic | | 8.50 | kaalia-of-the-vast-core 8.4, the-ur-dragon-core 8.3, kaalia-of-the-vast-optimized 8.2 | 5 → 5 |

**Fewer than five within 0.5:** Silver IV, Silver III and Silver II. Silver IV's three are Wilhelt Core, Chaos
Incarnate and Marisi Exhibition; Silver II's four are Wilhelt Core, Phelddagrif, Meren Exhibition and Syr Gwyn.
Mythic's five are Kaalia Core, The Ur-Dragon Core, Kaalia Optimized, Miirym Optimized and Edgar Core; no deck rates
between 8.4 and Lathliss's 9.9.

| Quick Match | Power band | Decks in the band |
|---|---|---|
| Easy | 3–4 | 9: chaos-incarnate, lathril-blade-of-the-elves-optimized, marisi-breaker-of-the-coil-exhibition, wilhelt-the-rotcleaver-optimized, marisi-breaker-of-the-coil-core, tormod-the-desecrator-core, kumena-tyrant-of-orazca-core, karador-ghost-chieftain-core, marrow-gnawer-core |
| Medium | 5–6 | 10: token-triumph, gishath-suns-avatar-optimized, edgar-markov-optimized, winota-joiner-of-forces-optimized, grave-danger, meren-of-clan-nel-toth-core, wilhelt-the-rotcleaver-upgraded, arahbo-roar-of-the-world-core, lathril-blade-of-the-elves-core, syr-gwyn-hero-of-ashvale-core |
| Hard | 7–8 | 11: edgar-markov-core, gishath-suns-avatar-core, gishath-suns-avatar-exhibition, the-ur-dragon-optimized, edgar-markov-upgraded, tiamat-core, the-ur-dragon-upgraded, old-gnawbone-core, gishath-suns-avatar-upgraded, krenko-mob-boss-optimized, krenko-mob-boss-upgraded |

## How long games took

- 64 min on 4 workers, 4.2 h of play. 40 s a game on average (median 24, longest 361), 18.1 turns (11–40).
- The slowest decks: Kumena 63 s on average, Meren Exhibition 57 s, Marrow-Gnawer 48 s; Kaalia Core 20 s.
- Going first won 219 of 384 games (57%).

## What did not run

- No runs beyond batch G and the smoke. No weight fit, and no formula, weights, deck-list, app or engine change; no
  edit to `ai-decks.json` beyond what `rate --write` writes. No unit tests (no code changed). No `batch-g2`.
- No native, iOS, Android or phone runs: JVM engine on the cloud CPU only, AI against AI, not against a person.
  Searches stop on a clock, so a rerun agrees statistically, not move for move.
