# Lighter engine plan (October 2026)

Caleb approved this plan on 2026-10-16: make the on-device XMage engine lighter on iPhone and Android (download size,
memory and heat), measured first, changed in small tested steps, and tried by Caleb on an internal build before any
public release. It includes the GraalVM upgrade and turning simple cards into data. The Mac session owns integration
and releases; heavy runs (profiling, calibration, native builds) happen in cloud sessions or CI, never on the 8 GB Mac
(the full iOS unit suite there caused a kernel panic on 2026-10-15). Update the checkboxes and the log as work lands.

## Where the weight is (measured 2026-10-16)

From iPhone build 41 and Android build 25 (engine `160e250`), Android 24's `native_reports` build, `dyld_info`,
`llvm-readelf` and REA on the iOS executable:

| | iPhone | Android |
|---|---|---|
| Download | 162 MB IPA | 143 MB APK |
| Installed | 399 MB | about 500 MB (APK plus extracted engine) |
| Engine | about 355 MB of the 375 MB executable | 354 MB `libmmengine.so` (94 MB of the APK) |
| Engine code | about 179 MB | 182 MB |
| Engine image heap | 159 MB (`__svm_heap`, writable `__DATA`) | 160 MB (`.svm_heap`) |
| Load-time pointer fixups in the image heap | 4.5 million, 3,049 pages = 47.6 MB | 4.5 million, 12,151 pages = 47.5 MB |

- Code: card classes 110 MB (constructors 63, `copy` 26, card-specific effects 15, static setup 7), set classes 27 MB,
  JDK about 14 MB, our adapter 8.5 MB, H2 4 MB, protobuf 1 MB.
- Image heap: 68,099 classes (48 MB of `Class` objects, mostly virtual-method tables full of code pointers, which is
  what the fixups patch), 271,000 strings (about 24 MB), 46 MB in ten huge byte arrays (likely GraalVM code metadata;
  bundled resources are only 8.6 MB).
- Cards (XMage `dac400b`, 32,498 card files): 1,500 simple (keywords, stats, types only; 2.8 MB code), 22,187 composed
  from shared effects in one class (61.7 MB), 8,811 custom (20,348 classes; 46 MB with helper classes).
- Long AI games: the AI copies the whole game for every search node (about 20 ms each; step 1 measured 3 ms per copy
  and 9.5 ms per search node on the JVM). C4 measured skill-6 games peaking at 270–420 MB of Java heap and one 22-turn
  game at 2.5 GB; think time is skill × 3 s per decision.
- Not yet measured: how much of the 47.6 MB iOS keeps resident.
- First phone readings (Caleb's iPhone, TestFlight 43 Game Performance report, 2026-10-17), both games at AI skill 2:
  a 14-minute, 18-turn Quick Match peaked at 1,112 MB with 2,263 MB still available and stayed "fair"; a 7-minute,
  15-turn Ranked game peaked at 1,040 MB with 2,335 MB available and reached "serious" for 3 minutes. So the app plus
  engine uses about 1.0–1.1 GB even in short, low-skill games (memory is not near this phone's limit), and heat can
  reach "serious" in a short game, so heat comes from more than long AI searches. Still needed: long games at skill
  4–6, and the Instruments session to split the 1.1 GB into Java heap, image heap and app memory.

## How every step is checked

1. CI's real-JVM suite (rules, checkpoints, game record replays).
2. Before/after AI calibration (C3 harness, cloud): win rates unchanged within confidence; CPU time and memory per game
   reported against the old engine.
3. Size: `native_code_sizes.py`, heap report and fixup count on the new native build, against the table above.
4. An internal-only TestFlight build and an Android test APK; Caleb plays a long AI game; the per-game performance log
   compares memory peak and thermal state with the previous build. External release only after that.
5. The previous engine artifacts stay in `~/Documents/MagicMobile-releases/engines/` so a release can always fall back.

Engine changes and app features ship in separate releases (release-sequencing rule); each engine release gets one native
build per platform.

## Steps

### 1. Measure (no code changes)
- [x] Cloud: profile long, complex AI games on the JVM (async-profiler CPU and allocation, Java Flight Recorder,
      a heap dump at the peak): where game copies spend time and memory, which objects dominate. Done 2026-10-18,
      results below.
- [ ] Caleb's iPhone, about 5 minutes, plugged into the Mac: Instruments (VM Tracker, Allocations, Time Profiler,
      Energy) during a long AI game; confirms the resident cost of the image heap fixups.
- [ ] Report the findings here before step 3 is written.

#### Cloud results (2026-10-18)

**How.** Engine `160e250` built with `build_jvm.sh`, run on JDK 21 (Serial GC, 4 GB cap) in a 4-CPU cloud container,
one game and one JVM at a time. AICalibration's phone budget (skill × 3 s on an empty stack, 2 s while responding) and
seeded schedule (seed 20261015), each skill against itself on the bracket 3–4 decks, four deck pairs: Gishath U vs
Wilhelt O, Edgar O vs Ur-Dragon O, Gishath O vs Ur-Dragon O, Lathril U vs Edgar U.
- 30 profile games (10 per skill; 9–24 turns, median 15, 19 of them 15+; 40 minutes of play, 1,325 searched AI
  decisions): async-profiler 4.1, CPU every 10 ms and allocations every 512 KB, attached for the game only (it writes
  JFR files; JDK Flight Recorder itself was not needed).
- 15 memory games (4 each at skills 4 and 5, 7 at skill 6 including replays of the spike's seed; 13–30 turns, median
  16): a full GC every 2.5 s for the live heap, a class histogram at each new live peak and a heap dump at the largest,
  read with Eclipse MAT 1.16 for retained sizes.
- Tools: `packages/ondevice-engine/scripts/profile_long_games.py` (`run`, `report`, `heap`) and
  `tools/ai-calibration/LongGameProfile.java`, which watches the game from outside (no engine change). Raw profiles,
  histograms and dumps stay in `packages/ondevice-engine/build/profile-long-games/`, outside git.
- These are JVM numbers. The phone's ahead-of-time engine has no JIT compiler (30% of all CPU here, left out of
  "engine CPU" below) and is slower per operation: shares and ratios carry over, milliseconds don't. The Instruments
  session checks them on the phone.

**Headline numbers.**
- The AIs search 95% of the time, and **game copies are 50% of engine CPU and 74% of all bytes allocated**.
  Allocation runs at 490 MB per second of play; GC is 16.5% of engine CPU (AI search threads 79%, GAME thread 4.5%).
- **One copy** of the live game: 3.0 ms of CPU once compiled (4.1 ms in the first turns), 2.1–2.5 MB allocated (about
  12 KB more per permanent), 1.65–2.1 MB kept alive (median 1.9 MB). **A search node** costs 9.5 ms of CPU and
  1.6–1.8 copies at every skill. The earlier "about 20 ms each" matches a whole search node at about half this
  machine's speed, not one copy.
- **60% of every copy is the cards:** `GameImpl.gameCards`, all 208 cards in the game, both libraries and hands
  included, deep-copied with all their abilities. Ability copies are 35% of engine CPU and 62% of bytes; inside them
  `Modes` is 21% and 35%, mana costs 10% and 24%. The rest of a copy: continuous effects 10%, battlefield 9%,
  triggers 8%, watchers 5%.
- **Live heap peaks are modest:** 155–223 MB at the 2.5-second samples of the 15 memory games (median 184), against
  about 115 MB before the game. A full GC the JVM ran on its own caught one more at 318 MB, in a 2-second skill-6
  search of only 185 nodes on turn 22: the many-copies-per-node pattern of the spike below. Heap after any GC, which
  still counts dead objects in the old generation, peaked at 246–398 MB (median 316) in 29 of the 30 profile games, in
  line with C4's 270–420 MB.
- **Multi-GB spikes come from fan-out, not from search size.** One 12-turn skill-6 game reached 1,000 MB after GC
  (1,084 MB before) in one 13-second search of 552 nodes and 642 copies, while searches of 2,000+ nodes stayed under
  510 MB. In that search 65% of AI CPU was `ComputerPlayer6.resolve`, which handles a library-search (tutor) effect by
  making one full game copy per eligible library card and holding them all as children of one node until each is
  searched, here five levels deep. A full GC part-way through left 537 MB live (over 220 copies) and the heap kept
  growing; GC took 65% of all CPU in that window. Replaying the seed in memory mode did not
  repeat it (searches are time-bounded, so games diverge), so there is no heap dump of a spike.
- **Fixed engine memory, not AI:** the card catalogue (`MobileCardCatalogue`, 94,000 `CardInfo` rows and 1.6 million
  strings) is about 100 of the 115 MB before the game. Phones initialize it at run time too
  (`--initialize-at-run-time=io.magicmobile,mage`), so it is in the Java heap of every game.

**AI decisions by skill** (searched decisions only; most priorities pass without a search):

| Skill | Decisions | Wall time median | p90 | Max | ≥ 90% of think budget | Nodes median (p90) | CPU per node | CPU per decision, mean | Allocated per decision, mean |
|---|---|---|---|---|---|---|---|---|---|
| 4 | 475 | 0.42 s | 5.5 s | 12.8 s | 13% | 34 (626) | 9.4 ms | 1.46 s | 910 MB |
| 5 | 476 | 0.53 s | 3.7 s | 15.0 s | 4% | 34 (318) | 9.5 ms | 1.29 s | 776 MB |
| 6 | 374 | 0.45 s | 5.2 s | 17.9 s | 5% | 30 (388) | 9.6 ms | 1.47 s | 880 MB |

- Skill hardly changes a typical decision: the median search ends long before its budget at every skill; skill only
  raises the ceiling (skill × 3 s). Searches over 5 s are 10% of decisions and 62% of think time. One player's
  thinking in one turn: median 0.8–1.4 s, p90 11–14 s, longest 46 s (skill 4), 48 s (5), 61 s (6).
- Turn number drives the cost: allocation per decision grows from 100–260 MB in turns 1–5 to 0.9–1.5 GB from turn 11
  (4.4 GB at skill 6 in turns 16–20), copies per decision from 40–110 to 300–430. A copy grows only about 20% over a
  game, so the growth is more options on bigger boards (more nodes), not bigger copies.
- Live heap peaks grow a little with skill (skill 4: 155–180 MB, 5: 175–223, 6: 167–210) and with game length (the
  largest sample at turn 27 of a 30-turn game).
- Half the think budget while the phone is hot would cut think time, and search CPU with it (0.8–0.84 of wall time),
  by 32% at skill 4, 20% at 5 and 23% at 6, changing only the 12–19% of decisions that run long.

**Engine CPU hotspots** (inclusive, so rows overlap; 235,000 samples) and where the copies come from:

| | Engine CPU | Bytes allocated |
|---|---|---|
| All game copies (`GameImpl` copy constructor) | 49.6% | 73.6% |
| · card copies (`CardImpl` copies, nearly all from `gameCards`) | 31.6% | 56.1% |
| · game state copy (`GameState`) | 19.1% | 26.7% |
| Copies for each action tried (`ComputerPlayer6.simulatePriority`) | 24.6% | 33.4% |
| Copies to list a node's options: `SimulatedPlayer2.simulatePriority`, then `getPlayable`, then `getManaAvailable` (three per node searched) | 20.0% | 32.6% |
| Library-search fan-out (`ComputerPlayer6.resolve`) | 2.3% | 3.8% |
| Ability copies (`AbilityImpl` copy constructor, in cards, permanents and spells) | 34.5% | 62.0% |
| · `Modes` copies | 21.2% | 34.7% |
| · mana cost copies (`ManaCostsImpl`) | 10.1% | 23.8% |
| Playable calculation (`PlayerImpl.getPlayable`, with its copies) | 18.2% | 26.5% |
| Activating abilities in simulations, with mana payment (`PlayerImpl.activateAbility`) | 16.0% | 13.7% |
| Continuous effects (`GameState.applyEffects`) | 15.3% | 16.9% |
| Scoring (`GameStateEvaluator2.evaluate`) | 1.6% | 0.9% |
| State hash string (`GameState.getValue`) | 0.6% | 0.5% |
| GC (VM thread) | 16.5% | – |

**Top allocation sites** (first non-JDK frame; share of all bytes): `Modes.<init>` 11.6%, `ManaOptions.<init>` 9.2%,
`Mana.copy` 7.8%, `CardUtil.deepCopyList` 5.4%, `Modes.copy` 3.5%, `Modes.getSelectedModes` 3.3%,
`NthTargetPointer.<init>` 3.1%, `ManaCostsImpl.copy` 2.9%, `CardState.<init>` 2.4%, `AbilityImpl.<init>` 2.3%,
`CardImpl.getAbilities` 2.2%. By allocated class: `Object[]` 14%, `ArrayList` 9%, `LinkedHashMap` 9%, `Mana` 8%,
`HashMap$Node[]` 7%, `ArrayList$Itr` 6%. Each ability copy builds its `Modes` (a `LinkedHashMap` plus two more maps
and a list, calling `getSelectedModes()` twice), and each mana symbol copies its derived `ManaOptions` and `Mana`.

**Heap at the live peak.** MAT on the 13 peak dumps: 5–47 AI search copies alive (median 29), 8–90 MB in all, almost
all held by the search still running; both AIs' kept search lines 0–20 MB, of which up to 16 MB in 3 of 7 skill-6
dumps were the root alternatives our adapter records for deliberate mistakes (`CancellablePlayer.rootChoices`, kept
at every skill though only skills 1–3 make mistakes); class statics, the catalogue above all, 100 MB. Top 20 classes
at the largest peak (skill 5, turn 27 of 30, 220 MB live):

| # | Class | Instances | MB | Share | MB over the heap before the game |
|---|---|---|---|---|---|
| 1 | `byte[]` | 1,250,678 | 50.2 | 22.8% | 0.8 |
| 2 | `String` | 1,647,056 | 37.7 | 17.1% | 0.4 |
| 3 | `jdk.internal.vm.FillerElement[]` (JDK heap filler, not objects) | 6,308 | 16.1 | 7.3% | 16.1 |
| 4 | `Object[]` | 200,408 | 11.6 | 5.3% | 10.0 |
| 5 | `mage.cards.repository.CardInfo` | 93,992 | 11.5 | 5.2% | 0 |
| 6 | `mage.Mana` | 209,590 | 9.6 | 4.4% | 9.6 |
| 7 | `LinkedHashMap` | 150,273 | 9.2 | 4.2% | 9.1 |
| 8 | `HashMap$Node[]` | 103,953 | 8.3 | 3.8% | 8.2 |
| 9 | `ArrayList` | 270,356 | 6.2 | 2.8% | 6.2 |
| 10 | `mage.abilities.Modes` | 40,124 | 4.3 | 1.9% | 4.3 |
| 11 | `Class` | 37,843 | 4.2 | 1.9% | 0.1 |
| 12 | `LinkedHashMap$Entry` | 103,600 | 4.0 | 1.8% | 3.9 |
| 13 | `mage.abilities.costs.mana.ManaCostsImpl` | 95,714 | 3.7 | 1.7% | 3.6 |
| 14 | `HashMap` | 69,008 | 3.2 | 1.4% | 3.1 |
| 15 | `mage.cards.ExpansionSet$SetCardInfo` | 93,420 | 2.9 | 1.3% | 0 |
| 16 | `ConcurrentHashMap$Node` | 75,399 | 2.3 | 1.0% | 0.1 |
| 17 | `HashMap$Node` | 65,240 | 2.0 | 0.9% | 1.8 |
| 18 | `mage.abilities.costs.mana.ColoredManaCost` | 31,883 | 1.7 | 0.8% | 1.7 |
| 19 | `mage.abilities.Mode` | 41,010 | 1.6 | 0.7% | 1.6 |
| 20 | `mage.target.targetpointer.FirstTargetPointer` | 44,825 | 1.4 | 0.6% | 1.4 |

The catalogue (rows 1, 2, 5 and 15: 102 MB, 46%) is fixed. What the game and the AIs add is collections (42 MB),
`Mana` (210,000 objects) and the ability structures `Modes`, `Mode`, mana costs and target pointers (13 MB): the
same objects that dominate allocation.

**Recommendations for step 3.**
- **What a memory cap should scale with.** A search holds (game copies alive at once) × (retained size per copy). The
  size is about 1.9 MB per copy at 208 cards (roughly 9 KB per card in the game) and grows only about 20% as the board
  fills. The count does not follow nodes searched: it follows the widest fan-out under one node (a library search
  holds one copy per eligible card) and the search depth (each level keeps its best line and the branch being
  explored). So cap game copies alive, not nodes or seconds: budget = a share of available memory (iOS
  `os_proc_available_memory`, Android `ActivityManager.MemoryInfo`) after the fixed engine memory (about 115 MB of Java
  heap here), divided by the copy size measured when each decision starts (one copy of the live game, or cards in game
  × 9 KB); when a new copy would pass it, score the node as a leaf, as the search already does when time runs out. The
  largest normal peak measured held 47 copies (90 MB) and the spike over 220, so with the fan-out fix in place a cap
  of 100–150 copies (190–280 MB at today's size) should only ever stop the outliers.
- **Game-copy fixes, most promising first** (same decisions, less CPU and memory):
  1. **Copy cards on first use.** A copy shares its parent's card objects and copies a card only when the copy first
     hands it out (`getCard`, the card maps); library and hand cards a simulation never touches stay shared. Copying
     `gameCards` is 30% of engine CPU and 46% of all bytes; skipping the untouched cards saves most of that and over
     half of each copy's 1.9 MB. A patch to the already-patched `GameImpl.java`; every direct `gameCards` read has to
     go through the copying accessor, checked by comparing lazy and full copies and by the game-record replays.
  2. **Search library-search branches one at a time** in `ComputerPlayer6.resolve`: build one target's branch,
     search it, keep the best, drop the rest, instead of creating a copy per eligible card up front. The same choice,
     with memory for one branch instead of the whole library; removes the spike type above and its GC storm.
  3. **One copy to list a node's options instead of three.** `SimulatedPlayer2.simulatePriority` copies the node's
     game, `getPlayable` copies that copy, and `getManaAvailable` copies the copy's copy, each to keep its caller's
     game untouched. Sharing one listing copy saves up to 13% of engine CPU and 22% of bytes; each removed copy needs
     a check that the step after it does not change the game (the `getManaAvailable` copy guards against a
     triggers-list change), and an equivalence test of the option lists.
  4. **Cheaper ability copies.** Allocate `Modes`' duplicate-mode maps only when used, call `getSelectedModes()` once
     in its copy constructor, and share mana costs' derived options until paid. Ability copies are 35% of engine CPU
     and 62% of bytes; after fix 1 they still run for every permanent, spell and activated ability copied. Small,
     local upstream patches.
  5. **Record root alternatives only when mistakes are possible** (skills 1–3), and then only their abilities,
     combat and score, not the node with its game copy and best line. Adapter-only (`MobileAICancellation`), no change
     at skill 4 and up; up to 16 MB per expert search at the peaks measured.
- **Think time.** Searches over 5 s are 62% of think time, so a hot-phone budget (half of skill × 3 s) takes 20–32%
  off AI search CPU and leaves typical decisions untouched; calibrate its strength cost with the C3 harness.
- **Free search memory after each decision.** Each AI keeps its chosen line between decisions (`ComputerPlayer6.root`:
  the best line's nodes, each with a game copy; 0–20 MB for both AIs at the peaks, root alternatives included).
  Continuing the plan (`getNextAction`) reads only each node's abilities, combat and state hash, so the kept line can
  drop its game copies once the decision is made, and the engine `trim` request can drop the line entirely.

### 2. App release: heat and memory awareness (PR A)
- [x] Thermal state (iOS `ProcessInfo.thermalState`, Android `PowerManager` thermal status): lighter board effects
      (half frame rate) while the phone is hot. Shorter AI think time needs the engine: moved to step 3.
- [x] Free memory on memory warnings and in the background (app caches; an engine trim request moves to step 3).
- [x] Per-game performance log (memory peak, lowest headroom, hottest thermal state, memory warnings), shared from
      Diagnostics. AI think time per decision needs engine timing and moves to step 3.

### 3. Engine release: long games and safe size cuts (PR B)
- [ ] Shorter AI think time while the phone is hot, and an engine `trim` request on memory warnings (from step 2).
- [ ] AI search memory cap scaled to available memory (bounded peaks instead of multi-GB spikes); free search memory
      after each decision.
- [ ] Game-copy fixes the profile points to (less CPU per AI turn at equal strength).
- [ ] Sets from the catalogue instead of set classes (−27 MB code, −24 MB runtime heap).
- [ ] Drop H2/ORMLite JDBC, protobuf, TLS/crypto and unused locales where unreachable (about −10 MB code).
- Expected: engine about −45 MB uncompressed (iPhone download about 162 → 147 MB, Android APK about 143 → 131 MB),
  −24 MB memory at all times, no multi-GB spikes, less heat in long games.

### 4. Toolchain release: GraalVM upgrade
- [ ] Move from GraalVM 22.1 (JDK 18 static runtime) to Gluon's GraalVM build for JDK 23 (substrate 1.0.24 or later;
      GluonFX 1.0.29 is current), alone in its own engine release.
- [ ] Port our compiler patches (`packages/ondevice-engine/native/gluon/compiler-patches/`, including far calls) and
      check XMage on JDK 23.
- [ ] Build with `-Os`; use the build report and `-H:+PrintAnalysisCallTree` to find further cuts.
- Expected: about 15–25% less engine code (cumulative engine about 260–275 MB; iPhone download about 125–135 MB, Android
  APK about 118–125 MB). Watch AI speed: size-optimized code can be slower; heat must not get worse.

### 5. Engine releases: cards as data
- [ ] Proof: the 1,500 simple cards built from catalogue data by one generic card class; an automatic check compares
      every converted card's abilities, characteristics and copies with the original class.
- [ ] Composed cards in batches by effect family (damage, draw, removal, tokens, ...): a data description of shared
      effects, targets and costs, with the same per-card equivalence check and real-game replays before each batch
      ships.
- Expected when complete: about −55 MB code, about −22,000 classes, about −20 MB image heap and −15 MB of load-time
  fixups (cumulative engine about 180–200 MB, roughly half of today; iPhone download about 105–115 MB, Android APK
  about 95–105 MB; about 50–60 MB less memory at all times). Custom cards stay as code.

## Not planned
- Removing cards (any imported deck must stay playable).
- GraalVM dynamic class loading for card classes (experimental, not on iOS, slow for AI copies).
- Avoiding the load-time fixups by dropping ASLR (iOS requires it).

## Log
- 2026-10-16: measurements above; Caleb approved the plan including the GraalVM upgrade and cards as data.
- 2026-10-16: step 2's app half built in release A (PR #188); the engine-side parts moved to step 3.
- 2026-10-17: first Game Performance report from Caleb's iPhone (above).
- 2026-10-18: cloud half of step 1: 45 long AI games on the JVM at skills 4–6 (30 profiled, 15 for memory). Game
  copies are half of engine CPU and three quarters of allocation, cards 60% of each copy; live heap peaks 155–223 MB;
  multi-GB spikes come from library-search fan-out. Results and step 3 recommendations under step 1.
