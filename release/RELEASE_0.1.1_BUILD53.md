# iOS 0.1.1 build 53: Arena browsers, glass panels, Auto Pay and loop fixes (internal only)

Apple reports build `4ecf26d3-1901-49a0-833b-e573fe1027ea` as `VALID` on October 20, 2026, with export compliance set
(`usesNonExemptEncryption = false`). Caleb asked for **Internal TestFlight only**: the Internal group has access to
all builds, and the controller's distribution step (which adds External) was not run. Same native engine as builds
48–52 (release C, `21a82eb7`), so tables seat Android 31–33. No Android build carries the Arena mode yet.

## Changes since build 52 (Arena board only)
- **Choices are full-table browsers**, after Arena gameplay footage: the table dims, a title names the effect over one
  line of instructions, the source card stands on the right, an orange Done answers, and View Battlefield steps aside.
  - Abilities and trigger order: tap triggers in the order they resolve (numbered coins), Auto Order or Done; a
    prompt's Cancel stays in the browser.
  - The stack: every object side by side as cards, the next to resolve first, with whose it is and its targets.
  - Scry (Bottom and Top zones), surveil (Graveyard and Library), library searches and top-of-library picks.
  - Modes: one card per mode with the spell's art.
  - "You may" and yes-or-no questions: the question as the title, the card it names in the middle, Yes and No plaques.
- **No iOS sheets or Hearth leather**: the log, game settings, prompt details and phase stops open as glass panels
  on the table; tags, title bars, search fields, rows and the stack list switch to glass.
- Commander casts: a gold rim and crown on the stack card, no Hearth showcase. Abilities on the stack are ability
  cards with an arc to their target. The caption stays left of the stack card; P/T draws above the outline; the phase
  strip always has 8 icons, so main 2 lights. XMage's mulligan question no longer shows behind the opening hand.
- Landscape: the home gesture is deferred, the hand sits higher and your medallion moves to the bottom left.
  Planeswalkers, battles and sagas take the side section; other artifacts and enchantments go to the back row.
- Auto Pay plans the whole cost by colour (Treasures, tri-lands, tapping before sacrificing), answers only its own
  tap's colour question and no longer stops on a quiet snapshot. All Attack waits through "which defender"
  questions. A chosen trigger order survives target questions and a refused pick.
- Combo loops: "Until they lose" is enabled only when each round drains every opponent the same and none has both
  cards and an untapped land; it then finishes behind a curtain. A running loop is a slim glass bar.

## Release
- **Source:** `codex/ios-build-53` at `60c8d92b` (`codex/ios-build-52` with build 52's record, `claude/arena-mode`
  through `08a2e25a`, and the build-number prepare). Preflight native decision `equivalent-source`. Xcode 27.1.
- **Run:** `ios-0.1.1-53`, fingerprint `6bcb3e82…`, delivery `4ecf26d3-1901-49a0-833b-e573fe1027ea`, IPA `6230ec1c…`. One guarded resume (upload only).

## Verification
- Preflight `ios-fast`: 14/14.
- `swift test`: ArenaBoardModelTests (23), ComboLoopTests (5), BattlefieldAdaptiveSizingTests and the session,
  readiness, interaction and model suites (113 in all).
- UI tests on the iPhone 17 Pro Max simulator, exact source: the three Arena tests (controls in both orientations
  with Auto Pay, a hand pop and Game Settings in glass; the ability browser; the question, scry and mode browsers)
  and presentation-smoke; ProfileHistoryUITests passed after a simulator reboot.
- An independent review of the gameplay logic found 8 issues; all were fixed before the build.
- The simulator cannot run the engine, so live play waits for the phone.
- **Still to check on Caleb's iPhone:** each browser in a live game (trigger order with targeted triggers, a fetch
  land or tutor, scry and surveil, a modal spell, a "you may" trigger), Auto Pay with a Treasure and a tri-land, All
  Attack with a planeswalker out, and a winning loop.
