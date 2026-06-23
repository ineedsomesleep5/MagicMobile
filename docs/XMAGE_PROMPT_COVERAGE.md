# XMage Prompt Coverage Matrix

This matrix maps each MagicMobile/XMage prompt family to its implementation, unit test, bridge-source test, and live play verification coverage status. Simulator-only coverage is not live evidence.

| Prompt Family | Action Type | Covered by Unit Test? | Covered by Bridge Test? | Covered by Live Smoke? | Gaps & Blockers |
| :--- | :--- | :---: | :---: | :---: | :--- |
| **Keep Hand / Mulligan** | `keep_hand`, `mulligan` | Yes | Yes | Partial | `keep_hand` is live-smoked; repeated mulligan branch still needs targeted live proof. |
| **Play Land** | `play_land` | Yes | Yes | Yes | None. Standard land play fully works. |
| **Make Mana** | `make_mana` | Yes | Yes | Yes | None. Verified against real land taps and mana pool adjustments. |
| **Play Mana / Choose Mana** | `play_mana`, `choose_mana` | Yes | Yes | Partial | `play_mana` is deterministic-fixture proven through `GAME_PLAY_MANA`; explicit color-choice `choose_mana` needs targeted fixture proof. |
| **Cast Spell** | `cast_spell` | Yes | Yes | Yes | None. Casting simple spells from hand is covered. |
| **Activate Ability** | `activate_ability` | Yes | Yes | Partial | Deterministic gauntlet proves no-target activation through Terramorphic Expanse; targeted activated-ability stack proof remains later scope. |
| **Choose Target** | `choose_target` | Yes | Yes | Yes | Live-smoked for starting-player/combat/search-style target callbacks; more targeted spell prompts still need fixture coverage. |
| **Choose Mode / Ability** | `choose_mode`, `choose_ability` | Yes | Yes | Partial | `choose_ability` is live-proven through Terramorphic Expanse; `choose_mode` still needs targeted fixture proof. |
| **Choose Card / Player** | `choose_card`, `choose_player` | Yes | Yes | Partial | Player/target-style choices were live-smoked; explicit `choose_card` fixture still needed. |
| **Choose Pile** | `choose_pile` | Yes | Yes | No | Mapped and unit-tested, but not live-smoked yet. |
| **Choose Amount** | `choose_amount`, `play_x_mana` | Yes | Yes | No | Mapped and unit-tested, but not live-smoked yet. |
| **Choose Multi Amount** | `choose_multi_amount` | Yes | Yes | No | Mapped and unit-tested, but not live-smoked yet. |
| **Order Triggers / Items** | `order_triggers`, `order_items` | Yes | Yes | No | Mapped and unit-tested; targeted trigger/order fixture proof remains later scope. |
| **Search Select** | `search_select` | Yes | Yes | Partial | Search is deterministic-fixture proven through XMage's `GAME_TARGET`/`choose_target` library-selection path; explicit `search_select` callback fixture still needed. |
| **Commander Zone Choice** | `commander_replacement` | Yes | Yes | Yes | Deterministic gauntlet proves Swords-to-commander replacement and command-zone response. |
| **Answer Yes/No / Pay Cost** | `answer_yes_no`, `pay_cost` | Yes | Yes | Partial | Boolean confirmations and payment prompts are deterministic-fixture proven; add explicit pay-decline fixtures later. |
| **Concede** | `concede` | Yes | Yes | Yes | None. Concede action is always safe. |
| **Combat Attackers** | `declare_attackers` | Yes | Yes | Yes | None. Pair-payload attacker-to-defender mapping verified. |
| **Combat Blockers** | `declare_blockers` | Yes | Yes | No | Pair payload exists; no live fixture forced a real blocker prompt yet. |

## Verification Details

1. **Unit Tests**: Mapped inside `apps/web/src/app/play/GameController.test.ts` and `apps/xmage-gateway/server.test.mjs`.
2. **Bridge Source Tests**: Bridge constraints on command mapping are asserted inside `apps/xmage-gateway/server.test.mjs`.
3. **Live Smoke Tests**: Verified only when the real Java bridge path passes. Simulator or mock success does not count.

Latest deterministic real bridge evidence from June 23, 2026:

```bash
ENABLE_XMAGE_FIXTURES=true NODE_ENV=test XMAGE_GATEWAY_URL=http://localhost:17171 XMAGE_SMOKE_SCENARIO=commander-gauntlet XMAGE_USE_FIXTURE=true pnpm smoke:xmage
```

The passing report used game `e9478822-a5fd-4b04-a691-2c2da193b3ac`, `source: "xmage-java-bridge"`, `fixtureCallUsed: true`, `directStateSeeded: true`, `seededStateVerified: true`, final `bridgeRevision: 115`, final `xmageCycle: 196`, and `stepsBlocked: []`. It exercised land play, mana, spell casting, pay-mana prompts, search selection through XMage's target callback, commander replacement, commander recast tax, stack presence, and AI waiting/progress.

`commander-gauntlet` is the current full acceptance gate and uses the deterministic fixture route. It should only be marked live-verified when the JSON report has real gameplay proof, `source: "xmage-java-bridge"`, `fixtureCallUsed: true`, `directStateSeeded: true`, `seededStateVerified: true`, and no release-gate blockers.

`commander-gauntlet` reports route-family evidence directly through `routeFamiliesRequired`, `routeFamiliesSeen`, and `routeFamiliesMissing`. Its required families are `play_land`, `cast_spell`, `make_mana`, `activate_ability`, `search_select/choose_card`, `choose_target`, `answer_yes_no`, `pay_cost`, `commander_replacement`, `pass_priority`, `stack_object_seen`, `trigger_seen`, `zone_update_seen`, and `commander_tax_seen`.

`prompt-variety` is a route-family proof, not a count of any three prompts. It requires real XMage evidence for `stack_object_seen`, `activate_ability`, `choose_ability`, `choose_mode`, `order_triggers/order_items`, `choose_amount`, `choose_multi_amount`, and `choose_pile`. It remains later scope until targeted fixture reports prove those prompt families.

Stack snapshots now carry source name/id, paid status, and rules text from `GameView.getStack()`. Controller and target ids are emitted only when the XMage stack `CardView` exposes them; iOS needs its Swift model widened before those optional controller/target fields can be shown on device.
