# iOS 0.1.1 build 51: Arena board mode (internal only)

Apple reports build `f3cc7414-3111-4003-aff1-8bfdfe444075` as `VALID` on October 20, 2026, with export compliance set
(`usesNonExemptEncryption = false`). Caleb asked for **Internal TestFlight only**: the Internal group has access to all
builds, and the controller's distribution step (which adds External) was not run. Same native engine as builds 48–50
(release C, `21a82eb7`), so tables seat Android 31–33. No Android build carries the Arena mode yet.

## Changes
- A second board mode beside Hearth (Settings → Board): the Duel Board Prototype artifact as the **Arena** mode, on a
  leaning tavern table, in both orientations. Hand postures, corner controls, Auto Pay (one tap per XMage answer),
  All Attack, the stack's top card on the right, deck piles with the real card back, exile piles, and a revealed top
  card face up on the deck.
- Card Frames setting per mode: off by default in Arena (the reference game's cropped card, name bar and silver
  power/toughness box), on in Hearth.
- Auras and Equipment peek out to the left behind their creature; floating mana sits above your medallion.
- Battlefield sections: creatures across the front row, planeswalkers, battles and other non-creatures in a section at
  its right end (loyalty and defense on a shield); lands from the left of the back row, mana rocks and Treasures at its
  right end. Rows use the table's full width and shrink cards to 70% before a section scrolls.
- Tiles and decks lean with the table plate's camera; a full raised hand stays whole on the screen.

## Release
- **Source:** `codex/ios-build-51` at `c9a6faac` (`f8c8706c`, the build-number prepare `16741953`, and
  `claude/arena-mode` through `f4708a83`). Preflight native decision `equivalent-source`. Xcode 27.1.
- **Run:** `ios-0.1.1-51`, fingerprint `416e187e…`, delivery `f3cc7414-3111-4003-aff1-8bfdfe444075`, IPA `bce8aeb5…`.
  One guarded resume (upload only). Uploaded 13:11 and VALID within about 20 minutes.

## Verification
- Preflight `ios-fast`: 14/14.
- `swift test`: ArenaBoardModelTests (19, including real XMage polls for Auto Pay and attacker selection) and
  BattlefieldAdaptiveSizingTests.
- UI tests on the iPhone 17 Pro Max simulator: the Arena board test (both orientations, Auto Pay) and presentation-smoke.
  ProfileHistoryUITests passed only after a simulator reboot (the simulator had stopped rotating apps).
- The simulator cannot run the engine, so live play (Auto Pay, All Attack, the skip pill) waits for the phone.
- **Still to check on Caleb's iPhone:** a live game in Arena mode in both orientations; Auto Pay; attacking; the hand.
