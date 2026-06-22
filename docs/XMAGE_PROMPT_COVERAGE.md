# XMage Prompt Coverage Matrix

This matrix maps each MagicMobile/XMage prompt family to its implementation, unit test, and live play verification coverage status.

| Prompt Family | Action Type | Covered by Unit Test? | Covered by Bridge Test? | Covered by Live Smoke? | Gaps & Blockers |
| :--- | :--- | :---: | :---: | :---: | :--- |
| **Keep Hand / Mulligan** | `keep_hand`, `mulligan` | Yes | Yes | Yes | None. Shuffling and initial hand decision is fully covered. |
| **Play Land** | `play_land` | Yes | Yes | Yes | None. Standard land play fully works. |
| **Make Mana** | `make_mana` | Yes | Yes | Yes | None. Verified against real land taps and mana pool adjustments. |
| **Play Mana / Choose Mana** | `play_mana`, `choose_mana` | Yes | Yes | Yes | None. Prompt-level mana payments and choices are verified. |
| **Cast Spell** | `cast_spell` | Yes | Yes | Yes | None. Casting simple spells from hand is covered. |
| **Activate Ability** | `activate_ability` | Yes | Yes | Yes | None. Activated abilities on permanents are verified. |
| **Choose Target** | `choose_target` | Yes | Yes | Yes | None. Targeted spells and abilities choose valid targets strictly. |
| **Choose Mode / Ability** | `choose_mode`, `choose_ability` | Yes | Yes | Yes | None. Multi-option choose pickers are mapped and tested. |
| **Choose Card / Player** | `choose_card`, `choose_player` | Yes | Yes | Yes | None. Mapped for search, discard, and player-targeted effects. |
| **Choose Pile** | `choose_pile` | Yes | Yes | Yes | None. Mapped to boolean pile selector. |
| **Choose Amount** | `choose_amount`, `play_x_mana` | Yes | Yes | Yes | None. Checked against X mana payments and scaling costs. |
| **Choose Multi Amount** | `choose_multi_amount` | Yes | Yes | Yes | None. String-joined array inputs sent to bridge. |
| **Order Triggers / Items** | `order_triggers`, `order_items` | Yes | Yes | Yes | None. Order list of item UUIDs mapped. |
| **Search Select** | `search_select` | Yes | Yes | Yes | None. Library and zone searches display card lists. |
| **Commander Zone Choice** | `commander_replacement` | Yes | Yes | Yes | None. Death/exile command zone decision mapped. |
| **Answer Yes/No / Pay Cost** | `answer_yes_no`, `pay_cost` | Yes | Yes | Yes | None. Boolean confirmations are strictly checked. |
| **Concede** | `concede` | Yes | Yes | Yes | None. Concede action is always safe. |
| **Combat Attackers** | `declare_attackers` | Yes | Yes | Yes | None. Pair-payload attacker-to-defender mapping verified. |
| **Combat Blockers** | `declare_blockers` | Yes | Yes | Yes | None. Pair-payload blocker-to-attacker mapping verified. |

## Verification Details

1. **Unit Tests**: Mapped inside `apps/web/src/app/play/GameController.test.ts` and `apps/xmage-gateway/server.test.mjs`.
2. **Bridge Source Tests**: Bridge constraints on command mapping are asserted inside `apps/xmage-gateway/server.test.mjs`.
3. **Live Smoke Tests**: Verified in `pnpm smoke:xmage` against the live rules engine stack.
