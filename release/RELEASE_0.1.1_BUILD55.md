# iOS 0.1.1 build 55: the glow border, spell targets, Arena zone screens (internal + external)

Apple reports build `23e7a503-9975-4b3d-a9e1-076b90066325` as `VALID` on October 21, 2026, with export compliance set
(`usesNonExemptEncryption = false`). It went to the Internal and External groups, and Beta App Review approved it
right away. This is the first Arena build in the External group. Same native engine as builds 48–54 (release C,
`21a82eb7`), so tables seat Android 31–33. No Android build carries the Arena mode yet. The Arena mode is on main
since PR #217 (`b25249c0`).

## Changes since build 54 (Arena board only, from Caleb's playtest notes)
- **The glow border** from the web board (`ArenaOutlineGlow`, memory `frame-outline-glow`). Light follows the tavern
  frame with Card Frames on, the card or token arch with them off, and the printed card in the hand. The colours:
  - cyan when playable (it breathes in the hand, softer on lands);
  - pale for a target, gold when selected;
  - red-orange for attackers, amber for blockers;
  - orange while a payment is open.

  Hand cards lose their coloured lines and the "up" badge.
- **Targets:** a spell on the stack points at its targets with an arc, as an ability does, and each target wears a
  reticle (cyan for yours, red for the opponent's). An opponent's Murder now shows what it hits.
- **The stack card:**
  - a tab on its left edge opens the stack and shows the count;
  - no power/toughness badges over the printed card;
  - it sits under the opponent's piles and clear of the phase strip;
  - the opponent's reveal no longer covers their piles;
  - a spell lands with a bloom of its colour, a shine and a few motes, once per object. The light rays are gone.
- **Piles:** graveyard and exile lean and stack like the library, always show their count and never show P/T. Your
  medallion and piles moved left, with room between the stacks for their counts.
- **Zones and players:** graveyard, exile, the command zone and revealed cards open as Arena browsers (cards, Cast
  plaques, Done). Medallions open an Arena player card: life, counters, commander damage, zone icons and exile zones
  by name. The Revealed and Looked-at pills sit by the opponent's piles, off the creature rows.
- **The hand:** a popped card can be dragged from its own picture. A carried card plays anywhere on the table above
  the hand, your land row included, except the controls corner, after a carry of 24 pt up or 80 pt in any direction.
  The table's edge lights up instead of a box.
- **Also:**
  - tapped tiles grey by a multiply, so their art reads;
  - token copies say COPY inside their frame;
  - long questions get a short title, with XMage's message under it;
  - ability cards borrow their permanent's art;
  - nothing is drawn over a full-table screen.

## Release
- **Source:** `codex/ios-build-55` at `1a85e571`: `codex/ios-build-54` with build 54's record, `claude/arena-mode`
  through `47c366a7`, and the build-number prepare. Preflight native decision `equivalent-source`
  (`prepare_ios_app_native.py --verify-installed` exit 0). Xcode 27.1.
- **Run:** `ios-0.1.1-55`, fingerprint `81f6d508…`, delivery `23e7a503…`, IPA `bd12d617…`. Two guarded resumes:
  upload, then distribution to Internal and External.

## Verification
- Preflight `ios-fast`: 14/14, no source drift.
- `swift test`: 750 tests, 0 failures, 5 skipped. New model tests cover the drop rule, the stack card's place and
  the pile spacing.
- UI tests on the iPhone 17 Pro Max simulator, exact source: presentation-smoke and the five Arena tests. The new
  `testArenaBoardStackTabDragAfterPopAndZoneBrowsers` covers the stack tab, a drag after a pop, a land under the hand,
  the player card, the command zone's Cast and the revealed browser.
  - `testArenaBoardChoosesAbilitiesInItsOwnBrowser` lost its first tap right after a simulator reboot and passed on
    rerun against the same build.
  - `ProfileHistoryUITests` needed the usual simulator reboot.
- An independent review of this round found nine issues, all fixed before the build:
  - test queries that didn't match;
  - Done disabled while an answer was pending;
  - the pills overlapping the graveyard and the gear;
  - the player card staying open over a new decision;
  - the landing effect replaying as the stack resolved;
  - the headline naming the wrong card;
  - a sideways slide on a popped card casting it;
  - the hand's touch area over the land row.
- The simulator cannot run the engine. The Arena screens send the same commands as the Hearth panels.
- **Still to check on Caleb's iPhone:** the glow with and without Card Frames, an opponent's targeted removal (arc
  and reticle), dragging a popped card, the player card and zone browsers against the engine, and the new landing.
