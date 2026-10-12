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
  Android `MainActivity.kt`.
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

- 2026-10-11 (Claude): Arena-style smart auto-pass and phase stops needed no engine change. The poll
  already carries XMage's own playable list (`gameView.canPlayObjects`, with `manaAbility` marks) and
  the step, so the session sends the same `pass_priority` a tap sends. **Rule:** client-side pass
  scheduling belongs in `OnDeviceSmartPass` (iOS `OnDeviceYieldPolicy.swift`, Android core
  `game/OnDeviceSmartPass.kt`); an engine edit means a native rebuild on both platforms.
- 2026-10-11 (Claude): the Android app CI job runs `:core:contractChecks` but never the `:core:test`
  JUnit task, so a new core JUnit class only compiles there. **Rule:** call new core checks from
  `ContractChecks.kt`'s `main` so CI executes them.

## Performance

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
  a new port.

## Native engine and releases

- 2026-10-11 (Claude): a game froze at combat damage when trample killed the planeswalker being
  attacked. XMage then keeps the attackers in combat with a null `defenderId` (rule 506.4,
  `PlayerImpl.removeFromBattlefield` → `Combat.removeDefendingPermanentFromCombat`; phasing out and
  control changes do the same), and both snapshot adapters threw "Missing combat defender" on every
  poll. **Rule:** a missing field the rules allow is state, not corruption; the adapters now emit
  `defenderKind: "none"`. Before rejecting engine data, check upstream for when it can be null.
- 2026-10-11 (Claude): XMage AI skill sets search depth `max(4, skill)` and think time `skill × 3` s,
  so skills 1–4 play at the same depth. Tune difficulty with decks first (docs/RANKED.md).
- 2026-09-27 (Claude): `verify_native.py` compares the whole engine package, including the iOS-only
  Swift wrapper, so Android build 10 had to ship with the package restored to the native library's
  source commit (`2c32482`). **Rule:** when the Android native library and the package source
  disagree, restore the package to the library's commit rather than rebuilding.

## Agent environment

- 2026-10-11 (Claude): the iOS CI `swift` job fails when any expression under `apps/ios/MagicMobile/Board/`
  takes over 200 ms to type-check, even after the build and tests pass. Wrapping a view in a Button inside
  the tavern bar's big ZStack, or a long settings body with ternaries, is enough to trip it. Cloud threads
  can't download the job's artifact that names the slow lines. **Rule:** keep new Board views small,
  as separate structs or helper functions with explicit types, rather than adding to a large closure.
- 2026-10-11 (Claude): a new iOS source file needs three registrations: `apps/ios/Package.swift`
  (`sources` of the target or test target, unless its folder is excluded, like `Board/`) and four
  entries in the committed `MagicMobileiOS.xcodeproj/project.pbxproj` (build file, file reference,
  group child, Sources phase). Copy a neighbour's entries with fresh 24-hex IDs.
- 2026-10-11 (Claude): cloud containers can't reach dl.google.com, so `gradle` in `apps/android`
  fails on the Android plugin. The JVM-only `:core` tests still run from a throwaway root two levels under the repo (the
  parity tests read `../..`, e.g. `apps/zz-coreonly/`) that includes only `../android/core` with the Kotlin plugins and `jvmToolchain(21)` (the container has
  JDK 21, not 17). Maven Central answers 429 in bursts; retry with `--max-workers=1`. The app module
  only compiles in the `magicmobile-android-app.yml` PR check (or on Caleb's Mac).
- 2026-10-11 (Claude): cloud threads ignore `defaultMode: bypassPermissions` / `dontAsk` in settings
  files, and run in auto mode. Commands every thread may run without a prompt go in
  `permissions.allow` in `.claude/settings.json`; cloud threads apply it only while the project has
  a single repository.
