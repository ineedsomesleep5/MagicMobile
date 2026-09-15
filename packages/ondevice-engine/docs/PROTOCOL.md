# In-process and peer protocol v1

## Trusted engine boundary

One UTF-8 JSON request per native call. Maximum input/output 4 MiB, bounded nesting. Integers must retain 64-bit fidelity for revisions. Unknown/missing top-level fields fail.

```
{"protocol":1,"op":"capabilities"}
{"protocol":1,"op":"create","configuration":{"seats":[...]}}
{"protocol":1,"op":"poll","matchId":"...","viewerId":"player-1","after":0}
{"protocol":1,"op":"respond","matchId":"...","viewerId":"player-1","command":{...}}
{"protocol":1,"op":"destroy","matchId":"..."}
{"protocol":1,"op":"shutdown"}
{"protocol":1,"op":"diagnostics"}
{"protocol":1,"op":"clearDiagnostics"}
```

Success: `{"protocol":1,"ok":true,"result":...}`. Failure: `{"protocol":1,"ok":false,"error":{"code":"...","message":"..."}}`. Never send raw Java exception objects or serialized game state.

`diagnostics` is **local host only** and returns `{"report":null}` or the latest
bounded exception text (at most 16,384 Java characters, up to eight causes and
48 frames per cause). Error messages may contain private card information.
It is never included in polls, events, regular failure replies, or guest RPC.
`clearDiagnostics` releases that in-memory report. The diagnostic iOS build
persists only the latest report plus app/OS/time/status metadata, capped at
64 KiB, protected on iOS and excluded from backup. The user reviews, shares or
deletes it explicitly; no automatic upload is added. No game state or action
payload recorder is enabled. Temporary capture is tagged `[DEBUG-native-failure]`.

A configuration has 2–4 unique seats with `seatId`, `name`, `controller: "human"` or `"ai"`, and `deck`, with at least one human. AI seats use actual upstream MAD and are not poll/response recipients. Deck keys are `name`, `main`, `commanders` and optional `companions`. Card rows have `count`, `setCode`, `collectorNumber`, optional exact `name`. They do **not** accept `className`, caller-supplied rules or rarity.

A response command has exactly:

```
{
 "requestId":"a stable UUID for this logical answer",
 "promptId":"the exact token returned by this prompt",
 "promptRevision":42,
 "answer":{"kind":"boolean","value":false}
}
```

Answer kinds: `boolean`, `uuid`, `string`, `integer`, `integers`, `mana`. Mana values have `playerId` (engine UUID) and `manaType`. Integer-array constraints include element bounds and total bounds. The adapter converts multi-amount arrays to upstream **space-separated** response text.

`queued` is receipt of the command, not proof of resolution or game legality. Preserve the same request UUID and identical command when retrying an uncertain submission. A fresh prompt uses a new token. Do not replay an old answer against a new prompt.

Poll results contain match/viewer IDs, global revision, phase, viewer snapshot, viewer prompt, bounded viewer events, a resync flag and any terminal failure. Snapshots are always full current per-view projections; events notify changes. A global revision can skip numbers for one viewer without indicating loss.

### Additive CardView presentation metadata

`gameView.canPlayObjects.objects[objectUUID][category]` rows preserve upstream
`id` (ability UUID) and `value` (label), and add `manaAbility: boolean` from current
`ActivatedManaAbilityImpl` objects. Upstream puts non-basic mana abilities in
`other`; that category alone is not a mana classification. Source actions still
answer with the object UUID, not the ability UUID. XMage may then ask for an exact
ability, additional cost, or color. Old payloads safely identify only
`basicManaAbilities` as mana during payment. Playability is upstream's offered
action estimate, not proof that a complete payment sequence exists.

Visible battlefield CardViews may carry the additive `ABILITY_MENACE` icon with
category `ABILITY` and text `Menace`, derived only from current permanent
abilities. It is omitted for face-down permanents and does not parse printed
rules. Older native icons omit categories; clients may map known pinned
CardIconType names to their upstream categories. No menace asset is implied.

Printed/visible-face costs already use CardView's `manaCostLeftStr` and
`manaCostRightStr` ordered symbol arrays (including hybrid, phyrexian and X).
They are not a payable amount, tax, discount, remaining cost or affordability
signal. Clients must not recover costs from hidden/facedown cards; absent/empty
costs remain absent, not guessed as zero. Split halves remain separate.

## Untrusted multiplayer boundary

The trusted API above must **not** be exposed raw to guests. `HostRouter` accepts a framed `hello`, `poll` or `respond`, with epoch and monotonically increasing sequence. Its peer ID is supplied by authenticated GameKit transport, outside the JSON body. The host's binding supplies the seat. Guests cannot create/destroy/shutdown the host engine or select another viewer.

Build identity includes protocol version, upstream commit, catalogue fingerprint and adapter version. It must match before player input. The fingerprint covers constructor/set inventory, so commit+adapter identity must also match; do not treat the catalogue hash alone as all-code equivalence.

`PacketChunk` splits messages into 8 KiB parts. `PacketAssembler` scopes buffers by authenticated peer+message ID, enforces 4 MiB/message, per-peer/global concurrency and aggregate byte quotas, validates indexes and duplicate content, and expires stale assemblies. A bounded chunk layer is not transport authentication or matchmaking.

The production app implements lobby/host election, deck exchange, request/reply correlation, suspension/cleanup and guest UI orchestration in `OnDeviceMultiplayer` and `GameKitTransport`. Portable tests do not establish actual Game Center or multi-phone execution. Guaranteed reconnect, host migration and durable match restoration remain outside the MVP. The host is trusted with the full game, including hidden information; guest filtering is not host anti-cheat.
