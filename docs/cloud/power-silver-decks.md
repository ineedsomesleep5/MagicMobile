# Cloud brief: deck Power, Silver and Mythic decks

Start a cloud session on branch `claude/deck-power-design` with: "Follow docs/cloud/power-silver-decks.md."
Caleb approved this run on 2026-10-25 ("go for it"). Measurement only: no app, engine, deck or weights changes.

docs/cloud/reports/power-3.md left Silver (Power 4–5) with one to three decks per division and Mythic (8.5) with four.
Eight decks were added for them and have no games yet: Kumena, Hakbal, Marrow-Gnawer, Arahbo, Syr Gwyn and Meren
Exhibition aimed at Silver; Kaalia and Miirym Core aimed at Mythic. This run measures them the same way as power-3.

## Setup

1. `git fetch origin claude/deck-power-design && git checkout claude/deck-power-design`. Work and push only on this
   branch. Read `AGENTS.md`, `docs/cloud/reports/power-3.md` and the calibration entries in `docs/LESSONS.md`.
2. `cd packages/ondevice-engine && bash scripts/build_jvm.sh`; delete any old `build/ai-calibration/decks`, then
   `python3 scripts/ai_calibration.py decks` must resolve all 48 decks (43 AI decks, 5 precons). Record
   `git rev-parse HEAD`, the upstream pin and the CPU count; `engine/`, `platform/` and the pin must match power-3.md's.
3. Smoke: `--games 4` of batch G into a scratch `--out` under `build/`; check the games end normally; delete it.

## Batch G: 384 games (8 decks × 3 references × 16, skill 3 against 3, phone budget, default heap and workers)

From `packages/ondevice-engine`, with `R=$(git rev-parse --show-toplevel)`:

```
python3 scripts/ai_calibration.py run --skill-a 3 --skill-b 3 --seed 20261027 --against first-flight,token-triumph,grave-danger \
  --pool ai-kumena-tyrant-of-orazca-core,ai-hakbal-of-the-surging-soul-core,ai-marrow-gnawer-core,ai-arahbo-roar-of-the-world-core,ai-syr-gwyn-hero-of-ashvale-core,ai-meren-of-clan-nel-toth-exhibition,ai-kaalia-of-the-vast-core,ai-miirym-sentinel-wyrm-core \
  --games 384 --out "$R/docs/cloud/power-results/batch-g"
```

Reruns with the same arguments resume; harness failures replay automatically. If a deck fails deck validation or
keeps failing, note it, rerun without it into `batch-g2`, keep the finished CSV, carry on.

## Progress and report

- Commit and push the CSVs at least every ~2 hours and when the batch ends (end commit messages with
  `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`). On a rejected push, `git pull --rebase` and push again.
- Then `python3 scripts/ranked/deck_power.py rate --write` from the repo root, and commit
  `scripts/ranked/deck-power-ratings.json` and `apps/ios/MagicMobile/Resources/ai-decks.json` (its `power` block only
  changes) with the CSVs.
- Write `docs/cloud/reports/power-4.md` (`STATUS: partial` until the batch ends, then `STATUS: ready-for-review`),
  short and plain like power-3.md: commands, engine commit, games played/ended/replayed; per new deck its games and win
  rate (Wilson 95% CI) against each reference and overall and its Power before and after; and `deck_power.py ladder`,
  saying which ranks still have fewer than five decks within 0.5 of their target. Separate what ran from what didn't.

Done = batch G's CSVs, the updated ratings and power-4.md pushed to `claude/deck-power-design`.

## Rules

No runs beyond batch G. Do not change the weights, the formula, the deck lists in `ai-decks.json`, app code or the
engine. Don't merge, open PRs, release or upload. If the engine build fails or many games fail, stop, write what
happened in power-4.md, commit and push it.
