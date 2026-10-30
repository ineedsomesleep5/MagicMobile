# Cloud brief: deck Power, the new Platinum, Diamond and Mythic decks

Start a cloud session on branch `claude/high-rank-decks` with: "Follow docs/cloud/power-high-decks.md."
Caleb approved this run on 2026-10-29 ("let's get it started"). Measurement only: no app, engine, deck or weights changes.

Players in Platinum, Diamond and Mythic kept meeting the same dragon and token decks. Fourteen decks were added for
those ranks and have no games yet, so their Power is the formula's guess (±4 points):
- aimed at Platinum (Core): Teysa Karlov, Arcades, Isshin, Sythis, Lord Windgrace;
- aimed at Diamond (Upgraded): Kinnan, Atraxa, Muldrotha, Rafiq, Prosper;
- aimed at Mythic (Optimized): Kinnan, Korvold, Omnath, Tergrid.

They play against three well-measured decks spread over the top of the ladder: First Flight (6.6, 1,017 games),
Gishath Core (7.9, 689) and The Ur-Dragon Core (8.3, 537), so a deck near 9 still loses some games.

## Setup

1. `git fetch origin claude/high-rank-decks && git checkout claude/high-rank-decks`. Work and push only on this
   branch. Read `AGENTS.md`, `docs/cloud/reports/power-4.md` and the calibration entries in `docs/LESSONS.md`.
2. `cd packages/ondevice-engine && bash scripts/build_jvm.sh`; delete any old `build/ai-calibration/decks`, then
   `python3 scripts/ai_calibration.py decks` must resolve all 62 decks (57 AI decks, 5 precons). Record
   `git rev-parse HEAD`, the upstream pin and the CPU count; `engine/`, `platform/` and the pin must match power-4.md's.
3. Smoke: `--games 4` of batch H into a scratch `--out` under `build/`; check the games end normally; delete it.

## Batch H: 1,008 games (14 decks × 3 references × 24, skill 3 against 3, phone budget, default heap and workers)

From `packages/ondevice-engine`, with `R=$(git rev-parse --show-toplevel)`:

```
python3 scripts/ai_calibration.py run --skill-a 3 --skill-b 3 --seed 20261029 --against first-flight,ai-gishath-suns-avatar-core,ai-the-ur-dragon-core \
  --pool ai-teysa-karlov-core,ai-arcades-the-strategist-core,ai-isshin-two-heavens-as-one-core,ai-sythis-harvests-hand-core,ai-lord-windgrace-core,ai-kinnan-bonder-prodigy-upgraded,ai-atraxa-praetors-voice-upgraded,ai-muldrotha-the-gravetide-upgraded,ai-rafiq-of-the-many-upgraded,ai-prosper-tome-bound-upgraded,ai-kinnan-bonder-prodigy-optimized,ai-korvold-fae-cursed-king-optimized,ai-omnath-locus-of-creation-optimized,ai-tergrid-god-of-fright-optimized \
  --games 1008 --out "$R/docs/cloud/power-results/batch-h"
```

Reruns with the same arguments resume; harness failures replay automatically. If a deck fails deck validation or
keeps failing, note it, rerun without it into `batch-h2`, keep the finished CSV, carry on.

## Progress and report

- Commit and push the CSVs at least every ~2 hours and when the batch ends (end commit messages with
  `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`). On a rejected push, `git pull --rebase` and push again.
- Then `python3 scripts/ranked/deck_power.py rate --write` from the repo root, and commit
  `scripts/ranked/deck-power-ratings.json` and `apps/ios/MagicMobile/Resources/ai-decks.json` (its `power` block only
  changes) with the CSVs.
- Write `docs/cloud/reports/power-5.md` (`STATUS: partial` until the batch ends, then `STATUS: ready-for-review`),
  short and plain like power-4.md: commands, engine commit, games played/ended/replayed; per new deck its games and win
  rate (Wilson 95% CI) against each reference and overall and its Power before and after; `deck_power.py ladder`; and,
  for Platinum, Diamond and Mythic, which decks each division would now bring and how many different commanders
  that is. Note any deck whose games often stall, time out or end by decking. Separate what ran from what didn't.

Done = batch H's CSVs, the updated ratings and power-5.md pushed to `claude/high-rank-decks`.

## Rules

No runs beyond batch H. Do not change the weights, the formula, the deck lists in `ai-decks.json`, app code or the
engine. Don't merge, open PRs, release or upload. If the engine build fails or many games fail, stop, write what
happened in power-5.md, commit and push it.
