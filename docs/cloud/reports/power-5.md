STATUS: ready-for-review

# Power 5: the Platinum, Diamond and Mythic decks

Cloud session for docs/cloud/power-high-decks.md (approved by Caleb, 2026-10-29). Branch `claude/high-rank-decks`.
Measurement only: no weights, formula, app, engine or deck-list changes; nothing merged, released or uploaded. The
only non-result files changed are the ratings `deck_power.py rate --write` writes (`scripts/ranked/deck-power-ratings.json`
and the `power` block of `apps/ios/MagicMobile/Resources/ai-decks.json`; everything outside `power` checked identical).

## Answer

- **Most of the fourteen played well below their formula.** Only five won 45% or more against the three references:
  Tergrid Optimized (64%, **9.2**), Sythis Core (54%, **7.9**), Kinnan Upgraded (53%, **8.0**), Isshin Core (46%,
  **7.0**) and Omnath Optimized (45%, **6.7**).
- **The rest fell, most by 1–4 points.** Muldrotha Upgraded 5.9 → **2.5**, Korvold Optimized 7.0 → **2.9**,
  Teysa Core 6.8 → **3.4**, Rafiq Upgraded 6.3 → **4.4**, Arcades and Lord Windgrace Core **4.8**, Prosper Upgraded
  7.0 → **4.9**, Kinnan Optimized 7.4 → **5.6** (below Kinnan Upgraded), Atraxa Upgraded 6.6 → **5.8**.
- **Mythic gains nothing.** Its three nearest decks are still Edgar Core 8.6, Kaalia Core 8.6 and The Ur-Dragon
  Upgraded 8.7. Tergrid (9.2) is too far above the 8.5 target and Kinnan Upgraded (8.0) too far below it.
- **Diamond gains Sythis and Isshin and loses Kinnan, Korvold and Prosper:** 9 decks, 5 commanders (Gishath, Krenko,
  The Ur-Dragon, Sythis, Isshin). **Platinum** keeps Isshin as its only new deck: 9 decks, 9 commanders. The extra
  variety the formula promised Platinum and Diamond mostly did not hold up in play.

## What ran

- **Engine.** Branch HEAD `acfcf4e` when the runs began. Upstream XMage pin `dac400ba1380f17492c9ad6a65ab60f12f28cd97`
  (same as power-4.md). `engine/`, `platform/` and `tools/` are **not** identical to power-4.md's `9cbd831`: six files
  differ, all outside the AI: `MobileHumanPlayer` (a game copy's end no longer closes the live human's channel),
  `XmageEngine`/`ViewProjector` (a paying seat's mana sources in the published view), `engine/tools/LessonCli.java`
  and two human-seat tests. Calibration seats are AI players and never use `MobileHumanPlayer` or `ViewProjector`, so
  the run went ahead; noted here so the comparison with earlier batches is explicit.
- 4 CPUs, 15 GB, OpenJDK 21.0.12, Maven 3.9.11. `bash scripts/build_jvm.sh`: BUILD SUCCESS, "Adapter compilation
  completed". Stale `build/ai-calibration/decks` deleted first; `ai_calibration.py decks` exits 0 and resolves all
  62 decks (57 AI decks, 5 precons).
- **Settings.** Skill 3 against 3, phone budget, default heap, 4 workers.
- **Smoke.** 4 games of batch H (Muldrotha Upgraded against The Ur-Dragon Core): all ended normally, 15–18 turns,
  35–74 s. Deleted.
- **Batch H**, 1,008 games, 03:18–06:32 UTC. The cloud tool stopped the first launch at its 2-hour limit after 619
  games; the same command resumed it (05:17) and played the remaining 389 plus one replay in 75 min.

  ```
  python3 scripts/ai_calibration.py run --skill-a 3 --skill-b 3 --seed 20261029 --against first-flight,ai-gishath-suns-avatar-core,ai-the-ur-dragon-core \
    --pool ai-teysa-karlov-core,ai-arcades-the-strategist-core,ai-isshin-two-heavens-as-one-core,ai-sythis-harvests-hand-core,ai-lord-windgrace-core,ai-kinnan-bonder-prodigy-upgraded,ai-atraxa-praetors-voice-upgraded,ai-muldrotha-the-gravetide-upgraded,ai-rafiq-of-the-many-upgraded,ai-prosper-tome-bound-upgraded,ai-kinnan-bonder-prodigy-optimized,ai-korvold-fae-cursed-king-optimized,ai-omnath-locus-of-creation-optimized,ai-tergrid-god-of-fright-optimized \
    --games 1008 --out "$R/docs/cloud/power-results/batch-h"
  ```

- **Games.** 1,008 played: 1,000 ended normally (989 with a winner, 11 rules draws), 7 hit the turn limit, 1 stopped
  in the engine. That one, game 269 (Isshin Core against Gishath Core), was replayed automatically on resume and
  stopped again (15 turns); it stays in the CSV as `engine-stopped` and `deck_power.py` ignores it. The worker logs
  also show two `StackOverflowError`s inside AI simulations and one XMage `NullPointerException` game error (casting
  Armadillo Cloak, `TriggeredAbilities.checkTriggers`); their games still finished. No deck failed validation, so no
  `batch-h2`. Data: `docs/cloud/power-results/batch-h/`. (The "batch H checkpoint" commits are mid-run snapshots; the
  last commit has all 1,008.)

## The fourteen decks

Each cell is wins–losses, win rate and Wilson 95% interval (draws left out). Each deck met each reference 24 times,
both seatings equally. Power is `deck_power.py rate` before and after this run, with its range.

| Deck | Aimed at | Formula | Power before → after | Games | vs First Flight | vs Gishath Core | vs The Ur-Dragon Core | Overall |
|---|---|---|---|---|---|---|---|---|
| ai-tergrid-god-of-fright-optimized | Mythic | 6.4 | 6.8 → **9.2** (5.2–10.0) | 72 | 13–9, 59% (39%–77%) | 15–9, 62% (43%–79%) | 16–7, 70% (49%–84%) | **44–25, 64% (52%–74%)** |
| ai-sythis-harvests-hand-core | Platinum | 6.1 | 6.4 → **7.9** (3.9–10.0) | 72 | 8–16, 33% (18%–53%) | 14–9, 61% (41%–78%) | 16–7, 70% (49%–84%) | **38–32, 54% (43%–65%)** |
| ai-kinnan-bonder-prodigy-upgraded | Diamond | 7.2 | 7.7 → **8.0** (4.0–10.0) | 72 | 12–11, 52% (33%–71%) | 12–10, 55% (35%–73%) | 12–11, 52% (33%–71%) | **36–32, 53% (41%–64%)** |
| ai-isshin-two-heavens-as-one-core | Platinum | 6.3 | 6.7 → **7.0** (3.0–10.0) | 72 | 13–11, 54% (35%–72%) | 8–15, 35% (19%–55%) | 12–12, 50% (31%–69%) | **33–38, 46% (35%–58%)** |
| ai-omnath-locus-of-creation-optimized | Mythic | 5.8 | 6.2 → **6.7** (2.8–10.0) | 72 | 12–12, 50% (31%–69%) | 7–16, 30% (16%–51%) | 13–11, 54% (35%–72%) | **32–39, 45% (34%–57%)** |
| ai-atraxa-praetors-voice-upgraded | Diamond | 6.2 | 6.6 → **5.8** (1.9–9.8) | 72 | 6–18, 25% (12%–45%) | 10–14, 42% (24%–61%) | 11–12, 48% (29%–67%) | **27–44, 38% (28%–50%)** |
| ai-kinnan-bonder-prodigy-optimized | Mythic | 6.9 | 7.4 → **5.6** (1.7–9.6) | 72 | 8–16, 33% (18%–53%) | 10–13, 43% (26%–63%) | 7–17, 29% (15%–49%) | **25–46, 35% (25%–47%)** |
| ai-prosper-tome-bound-upgraded | Diamond | 6.6 | 7.0 → **4.9** (1.0–8.9) | 72 | 8–16, 33% (18%–53%) | 7–17, 29% (15%–49%) | 7–17, 29% (15%–49%) | **22–50, 31% (21%–42%)** |
| ai-arcades-the-strategist-core | Platinum | 5.5 | 5.8 → **4.8** (1.0–8.8) | 72 | 7–17, 29% (15%–49%) | 10–14, 42% (24%–61%) | 5–18, 22% (10%–42%) | **22–49, 31% (21%–42%)** |
| ai-lord-windgrace-core | Platinum | 5.8 | 6.1 → **4.8** (1.0–8.8) | 72 | 6–18, 25% (12%–45%) | 7–17, 29% (15%–49%) | 9–15, 38% (21%–57%) | **22–50, 31% (21%–42%)** |
| ai-rafiq-of-the-many-upgraded | Diamond | 6.0 | 6.3 → **4.4** (1.0–8.4) | 72 | 7–17, 29% (15%–49%) | 6–18, 25% (12%–45%) | 7–17, 29% (15%–49%) | **20–52, 28% (19%–39%)** |
| ai-teysa-karlov-core | Platinum | 6.4 | 6.8 → **3.4** (1.0–7.5) | 72 | 4–19, 17% (7%–37%) | 4–19, 17% (7%–37%) | 6–17, 26% (13%–46%) | **14–55, 20% (12%–31%)** |
| ai-korvold-fae-cursed-king-optimized | Mythic | 6.5 | 7.0 → **2.9** (1.0–7.0) | 72 | 4–20, 17% (7%–36%) | 6–18, 25% (12%–45%) | 2–22, 8% (2%–26%) | **12–60, 17% (10%–27%)** |
| ai-muldrotha-the-gravetide-upgraded | Diamond | 5.6 | 5.9 → **2.5** (1.0–6.7) | 72 | 6–18, 25% (12%–45%) | 1–21, 5% (1%–22%) | 4–20, 17% (7%–36%) | **11–59, 16% (9%–26%)** |

The references against these fourteen: First Flight 218–114 (66%, 60–71), Gishath Core 210–117 (64%, 59–69),
The Ur-Dragon Core 203–127 (62%, 56–67).

Other ratings that moved only through the shared fit (±0.1 unless noted): The Ur-Dragon Core 8.3 → **7.9**, Gishath
Core 7.5 → 7.3, First Flight 6.5 → 6.6, Edgar Core 8.7 → 8.6, Krenko Upgraded 7.9 → 7.8, The Ur-Dragon Optimized
7.1 → 7.0, Miirym Core 6.5 → 6.4, Gishath Optimized, Winota Optimized, Lathril Core, Wilhelt Core, Chaos Incarnate
down 0.1; Marisi Core, Marrow-Gnawer, Tormod Core, Zedruu up 0.1. Every other deck is unchanged.

## What Platinum, Diamond and Mythic would bring

Each division picks among the three nearest allowed decks to its target (`closest: 3`); a tier brings the union of
its divisions' three. Before is the ratings this run started from, with the fourteen at their formula-based Power.

| Tier | Before: decks (commanders) | After: decks (commanders) | After, the decks |
|---|---|---|---|
| Platinum | 11 (11) | **9 (9)** | Arahbo Core 6.1, Token Triumph 6.4, Miirym Core 6.4, Syr Gwyn Core 6.5, First Flight 6.6, Krenko Core 6.6, Lathril Exhibition 6.6, Old Gnawbone Core 6.9, Isshin Core 7.0 |
| Diamond | 10 (6) | **9 (5)** | The Ur-Dragon Optimized 7.0, Isshin Core 7.0, Krenko Optimized 7.3, Gishath Core 7.3, Krenko Upgraded 7.8, Gishath Exhibition 7.8, Gishath Upgraded 7.8, The Ur-Dragon Core 7.9, Sythis Core 7.9 |
| Mythic | 3 (3) | **3 (3)** | Edgar Core 8.6, Kaalia Core 8.6, The Ur-Dragon Upgraded 8.7 |

Before, Platinum counted Lord Windgrace, Rafiq, Sythis, Teysa and Prosper, and Diamond counted Prosper, Korvold and
both Kinnans; all came from the formula guess. Diamond is still mostly Gishath, Krenko and The Ur-Dragon (7 of 9).
Kinnan Upgraded (8.0) sits 0.12 from Diamond I's target and just misses its three (7.9, 7.9, 7.8).

## Ladder

`python3 scripts/ranked/deck_power.py ladder` after `rate --write`. No division's nearest deck is more than 0.5 from
its target.

| Tier | Division | Target | Max bracket | Nearest allowed decks (Power) | Gap |
|---|---|---|---|---|---|
| Bronze | IV | 3.12 | 2 | chaos-incarnate 3.1, marisi-breaker-of-the-coil-core 3.3, teysa-karlov-core 3.4 | 0.0 |
| Bronze | III | 3.38 | 2 | teysa-karlov-core 3.4, marisi-breaker-of-the-coil-core 3.3, karador-ghost-chieftain-core 3.6 | 0.0 |
| Bronze | II | 3.62 | 2 | karador-ghost-chieftain-core 3.6, kumena-tyrant-of-orazca-core 3.7, marrow-gnawer-core 3.7 | 0.0 |
| Bronze | I | 3.88 | 2 | marisi-breaker-of-the-coil-exhibition 3.8, meren-of-clan-nel-toth-exhibition 4.0, kumena-tyrant-of-orazca-core 3.7 | 0.1 |
| Silver | IV | 4.12 | 2 | meren-of-clan-nel-toth-exhibition 4.0, wilhelt-the-rotcleaver-core 4.3, tormod-the-desecrator-core 4.4 | 0.1 |
| Silver | III | 4.38 | 2 | tormod-the-desecrator-core 4.4, wilhelt-the-rotcleaver-core 4.3, phelddagrif-core 4.5 | 0.0 |
| Silver | II | 4.62 | 2 | phelddagrif-core 4.5, lathril-blade-of-the-elves-core 4.8, arcades-the-strategist-core 4.8 | 0.1 |
| Silver | I | 4.88 | 2 | lathril-blade-of-the-elves-core 4.8, arcades-the-strategist-core 4.8, lord-windgrace-core 4.8 | 0.1 |
| Gold | IV | 5.12 | 3 | grave-danger 5.1, meren-of-clan-nel-toth-core 5.1, prosper-tome-bound-upgraded 4.9 | 0.0 |
| Gold | III | 5.38 | 3 | lathril-blade-of-the-elves-upgraded 5.4, tiamat-core 5.6, grave-danger 5.1 | 0.0 |
| Gold | II | 5.62 | 3 | tiamat-core 5.6, atraxa-praetors-voice-upgraded 5.8, lathril-blade-of-the-elves-upgraded 5.4 | 0.0 |
| Gold | I | 5.88 | 3 | atraxa-praetors-voice-upgraded 5.8, arahbo-roar-of-the-world-core 6.1, tiamat-core 5.6 | 0.1 |
| Platinum | IV | 6.12 | 3 | arahbo-roar-of-the-world-core 6.1, token-triumph 6.4, miirym-sentinel-wyrm-core 6.4 | 0.0 |
| Platinum | III | 6.38 | 3 | token-triumph 6.4, miirym-sentinel-wyrm-core 6.4, syr-gwyn-hero-of-ashvale-core 6.5 | 0.0 |
| Platinum | II | 6.62 | 3 | first-flight 6.6, krenko-mob-boss-core 6.6, lathril-blade-of-the-elves-exhibition 6.6 | 0.0 |
| Platinum | I | 6.88 | 3 | old-gnawbone-core 6.9, isshin-two-heavens-as-one-core 7.0, first-flight 6.6 | 0.0 |
| Diamond | IV | 7.12 | 4 | the-ur-dragon-optimized 7.0, isshin-two-heavens-as-one-core 7.0, krenko-mob-boss-optimized 7.3 | 0.1 |
| Diamond | III | 7.38 | 4 | krenko-mob-boss-optimized 7.3, gishath-suns-avatar-core 7.3, the-ur-dragon-optimized 7.0 | 0.1 |
| Diamond | II | 7.62 | 4 | krenko-mob-boss-upgraded 7.8, gishath-suns-avatar-exhibition 7.8, gishath-suns-avatar-upgraded 7.8 | 0.2 |
| Diamond | I | 7.88 | 4 | the-ur-dragon-core 7.9, sythis-harvests-hand-core 7.9, krenko-mob-boss-upgraded 7.8 | 0.0 |
| Mythic |  | 8.50 | 4 | edgar-markov-core 8.6, kaalia-of-the-vast-core 8.6, the-ur-dragon-upgraded 8.7 | 0.1 |

| Quick Match | Power band | Decks in the band |
|---|---|---|
| Easy | 3–4 | 10: lathril-blade-of-the-elves-optimized, meren-of-clan-nel-toth-exhibition, wilhelt-the-rotcleaver-optimized, marisi-breaker-of-the-coil-exhibition, kumena-tyrant-of-orazca-core, marrow-gnawer-core, karador-ghost-chieftain-core, teysa-karlov-core, marisi-breaker-of-the-coil-core, chaos-incarnate |
| Medium | 5–6 | 8: gishath-suns-avatar-optimized, winota-joiner-of-forces-optimized, atraxa-praetors-voice-upgraded, tiamat-core, kinnan-bonder-prodigy-optimized, lathril-blade-of-the-elves-upgraded, grave-danger, meren-of-clan-nel-toth-core |
| Hard | 7–8 | 10: kinnan-bonder-prodigy-upgraded, the-ur-dragon-core, sythis-harvests-hand-core, krenko-mob-boss-upgraded, gishath-suns-avatar-exhibition, gishath-suns-avatar-upgraded, krenko-mob-boss-optimized, gishath-suns-avatar-core, the-ur-dragon-optimized, isshin-two-heavens-as-one-core |

## Stalls, time-outs and odd endings

- **Turn limit (7 games):** Tergrid Optimized 3 (two against First Flight, one against The Ur-Dragon), Sythis Core 2,
  Teysa Core 1, Arcades Core 1. **Tergrid's three took 3.6–6.2 s for 41–42 turns**, so nobody was doing anything:
  a lock or stall worth a look before Tergrid goes to Mythic players. The other four took 60–319 s.
- **Rules draws (11, "ended" without a winner):** Kinnan Upgraded 4, Muldrotha 2, Teysa 2, Atraxa, Kinnan Optimized and
  Omnath 1 each. Two of them ended in 4–5 s at turn 13 (Teysa and Muldrotha against Gishath Core).
- **Slow decks:** Muldrotha 73 s a game on average, Lord Windgrace 67 s (longest game 775 s), Kinnan Upgraded 65 s,
  Arcades 61 s. Tergrid (18 s) and Isshin (22 s) were the quickest.
- **Decking** is not recorded in the CSV (it keeps winner, turns, seconds and end only), so this run cannot say how
  often games ended by decking.
- Overall: 46 s a game on average (median 26, longest 775), 18.1 turns (4–42), 12.9 h of play on 4 workers. Going
  first won 561 of 989 decided games (57%).

## What did not run

- No runs beyond batch H and the smoke; no `batch-h2`. No weight fit, and no formula, weights, deck-list, app or engine
  change; no edit to `ai-decks.json` beyond what `rate --write` writes. No unit tests (no code changed). The Tergrid
  stalls and the engine-stopped game 269 were not investigated.
- No native, iOS, Android or phone runs: JVM engine on the cloud CPU only, AI against AI, not against a person.
  Searches stop on a clock, so a rerun agrees statistically, not move for move.

## Addendum: what live Ranked brings (review, 2026-10-30)

The pool tables above use the ladder bands in `deck-power-weights.json`. Live Ranked takes its target from
`ranked_ai_tuning` (Platinum 6.75–7.75, Diamond 8–9, Mythic 8.75–9.75), and the picker drops a player's last 4 decks
before it takes the nearest 3. Simulated over 4,000 games per division with those rules (decks seen in at least 1% of
games; no commander of the player's own excluded):

| Tier | Now: decks (commanders) | With these ratings: decks (commanders) | New decks that reach it |
|---|---|---|---|
| Platinum | 13 (10) | 14 (11) | Isshin, Sythis, Kinnan Upgraded |
| Diamond | 12 (8) | 14 (11) | Kinnan Upgraded, Sythis, Tergrid |
| Mythic | 7 (6) | 7 (6) | Tergrid (replaces Lathliss) |

So "Mythic gains nothing" holds only for the ladder bands. Teysa, Korvold, Muldrotha, Rafiq, Arcades, Windgrace and
Prosper rate too low for these tiers and land in Bronze to Gold, which still adds variety there. Each new deck's Power
rests on 72 games, so its range stays wide; games against people will move them.
