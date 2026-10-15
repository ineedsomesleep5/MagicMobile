# Engine game record

C5 of the game improvement program (Phase 5, Release 3). The engine writes a compact, deterministic
record of every decision in a game. A JVM replay rebuilds the same game from the record alone, to the
same winner, turn count and life totals. The ranked server stores the record with each ranked AI
result and runs cheap checks on it; an offline JVM replay can verify any stored record.

Code: `packages/ondevice-engine/engine/xmage/src/main/java/io/magicmobile/xmage/`
(`GameRecord`, `GameRecorder`, `GameRandom`, `GameReplay`, plus hooks in `MobileHumanPlayer`,
`MobileAICancellation`, `MobileCommanderGame`, `XmageEngine` and `Checkpoints`). All of it is mobile
adapter code; nothing in upstream XMage changed. Protocol: `packages/ondevice-engine/docs/PROTOCOL.md`
("Game record").

## How a game becomes deterministic

XMage has three sources of run-to-run difference. The adapter controls each one.

1. **Randomness.** Upstream draws everything from one process-wide `java.util.Random`
   (`mage.util.RandomUtil`). At `create` the adapter replaces it with `GameRandom`, seeded from the
   match seed. Only rules code on the match's GAME thread draws the seeded stream: shuffles, coin flips,
   dice, "at random" effects and the opening player. AI reasoning draws from an unseeded source, both
   on its search threads and in its choice code on the GAME thread. A replay never runs that reasoning,
   so it would otherwise shift the stream. Upstream's "put on the bottom/top in a random order" uses
   `Collections.shuffle` with Java's own unseeded generator. Both seat classes override those two
   methods to take the order from the seeded stream instead.
2. **Hash order.** XMage builds each library from `Deck.getMaindeckCards()`, a `HashSet` ordered by
   identity hash codes, so the order before the opening shuffle differed in every run. The adapter
   puts each library in deck order before the game starts, so the seeded shuffle deals the same
   cards. Some rules code also iterates hash sets of player IDs (for example, which defending player
   declares blockers first in a multiplayer game), and player IDs are random. The record keeps the
   players' IDs, and the JVM replay gives its players the same IDs (by reflection on upstream's final
   field, replay only), so those orders match. Hash-ordered iterations over card and permanent IDs may
   remain (see the limits below).
3. **AI timing.** The AI searches with a time budget, so its choices depend on CPU speed. The record
   keeps every AI choice, and a replay feeds the choices back instead of searching.

Object IDs are random UUIDs, different in every run, so the record never stores one. It names objects
by structure, the same way in both runs (see "Names").

## Format (version 1)

The record is JSON. `setup` and `end` are JSON **strings**, hashed exactly as stored, so nobody has
to re-serialize JSON the same way to check the chain.

```json
{
  "format": "magicmobile-game-record",
  "version": 1,
  "setup": "{\"engine\":{...},\"seed\":\"-412...\",\"seats\":[...]}",
  "entries": ["0h b0", "1M 0", "1Q 0", "0h uc12", ...],
  "marks": ["1 0 d8637a56", "2 31 84e244e0", ...],
  "end": "{\"state\":\"ended\",\"turn\":15,\"winners\":[\"ai2\"],\"seats\":[...],\"entries\":867,\"digest\":\"1a4f4c0a\"}",
  "head": "5f0c...64 hex"
}
```

- `setup.engine`: `protocol`, `upstream` (XMage commit), `catalogueHash` and `engineBuild` (the same
  identity checkpoints carry). A replay refuses a record from another build unless asked
  (`--any-build`).
- `setup.seed`: the 64-bit match seed as a decimal string (JSON numbers lose precision past 2^53).
- `setup.players`: the engine player IDs in seat order (see above). They are random per game and
  reveal nothing.
- `setup.seats`: in seat order, `seatId`, `name`, `controller`, the `deck` exactly as `create` received
  it, and for AI seats the `aiSkill`, `aiSearchDepth` and `aiMistakePercent` they played with. The AI's
  mistake seed is not recorded; the replay does not need it.
- `entries`: one short string per decision, in the order the GAME thread made them (grammar below).
- `marks`: `"<turn> <entry index> <digest>"` at the first entry of each turn.
- `end`: `state` (`ended`, or `running` for a record taken mid-game), `turn`, `winners` (seat IDs),
  per seat `life`, `lost` and `left`, the entry count and the final digest.
- `head`: the hash chain (below).
- `broken` (only when present): recording met a value it cannot express and stopped. The game went on,
  but the record cannot be replayed (`record_incomplete`). No test game has produced one.

**Digest**: CRC-32 (8 hex digits) of UTF-8 text built from state both runs share that holds no UUID:
turn, step, active and priority seats; per seat life, total counters, hand, library and graveyard
sizes, lost and left; the sorted battlefield (name, controller seat, tapped, power/toughness); the
stack size and the exile size. It hides library order and hand contents.

**Hash chain**: `h0 = SHA-256(setup)`, `hi = SHA-256(h(i-1) ‖ "\n" ‖ entry i)`,
`head = SHA-256(hn ‖ "\n" ‖ end)`, where `‖` concatenates the 32 raw bytes of the previous hash
with the UTF-8 text. Lowercase hex.

### Entries

Every entry is `<seat><op>[ <args>]`. The seat is a single digit (0–3, seat order); `-R` has no seat.

| Entry | Meaning |
|---|---|
| `0h <answer>[ <action>…]` | A human answer, as the app sent it |
| `0c <n>` | The seat conceded, at the n-th concede check since the previous entry |
| `-R` | The recorded game was saved here and later restored from that save |
| `1Q 0/1` | AI priority (the return value). Before it: `1A <ability> <action>` for each searched action, `1p` for each pass |
| `1Y 0/1` | AI mana payment. Before it: `1V <ability>` for each mana ability or special action it activated |
| `1S 0/1` | AI attack (1: upstream declared; 0: a deliberate held-back attack). Before it: `1K <attacker> <defender> <undo>` |
| `1B 0/1` | AI blocks (as `S`). Before it: `1L <defender> <blocker> <attacker>` |
| `1M`, `1U`, `1P` | Mulligan, yes/no question, pile choice: `0` or `1` |
| `1R`, `1X`, `1I` | Replacement-effect index, announced X, amount |
| `1J a,b,c` | Several amounts |
| `1C 0/1[ k<key>/v<value>]` | A choice (`!` before the value marks a special answer) |
| `1T 0/1 <names>` / `1N …` | Targets or cards chosen (`N` with amounts, `name*amount`); `=` replaces all; `.` none |
| `1G <i>`, `1D <i>` / `1D a<i>`, `1F <i>` | Triggered ability to put first, mode, spell ability to cast (`-` for none) |

Human answers: `b0`/`b1`, `u<name>`, `i<n>`, `n<n,n,…>`, `m<MANATYPE>,<player>`, `z` (null),
`s<percent-encoded text>`, `k<i>` (the i-th option of the question), `S<name>` / `S#<name>` (an
object ID sent as text). Answer actions: `ra` + scope (`a`/`t`) + `0`/`1` (remembered answer;
the key comes from the question, as AnswerActions builds it), `rt`, `pu`, `ac0`/`ac1`, `xa`, `xt`.

An AI action (`A`) names the ability on its source plus a descriptor of what the search chose:
`P` (modes preselected), `m<i>,…` (selected modes), `;t<names>` per target (with `*amount`, `k` when
skipped), `;c<names>` per cost target, `;x<mana text>` for an X spell. The replay rebuilds the action
with upstream's own option generator and takes the option with the same descriptor.

### Names

| Name | Object |
|---|---|
| `p<i>` | The player in seat i |
| `c<n>` | The n-th card or card face in deck load order (seat by seat, main deck then commanders, faces as `GameImpl.loadCards` registers them) |
| `b<k>` | The k-th battlefield permanent that is not a loaded card (tokens) |
| `s<k>` | The k-th stack object from the top |
| `o<k>` | The k-th command-zone object |
| `x<k>` | The k-th special action |
| `a<name>/<i>` | The i-th ability of an object |
| `<name>/<i>`, `@<k>/<i>`, `!p`, `!m<k>`/`!a<k>` | Ability refs: on a source object, on the k-th command object (commander casts, with commander tax), the search's pass, special actions |
| `#<i>` | The i-th option of the question being answered (modes, abilities) |
| `?` | An ID unknown to the game (an answer that names nothing) |

## Size per game

Measured on the real JVM engine (`RealGameRecordTests`), with precon decks of about 100 distinct cards
per seat, skill-1 AIs:

| Game | Turns | Entries | JSON | gzip | Entries only, gzip |
|---|---|---|---|---|---|
| 2 AIs + watcher, precons | 15 | 867 | 27.4 KB | 5.0 KB | 0.6 KB |
| 2 AIs + watcher, precons | 23 | 1,503 | 32.4 KB | 5.5 KB | 1.0 KB |
| Human vs AI, precons | 13 | 476 | 18.2 KB | 3.6 KB | 0.4 KB |
| Human + 3 AIs | 32 | 2,341 | 25.3 KB | 3.8 KB | 1.1 KB |
| 2 AIs, basic-land fixture decks | 15 | 610 | 6.1 KB | 1.2 KB | 0.3 KB |

Most of the size is the deck lists in `setup`; the decisions of a whole game gzip to about a kilobyte.
Store and upload the record gzipped. Replaying one takes 0.2 to 1.5 s on the JVM (no AI search runs).

## Replay API

- **Java**: `GameReplay.replay(Map<String,Object> record, boolean anyBuild, long timeoutMillis)`.
  It checks the format, the hash chain and the engine build (errors `record_unsupported`,
  `record_incomplete`, `record_corrupt`, `record_engine_mismatch`), rebuilds the match from the setup,
  installs the same seeded generator and plays the game with every decision fed from the record. It
  returns `outcome` (`ended`; `exhausted` when the record ends at a question; `diverged`, `error` or
  `timeout`), `matches` (every entry used and the replay's end equals the recorded `end`: state, turn,
  winners, each seat's life, lost and left, and the digest), `entriesUsed`, `entries`, `resumes`,
  `sameBuild`, `end`, `recordedEnd` and a `message` on failure. At each turn mark the replay compares
  the digest and stops at the first difference.
- **Command line**: `java -cp <runtime classpath> io.magicmobile.xmage.GameReplay record.json [--any-build]`
  (after `scripts/build_jvm.sh`; the classpath is `build/runtime-classpath.txt`). It prints the result
  JSON and exits 0 only when the replay matches.
- **Save and resume**: a checkpoint carries the record so far. A restored game appends `-R` and goes
  on recording. When the replay reaches `-R` it does what the app did: it saves the parked game with
  the checkpoint serializer, restores it as `XmageEngine.restore` does, and resumes.
- XMage's generator is process-wide, so a replay must not run beside a live match in the same JVM.

## What the ranked server can check without the engine

Today the server bounds AI wins with a ticket (`mm_ranked_ai_start`), a four-minute minimum and a daily
cap (docs/RANKED.md). With a record it can also check, in SQL or an edge function, in milliseconds:

1. **Integrity and binding.** Recompute the hash chain (`pgcrypto` `digest`, one SHA-256 per entry) and
   compare it with `head`. The head is the result's fingerprint: store it with the result, so the
   result is bound to exactly this record for any later audit.
2. **A server seed.** Have `mm_ranked_ai_start` return a random 64-bit seed with the ticket and store
   it. The app passes it as `create`'s `seed`, and the result must carry a record with that seed. This
   stops seed grinding (choosing a deck order by trying seeds) and reusing an old winning record:
   one seed, one game.
3. **The right game.** `setup.engine.engineBuild` is a released build (a server table the release
   process fills). Two seats. The AI seat's `aiSkill`, `aiSearchDepth` and `aiMistakePercent` are the
   tier's values, its deck is in the tier's pool (compare a hash of the deck list with a table), and
   the human deck is legal for the bracket the ticket names.
4. **Consistency.** `end.state` is `ended`; `end.winners` is exactly the human seat; the AI seat has
   `lost: true`; `end.entries` equals the entry count. Marks start at turn 1, turns and indexes only
   increase, and the last mark is the final turn. Every entry matches the grammar above. The AI seat
   never concedes, and a human concede entry means the human lost.
5. **Bounds.** Turns at least a plausible minimum (a 40-life Commander win in under 4 turns is
   suspect), entries per turn within bounds, the AI seat made decisions in its own turns, and the
   time since the ticket covers the turns played.
6. **Sampling.** Keep records. A JVM worker (a scheduled job, not the phone) can replay a sample, every
   suspicious one, or every win that reaches a high tier, with `GameReplay`. A record that does not
   replay is a fabricated or corrupted result.

### What these checks cannot prove

- The cheap checks prove only that the record is well formed, unaltered since it was hashed, made for
  this ticket's seed, and consistent with the claimed result. They do not prove the game happened or
  that any decision was legal: a modified app can write a consistent record by hand. The hash chain is
  not a signature, because the phone holds no secret a player cannot extract.
- A full JVM replay proves the recorded decisions form a legal XMage game that ends as claimed. It
  cannot prove the AI's decisions came from the real AI: AI choices are recorded, not recomputed
  (the AI's search depends on time). A patched app that weakens its own AI produces records that replay
  perfectly. Catching that would need an AI that is deterministic for a given seed (a node budget
  instead of a time budget), so a verifier could recompute and compare the AI's choices. That is
  possible future work, not part of this record.
- Hidden information: a record holds every hand and library order (through the seed). It is fine for
  the player's own games and the server, but it must never go to the other side of an online game
  while that game is running.

## Known limits

- Rules code that iterates hash-ordered collections keyed by card or permanent UUIDs (random per run)
  or identity hash codes can still order things differently in a replay. The replay names objects structurally, so this matters
  only when the order changes an outcome. None of the test games hit one; the replay reports it as
  `diverged` at the entry where it shows.
- A few cards shuffle with `Collections.shuffle` outside the player methods the adapter overrides
  (Jalum Grifter, Jeskai Infiltrator, Vial Smasher the Fierce, Ghastly Conscription, Expose the
  Culprit). A game with one of these may not replay.
- AI reasoning that calls rules code the adapter does not intercept: the fallback Phyrexian-mana life
  payment in `ComputerPlayer.playManaHandling`, or a replacement effect that asks a question while the
  AI chooses targets. A game that hits one may not replay.
- Native builds: the code is in the adapter, so the native engine records too, but no native build or
  phone has run it yet (the cloud has no native toolchain).
