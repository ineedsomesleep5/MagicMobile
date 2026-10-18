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
