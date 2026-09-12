# Existing portrait gameplay is the product surface

The product remains `apps/ios`, bundle `com.calebfeliciano.magicmobile`, not
`apps/ios-ondevice` (the diagnostic harness). Native-linked Release now opens
local setup/session and preserves the portrait board and landscape support.
An unlinked Release reports a missing engine, never a remote rules fallback.

## Implemented integration

`OnDeviceSession`, `OnDeviceSnapshotAdapter` and `OnDevicePromptAdapter` map
per-seat XMage projections into the existing `GameSnapshot` / `ImmersivePlayShell`
and exact typed responses. Setup includes names, bundled/imported local decks,
1–3 MAD opponents and 2–4 Game Center human seats.

- Authenticated seats and engine UUIDs remain distinct; four-seat opponent focus
  does not assume fixed human/AI identities.
- Private hands/libraries remain counts unless views are explicitly authorized.
  Looked-at/revealed/exile/companion and controlled-turn data are engine supplied.
  Face-down identities are not reconstructed from the catalogue.
- Actions come from actual prompts and `canPlayObjects`, not displayed card types.
  Floating mana uses the acting player and named colors. Exact special responses,
  including empty metadata, are preserved; X/payment details remain reachable.
- Combat/targets advance through individual prompts. Declared attackers can be
  deselected, including authorized controlled turns. Nested control is unsupported.
- Commander tax/damage remains per commander; zone confirmation follows the actual
  decision. Private notices reach a bounded, nonpersistent, per-session log.

See the [source/control ledger](ISSUE4_SOURCE_CONTROL_LEDGER.md) for regression
entrypoints. 108 portable app tests and real JVM projections passed for uploaded
source `62789b0`; actual native-linked device Release and signing/export passed.

## Unexecuted acceptance

Builds do not prove rendered geometry, gestures or phone gameplay. Preserve the
430×932 portrait geometry contract with 59/34 safe insets, card proportions,
overflow/drop zones, combat anchors and separated contained controls. Simulator/UI
execution is not authorized for this phase.

TestFlight must cover portrait/landscape, four-player targeting, private zones,
full payment details, large text, VoiceOver and interruptions. These remain
**NOT RUN**; see [TESTFLIGHT_ACCEPTANCE.md](TESTFLIGHT_ACCEPTANCE.md).
