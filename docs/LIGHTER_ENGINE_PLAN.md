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
- Long AI games: the AI copies the whole game for every search node (about 20 ms each). C4 measured skill-6 games
  peaking at 270–420 MB of Java heap and one 22-turn game at 2.5 GB; think time is skill × 3 s per decision.
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
- [ ] Cloud: profile long, complex AI games on the JVM (async-profiler CPU and allocation, Java Flight Recorder,
      a heap dump at the peak): where game copies spend time and memory, which objects dominate.
- [ ] Caleb's iPhone, about 5 minutes, plugged into the Mac: Instruments (VM Tracker, Allocations, Time Profiler,
      Energy) during a long AI game; confirms the resident cost of the image heap fixups.
- [ ] Report the findings here before step 3 is written.

### 2. App release: heat and memory awareness (PR A)
- [x] Thermal state (iOS `ProcessInfo.thermalState`, Android `PowerManager` thermal status): lighter board effects
      (half frame rate) while the phone is hot. Shorter AI think time needs the engine: moved to step 3.
- [x] Free memory on memory warnings and in the background (app caches; an engine trim request moves to step 3).
- [x] Per-game performance log (memory peak, lowest headroom, hottest thermal state, memory warnings), shared from
      Diagnostics. AI think time per decision needs engine timing and moves to step 3.

### 3. Engine release: long games and safe size cuts (PR B)
- [ ] Shorter AI think time while the phone is hot, and an engine `trim` request on memory warnings (from step 2).
      Think time built on `claude/engine-hot-pace`: answer action `devicePace` halves each AI search's time (never
      below 2 s) while the phone is serious or critical, in unranked games the engine runs on that phone; JVM-tested
      in CI, waits for this release's native builds. `trim` waits for the profile (what to free).
- [ ] AI search memory cap scaled to available memory (bounded peaks instead of multi-GB spikes); free search memory
      after each decision.
- [ ] Game-copy fixes the profile points to (less CPU per AI turn at equal strength).
- [ ] Sets from the catalogue instead of set classes (−27 MB code, −24 MB runtime heap).
- [ ] Drop H2/ORMLite JDBC, protobuf, TLS/crypto and unused locales where unreachable (about −10 MB code).
- Expected: engine about −45 MB uncompressed (iPhone download about 162 → 147 MB, Android APK about 143 → 131 MB),
  −24 MB memory at all times, no multi-GB spikes, less heat in long games.
- Size cuts status, 2026-10-18 (draft PR #199; JVM-verified, no native build yet,
  so neither box is ticked):
  - Sets: the engine installs its sets from a bundled set catalogue (`mage/mobile/set-catalogue.tsv.gz`, 1.4 MB,
    written from the set classes at build time). 492 of the 589 set classes (5.7 of their 8.3 MB of bytecode) are no
    longer referenced; the 95 that make their own booster packs, and 2 parents, stay for Booster Tutor, created on first
    use. JVM: heap after engine start 26.5 → 4.5 MB (+5.7 MB printing index at the first deck), engine start 5.2 →
    0.15 s, 34,456 → 1,298 classes loaded. Native estimate by bytecode share: about −17 of the 27.7 MB of set code.
  - Libraries: H2 and ORMLite JDBC (reached through `mage.db.EntityManager`, which the checkpoint metadata registered),
    protobuf (`mage.game.result`) and TLS (Gluon's https handler) are cut from the native build, which now fails if they
    become reachable (measured before: H2 3.2 MB, protobuf 1.3 MB, TLS and crypto about 3.5 MB of code). Locale data
    unchanged: the engine formats with the phone's locale, so that needs a non-English device check first.
  - To measure: an Android native build with `native_reports`, then `magicmobile-native-code-sizes.yml` on it.

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
