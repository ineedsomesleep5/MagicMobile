# iOS 0.1.1 build 52: Arena layout, tucked hand, phase icons (internal only)

Apple reports build `b88a63ca-bc91-44cc-ba77-c6b1826034ad` as `VALID` on October 20, 2026, with export compliance set
(`usesNonExemptEncryption = false`). Caleb asked for **Internal
TestFlight only**: the Internal group has access to all builds, and the controller's distribution step (which adds
External) was not run. Same native engine as builds 48–51 (release C, `21a82eb7`), so tables seat Android 31–33. No
Android build carries the Arena mode yet.

## Changes since build 51
- The Arena board follows the current reference game's layout (Caleb's desktop screenshot): your graveyard, library
  and exile in the bottom-left corner, the opponent's top right; the opponent's hand fanned behind their medallion;
  your medallion above your hand.
- Planeswalkers, battles and sagas stand in their own section at the table's right edge, a size up, and shrink
  together with the creature row; the back row has lands on the left and artifacts, mana rocks and Treasures right of
  centre.
- The hand stays tucked along the bottom edge (portrait: full size, tops just below your lands, the rest behind the
  rail). A tap or a slide pops up the card under the finger while the rest stay tucked; a second tap plays it, and
  carrying it up onto the table plays it too. A hold magnifies the card and follows the finger.
- Phase strip: enamel icons in brass rims; the current step is lit, a size up, with a halo, and the played part of the
  turn is lit along the track. The blocks beside the card icons (an iOS rounded-rectangle fill bug) are gone.
- In portrait your deck and graveyard draw above the front rail again.

## Release
- **Source:** `codex/ios-build-52` at `6aa65676` (`codex/ios-build-51` with build 51's record, `claude/arena-mode`
  through `51d23093`, and the build-number prepare). Preflight native decision `equivalent-source`. Xcode 27.1.
- **Run:** `ios-0.1.1-52`, fingerprint `6b170814…`, delivery `b88a63ca-bc91-44cc-ba77-c6b1826034ad`, IPA `3a4705aa…`.
  One guarded resume (upload only).

## Verification
- Preflight `ios-fast`: 14/14.
- `swift test`: ArenaBoardModelTests (19) and BattlefieldAdaptiveSizingTests.
- UI tests on the iPhone 17 Pro Max simulator: the Arena board test (both orientations, Auto Pay, a tap pops a tucked
  card) and presentation-smoke; ProfileHistoryUITests passes on a freshly booted simulator.
- The simulator cannot run the engine, so live play waits for the phone.
- **Still to check on Caleb's iPhone:** popping and playing cards from the tucked hand in a live game, both
  orientations; the side section with a real planeswalker; Auto Pay and attacking.
