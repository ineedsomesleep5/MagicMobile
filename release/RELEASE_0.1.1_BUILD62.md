# TestFlight 0.1.1 (62): drag straight off the spread hand, full trigger text, tidy big hands

Uploaded October 25, 2026 and distributed to Internal and External testers; Beta App Review `APPROVED`. Released with
Android build 39 and a web deploy of the same main (`6f7d21e1`, deployment `dpl_EeTHL5v5WrtM3UwgJTeUAqUcWjL3`).

## What changed (PR #244)
- **Drag to cast from the spread hand:** the row decided swipe-or-carry on the pan's first report, which sits on its
  start, so every drag became a sideways swipe (only tap-then-drag carried). It now waits until the finger moves; a hold
  pulled up off the hand carries too.
- **Order your triggers** shows each trigger's full rule from the source card (`EngineDisplayText.abilityRule`); XMage's
  picker label was partial or empty for some cards (Wrathful Raptors read "2.").
- **Big hands:** past seven cards the fan keeps a seven-card hand's gentle edge; past eight the cost shows only on the
  popped card, which pops larger.

## Release
- **Source:** `codex/ios-build-62` in `~/Documents/MagicMobile-release-40` = main `6f7d21e1` + the release-only
  calibration-tooling restore (as build 61) + `prepare`. Never merge that branch.
- **Engine:** release C, unchanged; preflight `ios-fast` 14/14, `equivalent-source`.
- **Run:** `ios-0.1.1-62`, fingerprint `d4944b0e…`, delivery `19f0a127…`, VALID then distributed.

## Verification
- CI green on #244. Web 318 tests; Android `:core:test` 402; simulator checks on design previews: a flick and a
  press-pause-drag from the spread hand both cast, and a 21-card fan.
- **Not verified on a phone:** the drag, the trigger screen with real Wrathful Raptors, and a big hand in a real game.
