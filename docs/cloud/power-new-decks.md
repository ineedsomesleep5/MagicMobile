# Cloud brief: deck Power, new decks and top-up

Start a cloud session on branch `claude/deck-power-design` with: "Follow docs/cloud/power-new-decks.md."
Caleb approved this run on 2026-10-25 ("about five decks per rank"). Measurement only: no app, engine, deck or
weights changes.

Eight AI decks were added on 2026-10-25 so each Ranked tier has about five decks to choose from (docs/DECK_POWER.md,
Power v2): Tiamat, Lathliss and Old Gnawbone for the strong end; Phelddagrif, Zedruu, Karador, Meren and Marisi Core
for the gentle end. They have no games yet. Six more decks that Mythic and Bronze lean on have only 46–48 games each.
This run measures both, the same way as the gauntlet (docs/cloud/reports/power-1.md).

## Setup

1. `git fetch origin claude/deck-power-design && git checkout claude/deck-power-design`. Work and push only on this
   branch. Read `AGENTS.md`, `docs/cloud/reports/power-1.md` and the calibration entries in `docs/LESSONS.md`.
2. `cd packages/ondevice-engine && bash scripts/build_jvm.sh`, then `python3 scripts/ai_calibration.py decks` must
   resolve all 41 decks. If `build/ai-calibration/decks` exists from an older checkout, delete it first so the new
   decks resolve. Record `git rev-parse HEAD`, the upstream pin and the CPU count; `engine/`, `platform/` and the pin
   must match power-1.md's.
3. Smoke: `--games 4` of batch E into a scratch `--out` under `build/`; check the games end normally; delete it.

## Batches (skill 3 against 3, phone budget, default heap and workers)

Each pool deck plays First Flight, Token Triumph and Grave Danger with both seatings. The seed is new so the top-up
does not replay the gauntlet's games. From `packages/ondevice-engine`, with `R=$(git rev-parse --show-toplevel)`:

**E: 384 games** (8 new decks × 3 references × 16):

```
python3 scripts/ai_calibration.py run --skill-a 3 --skill-b 3 --seed 20261025 --against first-flight,token-triumph,grave-danger \
  --pool ai-tiamat-core,ai-lathliss-dragon-queen-core,ai-old-gnawbone-core,ai-phelddagrif-core,ai-zedruu-the-greathearted-core,ai-karador-ghost-chieftain-core,ai-meren-of-clan-nel-toth-core,ai-marisi-breaker-of-the-coil-core \
  --games 384 --out "$R/docs/cloud/power-results/batch-e"
```

**F: 288 games** (6 decks × 3 × 16), after E is pushed: the top-up.

```
python3 scripts/ai_calibration.py run --skill-a 3 --skill-b 3 --seed 20261026 --against first-flight,token-triumph,grave-danger \
  --pool ai-kaalia-of-the-vast-optimized,ai-miirym-sentinel-wyrm-optimized,ai-krenko-mob-boss-optimized,ai-tormod-the-desecrator-core,ai-marisi-breaker-of-the-coil-exhibition,ai-kynaios-and-tiro-of-meletis-exhibition \
  --games 288 --out "$R/docs/cloud/power-results/batch-f"
```

Reruns with the same arguments resume; harness failures replay automatically. If a new deck fails deck validation or
keeps failing, note it, rerun the batch without it into a new folder (`batch-e2`), keep the finished CSV, carry on.

## Progress and report

- Commit and push the CSVs at least every ~2 hours and after each batch (end commit messages with
  `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`). On a rejected push, `git pull --rebase` and push again.
- After both batches: `python3 scripts/ranked/deck_power.py rate --write` (from the repo root) and commit
  `scripts/ranked/deck-power-ratings.json` with the CSVs. Do not change `deck-power-weights.json`.
- Write `docs/cloud/reports/power-3.md` (`STATUS: partial` until both batches end, then `STATUS: ready-for-review`),
  short and plain like power-1.md: commands, engine commit, games played/ended/replayed; per deck its games and win
  rate (Wilson 95% CI) against each reference and overall; its Power before and after (`deck_power.py rate`); and
  `deck_power.py ladder`, saying which ranks have fewer than five decks within 0.5 of their band. Separate what ran
  from what didn't.

Done = both batches' CSVs, the updated ratings and power-3.md pushed to `claude/deck-power-design`.

## Rules

No runs beyond these two batches. Do not change the weights, the formula, `ai-decks.json`, app code or the engine.
Don't merge, open PRs, release or upload. If the engine build fails or many games fail, stop, write what happened in
power-3.md, commit and push it.
