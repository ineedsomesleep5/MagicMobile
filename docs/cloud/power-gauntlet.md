# Cloud brief: deck Power gauntlet

Start a cloud session on branch `claude/deck-power-design` with: "Follow docs/cloud/power-gauntlet.md."
Caleb approved this run on 2026-10-24. Measurement only: no app, engine, deck or weights changes.

MagicMobile is adding a hidden 1–10 Power rating for its 33 AI decks (docs/DECK_POWER.md). The formula
(`scripts/ranked/deck_power.py`, weights in `scripts/ranked/deck-power-weights.json`) matches C3's precon round robin
but generalises weakly from card counts, so each deck's own games will be blended into its Power. No Exhibition,
Upgraded or Optimized deck, and none of the seven decks added on 2026-10-24, has been measured yet.

## Setup

1. `git fetch origin claude/deck-power-design && git checkout claude/deck-power-design`. Work and push only on this
   branch. Read `AGENTS.md`, `docs/DECK_POWER.md` (Calibration), `docs/cloud/reports/c3.md` and the calibration
   entries in `docs/LESSONS.md` (search "calibration", "C4").
2. `cd packages/ondevice-engine && bash scripts/build_jvm.sh` (Maven 3.9+ and a JDK), then
   `python3 scripts/ai_calibration.py decks` must resolve all 33 decks. Record `git rev-parse HEAD`, the upstream pin
   and the CPU count.
3. Smoke: `--games 4` of batch A into a scratch `--out` under `build/`; check the games end normally; delete it.

## Batches (skill 3 against 3, phone budget, default heap, workers and seed)

Each pool deck plays each reference (First Flight, Token Triumph, Grave Danger) with both seatings, never another
pool deck. From `packages/ondevice-engine`, with `R=$(git rev-parse --show-toplevel)`:

**A: 624 games** (13 decks × 3 references × 16): the six decks whose Power looked off and the seven new ones.

```
python3 scripts/ai_calibration.py run --skill-a 3 --skill-b 3 --against first-flight,token-triumph,grave-danger \
  --pool ai-the-ur-dragon-optimized,ai-gishath-suns-avatar-exhibition,ai-krenko-mob-boss-optimized,ai-edgar-markov-optimized,ai-lathril-blade-of-the-elves-optimized,ai-wilhelt-the-rotcleaver-optimized,ai-kaalia-of-the-vast-optimized,ai-winota-joiner-of-forces-optimized,ai-the-first-sliver-optimized,ai-miirym-sentinel-wyrm-optimized,ai-marisi-breaker-of-the-coil-exhibition,ai-kynaios-and-tiro-of-meletis-exhibition,ai-tormod-the-desecrator-core \
  --games 624 --out "$R/docs/cloud/power-results/batch-a"
```

**B: 612 games** (17 decks × 3 references × 12), after A is pushed: every other AI deck.

```
python3 scripts/ai_calibration.py run --skill-a 3 --skill-b 3 --against first-flight,token-triumph,grave-danger \
  --pool draconic-destruction,chaos-incarnate,ai-krenko-mob-boss-exhibition,ai-krenko-mob-boss-core,ai-krenko-mob-boss-upgraded,ai-gishath-suns-avatar-core,ai-gishath-suns-avatar-upgraded,ai-gishath-suns-avatar-optimized,ai-lathril-blade-of-the-elves-exhibition,ai-lathril-blade-of-the-elves-core,ai-lathril-blade-of-the-elves-upgraded,ai-edgar-markov-core,ai-edgar-markov-upgraded,ai-the-ur-dragon-core,ai-the-ur-dragon-upgraded,ai-wilhelt-the-rotcleaver-core,ai-wilhelt-the-rotcleaver-upgraded \
  --games 612 --out "$R/docs/cloud/power-results/batch-b"
```

Reruns with the same arguments resume, and harness failures (out of memory, engine-stopped) replay automatically.
If a new deck (Kaalia, Winota, The First Sliver, Miirym, Marisi, Kynaios and Tiro, Tormod) fails deck validation or
keeps failing, note it, rerun the batch without it into a new folder (`batch-a2`), keep the finished CSV, carry on.

## Progress and report

- Commit and push the CSVs at least every ~2 hours of play and after each batch (end commit messages with
  `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`). On a rejected push, `git pull --rebase` and push again.
- Write `docs/cloud/reports/power-1.md` (`STATUS: partial` until both batches end, then `STATUS: ready-for-review`),
  short and plain like c3.md: commands, engine commit, games played/ended/replayed, per deck its games, wins–losses
  and win rate (Wilson 95% CI) against each reference and overall, and its Power (`python3 scripts/ranked/deck_power.py
  table`). Paste `python3 scripts/ranked/deck_power.py check` and `ai_calibration.py summarize --by-deck <csvs>`.
  Say which decks play far from their Power (in Power points, by check's slope), whether the Core decks' results on
  today's engine agree with the older C3/C4 games, and how long games took. Separate what ran from what didn't.

Done = both batches' CSVs and power-1.md pushed to `claude/deck-power-design`.

## Rules

No runs beyond these two batches. Do not change the weights, the formula, `ai-decks.json`, app code or the engine;
another session retunes. Don't merge, open PRs, release or upload. If the engine build fails or many games fail, stop,
write what happened in power-1.md, commit and push it.
