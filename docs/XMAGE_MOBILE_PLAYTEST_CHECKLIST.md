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
  ```

Expected result: health reports `ready`, the smoke output includes a game id, source, completed play-loop steps, and advancing `bridgeRevision` / `xmageCycle` when the Java bridge is active.

If the live smoke fails, capture the exact failing step instead of treating simulator success as product success. Current high-value failures are usually in pass priority, AI waiting, stale prompt answers, or a missing legal action after XMage changes state.

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
