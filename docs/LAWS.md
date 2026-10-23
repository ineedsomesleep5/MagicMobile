# Laws

A law is a rule the code must keep for **every** input, not just the cases a test author thought of. Each law runs against
hundreds of seeded random inputs on every CI run, so an edit that breaks it fails the PR. The idea comes from Bend's
`law` declarations (Caleb, 2026-10-23); we check laws with seeded random cases instead of proofs, in the languages we
already use. The laws ship nothing: they're test code only.

## Where they live
- **Kotlin:** `apps/android/core/src/test/kotlin/io/magicmobile/android/laws/` (`Laws.forAll`), run by `:core:test`.
- **Swift:** `apps/ios/MagicMobileTests/LawsTests.swift` (`forAll`, `law`), run by the package tests (`swift test --package-path apps/ios`).

## The laws
| Law | Kotlin | Swift |
| --- | --- | --- |
| Deck JSON export reads back as the same deck, printings included | ✓ | |
| Deck text export keeps every card count, for real awkward card names | ✓ | |
| Adding then removing copies of a card restores the deck | ✓ | |
| Rank points and ranks convert both ways; more points never mean a lower rank | ✓ | ✓ |
| A win always gains, a loss never gains or leaves its tier, a draw changes nothing; peak never falls | ✓ | ✓ |
| A new season never raises a rank and starts fresh | ✓ | ✓ |
| A saved game (`resume.json`) and its settings read back exactly | ✓ | |
| Every Arena board control's touch target stays on screen on every phone, both orientations | ✓ | ✓ |

The layout law found a real bug on its first run: the gear's 44 pt target still left the screen on 360–372 pt phones,
so the gear moved (landscape y 28, portrait 412, 30).

## Writing one
- State the rule in plain words first; that sentence is the law's name and its failure message.
- Generate realistic inputs (real card names, real screen sizes), not only random strings.
- Check a law catches a bug: plant one, watch it fail, restore the code.
- A failure prints its seed and case. Replay it with `forAll(name, seed = <seed>, runs = 1)` (Kotlin) or
  `forAll(name, runs: 1, seed: <seed>)` (Swift).
- Deeper local run (Kotlin): `apps/android/gradlew -p apps/android :core:test -Plaws.runs=20000 --tests "io.magicmobile.android.laws.*"`.
