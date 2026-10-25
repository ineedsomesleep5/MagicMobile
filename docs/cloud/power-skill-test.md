# Cloud brief: Power at a stronger AI

Start a cloud session on branch `claude/deck-power-design` with: "Follow docs/cloud/power-skill-test.md."
Caleb approved this run on 2026-10-25. Measurement only: no app, engine, deck or weights changes.

The gauntlet (docs/cloud/reports/power-1.md) played every AI deck at skill 3 against 3: search depth 4 and a 10%
chance of a deliberate mistake (`AIDifficulty.mistakePercent`; second-best play or a pass, a skipped attack, or no
blocks). Most Optimized decks played below their own Core deck, and The First Sliver played 7.5 Power points below
its rating. This run asks whether the misplays or the AI's limits cause that, or whether the formula overrates those
decks. The mistakes stay in the game (they make Bronze to Gold easier, C3); they are only switched off here.

## Setup

1. `git fetch origin claude/deck-power-design && git checkout claude/deck-power-design`. Work and push only on this
   branch. Read `AGENTS.md`, `docs/cloud/reports/power-1.md`, `docs/cloud/reports/c3.md` and the calibration entries
   in `docs/LESSONS.md` (search "calibration", "C4").
2. `cd packages/ondevice-engine && bash scripts/build_jvm.sh` (Maven 3.9+ and a JDK), then
   `python3 scripts/ai_calibration.py decks` must resolve all 33 decks. Record `git rev-parse HEAD`, the upstream pin
   and the CPU count. The engine's `engine/`, `platform/` and upstream pin must match power-1.md's (`37226f4`);
   if they differ, say so in the report.
3. Smoke: `--games 4` of batch D into a scratch `--out` under `build/`; check the games end normally and how long
   they take; delete it.

## Batches (phone budget, default heap, workers and seed)

The same nine decks in both: the four Optimized decks that played furthest below Power, the Core deck of the same
commander for three of them (The First Sliver has none), and Krenko Optimized and Core as the control (the one
commander whose Optimized deck beat its Core). Each plays First Flight, Token Triumph and Grave Danger with both
seatings, 12 games per pair, never another pool deck. Both seats always use the same settings, references included.

Write results to `docs/cloud/skill-results/`, **not** `power-results/`: `deck_power.py check` reads every CSV under
`power-results/`, and these games must not enter the Power fit. From `packages/ondevice-engine`, with
`R=$(git rev-parse --show-toplevel)` and

```
POOL=ai-the-first-sliver-optimized,ai-lathril-blade-of-the-elves-optimized,ai-lathril-blade-of-the-elves-core,ai-wilhelt-the-rotcleaver-optimized,ai-wilhelt-the-rotcleaver-core,ai-gishath-suns-avatar-optimized,ai-gishath-suns-avatar-core,ai-krenko-mob-boss-optimized,ai-krenko-mob-boss-core
REFS=first-flight,token-triumph,grave-danger
```

**C: 324 games** (9 × 3 × 12), skill 3 with no deliberate mistakes:

```
python3 scripts/ai_calibration.py run --skill-a 3 --skill-b 3 --mistake-a 0 --mistake-b 0 --against $REFS \
  --pool $POOL --games 324 --out "$R/docs/cloud/skill-results/batch-c"
```

**D: 324 games**, after C is pushed: skill 5 (depth 5, no mistakes, the expert search and combat planner).

```
python3 scripts/ai_calibration.py run --skill-a 5 --skill-b 5 --against $REFS \
  --pool $POOL --games 324 --out "$R/docs/cloud/skill-results/batch-d"
```

The baseline is these nine decks' games in `docs/cloud/power-results/batch-a` and `batch-b` (skill 3 with
mistakes); do not replay it. Reruns with the same arguments resume, and harness failures replay automatically.
Skill 5 thinks longer, so D may take several times as long as C. If D's games mostly hit the 30-minute time limit,
stop D, keep what finished, and say so.

## Progress and report

- Commit and push the CSVs at least every ~2 hours of play and after each batch (end commit messages with
  `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`). On a rejected push, `git pull --rebase` and push again.
- Write `docs/cloud/reports/power-2.md` (`STATUS: partial` until both batches end, then `STATUS: ready-for-review`),
  short and plain like power-1.md: commands, engine commit, games played/ended/replayed, and mistakes per seat per
  game (the CSV's `mistakes_a`/`mistakes_b`; C and D should show 0).
- For each of the nine decks, a row with its Power and its win rate against the three references (wins–losses,
  Wilson 95% CI) under each setting: baseline, C and D.
- For Lathril, Wilhelt, Gishath and Krenko, Optimized minus Core under each setting, with a 95% interval, and the
  first three pooled. Say whether the Optimized decks catch up with Core when the misplays go (C) and at the stronger
  AI (D), and whether The First Sliver moves.
- Answer plainly which it looks like: the misplays, the AI's limits, or the formula overrating these decks. Say what
  the data cannot tell (AI against AI only, 36 games per deck per setting). Paste
  `ai_calibration.py summarize --by-deck` for each batch. Report game times per batch. Separate what ran from what
  didn't.

Done = both batches' CSVs and power-2.md pushed to `claude/deck-power-design`.

## Rules

No runs beyond these two batches. Do not change the weights, the formula, `ai-decks.json`, app code or the engine,
and do not put these CSVs under `power-results/`; another session retunes. Don't merge, open PRs, release or
upload. If the engine build fails or many games fail, stop, write what happened in power-2.md, commit and push it.
