# XMage Mobile Playtest Checklist

Use this checklist when validating the XMage-backed Commander play loop from Docker, web, or an iPhone build. The current product scope is Commander-only digital play. The production play route must use XMage through the gateway and Java bridge; the simulator is only for `/dev/play-simulator`.

## Preflight

- [ ] Confirm Docker Compose config renders cleanly:

  ```sh
  docker compose config
  ```

- [ ] Start the XMage stack:

  ```sh
  pnpm dev:xmage
  ```

- [ ] Confirm gateway health is ready:

  ```sh
  curl -fsS http://localhost:17171/health
  ```

- [ ] Run the gateway smoke script against the live stack:

  ```sh
  XMAGE_GATEWAY_URL=http://localhost:17171 pnpm smoke:xmage
  XMAGE_GATEWAY_URL=http://localhost:17171 XMAGE_SMOKE_SCENARIO=combat pnpm smoke:xmage
  XMAGE_GATEWAY_URL=http://localhost:17171 XMAGE_SMOKE_SCENARIO=commander-state pnpm smoke:xmage
  ```

Expected result: health reports `ready`, the smoke output includes a game id, source, completed play-loop steps, and advancing `bridgeRevision` / `xmageCycle` when the Java bridge is active.

If the live smoke fails, capture the exact failing step instead of treating simulator success as product success. Current high-value failures are usually in pass priority, AI waiting, stale prompt answers, or a missing legal action after XMage changes state.

## Latest Verified Local Smoke

Verified on June 22, 2026 against the local Docker gateway at `http://localhost:17171`.

Commands run:

```sh
docker compose config --quiet
docker build -t magicmobile-xmage-bridge-check apps/xmage-gateway/bridge
pnpm --filter @magicmobile/xmage-gateway test
pnpm typecheck
docker compose up -d --build xmage-bridge xmage-gateway
XMAGE_GATEWAY_URL=http://localhost:17171 pnpm smoke:xmage
XMAGE_GATEWAY_URL=http://localhost:17171 XMAGE_SMOKE_SCENARIO=combat pnpm smoke:xmage
XMAGE_GATEWAY_URL=http://localhost:17171 XMAGE_SMOKE_SCENARIO=commander-state pnpm smoke:xmage
```

The Docker services were running, the bridge container was rebuilt, the gateway was restarted to pick up local source changes, and the smoke test used the live gateway/Java bridge path.

Current bridge health during smoke:

```json
{
  "status": "ready",
  "reason": "XMage Java bridge connected to 127.0.0.1:17171.",
  "recoveryAction": "wait"
}
```

Smoke result: passed.

Final broad smoke output:

- `gameId`: `a99ba08e-f04f-41d7-bd9b-ac3e451c51f0`
- `source`: `xmage-java-bridge`
- `bridgeRevision`: `242`
- `xmageCycle`: `414`
- `phase` / `step`: `precombat-main`
- `turn`: `9`
- `promptText`: `Waiting for AI`
- `promptChecks`: `GAME_TARGET:target`, `GAME_ASK:confirmation`, `GAME_PLAY_MANA:mana`

Targeted fixture smoke outputs:

- `XMAGE_SMOKE_SCENARIO=combat`: passed with `combatExercised: true` after submitting `declare_attackers: Attack Noaddrag with Isamaru, Hound of Konda`.
- `XMAGE_SMOKE_SCENARIO=commander-state`: passed with `combatExercised: true`, `commanderTaxChanges: [{ "playerId": "human", "tax": 2, "turn": 2 }]`, `commanderDamageChanges: [{ "recipient": "ai-1", "attacker": "human", "damage": 2, "turn": 4 }]`, and AI life at `38`.

Confirmed live steps across the local verification run:

- created a real Commander game with `source: "xmage-java-bridge"`
- received numeric `bridgeRevision`
- received `xmageCycle`
- kept opening hand
- played a land
- made mana from a real battlefield source
- passed through AI turns until a castable spell appeared
- answered a real mana-payment prompt through `PromptEnvelopeV2`
- cast multiple simple spells
- answered a real target prompt with a named card choice
- submitted typed combat pair payloads for real blockers in the broad smoke
- submitted a typed attacker-to-defender payload in the deterministic combat fixture
- verified commander tax from XMage command-card rules text
- verified commander damage from XMage command-card rules text and a changed life total
- passed priority
- ended in a real XMage priority state instead of mock/simulator state

Failures fixed during this verification:

- `make_mana` advanced the revision but did not add mana because the bridge sent the mana ability UUID where XMage expected the source permanent UUID for normal card clicks.
- command responses that advanced only `xmageCycle` were incorrectly returned as pending, leaving clients with only `concede` legal actions.
- mana-payment prompts exposed only generic `play_mana` choices and did not expose real untapped battlefield mana sources.
- the smoke helper was pre-tapping lands while searching for a cast action, which could hide the real castable spell state.
- commander tax and damage parsed directly from rules text in the bridge.
- prompt choice legal actions used raw UUID labels for library/search-style prompts, which made the smoke runner pick an invalid nonland for `Select a basic land card`.
- `PermanentView.isCanAttack()` / `isCanBlock()` was too conservative for the client view, so combat legal actions now use the current XMage combat step plus visible untapped creatures and still let XMage validate the submitted UUIDs.
- the smoke runner now treats recovered stale-action `409`s as a refresh-and-retry path rather than counting them as semantic progress.

Remaining live-coverage gaps:

- player-scoped snapshots are still required before human-vs-human or pods.
- damage assignment prompts have not been live-fixtured yet because the current Commander fixture does not produce a manual damage-assignment prompt.

## Web Play Loop

- [ ] Open `http://localhost:3000/play`.
- [ ] Confirm `/play` refuses to run without XMage health instead of falling back to the simulator.
- [ ] Confirm `/dev/play-simulator` is clearly labeled as simulator/dev mode.
- [ ] Create or enter a Commander game backed by the XMage gateway.
- [ ] Keep the opening hand when the mulligan prompt appears.
- [ ] Play a land from hand.
- [ ] Tap the land or another mana source with a `make_mana` action.
- [ ] Cast a simple legal spell from hand.
- [ ] Confirm the spell appears on the stack when XMage exposes stack state.
- [ ] Pass priority.
- [ ] Respond to at least one real `promptEnvelopeV2` prompt if XMage asks for a target, card, player, amount, mana, mode, ability, yes/no answer, or commander replacement choice.
- [ ] Confirm the battlefield, hand, stack, prompt text, and legal actions update without refreshing the page.
- [ ] Confirm stale snapshots do not replace newer snapshots. In debug output, `bridgeRevision` should not go backward.
- [ ] When XMage asks for a choice, confirm `promptEnvelopeV2` appears in the debug view and the UI exposes a matching response action.
- [ ] Confirm `pendingStatus: "waiting_for_xmage"` shows a waiting state instead of freezing the UI.
- [ ] Confirm AI turns show AI waiting/thinking rather than a dead screen.
- [ ] Confirm missing card art renders a placeholder and does not block gameplay.

### Casting And Mana Payment Regression

- [ ] Reach a state with at least two untapped mana sources on your battlefield and `Arcane Signet` or another two-mana spell in hand.
- [ ] Select the hand card and confirm the context panel shows a primary `Cast` action.
- [ ] Run the cast action without manually pre-tapping lands.
- [ ] If XMage asks for mana/payment, confirm the prompt panel shows `Available Mana Sources` before generic mana buttons.
- [ ] Tap exposed mana-source actions only from XMage legal actions.
- [ ] Confirm floating mana/prompt state updates from the next authoritative snapshot.
- [ ] Confirm the card moves to stack/battlefield/graveyard only after XMage returns that state.
- [ ] Select a non-castable hand card and confirm the UI explains that XMage did not expose a cast/play action instead of silently doing nothing.

## iPhone Play Loop

- [ ] Put the iPhone and development machine on the same network.
- [ ] Set the app's gateway base URL to the development machine host reachable from the phone.
- [ ] Install and launch the iPhone build.
- [ ] Start a Commander game from the real play entry point, not the simulator-only route.
- [ ] Confirm the created snapshot source is not mock. Real games should report `source: xmage-java-bridge` and a non-nil `bridgeRevision`.
- [ ] Keep hand, play land, make mana, cast a simple spell, and pass priority.
- [ ] Confirm the mobile UI updates after each action without duplicate taps or manual refresh.
- [ ] Confirm the action tray changes from hand actions to battlefield or prompt actions as the snapshot changes.
- [ ] Confirm an XMage choice prompt renders from `promptEnvelopeV2` when the bridge asks for a target, card, player, mode, ability, amount, multi-amount, mana, pay cost, yes/no, commander replacement, order, search/select, or combat response.
- [ ] Confirm prompt controls do not auto-pick the first choice or default yes/colorless/zero when XMage did not expose enough data.
- [ ] Test declare attackers and declare blockers; command payloads must include attacker/defender or blocker/attacker pairs.
- [ ] Stop the XMage gateway and confirm iPhone shows bridge/XMage unavailable instead of entering mock gameplay.
- [ ] Confirm selected cards, tapped cards, pending actions, and prompt selections show instant local feedback.
- [ ] Confirm the real board state only changes after an authoritative XMage snapshot.
- [ ] Confirm the stack, command zone, graveyard, exile, life total, poison, commander tax, commander damage, phase/step, active player, priority player, pending status, legal action count, and game log are reachable.
- [ ] Confirm manual reconnect/refresh recovers after a network interruption without duplicate command submission.
- [ ] If the UI appears frozen, compare the visible state to `GET /games/{gameId}/debug` and verify whether `bridgeRevision` or `xmageCycle` is still advancing.

### iPhone Arcane Signet / Two Lands Regression

- [ ] With two untapped lands on the battlefield, tap `Arcane Signet` in hand.
- [ ] Confirm tapping selects the card and shows a selected-card action section; it must not open the inspector unless long-pressed.
- [ ] Confirm `Cast Arcane Signet` or a clear cast/play chooser appears when XMage exposes the action.
- [ ] Dragging the card to the battlefield may be used as a shortcut, but the visible button must also work.
- [ ] After casting, confirm any payment prompt shows source-based `Tap [land/artifact]` buttons.
- [ ] Confirm every source button uses a real `make_mana` legal action and shows produced mana hints when available.
- [ ] Confirm rejected or stale actions refresh from XMage and show a visible message instead of leaving the card half-played.

## Commander Deck Flow

- [ ] Import a pasted Commander text list.
- [ ] Import text exported from Moxfield or Archidekt when available.
- [ ] Validate exactly 100 cards including commander.
- [ ] Validate singleton rules except basic lands.
- [ ] Validate color identity and Commander legality where card data is available.
- [ ] Submit the selected deck into the XMage Commander game startup path.
- [ ] Confirm deck-loading errors surface clearly instead of starting a fake simulator game.

## Timing Capture

For slow actions, record:

- [ ] client action time
- [ ] API command response time
- [ ] gateway command timing
- [ ] Java bridge command timing
- [ ] `pendingStatus` returned, if any
- [ ] latest `bridgeRevision` and `xmageCycle`
- [ ] whether a WebSocket update arrived
- [ ] whether card image loading was involved

## Failure Notes To Capture

- Gateway `/health` response and recovery action.
- The command type that failed: `keep_hand`, `play_land`, `make_mana`, `cast_spell`, `pass_priority`, or prompt response.
- Previous and next `bridgeRevision` / `xmageCycle`.
- Whether `promptEnvelopeV2` was present and whether matching legal actions were exposed.
- Browser console logs or iPhone device logs around the failed command.
- Whether the app was waiting on a human player, AI player, or XMage prompt.
