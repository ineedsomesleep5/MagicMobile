STATUS: partial

# Power 2: the same decks with no AI mistakes and at skill 5

Cloud session for docs/cloud/power-skill-test.md (approved by Caleb, 2026-10-25). Branch `claude/deck-power-design`.
Measurement only: no weights, formula, `ai-decks.json`, app or engine changes; nothing merged, released or uploaded.

Batch C is complete. Batch D (skill 5) started 16:11 UTC and is running; this file is updated when it ends.

## What ran

- **Engine.** Branch HEAD `0062d807`. `engine/`, `platform/`, `tools/`, `scripts/` and `upstream.lock.json` are
  identical to power-1.md's `37226f4` (empty diff). Upstream XMage `dac400ba1380f17492c9ad6a65ab60f12f28cd97`. 4 CPUs,
  15 GB, JDK 21.0.12, Maven 3.9.11. `bash scripts/build_jvm.sh`: BUILD SUCCESS, "Adapter compilation completed".
  `ai_calibration.py decks`: exits 0, all decks resolve.
- **Settings.** Phone budget, default heap, 4 workers, default seed. Both seats always on the same settings.
- **Smoke.** 4 games of batch D (The First Sliver against Grave Danger, skill 5): all ended normally, 15–24 turns,
  35–118 s, 0 mistakes in either seat (one real draw). Deleted afterwards.
- **Batch C**, 324 games, 15:09–16:11 UTC (59 min), skill 3 with mistakes off (search depth 4, 0%):

  ```
  python3 scripts/ai_calibration.py run --skill-a 3 --skill-b 3 --mistake-a 0 --mistake-b 0 --against $REFS \
    --pool $POOL --games 324 --out "$R/docs/cloud/skill-results/batch-c"
  ```

- **Batch D**, 324 games, from 16:11 UTC, skill 5 (depth 5, 0% mistakes, expert search and combat planner):

  ```
  python3 scripts/ai_calibration.py run --skill-a 5 --skill-b 5 --against $REFS \
    --pool $POOL --games 324 --out "$R/docs/cloud/skill-results/batch-d"
  ```

`POOL` and `REFS` as in the brief. Data: `docs/cloud/skill-results/batch-c/` (and `batch-d/`), outside
`power-results/`, so `deck_power.py check` does not read them. Baseline: these nine decks' 372 games in
`power-results/batch-a` and `batch-b` (skill 3, 10% mistakes), not replayed.

## Games

| Setting | Games | Ended normally | Draws | Replayed | Mistakes per seat per game (A, B) |
|---|---|---|---|---|---|
| Baseline (skill 3, 10%) | 372 | 372 | 2 | 0 | 2.10, 2.26 |
| C (skill 3, 0%) | 324 | 324 | 2 (real) | 0 | 0, 0 |
| D (skill 5) | pending | | | | |
