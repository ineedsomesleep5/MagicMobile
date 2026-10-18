# AI-vs-AI calibration

A repeatable harness for measuring how strong each ranked AI tier plays, on the real XMage JVM engine.
It is a measurement tool, never an app path. Results back the ranked tier settings in docs/RANKED.md.

```sh
cd packages/ondevice-engine
bash scripts/build_jvm.sh                       # once per engine change
python3 scripts/ai_calibration.py decks         # resolve the ranked AI deck pools
python3 scripts/ai_calibration.py run --skill-a 2 --skill-b 6 --games 80
python3 scripts/ai_calibration.py matrix tools/ai-calibration/baseline-matrix.json
python3 scripts/ai_calibration.py summarize build/ai-calibration/results/*.csv
```

- **Decks:** the five precons from `apps/ios/MagicMobile/PreconCatalog.swift` and the 21 bracket decks in
  `apps/ios/MagicMobile/Resources/ai-decks.json` (the pools `AIDeckPool.swift` picks from), resolved against
  the compiled catalogue and checked by XMage's Commander validator when each game starts. Pools: `precon`,
  `core`, `core+precon` (default, all eleven Core decks), `upgraded`, `optimized`, or a comma-separated list
  of deck ids.
- **Pairing order:** every four games play one deck pair with both deck assignments and both seatings
  (skill A on deck X first, X second, Y first, Y second), so deck strength and going first cancel out.
- **Budgets:** `phone` (default) gives each AI the think budget it has against a person who is playing
  (`skill × 3` s on an empty stack, 2 s while responding). `watcher` is the October 2026 method: a human
  watcher seat goes through the production adapter, picks the starting AI and concedes at its first
  priority, after which the engine thinks at watching pace (every search capped at 2 s,
  `MobileAICancellation.STACK_THINK_SECS`). Watcher results therefore do not show the skill budgets a
  ranked player faces.
- **Seeds:** `--seed` (default 20261015) fixes the deck pair order and XMage's `RandomUtil` per game
  (shuffles and random choices). AI searches are time-bounded on their own thread, so a rerun agrees
  statistically, not move for move.
- **Parallelism:** one JVM per worker (`--workers`, default the CPU count), each playing games one at a
  time from a shared queue; upstream AI search state is static, so games never share a JVM. Workers
  (2560m heap each) restart every 10 games. Searches are time-bounded, so a busy machine weakens every AI equally; keep
  other heavy work off the machine during a run.
- **Limits:** a game stops as a draw after 40 turns or 1800 s (`--max-turns`, `--max-seconds`).
- **Output:** one CSV per pairing in `build/ai-calibration/results/` (game, game_seed, budget, skill_a,
  skill_b, deck_a, deck_b, first, winner, winner_skill, turns, seconds, end), appended as each game
  ends. Rerunning the same command resumes: games already in the CSV are skipped, and games that failed in
  the harness (`engine-stopped`, `jvm-exit`, for example a worker out of memory) are played again. Worker logs (XMage
  warnings) are in `build/ai-calibration/logs/`.

`AICalibration.java` sits in the adapter's package so it can build matches from the production classes
(`MobileCommanderMatch`, `MobileAICancellation` players, `DeckLoader`, `XmageEngine`) without changing them.

## Long-game profiles

`LongGameProfile.java` plays one game of the same phone budget and schedule and watches it from outside: AI search
times, game copies, heap over time and per-turn copy cost, plus async-profiler (profile mode) or live-heap sampling,
class histograms and a heap dump at the peak (memory mode). `scripts/profile_long_games.py` runs it one JVM at a time
and reports; async-profiler and Eclipse MAT are downloaded separately (`ASYNC_PROFILER_HOME`, `MAT_HOME`). Results:
docs/LIGHTER_ENGINE_PLAN.md, step 1.

```sh
python3 scripts/profile_long_games.py run --mode profile --skills 4,5,6 --games 2 --first-game 4
python3 scripts/profile_long_games.py run --mode memory --skills 6 --games 1
python3 scripts/profile_long_games.py report build/profile-long-games/profile
python3 scripts/profile_long_games.py heap build/profile-long-games/memory
```
