# XMage Prompt Coverage Matrix

This matrix maps each MagicMobile/XMage prompt family to its implementation, unit test, and live play verification coverage status.

| Prompt Family | Action Type | Covered by Unit Test? | Covered by Bridge Test? | Covered by Live Smoke? | Gaps & Blockers |
| :--- | :--- | :---: | :---: | :---: | :--- |
| **Keep Hand / Mulligan** | `keep_hand`, `mulligan` | Yes | Yes | Yes | None. Shuffling and initial hand decision is fully covered. |
| **Play Land** | `play_land` | Yes | Yes | Yes | None. Standard land play fully works. |
| **Make Mana** | `make_mana` | Yes | Yes | Yes | None. Verified against real land taps and mana pool adjustments. |
| **Play Mana / Choose Mana** | `play_mana`, `choose_mana` | Yes | Yes | Yes | None. Prompt-level mana payments and choices are verified. |
| **Cast Spell** | `cast_spell` | Yes | Yes | Yes | None. Casting simple spells from hand is covered. |
| **Activate Ability** | `activate_ability` | Yes | Yes | Partial | Transport exists; needs a targeted real-XMage fixture with an activated non-mana ability. |
| **Choose Target** | `choose_target` | Yes | Yes | Yes | Live-smoked for starting-player/combat/search-style target callbacks; more targeted spell prompts still need fixture coverage. |
| **Choose Mode / Ability** | `choose_mode`, `choose_ability` | Yes | Yes | No | Mapped and unit-tested, but not live-smoked yet. |
| **Choose Card / Player** | `choose_card`, `choose_player` | Yes | Yes | Partial | Player/target-style choices were live-smoked; explicit `choose_card` fixture still needed. |
| **Choose Pile** | `choose_pile` | Yes | Yes | No | Mapped and unit-tested, but not live-smoked yet. |
| **Choose Amount** | `choose_amount`, `play_x_mana` | Yes | Yes | No | Mapped and unit-tested, but not live-smoked yet. |
| **Choose Multi Amount** | `choose_multi_amount` | Yes | Yes | No | Mapped and unit-tested, but not live-smoked yet. |
| **Order Triggers / Items** | `order_triggers`, `order_items` | Yes | Yes | No | Mapped and unit-tested, but not live-smoked yet. |
| **Search Select** | `search_select` | Yes | Yes | Partial | Search-like multi-card target selection was live-smoked; explicit `search_select` command fixture still needed. |
| **Commander Zone Choice** | `commander_replacement` | Yes | Yes | No | Mapped, but commander death/exile replacement prompt is not live-fixtured yet. |
| **Answer Yes/No / Pay Cost** | `answer_yes_no`, `pay_cost` | Yes | Yes | Yes | None. Boolean confirmations are strictly checked. |
| **Concede** | `concede` | Yes | Yes | Yes | None. Concede action is always safe. |
| **Combat Attackers** | `declare_attackers` | Yes | Yes | Yes | None. Pair-payload attacker-to-defender mapping verified. |
| **Combat Blockers** | `declare_blockers` | Yes | Yes | No | Pair payload exists; no live fixture forced a real blocker prompt yet. |

## Verification Details

1. **Unit Tests**: Mapped inside `apps/web/src/app/play/GameController.test.ts` and `apps/xmage-gateway/server.test.mjs`.
2. **Bridge Source Tests**: Bridge constraints on command mapping are asserted inside `apps/xmage-gateway/server.test.mjs`.
3. **Live Smoke Tests**: Verified only when the real Java bridge path passes. Simulator or mock success does not count.

Latest real bridge evidence from June 22, 2026:

```bash
XMAGE_GATEWAY_URL=http://localhost:17171 pnpm smoke:xmage
XMAGE_GATEWAY_URL=http://localhost:17171 XMAGE_SMOKE_SCENARIO=combat pnpm smoke:xmage
XMAGE_GATEWAY_URL=http://localhost:17171 XMAGE_SMOKE_SCENARIO=commander-state pnpm smoke:xmage
```

The broad smoke reached turn 5 on source `xmage-java-bridge` and exercised keep, land play, mana, spell casting, pay-mana prompts, pass priority, stack presence, combat steps, and AI waiting/progress. The `combat` fixture exposed and submitted typed `declare_attackers`. The `commander-state` fixture proved commander tax and commander damage through XMage snapshots. The attempted `arcane-signet` fixture is not counted because XMage correctly rejected its repeated nonbasic cards under Commander legality.
