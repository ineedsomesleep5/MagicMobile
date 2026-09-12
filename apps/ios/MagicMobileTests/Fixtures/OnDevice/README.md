# Actual XMage JVM portrait fixtures

These 13 compact polls come from the current production `XmageEngine`,
`ViewProjector`, `QueryEncoder` and `EngineService`, running against the already
built, pinned real XMage classes. They test transport and projection consumption.
They do **not** establish native or iOS runtime behavior, full-game completion,
multiplayer networking, exhaustive privacy, or complete card/prompt coverage.

Each numbered JSON file is the **complete `result` object of a successful poll**,
not its `{protocol, ok, result}` transport envelope. `snapshot.gameView`, prompt
payloads/constraints/tokens/revisions, events, nulls, HTML messages, and unknown
upstream fields are preserved without pruning, renaming, UUID normalization, or
Swift-model conversion. JSON whitespace/key ordering may differ from wire text.
`manifest.json` is metadata, not a poll; consumers should use its `fixtures` list.

| Files | Real state captured |
| --- | --- |
| `2p-initial-player-{1,2}.json` | Both seat projections at the first mulligan ASK; the waiting opponent has no prompt |
| `4p-initial-player-{1,2,3,4}.json` | Four human seat projections at the first mulligan ASK |
| `2p-priority.json`, `4p-priority.json` | Priority SELECT with nonempty upstream `canPlayObjects.objects` |
| `2p-mana.json` | Actual PLAY_MANA while casting Isamaru from the command zone; includes `manaPlayerId` and real response types |
| `2p-stack.json` | Priority SELECT after payment, with a spell awaiting resolution on the stack |
| `2p-battlefield.json` | The creature after normal spell resolution |
| `2p-attackers.json` | Real attacker selection, including upstream button/selection metadata |
| `2p-combat.json` | Declared combat after attacker selection, including actual attacker and defender identities |

The manifest records `matches[].seatToEnginePlayerId`, derived directly from each
seat's `snapshot.enginePlayerId`; use that mapping to associate protocol seat IDs
with `gameView.players[].playerId`. UUIDs are local to their match. The initial
seat projections are polled without submitting responses between them. Later
fixtures are independent snapshots at the listed revision, not a complete event
replay. Incremental poll cursors bound events without modifying their contents.

Only the synthetic legal regression decks from `tests/decks/isamaru.txt` and
`tests/decks/yargle.txt` are used: 99 appropriate basic lands and one commander,
duplicated across separate players for four seats. Production deck validation
runs at match creation. No user data, arbitrary game-state setup, test-only
engine replacements, altered mana, or bypassed rules are used. The protocol
driver follows `scripts/play_jvm.py`: keep hands, play lands, cast commanders,
choose available mana sources, pass priority, and select attackers. It stops
once the bounded fixture coverage is met and destroys each match.

## Reproduce

From `/Users/calebfeliciano/Documents/MagicMobile-ondevice`:

```sh
PYTHONDONTWRITEBYTECODE=1 python3 packages/ondevice-engine/scripts/export_portrait_fixtures.py \
  --java-home /opt/homebrew/opt/openjdk@21 --timeout 180
```

Prerequisite: the existing real build from
`packages/ondevice-engine/scripts/build_jvm.sh`, including
`build/runtime-classpath.txt` and generated registry classes. The exporter does
not run the upstream build, fetch dependencies, or edit production files.
It compiles the current core/adapter sources with JDK 21 (`--release 17`, compiler
heap 384 MiB) into `build/test-portrait-fixtures/classes`, then starts one headless
JVM with `-Xmx512m`. Two- and four-seat matches execute sequentially in that JVM.
Use another JDK 21 location with `--java-home` if needed. Per-match time and
response counts are bounded; unknown prompts fail rather than fabricate data.

The export validates real `engine="xmage"`, `execution="jvm-integration"`, the
upstream checkout pin, distinct seat UUIDs, projection player identities, prompt
tokens/revisions, and exact JSON round trips. It hashes current sources and
fresh compiled adapter/core classes and fails if sources change during capture.
The manifest also records capabilities, source commit, exporter hash, JDK,
command, synthetic configurations, and fixture hashes/sizes. Random UUIDs,
shuffle/turn outcomes, timing/revisions, and timestamps are not byte-repeatable;
the bounded coverage and reproduction procedure are repeatable.

Generated diagnostics and the successful validation summary are confined to
`packages/ondevice-engine/evidence/portrait-fixtures/`; upstream runtime logs and
compiled classes are confined to `packages/ondevice-engine/build/test-portrait-fixtures/`.
Re-running replaces these named fixture JSON files and their manifest.
No Swift application-model decoding or iOS build is performed by this exporter;
the portrait integration tests must provide that separate acceptance check.
