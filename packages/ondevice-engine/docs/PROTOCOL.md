# In-process and peer protocol v1

## Trusted engine boundary

One UTF-8 JSON request per native call. Maximum input/output 4 MiB, bounded nesting. Integers must retain 64-bit fidelity for revisions. Unknown/missing top-level fields fail.

```
{"protocol":1,"op":"capabilities"}
{"protocol":1,"op":"create","configuration":{"seats":[...]}}
{"protocol":1,"op":"restore","checkpoint":{"path":"/absolute/app/private/game.ckpt"}}
{"protocol":1,"op":"poll","matchId":"...","viewerId":"player-1","after":0}
{"protocol":1,"op":"respond","matchId":"...","viewerId":"player-1","command":{...}}
{"protocol":1,"op":"concede","matchId":"...","viewerId":"player-1"}
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

`concede` concedes the authenticated human seat (`unauthorized_seat` for AI or unknown
seats; `match_unavailable` once the match ended). The request is queued on the match and
XMage's own `GameImpl.concede` runs on the GAME thread: at the next upstream concede check
(every priority and resolution) or within 250 ms if a human seat is waiting for an answer.
The seat's open question is retracted at once (`prompt_retracted` event) and never delivered.
In a pod the remaining players play on; the seat keeps receiving snapshots with its player
`hasLeft: true` and never a prompt, so the app shows it spectating. A player eliminated
normally also leaves this way. Once only AI seats remain, AI think time is capped at the
2-second stack budget so a watched game moves at a readable pace. Capabilities advertise
`"concede": true`; engines without it answer `unknown_operation` (older builds) or
`concede_unavailable` (other backends), and the app then treats leaving as the forfeit.

A configuration has 2–4 unique seats with `seatId`, `name`, `controller: "human"` or `"ai"`, and `deck`, with at least one human. AI seats use actual upstream MAD and are not poll/response recipients. Deck keys are `name`, `main`, `commanders` and optional `companions`. Card rows have `count`, `setCode`, `collectorNumber`, optional exact `name`. They do **not** accept `className`, caller-supplied rules or rarity.

AI seats additionally accept optional `aiSkill`, an integer from 1 to 10 matching the pinned
XMage desktop Skill control. Omission preserves the prior level-1 engine behavior; the app's
new setup control defaults to desktop level 2. The value goes directly to the upstream MAD
constructor (search depth `max(4, skill)` and thinking budget `skill * 3` seconds per calculation).
Higher levels allow more thinking, not different rules or access to additional private information.
Human seats reject this field. Invalid values fail rather than silently becoming a different level.

### Save/resume checkpoints (solo games)

A solo game against AI seats can survive the app process being killed, including a
force quit. The engine saves the whole match to a local file; the app offers
Resume or Abandon on relaunch and owns the file's lifecycle (resumable window,
deletion, backup exclusion, file protection). Multiplayer games are not resumable.

- **Capability.** `capabilities` reports `"saveResume": true` only when this build
  can save and read checkpoints. The first call runs a small self-test (a real
  card, a game zone, collections and the RNG through the same writer, SHA-256,
  filter and reader). A native build without serialization metadata fails it and
  reports `false`; the failure is kept in `diagnostics`. `hostMigration` stays `false`.
- **Create.** `configuration` accepts an optional `"checkpoint": {"path": "<absolute file path>"}`.
  It fails with `invalid_configuration` unless the configuration has exactly one
  human seat, the path is absolute and its directory exists, and the object has
  only `path`. It fails with `checkpoint_unavailable` when the capability is false.
- **When the engine saves.** At every safe point: the first question of the
  human seat's own `priority()` call (step part `PRIORITY`, between actions),
  on the GAME thread, **before** that priority prompt is published. The file on
  disk therefore always matches a published priority decision. Targets,
  payments, mulligans, combat declarations and other mid-action questions are
  never safe points. The write goes to `path + ".tmp"`, is flushed and
  fsynced (`FileChannel.force`), then renamed atomically over `path`. Each AI's
  retained search tree (`ComputerPlayer6.root`, a whole game copy that a late
  simulation thread may still change) is detached while writing. A failed
  write is recorded in `diagnostics` and in polls; it never ends or blocks the game.
- **Polls.** Additive fields, local metadata only:
  - `"checkpoint": {"sequence": n, "savedAtMillis": <epoch ms>, "turn": t, "bytes": b, "writeMillis": w}`
    describes the latest successful write. It is absent before the first one.
    `sequence` starts at 1 and continues after a restore.
  - `"checkpointFailure": {"code": "checkpoint_write_failed", "message": "...", "atMillis": <epoch ms>, "failedWrites": k}`
    is present only while the most recent write attempt failed (before or after a
    success). The next successful write removes it.
- **Restore.** `{"protocol":1,"op":"restore","checkpoint":{"path":"..."}}` returns the
  same result as `create` (`matchId`, `seats`, `engine`) plus
  `"restored": {"turn": t, "savedAtMillis": <epoch ms>, "sequence": n}`. The match
  keeps its original `matchId`, and its mailbox is new: prompt tokens are new and
  cursors restart at 0, so poll from `after: 0`. The game re-asks the human the
  checkpointed priority decision (upstream `GameImpl.resume` →
  `playPriority(resuming=true)`); any action started after it is gone, and AI
  seats think again, so they may play differently than they would have without
  the interruption. The engine keeps saving to the same path. Errors:
  - `checkpoint_unavailable`: this build cannot save or restore games;
  - `checkpoint_incompatible`: the header's format version, protocol, upstream
    commit, catalogue hash or engine build identity differs from this engine
    (an app update that changes the engine ends saved games);
  - `checkpoint_corrupt`: missing, truncated or oversized file, extra bytes,
    SHA-256 mismatch, a class the filter refuses, or any read or rehydration
    failure (cause kept in `diagnostics`);
  - `invalid_request` for a malformed request or a relative path, `match_limit`
    while another match exists, `engine_closed` after shutdown.

  A failed restore leaves no match and no running game or mailbox thread.
- **RNG.** The checkpoint holds the state of `mage.util.RandomUtil`'s generator. A
  restore installs it just before the game thread starts, so the draws after a
  restore equal the draws the saved process would have made from that state.
- **File format.** 8-byte magic `MMCHKPT\n`, big-endian u16 format version (1),
  big-endian u32 header length, a UTF-8 JSON header, then the payload: gzip'd
  Java serialization of the game, the seat binding and the RNG. The header holds
  `format`, `protocol`, `upstream`, `catalogueHash`, `engineBuild`, `sequence`,
  `savedAtMillis`, `turn`, `seats` (`seatId`, `name`, `controller`), `payloadBytes`
  and `payloadSha256`. `engineBuild` is generated from the adapter sources, the
  upstream lock and the reviewed upstream patches (`scripts/engine_build_identity.py`).
  Reads go through one `ObjectInputFilter` allowlist (`mage.*`,
  `io.magicmobile.xmage.*` and a fixed list of JDK collection and value types in
  `Checkpoints.java`) with depth, reference, array and byte limits; lambdas and
  proxies are refused. The writer enforces the same allowlist, so the engine never
  saves a file it would refuse to read.
- **Hidden information.** A checkpoint contains every hand and library. It is local
  only: never send it, or its path, to a peer, relay or poll. `HostRouter` never
  forwards `restore`. The engine never deletes checkpoint files (including a
  leftover `.tmp`); the app deletes both when the game ends or the player abandons it.

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
`ActivatedManaAbilityImpl` objects and `spellAbility: boolean` from current
`SpellAbility` objects in the same playable list. Upstream puts non-basic mana
abilities and modal spell faces in `other`; that category alone classifies neither.
These booleans describe only currently offered abilities and do not parse labels.
Source actions still answer with the object UUID, not the ability UUID. XMage may then ask for an exact
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

The trusted API above must **not** be exposed raw to guests. `HostRouter` accepts a framed `hello`, `poll`, `respond` or `concede` (empty payload, allowed even while the host is suspended), with epoch and monotonically increasing sequence. Its peer ID is supplied by authenticated GameKit transport, outside the JSON body. The host's binding supplies the seat. Guests cannot create/destroy/shutdown the host engine or select another viewer.

Build identity includes protocol version, upstream commit, catalogue fingerprint and adapter version. It must match before player input. The fingerprint covers constructor/set inventory, so commit+adapter identity must also match; do not treat the catalogue hash alone as all-code equivalence.

`PacketChunk` splits messages into 8 KiB parts. `PacketAssembler` scopes buffers by authenticated peer+message ID, enforces 4 MiB/message, per-peer/global concurrency and aggregate byte quotas, validates indexes and duplicate content, and expires stale assemblies. A bounded chunk layer is not transport authentication or matchmaking.

The production app implements lobby/host election, deck exchange, request/reply correlation, suspension/cleanup and guest UI orchestration in `OnDeviceMultiplayer` and `GameKitTransport`. Portable tests do not establish actual Game Center or multi-phone execution. Guaranteed reconnect, host migration and durable restoration of multiplayer matches remain outside the MVP (solo save/resume is above). The host is trusted with the full game, including hidden information; guest filtering is not host anti-cheat.

### Game Center starting D20 presentation

The iOS lobby's `start` handshake includes one host-generated, validated D20 plan
(`roll`) for all seats and tie rounds. The plan is presentation data, not an XMage
rule change. It is not displayed ahead of each turn. A human's tap sends `rollStep`
with the zero-based next index to the host; the host verifies the authenticated
peer owns that turn and broadcasts `rollAdvance` with that index over reliable
GameKit transport. AI seats advance from the host after the prior presentation
step. Clients advance only in order, and their animation never chooses a face or
the winner. The native starting-player prompt is answered only after the final
shared step has been shown. The app's adapter identity includes `rollstep-2`, so
older clients cannot join this presentation protocol despite sharing XMage inputs.

### Quick chat

Players in a running match may broadcast `{"type":"emote","epoch":"...","emote":"<id>"}`
directly to the other devices. `emote` is one of a fixed set (`hello`, `wellPlayed`,
`thanks`, `oops`, `wow`, `goodGame`); there is no free text. It never reaches the engine or
the host router, carries no seat claim (the receiver maps the authenticated GameKit peer to
its seat's table name), and at most one line per peer per 1.5 s is shown; extra lines are
dropped, not errors. The adapter identity includes `concede-1/emote-1`.
