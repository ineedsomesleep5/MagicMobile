# Existing portrait gameplay is the product surface

Caleb confirmed this requirement on 2026-09-11. Commander with real on-device XMage is the primary goal; preserve and improve the in-progress vertical playing mode. Do not substitute the engine laboratory UI or a remote engine fallback.

## Verified existing integration boundary

The installed worktree preserves `apps/ios/MagicMobile/ContentView.swift` unchanged. Its `ImmersivePlayShell` accepts a `GameSnapshot`, selections, pending/rejection state, `runAction`, `runCommand`, lifecycle callbacks, and the portrait preference. It feeds `NativeGameView` and `portraitGameContent`, including hand, battlefield, mana payment, targeting, combat arrows, stack, zones and commander controls.

The new protocol is not the previous gateway snapshot. Connect it through a local session controller and explicit presentation/response adapters:

- Map the per-seat `MatchPoll.snapshot.gameView` into `GameSnapshot`, preserving engine UUIDs separately from authenticated seat IDs. Convert UUID-keyed collections, card types, counters, string power/toughness and named mana colors deliberately.
- Replace the presentation assumption that the viewer is `human` and the opponent is `ai-1`. Four-human Commander needs visible opponent selection and explicit combat-arrow/HUD identity mapping while retaining the vertical layout.
- Represent private hand/library **counts** without fabricating hidden card arrays. Preserve authorized looked-at/revealed cards and face-down redaction. Command-zone entries also include emblems/dungeons; do not label every entry a commander or invent unreported tax/damage values.
- Build actions from the actual prompt and `canPlayObjects`. Do not infer playability from card types or displayed mana. Reuse prompt widgets with the exact typed answer contract, including boolean pile selection, UUID targets/modes/abilities, ordered choices, allocations and mana player identity.
- Advance aggregate combat selections through each actual upstream prompt; never dispatch a guessed batch of UUID responses. Reconcile submitted/consumed state with polling. Poll revision and prompt revision are different; retain the same request UUID for retries.

## Acceptance

Preserve the existing portrait geometry tests (430×932 with 59/34 safe insets, card proportions/minimum widths, overflow, drop zones, combat anchors, control containment and separation). Add real-engine snapshot/response fixtures, four-player targeting, private counts, stale/submitted responses and interruption tests.

The native engine gate still precedes switching the primary experience. The laboratory's separate `.ondevice` bundle is not the existing TestFlight product. Release through `com.calebfeliciano.magicmobile` only after actual iOS linkage and gameplay validation; retain portrait and landscape support.

This document records inspected interfaces and acceptance constraints, not completed integration or a fresh iOS test pass.
