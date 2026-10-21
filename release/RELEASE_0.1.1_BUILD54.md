# iOS 0.1.1 build 54: Arena choice screens, Arena pace, fuller back row (internal only)

Apple reports build `070e4c8a-b2b3-42c6-8795-24fb37b7a91f` as `VALID` on October 21, 2026, with export compliance set
(`usesNonExemptEncryption = false`). Internal TestFlight only, as with builds 51–53: the controller's distribution
step (which adds External) was not run. Same native engine as builds 48–53 (release C, `21a82eb7`), so tables seat
Android 31–33. No Android build carries the Arena mode yet.

## Changes since build 53 (Arena board only)
- **An Arena style guide** (`docs/ARENA_STYLE.md`, linked from CLAUDE.md) sets the rules every Arena screen follows:
  full-table browsers, plaques, glass, no system or Hearth UI, the reference's timings.
- **New full-table screens** for the choices that still used the glass panel:
  - named choices (replacement effects show the cards they name, with a "Remember my choice" toggle; colours as mana
    symbols; long lists as glass tiles with search);
  - who goes first, as the players' medallions;
  - X and other numbers, as the reference's pill in the button corner: [−5] [−] [Pay X = n] [+] [+5], Cancel under
    it; X starts at the most your mana can pay; hold − or + to keep stepping;
  - damage, counter and mana splits: each blocker or target as its card (a player as their medallion, a colour as its
    symbol) with its number, − and +, lethal marked, what's left to give, Done only when the split is legal;
  - choosing a pile (both piles fanned side by side) and separating cards into Pile 1 and Pile 2.
- Planeswalker abilities show their loyalty cost on a badge.
- **Card inspection the Arena way:** the card large with no panel, glass notes beside it with its live state, what its
  keywords mean, its rules when the picture can't show them, and what's attached.
- **The reference's pace:** your spell reaches the stack card in 0.35 s; an opponent's is revealed larger toward the
  middle and settles after 1.6 s (smart pass waits for the reveal only); triggers 0.5 s; arrivals 0.6 s; strikes one
  after another, 0.45 s each, 0.38 s apart. A spell cast and resolved between two board updates still shows at the
  stack card's place. Hearth keeps its timings.
- **More artifacts in view:** in portrait, artifacts, Treasures and enchantments get their own row in front of the
  lands while your creatures fit one row; in landscape they share the whole back row with the lands.
- **Hand slides move one card at a time,** at any height along the tilted, tucked hand.

## Release
- **Source:** `codex/ios-build-54` at `ab0479af` (`codex/ios-build-53` with build 53's record, `claude/arena-mode`
  through `a0014b3d`, and the build-number prepare). Preflight native decision `equivalent-source`. Xcode 27.1.
- **Run:** `ios-0.1.1-54`, fingerprint `68a3779d…`, delivery `070e4c8a-b2b3-42c6-8795-24fb37b7a91f`, IPA `b3f1c583…`. One guarded resume (upload only).

## Verification
- Preflight `ios-fast`: 14/14.
- `swift test`: 146 tests across ArenaBoardModelTests (new: choices, loyalty, amounts, splits, glossary),
  BoardEventTimelineTests (new: Arena pace), ComboLoopTests and the session, interaction and model suites.
- UI tests on the iPhone 17 Pro Max simulator, exact source: the four Arena tests (new: choice browser, who goes
  first, piles, mana split, the X pill) and presentation-smoke; ProfileHistoryUITests after a simulator reboot.
- An independent review found seven defects in this round (hold-to-repeat that could overshoot or not stop, the
  landscape back row's sizing, a stale spell drawn over the next, a colour browser flash during Auto Pay, XMage's
  "[id]" in replacement-effect labels, a command-type helper, short number ranges); all fixed before the build.
- The simulator cannot run the engine. The screens send the same commands as the Hearth panel, and the new pace
  changes only presentation and how long smart pass waits (still capped at 4–5 s).
- **Still to check on Caleb's iPhone:** a real replacement-effect choice (Doubling Season with Chatterfang), an X
  spell, a double block and a divided-damage spell, Fact or Fiction, the opponent's spell reveal and the strike pace
  against the engine, and sliding through the hand.
