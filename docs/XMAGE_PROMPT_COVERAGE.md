# XMage Prompt Coverage Matrix

This matrix maps each MagicMobile/XMage prompt family to its implementation, unit test, bridge-source test, and live play verification coverage status. Simulator-only coverage is not live evidence.

| Prompt Family | Action Type | Covered by Unit Test? | Covered by Bridge Test? | Covered by Live Smoke? | Gaps & Blockers |
| :--- | :--- | :---: | :---: | :---: | :--- |
| **Keep Hand / Mulligan** | `keep_hand`, `mulligan` | Yes | Yes | Partial | `keep_hand` is live-smoked; repeated mulligan branch still needs targeted live proof. |
| **Play Land** | `play_land` | Yes | Yes | Yes | None. Standard land play fully works. |
| **Make Mana** | `make_mana` | Yes | Yes | Yes | None. Verified against real land taps and mana pool adjustments. |
| **Play Mana / Choose Mana** | `play_mana`, `choose_mana` | Yes | Yes | Partial | `play_mana` is deterministic-fixture proven through `GAME_PLAY_MANA`; explicit color-choice `choose_mana` needs targeted fixture proof. |
| **Cast Spell** | `cast_spell` | Yes | Yes | Yes | None. Casting simple spells from hand is covered. |
| **Activate Ability** | `activate_ability` | Yes | Yes | Yes | Deterministic gauntlet proves activation through Terramorphic Expanse, and `activated-ability-stack` proves targeted non-mana activation with `GAME_CHOOSE_ABILITY`, `GAME_TARGET`, stack observation, and resolution. |
| **Choose Target** | `choose_target` | Yes | Yes | Yes | Live-smoked for starting-player/combat/search-style callbacks and targeted activated ability selection; more targeted spell prompts still need fixture coverage. |
| **Choose Mode / Ability** | `choose_mode`, `choose_ability` | Yes | Yes | Yes | `choose_ability` is deterministic-fixture proven through Terramorphic Expanse and `activated-ability-stack`. `choose_mode` is deterministic-fixture proven through the targeted `prompt-mode` Lavabrink Venturer fixture; the smoke now submits a real `choose_mode` command and waits for an authoritative XMage snapshot where the chosen mode is reflected in card text. iOS command construction for both is unit-tested through `PromptCommandBuilder`. |
| **Choose Card / Player** | `choose_card`, `choose_player` | Yes | Yes | Partial | Player/target-style choices were live-smoked; explicit `choose_card` fixture still needed. |
| **Choose Pile** | `choose_pile` | Yes | Yes | No | Mapped and unit-tested, including iOS fail-closed command generation, but not live-smoked yet. |
| **Choose Amount** | `choose_amount`, `play_x_mana` | Yes | Yes | No | Mapped and unit-tested, including iOS fail-closed command generation, but not live-smoked yet. |
| **Choose Multi Amount** | `choose_multi_amount` | Yes | Yes | No | Mapped and unit-tested, including iOS command payload preservation, but not live-smoked yet. |
| **Order Triggers / Items** | `order_triggers`, `order_items` | Yes | Yes | No | Mapped and unit-tested; triggered-stack visibility is fixture-proven, but explicit multi-trigger ordering still needs a targeted XMage prompt. Next candidate is Soul Warden plus Spirited Companion. |
| **Search Select** | `search_select` | Yes | Yes | Partial | Search is deterministic-fixture proven through XMage's `GAME_TARGET`/`choose_target` library-selection path; explicit `search_select` callback fixture still needed. |
| **Commander Zone Choice** | `commander_replacement` | Yes | Yes | Yes | Deterministic gauntlet proves Swords-to-commander replacement and command-zone response. |
| **Answer Yes/No / Pay Cost** | `answer_yes_no`, `pay_cost` | Yes | Yes | Partial | Boolean confirmations and payment prompts are deterministic-fixture proven; add explicit pay-decline fixtures later. |
| **Concede** | `concede` | Yes | Yes | Yes | None. Concede action is always safe. |
| **Combat Attackers** | `declare_attackers` | Yes | Yes | Yes | Deterministic `commander-damage` fixture proves attacker-to-defender mapping and combat damage after the combat-selection Done response fix. |
| **Combat Blockers** | `declare_blockers` | Yes | Yes | Yes | Targeted `blocker-flow` fixture proved a real blocker prompt and submitted a blocker/attacker pair. Multi-attacker/blocker UI polish remains later scope. |
| **Damage Assignment** | `damage_assignment` | No | No | No | Active full-AI blocker. A probe scenario exists, but bridge emission/command handling, shared types, Swift decode, iOS UI, and real fixture proof are still missing. |

## Verification Details

1. **Unit Tests**: Mapped inside `apps/web/src/app/play/GameController.test.ts` and `apps/xmage-gateway/server.test.mjs`.
2. **Bridge Source Tests**: Bridge constraints on command mapping are asserted inside `apps/xmage-gateway/server.test.mjs`.
3. **Live Smoke Tests**: Verified only when the real Java bridge path passes. Simulator or mock success does not count.

Latest deterministic real bridge evidence from June 23, 2026:

```bash
ENABLE_XMAGE_FIXTURES=true NODE_ENV=test XMAGE_GATEWAY_URL=http://localhost:17171 XMAGE_SMOKE_SCENARIO=commander-gauntlet XMAGE_USE_FIXTURE=true pnpm smoke:xmage
```

The passing gauntlet report used real `source: "xmage-java-bridge"`, `fixtureCallUsed: true`, `directStateSeeded: true`, `seededStateVerified: true`, final `bridgeRevision: 133`, final `xmageCycle: 223`, and `stepsBlocked: []`. It exercised land play, mana, spell casting, pay-mana prompts, search selection through XMage's target callback, commander replacement, commander recast tax, stack presence, and AI waiting/progress. A later targeted `commander-damage` fixture passed on game `26816c39-99a2-478f-abb8-e17065c784e0` with final `bridgeRevision: 56`, final `xmageCycle: 94`, `commanderDamageChanges: [{ recipient: "ai-1", attacker: "human", damage: 2 }]`, and `stepsBlocked: []`. A targeted `triggered-ability-stack` fixture passed on game `578bbd14-38ce-44c9-83a5-d8de64af28ea` with final `bridgeRevision: 27`, final `xmageCycle: 51`, `routeFamiliesMissing: []`, and `stepsBlocked: []`.

The latest targeted `prompt-mode` proof on June 23, 2026 used game `22c1aafb-41f4-4d8c-a8c8-914b64a19a12`, real `source: "xmage-java-bridge"`, `fixtureCallUsed: true`, `directStateSeeded: true`, `seededStateVerified: true`, final `bridgeRevision: 51`, final `xmageCycle: 91`, `actionsByType.choose_mode: 1`, `promptMode.choiceSubmitted: true`, `promptMode.choiceResolved: true`, `routeFamiliesMissing: []`, and `stepsBlocked: []`. This proves the generic mode-choice route with Lavabrink Venturer's upstream `ChooseModeEffect`; it does not prove amount, multi-amount, pile, ordering, or damage-assignment prompts.

`commander-gauntlet` is the current full acceptance gate and uses the deterministic fixture route. It should only be marked live-verified when the JSON report has real gameplay proof, `source: "xmage-java-bridge"`, `fixtureCallUsed: true`, `directStateSeeded: true`, `seededStateVerified: true`, and no release-gate blockers.

`commander-gauntlet` reports route-family evidence directly through `routeFamiliesRequired`, `routeFamiliesSeen`, and `routeFamiliesMissing`. Its required families are `play_land`, `cast_spell`, `make_mana`, `activate_ability`, `search_select/choose_card`, `choose_target`, `answer_yes_no`, `pay_cost`, `commander_replacement`, `pass_priority`, `stack_object_seen`, `trigger_seen`, `zone_update_seen`, and `commander_tax_seen`.

`prompt-variety` is a route-family proof, not a count of any three prompts. It requires real XMage evidence for `stack_object_seen`, `activate_ability`, `choose_ability`, `choose_mode`, `order_triggers/order_items`, `choose_amount`, `choose_multi_amount`, and `choose_pile`. The standalone `prompt-variety` scenario remains red; `prompt-mode` is the first targeted prompt-variety slice and is now part of the stricter `commander-full-ai` gate. Do not describe full-product readiness until targeted fixture reports prove every required prompt family or explicitly exclude it with a safe iOS fallback.

`damage-assignment` is also part of the stricter full-AI gate. The current probe starts from a deterministic combat fixture, but no inspected bridge path emits or accepts a `damage_assignment` command yet. A passing blocker-flow or commander-damage report does not prove manual damage assignment.

Stack snapshots now carry source name/id, paid status, and rules text from `GameView.getStack()`. Controller and target ids are emitted only when the XMage stack `CardView` exposes them; iOS needs its Swift model widened before those optional controller/target fields can be shown on device.
