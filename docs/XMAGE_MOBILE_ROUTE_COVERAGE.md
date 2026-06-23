# XMage Mobile Route Coverage

MagicMobile is Commander-only for the current product milestone. The app should behave like a mobile XMage client: XMage owns rules, legality, priority, stack, prompts, AI, and Commander state. Fixture cards such as Sol Ring, Evolving Wilds, a commander with an ETB trigger, or a removal spell are proof cases only. Do not add card-specific routes unless the change fixes a generic XMage action, prompt, stack, or zone path.

## Route Rule

Every gameplay action must follow this chain:

1. XMage exposes state, playable objects, or a callback prompt.
2. The Java bridge preserves exact XMage ids and prompt metadata.
3. Shared `LegalAction`, `PromptEnvelopeV2`, or `GameCommand` carries the needed ids without client guessing.
4. iOS/web render a safe mobile surface for that generic route.
5. The client submits only exact prompt/action data.
6. XMage returns the authoritative snapshot.

If any step is missing, the UI should show a visible unsupported/incomplete action state and refresh from the latest snapshot. It must not auto-pick the first option, default yes, default pile 1, default amount 0, default colorless mana, or default command-zone replacement.

For normal card clicks, match XMage desktop behavior: `play_land`, normal `cast_spell`, and basic `make_mana` submit the source card UUID. Only explicit ability choices, such as non-mana activated abilities, submit a selected ability UUID.

## Current Generic Route Status

| Route family | Current status | Verification standard | Remaining work |
|---|---|---|---|
| Dev-only fixture harness | Gateway route exists at `POST /dev/xmage-fixtures/commander`, guarded by `ENABLE_XMAGE_FIXTURES=true` and `NODE_ENV !== production`. It returns `fixtureHarness` metadata and currently falls back to deterministic real-XMage decks because direct server-side state seeding is unavailable. | `XMAGE_USE_FIXTURE=true` smoke must return `fixtureHarness.enabled: true`, `source: xmage-java-bridge`, and `directStateSeeded: false` until an in-server setup hook exists. | Add an XMage server-side fixture hook or upstream-supported setup path that can seed hand/library/battlefield/phase/priority without faking gameplay. |
| Keep/mulligan | Routed through legal actions. | Real `smoke:xmage` opening hand flow. | Add repeated mulligan smoke branch. |
| Play land | Routed through XMage legal action ids. | Real smoke proves a land moves only after snapshot. | Keep drag-to-play using this same action. |
| Cast spell | Routed through legal actions and stack snapshots. | Real smoke proves stack object and snapshot update. | Add richer stack metadata assertions. |
| Make mana | Routed through source ids and mana actions. | Real smoke proves land/mana source activation. | Verify non-land mana rocks through deterministic fixture. |
| Play/choose mana | Prompt route exists and now requires explicit mana choice from the real human `ManaPoolView`. | General real-XMage smoke proves no fake colorless choice for generic costs. | Keep native/web fail-closed behavior and add non-land mana-rock fixture. |
| Activate ability | Generic action exists; mana-vs-non-mana land ability classification was tightened. | Real fixture with non-mana activated ability. | Ensure labels preserve XMage ability text. |
| Choose target/card/player | Prompt route exists; UUID clicks now match XMage desktop by sending the UUID without an immediate boolean cancel/done response. | Real prompt fixture with each choice kind. | Add min/max UI selection polish and targeted startup reliability. |
| Choose mode/ability | Prompt route exists. | Real modal spell or ability fixture. | No default first mode. |
| Choose pile | Prompt route exists and clients now require explicit pile. | Real split-pile fixture. | Add iOS/web pile sheet polish. |
| Choose amount / X mana | Prompt route exists and clients now require explicit amount. | Real amount fixture. | Add bounded numeric picker using XMage min/max. |
| Choose multi amount | Prompt route exists and clients now require explicit amounts. | Real multi-amount fixture. | Add multi-field prompt UI. |
| Pay cost / answer yes-no | Prompt route exists and clients now require explicit bool/template. | Real pay/decline and confirmation fixtures. | Keep command templates complete. |
| Search/select | Prompt route exists. | Real library search fixture. | Mobile search drawer and min/max validation. |
| Order triggers/items | Prompt route exists. | Real trigger-order fixture. | Reorderable mobile UI. |
| Commander replacement | Prompt route exists and clients now require explicit replacement choice. | Real death/exile commander fixture. | Surface command-zone/original-zone choice clearly. |
| Declare attackers/blockers | Typed payloads exist. | Real combat fixture for attackers; blocker fixture still needed. | Add blocker and damage-assignment fixtures. |
| Stack objects | Stack zone exists. | Real cast/resolve fixture with source/controller/rules text. | Enrich metadata and mobile stack drawer. |
| Commander tax/damage | Snapshot fields exist, but the latest focused gate is not green. Older artifacts observed tax/damage; current release proof is blocked by real AI priority stalls before deterministic commander combat can be reproved. | `commander-state` smoke must report non-empty tax and damage changes on the current bridge before this is treated as live-verified. | Keep parsing tied to XMage data only and make the targeted smoke AI-stall-resistant without faking combat. |

## Fail-Closed Client Policy

iOS and web should submit no command when XMage does not expose enough data for a route. Current examples:

- `choose_pile` requires pile `1` or `2`.
- `choose_amount` and `play_x_mana` require a finite amount.
- `choose_mana` and `play_mana` require `W`, `U`, `B`, `R`, `G`, or `C`.
- `answer_yes_no`, `pay_cost`, and `commander_replacement` require an explicit boolean or exact replacement target.
- Unknown action types are unsupported until the bridge/shared contracts define them.

This is intentional. A visible unsupported prompt is better than a wrong game action.

## Smoke Fixtures

Representative fixtures should prove generic routes:

- Sol Ring or Arcane Signet proves generic artifact spell, mana-rock activation, and play/choose mana.
- Evolving Wilds proves generic land activated ability, search/select, shuffle, and zone movement.
- An ETB commander proves generic cast from command zone, trigger stack object, and optional/target prompts.
- A kill spell proves generic target selection, stack resolution, commander replacement, commander tax, and commander damage continuity.

Do not make bridge code recognize these card names. If a fixture fails, fix the underlying route or mark the route incomplete.

Current fixture harness command:

```sh
ENABLE_XMAGE_FIXTURES=true XMAGE_GATEWAY_URL=http://localhost:17171 XMAGE_SMOKE_SCENARIO=commander-gauntlet XMAGE_USE_FIXTURE=true pnpm smoke:xmage
```

The route is intentionally dev/test-only and production-disabled. Today it can create deterministic legal Commander decks through the real bridge and report fallback metadata, but it cannot yet seed exact game zones because `MagicMobileBridge` is a remote XMage `Session` client and does not hold the server-side `Game` instance required for `Game.cheat(...)`.
