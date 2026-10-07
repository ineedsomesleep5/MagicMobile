# Engine update: XMage dac400b and quality-of-life answer actions

Caleb asked on October 7, 2026 for one engine update that bundles the latest XMage with every engine-side
quality-of-life improvement. This replaces pin `4825513287ba6c42c32fd205d227f4a5fc44c2f3` with upstream
`dac400ba1380f17492c9ad6a65ab60f12f28cd97`: 221 commits from September 21 to October 7, 2026. That
range includes the 1.4.62 version bump, 74 new card files, 291 changed cards and the async-concede rework in
`HumanPlayer`/`PlayerResponse`. It does not by itself establish native execution, distribution or acceptance on a phone.

## XMage review and validation (automated review by Claude, labeled as such)

- **Detection digest:** `9392cb0d076fa37ccbe55f2460bcf4c066ce4aeb672f1139610944cd1e26d1e0`, 558 changed paths.
- **Dependencies:** only the 1.4.61→1.4.62 version bump and test-scope `assertj-core` 3.21.0→3.27.7.
- **Patched upstream files that changed:** `HumanPlayer.java` and `GameImpl.java`. Every exact-signature transformer still
  applies. The adapter change was `PlayerResponse.clear()` → `resetAnswers()` (commit `750d47c`).
- **Generated review digest:** `3d62229ed0744c6cf9785a5aaeb3eed99e9d8447b98e1fd9eeeed45aae1e9b8b`, accepted.
- **Catalogue:** 31,959 supported names, up from 31,881, with 93,420 printings. 197 printings were added and 119 removed.
  - Every removed name comes back under a new collector number (mostly LTC and MOC).
  - One name is newly excluded: Pool of Vigorous Growth, newly implemented upstream but printed only in the Arena-only
    Jumpstart: Historic Horizons, so it is not eternal.
- **Local maintenance run:**
  - It ran in `~/Documents/MagicMobile-xmage/candidate-dac400b` on the development Mac, with JDK 21 and Maven, under
    `scripts/dev/heavy.sh`.
  - `regenerate --execute` passed, and so did `validate --execute`:
    - catalogue self-test, export and check;
    - tooling and protocol suite, and native-boundary fixtures;
    - Swift protocol and app tests exporting fresh decks;
    - Swift-close and runtime-manager fixtures;
    - the real-engine suite and seeded soak;
    - the desktop-dependency audit;
    - real validation of the five bundled decks.
  - The receipt is `maintenance-validation.json` in that tree.
- **Remaining real XMage changes worth knowing:** a critical engine error now ends the game with a technical winner
  (highest life) instead of stopping it, and our bridge reports the winner as usual.

## Engine quality-of-life changes (one native build with the XMage update)

- **Answer actions** (`AnswerActions`, `docs/PROTOCOL.md` "Answer actions"). An answer may carry XMage desktop's own player
  actions:
  - remembered yes/no answers, by ability or by text;
  - a remembered trigger order (this card's trigger first);
  - pass until the stack resolves (F10);
  - pass priority after casting a spell;
  - resets.

  Keys come from the pending prompt's `originalId` and `autoAnswerMessage`, never from the client. Capabilities list
  `answerActions`.
- **AI pacing:** an AI that chose to pass with an opponent's ability on top of the stack passes again without another
  search while that stack only resolves. Sixteen quest-counter triggers no longer mean sixteen searches.
- **Tests:** `RealQueryTests` adds five suites:
  - validation and engine-derived keys;
  - real `HumanPlayer` remembered yes/no;
  - real trigger order;
  - the pass-after-cast preference;
  - the AI repeat-pass rule.

  21/21 passed against the regenerated `dac400b` classes.

## Remaining release gates

Run CI's real JVM gate on the integrated commit. Rebuild both native engines from it, using the iOS gate, then far-calls,
then product-device, plus the Android native build. Ship iOS and Android together, because relay tables require the same
upstream commit and catalogue. Keep marketing version 0.1.1.
