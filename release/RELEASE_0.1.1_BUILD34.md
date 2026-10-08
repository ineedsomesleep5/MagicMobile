# iOS 0.1.1 build 34: XMage dac400b, Don't ask again, Resolve all, card artwork, every token offline

Apple reports build `9e69feee-eb52-4cd0-bb65-dde1b59c3511` as `VALID`, with internal and external state `IN_BETA_TESTING`
(Beta App Review `APPROVED`), in the Internal (all builds) and External (added) groups, on October 7, 2026. The External
invitation remains https://testflight.apple.com/join/2mSHE8rZ. It shipped together with Android build 19 (same XMage
`dac400b` and catalogue, so tables still seat both platforms). None of this proves anything on a physical iPhone or iPad.

## Changes ([#126](https://github.com/ineedsomesleep5/MagicMobile/pull/126), on [#121](https://github.com/ineedsomesleep5/MagicMobile/pull/121))
- **Engine update** (`docs/ENGINE_UPDATE_dac400b.md`):
  - XMage `4825513` → `dac400b`: 221 commits, 31,959 names (+78), no name lost.
  - **Answer actions:** XMage desktop's own remembered answers, trigger order, pass until the stack resolves, and pass
    after casting. Keys come from the prompt.
  - **AI:** passes again without another search while an opponent's ability resolves off a stack it already declined.
- **Prompts:**
  - "Don't ask again this game" on a card's "you may" question, and "Always put my pick first" on the trigger order.
  - Settings → Pass After Casting, on by default.
  - Game menu → Remembered this game.
- **The stack:**
  - "Resolve all" under the stack tray and in the stack sheet.
  - The stack sheet drawn as parchment slips, with what resolves next, whose it is, targets and rules.
- **Card choices:** "any number" targets are picked at once, with Select all and Clear.
- **Card art** (work by a delegated agent, reviewed and merged):
  - Choose any card's artwork in Deck Studio.
  - Online images request that exact printing, and the offline pack stores it.
  - Export and import keep the printing.
  - The offline download includes every token and emblem.
- **Gate fixes:** typed steps in the snapshot adapter, and a stray `@ViewBuilder` removed. The native gate's runner uses
  Xcode 26.6.

## Verification
- **Signed source:** `codex/ios-build-34` at `a4877e5`:
  - `codex/engine-qol` at `1fb077a`;
  - merged with the `codex/ios-build-33` records;
  - plus the build-34 bump;
  - plus the Deck Studio Scryfall standalone fix.
- **Engine:**
  - new, from far-calls [run 37688048159](https://github.com/ineedsomesleep5/MagicMobile/actions/runs/37688048159) on
    candidate `def8fc8`;
  - native gate [run 37685619001](https://github.com/ineedsomesleep5/MagicMobile/actions/runs/37685619001) passed,
    including real-jvm;
  - staged with `controller.py stage-native`, with digest, hash receipt and engine-input equivalence checked.
- **`ios-fast` preflight:** passed, native decision `equivalent-source`. The first run failed the standalone Deck Studio
  compile; that is fixed.
- **Tests:**
  - `swift test`: 653 tests, 0 failures.
  - `MagicMobileTests`: 908 tests, 0 failures, on the merged app code (`dc141ed`).
  - The new UI test (Don't ask again, Resolve all) passed.
  - 10 board regression UI tests passed: choices, ability choice, mana payment, zone inspection, tavern pop-overs,
    landscape table, pass button, d20.
  - The engine's core and full real-engine suite passed locally on the regenerated classes.
- **Run:** `ios-0.1.1-34`, fingerprint `0a51ac61…22bf`, IPA SHA-256 `f3d58345…f73a`, delivery `9e69feee…`, Xcode 27.0.
- **Not verified:**
  - a physical iPhone or iPad;
  - a live game with sixteen Quest for the Goblin Lord triggers on the real engine. The engine actions are covered by
    real HumanPlayer tests and the UI by fixtures.
