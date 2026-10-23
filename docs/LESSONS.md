# Lessons log

Fixes and gotchas worth knowing before you start. Every agent (Claude, Codex) reads this at the start
of a task and adds an entry before handing back whenever it fixed something non-obvious, lost time to
a trap, or learned how a tool or service really behaves.

Write an entry for what the next agent would otherwise rediscover. Skip what the code, a commit
message or another doc already makes plain. Link to that doc instead.

## How to add an entry

Newest first, under the right heading. Keep each one to a few lines:

```
- YYYY-MM-DD (who): What went wrong or surprised you. **Fix / rule:** what to do instead.
  Where: file paths, PR or workflow run.
```

If an entry turns out to be wrong or stale, correct it in place and add the date. Don't append a
contradicting one.

## Style and Android parity

- 2026-10-22 (Claude, Android Arena menus phase B): three traps. (1) A screen moved inside the menu shell's page box sits
  under the top bar, so a full-screen cover drawn from it (Deck Studio's editor) ends up below the bar: the shell steps aside
  while the cover is open (`DeckStudioRootView(covered =)` sets `decksCovered`, which drops the top padding and hides
  `ArenaTopBar`). (2) `LocalArenaMenuBackdrop` carries into Dialogs and in-place overlays, so `PublicProfileScreen` drew no
  backdrop and showed the page under it; it sets the local false for itself. (3) In an isolated agent worktree the guard
  refuses heredoc Python, `sed -f` and `xargs` git calls; save the script in the scratchpad and run `python3 -I script.py
  <file>`. Also: the Mac's disk filled (ENOSPC) while three agent worktrees built at once; check `df -h` before parallel
  Gradle work. Where: `apps/android/app/src/main/java/io/magicmobile/android/ondevice/OnDeviceRootView.kt`, `ranked/`.

- 2026-10-22 (Claude, Android Arena menus): an agent worktree cut from `main` lacked the newest iOS Arena sources
  (orange `ArenaButtonFace`, the sans/serif `font()` mix, the `home-art-*` sets), which lived only on `claude/arena-mode`.
  **Rule:** before porting an iOS screen, check `git log --all -- <iOS file>` for a newer commit and merge it, so the port
  and `prepareBrandAssets` see the same files. In Compose, `runCatching { ImageBitmap.imageResource(id) }` does not
  compile (a try/catch around a composable call); resolve drawables through `R` so a missing one fails the build instead.
  Where: `apps/android/app/src/main/java/io/magicmobile/android/menus/`.

- 2026-10-20 (Claude, Arena mode): a pitched Blender camera (`tavern_table.py --pitch`) draws the far half of the mat
  narrower and its true centre above its visual middle. Cards placed on the canvas edge spilled onto the frame at the
  opponent's land row, and the compass sat about 50 pt high. **Rule:** measure the rendered plate (sample brightness
  rows with `magick … -crop Wx1+0+y txt:-` to find the mat's inner edge per row) before setting lanes. Move the emblem
  with `--emblem-y`. Render a portrait mat wider than the screen when the far rows need its full width
  (`arena_layout.json` portrait mat −16…456). Also: `print -r` writes `\n` literally in zsh. An asset
  `Contents.json` written that way breaks actool ("failed to read asset tags") with no file named; use real newlines
  as `install_tavern_assets.sh` does.
- 2026-10-20 (Claude): the hidden-card image `https://gatherer.wizards.com/Images/CardBack.jpg` answers 404 since
  Gatherer's redesign, so every face-down card fell back to its placeholder. **Fix:** Scryfall's card back
  (`backs.scryfall.io/large/0/a/0aeebaf5-….jpg`) in `CardImageURL.image("Hidden card")`; the Arena board caches it once in
  Caches (`ArenaCardBackArt`, only with the artwork consent). Where: `Board/CardImageURL.swift`, `Board/ArenaBoardViews.swift`.

- 2026-10-11 (Claude): the guided first game's coach (`GuidedGame.swift` / `GuidedGame.kt`) reads only
  the snapshot (prompt envelope, legal action types, stack, turn), not the board's interaction
  state, so it stays inside the SwiftPM package and the JVM core and both run the same
  `guided-game-cases.json`. **Rule:** a new coach note gets a case there first; a snapshot case is a
  patch over `base`.
- 2026-10-11 (Claude): the battlefield picker is gone; Walnut Tavern is the only table. At launch both
  apps delete the saved `magicmobile.boardAppearance`, so players stuck on an old skin return to the
  tavern. **Rule:** UI tests that need another board still pin it with the
  `-magicmobile.boardAppearance arena` launch argument (iOS argument domain, untouched by the reset)
  or `MAGICMOBILE_UI_TEST_BOARD_APPEARANCE` (set after the reset). Where: `MagicMobileApp.swift`,
  Android `MainActivity.kt`. Updated 2026-10-14 (Claude): the other boards' textures are gone; `arena`
  (the classic layout on a plain gradient) is the only other value, and anything else resolves to the
  tavern.
- 2026-10-11 (Claude): Android screens drift back to plain Material, `IosAlert` or `IosListRow`
  when a port reaches for whatever control is handy. **Rule:** follow `docs/TAVERN_STYLE.md` and use
  the `Tavern*` counterpart of the iOS piece; port the piece into `ui/TavernKit.kt` first if it is
  missing.
- Undated (recorded in `DESIGN.md`, Components): the menu and the board used two
  slightly different golds because `MagicPalette` kept its own copy. **Rule:** new code takes colours
  from `GameBoardTheme.current` / `TavernPalette` / `BrandTheme`, never a fresh literal.
- 2026-10-03 (Claude): parity golden entries for a new adapter case can be written by hand in the
  iOS format, but only count once regenerating on iOS gives no diff:
  `MAGICMOBILE_WRITE_PARITY_GOLDENS=1 swift test --package-path apps/ios --filter ParityGoldenTests`.
- 2026-09-24 (Claude): Apple's fonts can't ship on Android. Inter, Source Serif 4 and Nunito stand
  in, with widths fitted by `AppleFontMetrics`. Small wrap differences against iOS are expected; a
  layout that only fits with SF metrics isn't.

- 2026-10-11 (Claude): the held card inspector can't take taps: `inspectionTouchPassthrough()` turns hit
  testing off while a finger holds the card, so a button on it only works when the inspector was opened
  explicitly. **Rule:** anything a held inspector must show without a tap happens by itself (the double-faced
  flip turns after 1.4 s); give opened inspectors a real button as well. Where: `Board/CardInspector.swift`,
  `board/InspectorViews.kt`.

## Gameplay

- 2026-10-19 (Claude, audio): AVAudioPlayer takes up to ~50 ms to start the first time, and making a player per
  play cost ~40 ms, so a card slam and its colour layer (since retired) started as a smeared flam. **Rule:** sounds meant to land
  together go through `GameAudio.playTogether` (one `play(atTime:)` on the device clock, set `lead` ahead), players are
  reused when idle, and `GameAudio.boardSounds` are preloaded when a game appears (`preload` existed on both
  platforms but was never called; Android's SoundPool skipped a first play still decoding). `simctl io recordVideo`
  records no audio: run a preview with `MAGICMOBILE_LOG_SOUNDS=1` and give the recording its soundtrack with
  `scripts/audio/demo_soundtrack.py`; pass `--rec-start` (the recorder's launch), since steps ~3 s apart otherwise sync
  one step off, and the turn banner crosses the step label. Where: GameAudio.swift/.kt, BoardFXOverlay, demo_soundtrack.py.
- 2026-10-19 (Claude, audio): pedalboard's `PitchShift` smears very short foley grains (under ~100 ms) into a faint
  tonal ring (seen as horizontal lines at 4-6 kHz in the spectrogram). **Rule:** to lower a recording's pitch, slow it
  down tape-style (`scipy.signal.resample_poly`), which also lengthens it naturally; keep pedalboard for EQ, compression
  and reverb. Kenney packs are Ogg, which afconvert cannot read: convert them with ffmpeg. Claude cannot listen, so check
  every render with `showspectrumpic`/`showwavespic` and a short-term loudness envelope before sending it to Caleb.
  A new cue's file is listed one by one in the Xcode project: after adding it to Resources/Audio, regenerate the
  project (`xcodegen generate --spec native-engine.yml …`) or it builds without it (GameAudioTests would catch it);
  Android stages the folder by itself.
  Where: scripts/audio/build_game_audio.py (`slowed`, `tavern_room`, `r_steal`), trials.py, SOURCES.md.
- 2026-10-19 (Claude): The dice table's recorded throws (`scripts/brand/d20.py --mode throws`) are tuned offline; the
  apps only play them. To change how a throw feels, change `START_DISTANCE`/`REST_SPOT`/`RAIL_KISS`/`PROFILES` and the
  picker, and check them with a quick harness that runs `simulate` and `throw_is_good` under Blender's bundled Python
  (`/Applications/Blender.app/Contents/Resources/5.2/python/bin/python3.13`; Homebrew's python3 has no numpy) before a
  Blender run. The resting face does not matter (the apps turn the die by a symmetry), and every throw must still touch
  the rail: `railTime` is required on both platforms and BoardPolishUITests expects "Rebounded from screen edge".
  Where: d20.py, `D20TableLayout` (`throwDepth` 11.5, 34–50 points per radius) in StartingRollDice.swift/.kt.
- 2026-10-19 (Claude): Ranked AI games used the shared "Who goes first?" preference (default "choose", and the
  Ranked lobby has no picker), so a ranked game asked the player to pick the starter instead of rolling the D20.
  **Rule:** a game's starting mode comes from `PlayMode.startingPlayerMode(preference:)` (Ranked always "roll"), not
  the raw preference, and resuming a ranked game never writes its "roll" back into the player's choice.
  Where: `OnDeviceRootView.swift`/`.kt` (`startingPlayerMode`), `PlayerRecord.swift`, `Ranked.kt`.
- 2026-10-15 (Claude, C1): `mm_record_game` now stores the server's standing at the moment a ranked game arrives
  (`20261015180000_ranked_record_points.sql`), but both apps upload a game as soon as it is recorded, racing
  `syncRank`, and `afterRefresh` uploads before it seeds. **Rule:** for ranked games, run `syncRank` first and upload
  after, or the rank history charts the points from before the game. A ladder floor can read only the current points:
  you can't fall out of a tier, so "start of your tier" equals "highest tier reached", and a stored peak can sit above
  the points (imported or seeded standings). Ladder SQL waiting for Caleb lives in `supabase/pending/`, outside
  `migrations/`, and is tested with `npm run test:ranked-pending --prefix supabase/tests`. Where: `docs/cloud/reports/c1.md`.

- 2026-10-11 (Claude): Arena-style smart auto-pass and phase stops needed no engine change. The poll
  already carries XMage's own playable list (`gameView.canPlayObjects`, with `manaAbility` marks) and
  the step, so the session sends the same `pass_priority` a tap sends. **Rule:** client-side pass
  scheduling belongs in `OnDeviceSmartPass` (iOS `OnDeviceYieldPolicy.swift`, Android core
  `game/OnDeviceSmartPass.kt`); an engine edit means a native rebuild on both platforms.
- 2026-10-11 (Claude): the Android app CI job runs `:core:contractChecks` but never the `:core:test`
  JUnit task, so a new core JUnit class only compiles there. **Rule:** call new core checks from
  `ContractChecks.kt`'s `main` so CI executes them.

## Performance

- 2026-10-18 (Claude): Instruments on Caleb's iPhone showed the board redrawing 30–60 times a second with nothing
  happening. Each glow's `TimelineView(.animation(minimumInterval: 1/30))` started on its own phase, so a few 30 Hz glows
  (plus the inspector's foil) drove SwiftUI at 60 Hz, and the AI thinking ring's `repeatForever` animation redrew every
  frame. Every update re-walks the whole board's display list (shadowed shapes even rebuild their shadow paths), so the
  cost follows the board's size, not the glow's; the app's own code barely shows in the samples. **Rule:** ambient
  timelines use `AmbientTimelineSchedule` (one grid, heat-aware, paused when `BoardActivity` says idle); a spinner that
  turns forever runs in Core Animation (`OrbitingArcView`). To name a ticker, export the time profile and run
  `scripts/ios/time_profile_summary.py`: gaps of 33.3 ms between display-link updates mean one 30 Hz timeline, 16.7 ms
  mean 60 Hz. Separately, `JSONValue.init(from:)` probes types with `try?`, and building those errors' coding paths was a
  quarter of the polling thread: skip decoding repeated replies (`OnDevicePollReader`) rather than editing the engine
  package's decoder, which ships with the engine.
- 2026-10-03 (Claude): a quiet Android tavern board used about 105% CPU on the emulator because
  breathing glows redrew every frame. **Fix:** one shared 20 Hz clock (`rememberBoardBreath` in
  `board/BoardSupport.kt`), read at draw time; it now uses about 45% CPU, and 0.6% with
  animations off. Any new ambient animation should use that clock, not its own
  per-frame animation.

## Website

- 2026-10-11 (Claude): the donation link lives in one place, the tip button on the site's support page
  (`apps/site/public/support/index.html`). Both apps' support links (main menu, Settings, Updates) and
  the home page open `https://magicmobile-downloads.vercel.app/support/`, so swapping the provider is a
  one-line site change that needs no app build. **Rule:** never link the apps straight to a payment or
  donation provider (Caleb, 2026-10-11, to keep iOS review safe); link our support page. Where:
  `NativeUpdateNewsView.swift` (`SupportProject`), Android `ondevice/SupportViews.kt`.
- 2026-10-11 (Claude): `pkill -f "vite preview"` inside a Bash call also matches that call's own shell
  and kills it (exit 144). **Rule:** stop a preview server by port or PID, or just start the next one on
  a new port. Same for calibration workers (C4, 2026-10-15): anchor the pattern, e.g.
  `pgrep -f '^java .*AICalibration'`.

## Native engine and releases

- 2026-10-18 (Claude, release C out-of-memory): interrupting an AI search, upstream's only stop signal
  (`FutureTask.cancel(true)` at the timeout), does not stop code that never checks the flag. `SimulatedPlayer2.triggerAbility`
  makes a full deep game copy for every option of a trigger, and Loaming Shaman (Draconic Destruction) targets "any number"
  of graveyard cards: up to about 4,000 options (upstream's limit is 4 of 18 cards). A timed-out search kept copying while
  the AI's next search ran beside it, 1.9 GB in one node's children. Those copies also hang under a node the tree does not
  reach yet (`simulatePriority` handles triggers before it attaches the new node), so #202's copy count never saw them.
  **Rule:** stop searches at their game copies (`AISearchMemory.Stopped`), count the node being copied, and take a live
  heap dump before tuning budgets (MAT's leak suspects named the thread and the node). An out-of-memory error on a search
  thread is swallowed by its cancelled task (calibration only shows `engine-stopped`); `-XX:OnOutOfMemoryError=touch <file>`
  marks it. A watcher that flags search threads busy while the GAME thread is idle misses an orphan that overlaps the next
  search: count busy search threads instead. Where: `AISearchMemory.java`, `RealSearchMemoryTests` (`trigger-fan-out`).
- 2026-10-18 (Claude, release C AI memory): sharing card objects between game copies (`GameImpl`
  `MOBILE_LAZY_CARDS`) is exact only while a source is not changed again while a copy that shares its cards is alive.
  The AI's search sources are frozen once copied, or their copies are dropped before the source goes on, except
  `SimulatedPlayer2.triggerAbility`, which copies the game for each trigger option in the middle of
  `checkStateAndTriggered` and lets rules processing go on; copies made while a trigger is handled stay deep. Copies
  of the live game are always deep, so a late search thread never shares objects with it. **Rule:** a new game copy
  in AI code needs a frozen source or a copy that dies first; check it with `RealSearchMemoryTests` and
  `profile_long_games.py equivalence` (the switches `GameImpl.mobileLazyCards`, `ComputerPlayer6.mobileSearchMemory`).
- 2026-10-18 (Claude, release C AI memory): the engine ships no log4j configuration, so reload4j's root logger is
  DEBUG with no appender: on phones every `isInfoEnabled()`/`isDebugEnabled()` block runs and its output is dropped
  (in `ComputerPlayer6`, a score for every step of each root action's line, a board printout at each priority). The
  calibration and profile tools set WARN (`tools/ai-calibration/log4j.properties`), so their CPU numbers leave that out.
  Not changed yet. Also: memory readings in engine code avoid `java.lang.management`, which would make JMX reachable in
  the native image; `DeviceMemory` uses `os_proc_available_memory` (iOS), `/proc/meminfo` and a JVM property.
- 2026-10-18 (Claude, release C size cuts): GraalVM 22.1 compiles the static initializer of every reachable class
  that initializes at run time (`DynamicHubInitializer.buildRuntimeInitializationInfo`), and registering a class for
  checkpoint serialization or reflection makes it reachable. That kept all 589 set classes with their card lists in the
  image, and `mage.db.EntityManager` (a Serializable enum whose initializer opens H2 through ORMLite JDBC) pulled in H2.
  **Rule:** packages that are never game state stay out of the checkpoint list (`NOT_CHECKPOINTED` in
  `NativeReflectionExporter`); read the pinned toolchain's own sources (`lib/svm/builder/svm.src.zip` in the Gluon
  archive `scripts/android/prepare_toolchain.py` downloads) rather than guessing what makes code reachable. Gluon always
  adds `-H:EnableURLProtocols=http,https` (`allowHttps()` returns true); `-H:DisableURLProtocols` overrides it.
- 2026-10-18 (Claude): the JVM verifier loads every class a method returns where a supertype is expected, so a
  generated `switch` of `return X.getInstance();` loaded all 95 listed set classes the first time the engine started.
  **Fix:** `return (ExpansionSet)(Object)X.getInstance();` checks at run time instead (`GeneratedBoosterSets`).
  `test_real_engine.sh` fails if a game loads any `mage.sets` class. Also for memory readings: the test decks that
  `resolve_deck.py` builds use some Arena-only printings (AKR, ANB, HA4), so XMage's Commander validator falls back to
  `CardRepository.findCards(name)` and loads the whole card-metadata catalogue (about 87 MB of JVM heap); app decks only
  use eternal-legal printings. Measure with `build/isamaru.json`, or say which deck you used.
- 2026-10-18 (Claude, lighter engine step 1): JVM memory traps in the long-game profiles. `GcInfo` before/after usage
  covers every memory pool, Metaspace included (the card classes), so summing it read 550 MB "after GC" while the live
  heap was 147 MB; heap after a Serial GC also counts dead objects in the old generation. The card catalogue (about
  100 MB) loads on the first deck validation, so a baseline taken before `DeckLoader.load` is 27 MB, not 115. And
  AICalibration's schedule plays one deck pair per block of 4 games, so a 4-game run covers one pair. **Rule:** sum only
  `MemoryType.HEAP` pools, measure live heap with a full GC (or a heap dump), take baselines after loading the decks,
  and spread runs with `--first-game 0, 4, 8, ...`. async-profiler 4.1 (GitHub release; CPU mode works at
  `perf_event_paranoid` 2) and Eclipse MAT (download.eclipse.org) both run in the cloud container.
  Where: `scripts/profile_long_games.py`, docs/LIGHTER_ENGINE_PLAN.md step 1.

- 2026-10-15 (Claude, C4): XMage's AI search is limited by time, not by its 5000-node cap. Calibration
  searches use a median of 12–18 nodes (90th percentile about 600); each node copies the whole Commander
  game, about 20 ms. Attacks and blocks are fixed rules in `ComputerPlayer6` and never searched. **Rule:**
  more depth or nodes buys nothing; strengthen the AI in its decisions (`CombatPlanner`, `AIDifficulty.expert`).
  Where: docs/cloud/reports/c4.md.
- 2026-10-15 (Claude, C4): C3's calibration harness built `AIDifficulty` itself by reflection, so a new
  per-skill setting silently never reached calibration seats and a first run measured the old AI. **Rule:**
  calibration seats go through `XmageEngine.aiDifficulty`, the production seat parser.
  Where: `tools/ai-calibration/AICalibration.java`.
- 2026-10-15 (Claude, C4): GraalVM 22.1 has no `--emit build-report`, and Gluon's cross-compiles
  (`-H:+ExitAfterRelocatableImageWrite`) stop before the "Top 10" size table prints. The cloud container
  also can't download Actions artifacts (the blob host is refused). **Rule:** break code down with
  `magicmobile-native-code-sizes.yml` (symbols artifact, runs in Actions, about a minute); for the heap,
  dispatch the Android build with `native_reports`. Where: docs/cloud/engine-size.md.
- 2026-10-15 (Claude, C5): a seeded `RandomUtil` alone does not make an XMage game repeat. Libraries are
  filled from `Deck.getMaindeckCards()` (a `HashSet` in identity-hash order) before the opening shuffle;
  "in a random order" library placement uses `Collections.shuffle`'s own generator; AI reasoning draws
  from the same generator on the GAME thread; and a commander cast from the command zone uses the
  command object's copy of the spell ability (same ID as the card's, but with commander tax). Name
  checks also hide instance differences: test decks of 99 identical basics compare equal by name.
  **Rule:** compare card instances (the record's `c<n>` names), not names; when a replay diverges, run
  `RealGameRecordTests` with `-Dmagicmobile.recordOnly=<scenario>` and diff the per-entry traces it
  writes. Where: `GameRandom.java`, `GameRecorder.java`, `XmageEngine.build`, docs/cloud/game-record.md.
- 2026-10-15 (Claude, C5): a game replay that matched inside the recording JVM failed in a fresh one
  (simultaneous tokens enter in identity-hash order), and an exception in replay code inside an AI's
  `priority()` vanished: `GameImpl.playPriority` catches `Exception`, rolls back and asks again, which
  looked like an unrelated mismatch two entries later. **Rule:** verify replays in a fresh JVM
  (`GameReplay` command line); turn any replay-side exception into `GameRecorder.Stop` (an `Error`),
  never let it reach XMage's error recovery. A human's UUID answer is often not an object at all (a
  mode, or a triggered ability to order): name it by its place in the question's options first.
- 2026-10-15 (Claude, C5): `RealControlPrivacyTests` builds `XmageEngine.Running` by reflection with its
  exact constructor signature, so a new `Running` parameter compiles everywhere and then fails ten
  checks at run time with `NoSuchMethodException`. **Rule:** when `Running`'s constructor changes,
  update that rig too, and run `test_real_engine.sh`, not just the suite you touched.

- 2026-10-15 (Claude, C2): RELR packing needs Android API 28 only with lld's
  `--use-android-relr-tags` (`android+relr`); `-z pack-relative-relocs` uses the official tags and needs
  API 30. Packing only shrinks the table: bionic still applies all 4.5 M `libmmengine.so` relocations.
  GraalVM 22.1 has no option to remove them (`-H:+RelativeCodePointers` arrives in GraalVM 25).
  **Rule:** keep `--pack-dyn-relocs=android` at minSdk 26; measure before changing anything.
  Where: docs/cloud/c2-relocations.md.
- 2026-10-14 (Claude): build 38's privacy manifest declared only UserDefaults, but the executable also
  calls file-timestamp, boot-time and disk-space APIs, some from Swift (`systemUptime`,
  `contentModificationDate`, `systemFreeSize`) and some from the engine's static JDK libraries (`stat`,
  `fstat`, `lstat`, `fstatfs`, `fstatvfs`, `mach_absolute_time`). App Store Connect refuses that at App
  Store submission, though TestFlight let it through. **Rule:** `PrivacyManifestTests` (#155) scans the
  Swift sources only. After an engine update, check the executable's imports (REA `inspect_macho`, or
  `nm -u`) against `PrivacyInfo.xcprivacy`. Where: docs/audits/APP_AUDIT_2026-10.md.
- 2026-10-11 (Claude): a game froze at combat damage when trample killed the planeswalker being
  attacked. XMage then keeps the attackers in combat with a null `defenderId` (rule 506.4,
  `PlayerImpl.removeFromBattlefield` → `Combat.removeDefendingPermanentFromCombat`; phasing out and
  control changes do the same), and both snapshot adapters threw "Missing combat defender" on every
  poll. **Rule:** a missing field the rules allow is state, not corruption; the adapters now emit
  `defenderKind: "none"`. Before rejecting engine data, check upstream for when it can be null.
- 2026-10-15 (Claude, C2): upstream MAD depth counts one unit per action and scores the last unit
  before that action resolves, so at depth 1 the AI judges a spell while it is still on the stack and
  never casts anything; depth 2 is the shallowest useful search (one action seen resolved).
  **Rule:** N plies of lookahead is depth N+1. AI board fixtures must also call
  `game.getPlayerList().setCurrent(aiId)`: the search simulates whoever that cursor points at, and
  otherwise about half the runs search the human's priority and only ever see Pass.
  Where: `AIDifficulty.java`, `RealAIDifficultyTests.java`.
- 2026-10-11 (Claude): XMage AI skill sets search depth `max(4, skill)` and think time `skill × 3` s,
  so skills 1–4 play at the same depth. Tune difficulty with decks first (docs/RANKED.md).
  Corrected 2026-10-15 (Claude, C2): engine release A gives skills 1 and 2 depth 2 and 3 and adds
  seeded mistakes at skills 1–3 (`AIDifficulty.java`); skill 4 and up still use upstream's depth.
- 2026-09-27 (Claude): `verify_native.py` compares the whole engine package, including the iOS-only
  Swift wrapper, so Android build 10 had to ship with the package restored to the native library's
  source commit (`2c32482`). **Rule:** when the Android native library and the package source
  disagree, restore the package to the library's commit rather than rebuilding.

## Agent environment

- 2026-10-14 (Claude): REA on our own builds: `inspect_binary_layout` handles only Linux x86-64 ELF, and
  `decode_android_resources` / `inspect_android_package` need apktool or JADX, which aren't installed. For
  the arm64 engine use REA `inspect_with_objdump` (section headers) and the NDK's `llvm-readelf`
  (`/opt/homebrew/share/android-commandlinetools/ndk/*/toolchains/llvm/prebuilt/darwin-x86_64/bin`).
  For the manifest use build-tools `aapt2 dump xmltree|badging`; `aapt2 dump resources` maps a release
  APK's shortened `res/xx.webp` names back to drawables. Separately, `rg` in Claude's Bash is a shell
  function, so a `zsh script.sh` that calls it finds nothing, and with `2>/dev/null` it prints no error
  either. **Rule:** scripts use `grep` (or a real binary path), and get checked against a known hit first.
- 2026-10-14 (Claude): Cormorant's old-style figures are on by default in both the SC and Garamond
  files, so "1v1" reads "ivi" unless `lnum` is set (`UIFontDescriptor` feature settings on iOS,
  `fontFeatureSettings = "lnum"` in Compose). Its x-height is 0.386 em against about 0.475 for New
  York and Source Serif, which is why it is display-only. Bundled fonts in `Resources/Fonts` need a
  `UIAppFonts` entry in `Info.plist` plus pbxproj entries (CI and the TestFlight script regenerate the
  project with xcodegen, which picks the folder up anyway).
- 2026-10-12 (Claude): `OnDeviceRootView.presentedContent` is one very long SwiftUI modifier chain; adding
  two sheets tipped Xcode 27 into "unable to type-check this expression in reasonable time" (reported
  at an unrelated line near the end). **Fix:** the chain is split into `let` stages, and long `||`
  conditions live in computed properties (`menuSheetOpen`). Add new sheets in a helper such as
  `learningSheets(_:)` rather than lengthening the chain. After the split, the same sheets failed with
  "failed to produce diagnostic for expression" (a compiler crash, so it names no cause). Inside a sheet,
  pass plain closures that call named methods, and build the sheet's view in a typed computed property.
  Don't use multi-statement closures, `Task` blocks, ternaries that mix `nil` with a method reference, or
  bare method references (`skip: someMethod`). No Swift toolchain is installed in the cloud container,
  so CI is the only check.
- 2026-10-11 (Claude): the iOS CI `swift` job fails when any expression under `apps/ios/MagicMobile/Board/`
  takes over 200 ms to type-check, even after the build and tests pass. Wrapping a view in a Button inside
  the tavern bar's big ZStack, or a long settings body with ternaries, is enough to trip it. Cloud threads
  can't download the job's artifact that names the slow lines. **Rule:** keep new Board views small,
  as separate structs or helper functions with explicit types, rather than adding to a large closure.
- 2026-10-11 (Claude): a new iOS source file needs three registrations: `apps/ios/Package.swift`
  (`sources` of the target or test target, unless its folder is excluded, like `Board/`) and four
  entries in the committed `MagicMobileiOS.xcodeproj/project.pbxproj` (build file, file reference,
  group child, Sources phase). Copy a neighbour's entries with fresh 24-hex IDs.
  Corrected 2026-10-14 (Claude): hand-added entries build, but release preflight's `generated-project`
  check compares the pbxproj with XcodeGen output, and build 37's preflight failed on the entries from
  #138–#145. On a Mac, run `xcodegen generate --spec native-engine.yml --project . --project-root .
  --no-env --quiet` in `apps/ios` and commit the result. From the cloud (no xcodegen), hand-add the
  entries and expect the release to regenerate the project.
- 2026-10-11 (Claude): cloud containers can't reach dl.google.com, so `gradle` in `apps/android`
  fails on the Android plugin. The JVM-only `:core` tests still run from a throwaway root two levels under the repo (the
  parity tests read `../..`, e.g. `apps/zz-coreonly/`) that includes only `../android/core` with the Kotlin plugins and `jvmToolchain(21)` (the container has
  JDK 21, not 17). Maven Central answers 429 in bursts; retry with `--max-workers=1`. The app module
  only compiles in the `magicmobile-android-app.yml` PR check (or on Caleb's Mac).
- 2026-10-11 (Claude): cloud threads ignore `defaultMode: bypassPermissions` / `dontAsk` in settings
  files, and run in auto mode. Commands every thread may run without a prompt go in
  `permissions.allow` in `.claude/settings.json`; cloud threads apply it only while the project has
  a single repository.
- 2026-10-13 (Claude): to see the online turn timer on a real board without an online match, launch a
  Debug simulator build with `SIMCTL_CHILD_MAGICMOBILE_DESIGN_PREVIEW=normal-battlefield
  SIMCTL_CHILD_MAGICMOBILE_PREVIEW_TURN_ROPE=you|opponent|strike` (loops a 24 s cycle). The first
  rope design centred on the whole screen and covered the bottom creature row, so it became a ring
  on the pass button (yours) and on the opponent's medallion (theirs). A view that reads an
  `ObservableObject` it doesn't observe (TavernMedallion looking up the seat in `TurnClockFeed`)
  never refreshes when that object changes; resolve such lookups inside the observing view.
  Cloud containers can't reach Scryfall, so real card art only shows in a simulator or device run.
  On Android the ring's `LocalTurnClock` holds lambdas that read the table's state, not the values,
  so a clock tick recomposes only the rings instead of the whole board under the provider. Cloud
  containers have no Android SDK; the PR's Android app CI job is the compile check.
- 2026-10-15 (Claude, R2): `Data.write(options: .completeFileProtection)` passed in the iOS simulator tests but
  failed in preflight's `presentation-contracts`, which runs `apps/ios/Package.swift` tests on macOS, where file
  protection isn't supported and the write throws. CI's `swift` job didn't catch it. **Rule:** guard iOS-only write
  options with `#if os(iOS)`, and run `swift test --package-path apps/ios` (or preflight `ios-fast`) after
  touching code the package compiles. Where: `PlayerRecordStore.keepGameRecord`.
- 2026-10-15 (Claude): a test added to `BoardEventTimelineTests.swift` that used `BattlefieldRow` passed in the Xcode
  test target but broke CI's `swift` job, because `apps/ios/Package.swift` compiles that test file without the `Board/`
  views. **Rule:** tests of board views go in a file the package excludes (`PortraitPolishTests.swift`), and run
  `swift test --package-path apps/ios` (macOS, no simulator, ~1 min) before pushing iOS test changes.
- 2026-10-16 (Claude, release A): after Xcode updated itself to 27.1, local `xcodebuild` failed with "missing Metal
  Toolchain" and "CoreSimulator is out of date" (simulator support disabled), although `xcodebuild -showComponent
  MetalToolchain` still listed the 27.0 toolchain as installed. The new Xcode needs its own first-launch components
  (`sudo xcodebuild -runFirstLaunch`, then `xcodebuild -downloadComponent MetalToolchain`), which need Caleb's password.
  Until then `swift test --package-path apps/ios` still works locally, and the PR's `swift` CI job (Xcode 27.0, installs
  its own Metal toolchain) is the iOS compile check; Android emulator screenshots stand in for simulator ones.
- 2026-10-16 (Claude, release A): fixtures must honour the same limits as the server function they stand in for. The
  leaderboard fixture ignored `p_limit`, so the Ranked Hall's three-badge teaser drew all ten players and overflowed;
  only an emulator screenshot showed it. `SocialFixtures.leaderboard` now takes `limit` on both platforms.
- 2026-10-16 (Claude, release A): build 42's archive failed with "cannot find type 'SocialFixtures'" because a new
  extension was appended after `SocialFixtures.swift`'s closing `#endif` (the fixtures are DEBUG-only). Package tests,
  the simulator UI tests and CI's `swift` job all build Debug, so only the Release archive saw it; nothing reached Apple.
  **Rule:** when adding to a `#if DEBUG` file, add inside the guard, and before a release run a Release compile
  (`xcodebuild build -configuration Release -destination generic/platform=iOS CODE_SIGNING_ALLOWED=NO`). A failed
  archive leaves the controller run `uncertain`: confirm with `asc builds list` that nothing uploaded, then plan a new
  run ID with the same build number.
- 2026-10-17 (Claude): release A put the per-game performance report inside the "Engine error report" sheet, whose
  button only appears after an engine error, so on a healthy phone the report was unreachable (Caleb couldn't find it).
  **Rule:** a feature the player is meant to use needs a path a tester can actually walk on a normal install; check it
  on the simulator/emulator from the main menu, not just the sheet in isolation. The report now has its own panel in
  Settings on both apps (`GamePerformancePanel`; iOS UI fixture `MAGICMOBILE_UI_TEST_PERFORMANCE=1`).
- 2026-10-17 (Claude, release B): in Postgres, `row_value IS NOT NULL` is true only when every field of the row is
  non-null, so `where c.last is not null` (a whole `friend_messages` row) dropped every conversation whose last message
  was unread (`read_at` null). Test a row's key instead (`(c.last).id is not null`). The PGlite suite caught it.
- 2026-10-17 (Claude, release B): a SwiftUI `Button` whose `.background`/`.overlay` sit outside the label only takes taps
  on the label's text; put the capsule inside the label with `.contentShape`. Synthesized UI-test taps on small targets
  can also be swallowed under load: find results by their label text and allow one retry, rather than fixed ids.
- 2026-10-17 (Claude, release B): the combo loop records only the player's own answers (`OnDeviceSession.send`), never
  smart pass, auto-yield or ability follow-ups (they call `submit` with their own action-id prefixes), and replays by
  card name, action text and target names, because tokens made by a loop get new ids every round.
- 2026-10-17 (Claude, release B): TestFlight 44 crashed on the player's first action in any solo game:
  `ComboLoop.cycle(in:)` looped over `1...min(12, history.count / 3)`, which is `1...0` with one or two steps, and a
  Swift closed range whose upper bound is below its lower bound traps (Kotlin's `1..0` is just empty, so Android was
  fine). The parity cases all had three or more steps. **Rule:** guard the bounds before building a `...` range from a
  computed value, and put the empty and smallest inputs in shared parity cases ("", "A", "AT" now are).
- 2026-10-17 (Claude, combo loop 2): exact replay was too strict for real loops. Chatterfang's round sacrifices
  Squirrel tokens, makes new ones and keeps shrinking one creature, so matching by card name and stopping on an
  unchanged life/zone digest stopped after 2 rounds. Record each choice as *kind* (whose, creature/artifact/…, token or
  card; options by name), prefer last round's pick, and put power, toughness, damage and tapped state in the digest.
  Passes are not round steps: record whether the stack was empty when a step was taken and pass for the player's own
  triggers before it. In the parity fixture, separate targets with `;`: card names like "Zacama, Primal Calamity"
  contain commas. Test snapshots that include `xmage` need every `panels` field or decoding fails.
- 2026-10-17 (Claude, TestFlight 46): the release controller distributes to External only from the exact commit it
  uploaded (`sourceCommit` is part of the run identity), with at most the upload's `build-ledger.json` change left
  uncommitted. Committing the ledger first and then running the second `resume` would invalidate the run. If the
  ledger is already committed: `git reset <upload commit>` (keeps the ledger as an unstaged change), run `resume` with
  the same fingerprint, then `git reset <ledger commit>` to return to the pushed branch. No force push needed.
- 2026-10-18 (Claude): CI's `swift` job also runs `packages/ondevice-engine/scripts/test_runtime_manager.sh`, which
  compiles `OnDeviceRuntimeManager.swift` with a fixed list of app files (not `OnDeviceSession.swift`), so a new app type
  used there fails only in CI ("cannot find type in scope") after every package test passed. **Rule:** keep the runtime
  manager's API in engine-package types (it now exposes `clientTransport`; the root view builds the
  `OnDevicePollReader`), and run that script locally after touching the manager.
- 2026-10-18 (Claude): `xcodebuild build -destination generic/platform=iOS` fails at "Verify staged native input
  hashes (device only)" ("Installed file set differs from owned native inputs") in a worktree without the staged engine.
  **Rule:** for a compile check, build `-destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO`; device
  and Release builds need the engine staged (a release worktree).
- 2026-10-17 (Claude): main has a ruleset ("main: CI must pass", id 25329787) requiring `Download site build`, `app`,
  `boundary-tests`, `swift` and `real-jvm`, and the repo allows auto-merge (`gh pr merge N --auto --merge`). GitHub's
  auto-merge waits only for required checks, and a required check that never reports blocks the PR forever, so never
  put `paths:` on the `pull_request` trigger of a workflow with a required job. Filter inside the workflow instead: the
  `changes` job in magicmobile-ondevice.yml and magicmobile-android-app.yml decides, and a job skipped by `if:` counts
  as passing. A new required job needs the same pattern before it is added to the ruleset.
- 2026-10-18 (Claude, release C): a far-calls run can finish every step and still end `cancelled` when GitHub's runner
  hangs in "Complete job" until the 3 h job limit. Don't `gh run rerun` it: the rerun's artifact sits beside the first
  attempt's with the same name and `controller.py stage-native` refuses ("Expected one unexpired ... artifact").
  Dispatch a fresh run with the same `candidate_sha` and `cheap_run_id`. stage-native also refuses while
  `apps/ios/NativeEngine` exists: move the old engine into `packages/ondevice-engine/build/` first.
- 2026-10-14 (Claude): Cormorant SC has no lowercase; it sets lowercase as small caps, so mixed-case
  proper names like "iPhone" render as "iPHONE". On the site the platform plaques go full caps
  (`text-transform: uppercase`); keep such names out of Cormorant SC text in the app, or uppercase them.
  Headless Chrome's `--window-size` can't go below about 500 px wide, so phone-width site screenshots
  need playwright-core with a real 390 px viewport.
- 2026-10-19 (Claude, card moments): an image set named `tavern-*` in the iOS asset catalogue reaches Android for free
  (`prepareBrandAssets` copies every `tavern-*.imageset/*.png` into drawable-nodpi, dashes to underscores), so new board
  art needs no Gradle change if it follows that name. XMage's reported power and toughness already include counters:
  subtract the counters' share before calling something a pump, or every +1/+1 counter also plays a stats moment. And
  check the card view before adding a board state look: `ArenaBattlefieldCard` already dims phased-out permanents.
- 2026-10-19 (Claude, audio): `slowed(x, semitones)` in `scripts/audio/build_game_audio.py` is a tape-speed change whose
  sign is the pitch direction: negative slows it down (lower, longer), positive speeds it up (higher, shorter). Round 10
  passed +2/+3 to "slow" goblin voices and made them squeaky. Check the rendered length when retuning a voice.
  New-source traps: downloads.sonniss.com and pixabay.com pages sit behind a Cloudflare check (curl gets 403; never
  bypass). The GDC 2026 bundle's Google Drive mirror honours HTTP Range, so single WAVs can be pulled out of the
  1.3-1.9 GB zips without downloading them (it throttles: retry), and Pixabay's `cdn.pixabay.com/download/audio/...`
  files fetch fine with curl once a browser page has given the URL.
- 2026-10-19 (Claude, audio): Caleb judges sounds by ear on his phone, so audition on a page he can open there: the
  Tavern Sound Bin artifact plays every clip levelled, on a switchable landing sound, with Keep / Maybe / No /
  Comment marks saved to its `picks` db (read with ArtifactData). Pack clips as one base64 JSON per group: a publish
  takes at most 255 files. When rebuilding a take for the app, use the loudness target the audition used, not the
  level it measured: `match_loudness` saturates past -1 dB, so a sharp card snap asked for -22.2 lands at -25 (asking
  for -25 gave -27). Short cues build as `.caf`, which browsers can't decode: convert them to m4a for any web page.
- 2026-10-20 (Claude, Arena sections): BattlefieldRow sizes itself with `ArenaPermanentLayout`, which caps the shrink at
  five visible columns and splits into two rows once a row has more than five tiles. A board that lays out its own
  sections has to pass the card size it fitted and `preferredRows`, or a sixth creature scrolls behind the edge fade
  however wide the lane is. Count tiles the way the row draws them (`BattlefieldRow.arenaTileUnits`): piles open into
  single cards while they are targeted or in combat, and attachments peek out to the left.
- 2026-10-20 (Claude, simulator): after many launches that force landscape (`-magicmobile.portraitModeEnabled NO`) the
  iOS 26.5 simulator stopped turning apps when a UI test set `XCUIDevice.shared.orientation`: ProfileHistoryUITests'
  "Landscape charts sit side by side" failed alone and in order, and its recording stayed portrait. Rebooting the
  simulator (shutdown, boot) fixed it with no code change. Check the recording before debugging a rotation failure.
- 2026-10-21 (Claude, commander taken by a sweeper): Necromantic Selection destroyed Caleb's commander and returned it
  under the AI's control, and he was never asked about the command zone. That is the rules, not a bug. XMage moves a
  dead commander home as a state-based action (GameImpl, after CR 903.9a), which runs only after the spell has finished
  resolving, so a spell that destroys and then returns creatures takes the commander first. The board now says so
  (`ArenaCommanderSteal`). The log showed "Auto-passed: Necromantic Selection": smart pass stops for an opponent's
  spell only when the engine marks a playable answer (`respondsToStack`). It found none, probably because his mana was
  tapped, so the spell went by unread. Smart pass now also stops for an opponent's removal, sweepers and steals
  (`OnDeviceSmartPass.threatensViewer`, setting Stop for Removal). Holding a card open holds the pass too
  (`BoardPresentationHold.reading`). Android's smart pass doesn't have these stops yet.
- 2026-10-21 (Claude, Arena glow and motion): three SwiftUI traps.
  - `ArenaStackArc` as a `Canvas` that trimmed its path by an `@State` animated in `onAppear` drew nothing on the board's
    overlay (`overlayPreferenceValue`), though the reticle beside it, a plain view, showed. The same arc as a `Shape`
    with `.trim(from:to:)` draws itself in. Use shapes for anything that animates.
  - A curve of an animated value (`sin(.pi * t)` for a flare) does not animate: SwiftUI interpolates modifier values
    between the start and end states, and a flare is 0 at both. Drive such moments with a short `TimelineView` that stops
    (`ArenaStackCard`'s landing).
  - A glow drawn as `.background` before a `.shadow` casts a shadow of its own light. Put the glow after the shadow.
  The glow border itself (`ArenaOutlineGlow`) blurs each outline once with Core Image and caches it, as the web
  board's `glowCanvas` does. Never blur live per tile.
- 2026-10-21 (Claude, Arena hand touch): a touch on the popped card's upper part went to the table, because the hand's
  touch surface stopped at the tucked hand. Two fixes that look obvious fail:
  - Growing the surface to cover where cards pop, then filtering touches with `UIView.point(inside:)`, made the lands
    under it untappable. The UI test caught it ("not hittable"): SwiftUI hit-tests a `UIViewRepresentable` by its frame.
  - Swapping in a new surface when the card pops would cancel the pan, because a gesture ends when its view leaves.
  So the popped card gets its own surface the size of its picture (`ArenaHandFan.touchSurface`). It stays where the
  card was while the card is carried (`carrySurface`), so the drag that started on it keeps going.
  The drop rule is `ArenaLayout.drops`: the whole table above the hand except the controls corner, after a carry of
  24 pt up or 80 pt in any direction. In landscape a popped card already sits over your land row, and a short sideways
  slide must not cast it.
- 2026-10-21 (Claude, Arena hand): a slide along the tucked hand skipped cards because the hit test gave a popped card
  its whole enlarged width, which covers its neighbours' strips, and ignored the fan's tilt. Scrubbing now maps the
  finger to each card's visible strip at the finger's height along its rotation (`ArenaHandFan.scrubCard`), with a small
  dead zone. Taps still prefer the popped card so a second tap plays it.
- 2026-10-21 (Claude, Arena fixtures): the card-choice browser opens only for `choose_target` prompts with
  `maxChoices == 1` (`PortraitInteractionPolicy.cardChoiceKey`): XMage asks one pick at a time and reports earlier picks
  in `options.chosenTargets`. A fixture asking for five picks at once never opened it. Long SwiftUI modifier chains
  with ternaries over colours (a split's number badge) time out the type checker; build such views from small helpers.
- 2026-10-20 (Claude, Arena panels): the prompt-detail sheet opens by itself for every ability, order, amount and
  search question (`PortraitInteractionPolicy.detailChoiceKey`, read in six places in NativeGameView). A board that answers
  one of those in its own view has to filter the key (`boardDetailChoiceKey`), or the sheet covers its view. Showing a
  sheet's view in an overlay instead (`boardSheet`) also breaks its close button: `dismiss` there acts on the nearest
  presentation, which can be the screen holding the board. Panels in an overlay close with `boardPanelClose`.
- 2026-10-20 (Claude, Arena browsers): a screen that takes over a prompt must use the same gate as the pop-up it
  replaces. `arenaQuestion` first checked only "the prompt has answers", so a mana payment counted as a question and
  hid the corner (Auto Pay, the phase strip); the Arena UI test caught it. Gate such screens with
  `CompactPromptPopup.shouldShow`, the payment checks and the other browsers' prompts. Also, XMage asks a trigger's
  targets as soon as that trigger goes on the stack, between its trigger-order prompts: a planned order must survive
  other questions (`arenaTriggerStep` keeps the plan until your next priority) and never answer one prompt twice.
- 2026-10-20 (Claude, Arena phase strip): on iOS a small custom `Shape` that returns `Path(roundedRect:cornerRadius:)`
  fills at the shape's whole frame size, starting from the rectangle's corner, while its stroke draws correctly: each
  card icon in the phase strip had a pale or dark block beside it. The same code renders fine through `ImageRenderer`
  on macOS, so a Mac probe doesn't reproduce it. Draw such rectangles from lines and arcs (`arenaRoundedRectPath`).
  Also, a child bigger than its `ZStack`'s fixed frame (a halo) makes the stack's shapes draw at the child's size on
  macOS: put halos in `.background`.
- 2026-10-22 (Claude, Arena menus): `ScrollViewReader.scrollTo` does nothing for an id inside a `LazyVGrid` nested in a
  `LazyVStack` until that row has been built, so the Play panel opened with the chosen deck off screen in landscape
  (portrait worked only because the row was already built). Put the scroll id on something always built (each shelf's
  heading in a plain `VStack`) and scroll to that.
- 2026-10-22 (Claude, Arena menus): a custom `Shape` animates only its `animatableData`. The deck box's side first took
  a value computed from `openness` outside the shape, so it jumped to the open shape while the rest animated. Pass
  constants into the shape and compute from the animatable value inside `path(in:)`.
- 2026-10-22 (Claude, Arena menus): menu pages shown as overlays (`arenaPanel`) are not presented, so `dismiss()` in them
  closes nothing. Read `\.arenaPanelClose` and fall back to `dismiss` only outside a panel. The app-wide
  `\.arenaBoard = true` reaches into a game too: the game sets its own board's value, and so does the starting roll.
- 2026-10-22 (Claude, screenshots): in zsh `for o in ${ORIENT:-port land}` loops once over the whole string; split it
  with `${=${ORIENT:-port land}}`.
- 2026-10-22 (Claude, screenshots): when the Mac's audio output stalls, the simulator app stays on its launch screen:
  the menu's `GameAudio.playMusic` calls `AVAudioPlayer.play()` on the main thread and waits on the audio device
  (`sample <pid>` shows `AQMEIO_Base::StartIO_Sync`). The stuck process also survives `simctl launch
  --terminate-running-process` and `simctl terminate`, so later launches just bring it back; `kill -9` it. Launch
  arguments don't reach the UI-test preferences suite, which the test launch resets anyway. GameAudio now stays silent
  under `--ondevice-setup-ui-test` and when `MAGICMOBILE_MUTE_AUDIO=1` is set (scripted screenshot runs). Also: a NavigationStack around a screen paints an opaque page,
  so Deck Studio inside the menu shell hid the room until the stack (which pushed nothing) was removed.
- 2026-10-22 (Claude, Hearth board): two player reports. (1) Held sideways, the tavern zone pop-over (`TavernMenu`, opened
  from a medallion) ran past the screen and could not scroll: its plain `VStack` is as tall as its rows and UIKit just
  clips a popover that is taller than the window. **Fix:** with a compact vertical size class the rows sit in a
  `ScrollView` under `.frame(maxHeight: screenHeight - 64)`; portrait is unchanged. A UI test cannot swipe a row that is
  scrolled out of view ("visible frame is empty"): swipe the scroll view that contains it
  (`BoardPolishUITests.testLandscapeZonePopoverReachesEveryRow`). (2) The "TURN N" plate showed XMage's turn number,
  which every player's turn raises (turn 9 of a two-player game is round 5). The snapshot carries no starting player
  and the log keeps only 64 lines, so `TableRounds` (Models.swift) counts the first player's turns as polls arrive;
  `OnDeviceSession` sets `GameSnapshot.round`, and `displayTurn` (round, else turns / players in) feeds the labels.
  `snapshot.turn` stays the engine's count for logic, stats and saved games. The game log's "TURN 9 for AI 1" lines are
  XMage's own text and still show the engine number. Where: `Board/BoardChrome.swift`, `Models.swift`,
  `OnDeviceSession.swift`, `PortraitBoardViews.swift`, `NativeGameView.swift`, `PortraitInteractionPolicy.swift`.
- 2026-10-22 (Claude, Arena menus): three SwiftUI traps from the Arena menus. (1) A custom control drawn over a real
  Toggle/Slider/Stepper at `.opacity(0.02)` still shows the system track or thumb on dark glass; draw only your own
  control and give VoiceOver and UI tests the real one with `.accessibilityRepresentation { Toggle(...) }` (XCUITest
  still finds `app.switches[id]`; a slider's `adjust` needs a tap on the drawn track instead). (2) `.opacity` on a
  container is applied to each layer, so a dimmed 3D deck box turned see-through; dim with a scrim over the area.
  (3) A view taller than its `.frame(width:height:)` is centred by that frame, so a drawer that runs into the home bar
  rose over the top bar: pass `alignment: .topLeading` to the frame, not only to the ZStack. Also: a judge working from
  memory missed whole layouts; compare against real reference shots (build_output/arena-menus-reference/more/).
- 2026-10-22 (Claude, Deck Studio upright page): `onGeometryChange` on a ScrollView that has a
  `.safeAreaInset(edge: .bottom)` after it reports the height already inside the inset bar, yet `safeAreaInsets.bottom`
  still names the bar's 60 pt, so subtracting it counts the bar twice. XCUITest shows the ScrollView's full frame. The
  upright chapters' `minHeight` was a guess (`geometry - 70`) that ran 100+ pt past the visible page once the Done and
  Play bar arrived, so a short Ideas page could scroll its own source picker under the tabs. It now uses the measured
  height plus 24 pt so the landing scroll still clears the header. Also: `scripts/deck-studio/ios-ui-tests.py` takes
  `build` then `test` as separate runs.
- 2026-10-22 (Claude, Arena look pass): (1) A `DragGesture` attached with `.gesture` to a view whose child is a `Button`
  never fires: the Button takes the touch, which is why the home carousel didn't swipe. Use `.highPriorityGesture` and
  check the drag is mostly sideways. (2) A pill drawn behind a label with `.padding(.vertical, inset)` must have a
  frame taller than the label, or the capsule shrinks to a line. `ArenaButtonFace` pads hugging pills and insets only
  filling ones (`fills`). (3) Scryfall's largest art crop is 626 px wide for every card. The home art is that crop,
  upscaled with Real-ESRGAN (official v0.2.5.0 macOS release, `realesrgan-x4plus`, 4× then Lanczos down to 1252 px),
  and shipped in the asset catalog. (4) To change how something looks on the Arena board only, branch on
  `\.arenaBoard` inside the shared style (`TavernButtonStyle`, `StartingRollCover`, `OpeningHandButtonStyle`) rather
  than at each caller. The menus set it true, and a game sets it to its own board.
- 2026-10-22 (Claude, TestFlight 56 crash): switching to the Arena board crashed on Caleb's iPhone (iOS 26.6.2) with
  EXC_BAD_ACCESS in the main thread's stack guard, inside `swift_getTypeByMangledName` called from
  `NativeGameView.arenaOpponentSeat` under `arenaTable`. The board was one giant `@ViewBuilder` value in a Release build
  (the piles, overlays, medallion branches and menu inlined into one nested type), and the device's main thread has
  about 1 MB of stack. Debug builds and the simulator, which has a larger stack, never showed it. The fix type-erases
  each table layer (`ArenaLayer`, an AnyView over a ZStack, with the z-order applied outside it) and the board in `body`.
  Rules: don't let one function build a whole screen as a nested view, split it into erased layers or separate `View`
  structs; read the crash with `asc testflight crashes list --app 6784735182 --sort -createdDate` and
  `asc testflight crashes log --submission-id <id>` (sandbox off).
- 2026-10-22 (Claude, Arena safe area): reading UIKit state in a SwiftUI body (`UIApplication...windows.first?.safeAreaInsets`,
  for padding) made the Arena scry browser lose its cards, even though the padding value was the same as before.
  Bisected to that one line. Pass measured insets down the environment instead: the Arena board sets `\.arenaSafeArea`
  from its root GeometryProxy, and full-table layers read `safeArea.top(_:)` / `safeArea.side`.
