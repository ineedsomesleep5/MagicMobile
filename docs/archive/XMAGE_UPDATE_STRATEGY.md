# XMage Update Strategy

XMage is the rules engine behind MagicMobile. Updates should improve compatibility without breaking Commander play in production.

## Version Policy

- Pin a known-good XMage release or commit for production bridge images.
- Do not auto-promote a new upstream XMage build to production.
- Test new XMage versions in staging with the same Commander smoke flow before promotion.

## Update Flow

1. Build the bridge image with the candidate XMage version.
2. Run gateway and bridge unit tests.
3. Run Docker Compose config validation.
4. Start `xmage-bridge` and `xmage-gateway`.
5. Wait for `/health` to report `ready`.
6. Run the live Commander smoke:

   ```sh
   XMAGE_GATEWAY_URL=http://localhost:17171 pnpm smoke:xmage
   ```

7. Run an iOS/web manual playtest for:
   - keep/mulligan
   - play land
   - make mana
   - cast spell
   - pass priority
   - stack resolution
   - at least one prompt response
   - AI turn progression

8. Promote only if bridgeRevision/xmageCycle advance correctly and no prompt family regresses.

## Failure Evidence To Capture

- XMage version or commit.
- Bridge image tag.
- Gateway and bridge health responses.
- Failing command type.
- Request id/correlation id if available.
- Previous and next `bridgeRevision` / `xmageCycle`.
- `promptEnvelopeV2` method/response kind/message id.
- Snapshot source.
- Whether failure happened on web, iOS, gateway, bridge, or XMage/AI.

## Rollback

If a new XMage version breaks Commander play:

1. Roll back the bridge image to the last known-good version.
2. Keep the failed version logs and smoke output.
3. Add a regression fixture or checklist item before retrying the update.

## Compatibility Rules

- Do not patch around XMage by implementing rules in the client.
- Do not silently fall back to simulator if XMage is unavailable.
- Keep prompt and legal-action contracts backward-compatible where practical.
- When upstream XMage changes callbacks, update the bridge and prompt fixtures first, then iOS/web UI if needed.
