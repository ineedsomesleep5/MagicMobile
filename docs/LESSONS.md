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

## Performance

- 2026-10-03 (Claude): a quiet Android tavern board used about 105% CPU on the emulator because
  breathing glows redrew every frame. **Fix:** one shared 20 Hz clock (`rememberBoardBreath` in
  `board/BoardSupport.kt`), read at draw time; it now uses about 45% CPU, and 0.6% with
  animations off. Any new ambient animation should use that clock, not its own
  per-frame animation.

## Native engine and releases

- 2026-09-27 (Claude): `verify_native.py` compares the whole engine package, including the iOS-only
  Swift wrapper, so Android build 10 had to ship with the package restored to the native library's
  source commit (`2c32482`). **Rule:** when the Android native library and the package source
  disagree, restore the package to the library's commit rather than rebuilding.

## Agent environment

- 2026-10-11 (Claude): the cloud container can't reach Google's Maven (`dl.google.com` is blocked), so the
  Android build fails at the AGP plugin, and there is no Swift toolchain. **Fix:** run the JVM `:core` tests from a
  scratch Gradle root that includes only `apps/android/core` with the Kotlin JVM plugin 2.0.21 and
  `jvmToolchain(21)` (only JDK 21 is installed); leave app and iOS compilation to PR CI or the Mac. Maven Central
  can answer 429 for a minute: wait and retry.
- 2026-10-11 (Claude): cloud threads ignore `defaultMode: bypassPermissions` / `dontAsk` in settings
  files, and run in auto mode. Commands every thread may run without a prompt go in
  `permissions.allow` in `.claude/settings.json`; cloud threads apply it only while the project has
  a single repository.
