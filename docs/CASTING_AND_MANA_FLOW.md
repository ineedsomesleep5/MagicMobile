# Casting And Mana Payment Flow

MagicMobile must make XMage legal actions easy to perform without becoming a second Magic rules engine.

## Expected Flow

1. The player taps a hand card.
2. The client selects/focuses the card.
3. If XMage exposes `cast_spell` or `play_land`, the UI shows that action clearly.
4. The player can press the action button or drag the card to the battlefield shortcut.
5. The client submits the exact `LegalAction` / `commandTemplate` from XMage.
6. If XMage asks for mana, payment, targets, modes, or another prompt, the UI renders that prompt.
7. During mana/payment prompts, source-based `make_mana` actions should appear before generic mana buttons.
8. Real card movement happens only after an authoritative XMage snapshot confirms the new zone.

## Arcane Signet Regression

The key manual regression is: two untapped lands on battlefield, `Arcane Signet` in hand.

- Selecting `Arcane Signet` should show a primary `Cast` action if XMage says it is legal.
- The user should not have to pre-tap lands before pressing `Cast`.
- If XMage asks for payment, the app should list available mana sources from `make_mana` legal actions.
- If XMage does not expose a cast action, the UI must explain that instead of silently doing nothing.

## Source Of Truth

- XMage owns legality, costs, priority, stack, prompts, mana choices, and final zones.
- The client may show pending feedback, but it must reconcile to the next ordered XMage snapshot.
- Simulator behavior is only a development aid and cannot prove real gameplay correctness.
