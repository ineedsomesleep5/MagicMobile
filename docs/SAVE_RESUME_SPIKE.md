# Save/resume research spike

Research only, September 26, 2026. Nothing here changes app or engine source, and nothing
was built for a device. The measurements come from a throwaway harness run on the desktop
JVM (see [Experiments](#experiments-jvm)). They are not native, iOS or Android execution
evidence.

## Problem

A live game against the on-device engine exists only in the app process. The Graal isolate
holds the XMage `Game`, the GAME thread is blocked inside the pending prompt, and
`MatchMailbox` holds prompt tokens and history. When iOS or Android terminates the process,
for example after backgrounding under memory pressure, the game is gone. Today:

- `XmageEngine.capabilities()` reports `"saveResume":false` and `"hostMigration":false`.
- Backgrounding only pauses UI polling and input
  (`OnDeviceRootView.swift` `scenePhase` → `setSceneActive` → `OnDeviceSession.setForeground`).
  Android does the same from `ON_PAUSE`/`ON_RESUME`. The engine thread keeps running until the OS
  suspends the process.
- The download site already tells Android players that live games do not resume after process
  death (`apps/site/src/main.tsx`).
- Relay tables keep the relay resume token in memory only (`RelayTransport.swift`
  `private var token`). A relaunched process cannot reclaim its seat.

## Recommendation in one paragraph

Checkpoint the live engine with Java serialization, which XMage already uses to save games.
Take the checkpoint at safe points: each time a human seat is asked for priority, before it
answers. Write it to an app-private file and restore it in a fresh process on relaunch. Leave
out the AI's cached search trees. After Java deserialization, reinitialize the small, known
set of transient and process-global fields. Do not build resume on deterministic replay:
the experiments show that a fixed seed does not reproduce XMage AI games. Add cheap platform
mitigations first; they need no engine rebuild. Multiplayer resume is possible only for relay
tables, and only after single-player resume works. The cost to single-player resume on iOS
is about **13–19 working days**, including a native rebuild that needs approval. Android
adds 2–4 days when Android work resumes. The phases are [below](#recommended-plan).

## What the adapter holds

| Object | Serializable? | Notes (V = verified by experiment, R = from reading) |
|---|---|---|
| `MobileCommanderGame` / `GameImpl` + `GameState` (zones, stack, effects, watchers, turn structure, players) | Yes | V: a full mid-turn game writes and reads back with an identical fingerprint, including every library's order. |
| `GameImpl` transient fields | Partly restored | R+V: upstream `GameImpl.readObject` recreates the listener sources, `savedStates` and `gameStates`. It does **not** recreate `stackObjectsCheck` (a `final transient`) or `gameStatesRollBack`. V: without them, the first resolution throws an NPE and XMage's auto-rollback loop takes over. |
| `MobileCommanderGame.cancellation` | `transient` | R: null after a read, and `hasEnded()` dereferences it. It must be rebound (`setCancellation`). |
| `MobileHumanPlayer` | **No** | V: `NotSerializableException: MobileHumanPlayer$Channel`. The channel must become `transient` and be rebound. Upstream `HumanPlayer.response` is `final transient` (patched `protected` by `prepare_upstream.py`), so a restored human has a null `PlayerResponse`. |
| AI seats (`CancellablePlayer` → upstream `ComputerPlayerControllableProxy`/MAD) | Yes, with caveats | R+V: `cancellation` is `transient`. `ComputerPlayer` has three `final transient` collections (`lastUnpaidMana` NPEs when the AI pays mana). `ComputerPlayer6.root` retains the last search tree, including a full game copy (V: 80–90% of checkpoint size). The copy constructor drops `maxNodes` and `maxThinkTimeSecs` (V: `copy()` is not a safe restore path). |
| Pending prompt | No (it is a call stack) | R: the question lives in the GAME thread, blocked in `waitForResponse`. It cannot be written, but XMage recreates it: `GameImpl.resume()` → `Phase.resumeStep` → `playPriority(..., resuming=true)` asks the priority player again. V: every resumed game re-asked the checkpointed player. |
| `MatchMailbox` (tokens, revisions, history, receipts) | Not needed | Rebuild it on restore. Prompt tokens are new and cursors restart, so clients must resync. |
| RNG | Process-global | R: `mage.util.RandomUtil` is one static `java.util.Random`. It is never seeded in production and has `setSeed`. Object IDs come from `UUID.randomUUID()` (`SecureRandom`). |
| Other process-global state | Not captured | V: `Exile.PERMANENT` is a `static final UUID = UUID.randomUUID()`, so a new process cannot find the main exile zone (NPE). V: `MageSingleton` keyword abilities (Flying, Intimidate…) `readResolve` to the new process's singleton, which lacks the "dirty" `sourceId` the old process had set, and logs `FATAL … no sourceId`. |

The key upstream facts above were re-checked at the current pin
`4825513287ba6c42c32fd205d227f4a5fc44c2f3`: `Exile.PERMANENT`, `GameImpl.readObject`,
`stackObjectsCheck`, `RandomUtil`, the `ComputerPlayer6` copy constructor and `root`, the
`ComputerPlayer` `final transient` fields, `HashMap<MageObject,…>` in `getSortedProducers`,
the timed `task.get(maxSeconds)`, and `FlyingAbility.readResolve`.

## Experiments (JVM)

**Setup.** The existing read-only JVM build in `MagicMobile-ondevice` was used. Its upstream
is `8aea65ae`, the previous pin; its adapter classes are older than this branch. The harness
lives in this worktree's git-ignored `build_output/spike/` and was not committed. It builds a
real `MobileCommanderMatch`/`MobileCommanderGame` from the bundled precons (Token Triumph,
First Flight, Grave Danger, Draconic Destruction) with upstream MAD AI seats (`ComputerPlayer7`,
skill 1). It writes a checkpoint from inside the active player's live `priority()` call at
turn *K*, precombat main, empty stack. It restores the checkpoint in a **fresh JVM**, which
simulates process death, and calls `game.resume()`. All seats are AI, so no human prompts
were exercised.

Every priority call records a UUID-free fingerprint: turn, step, active and priority player;
each player's life, hand, **full library order**, graveyard and mana pool; battlefield (P/T,
damage, counters, tapped); stack; exile. Every run went through the machine-wide heavy lock
with `-Xmx1g`.

### Checkpoint size and time

| Game | Checkpoint | Raw | gzip | Serialize |
|---|---|---|---|---|
| 2 seats, turn 10 | full | 3.2–3.4 MB | 381–398 KB | 225–400 ms first, ~310 ms repeated |
| 2 seats, turn 10 | **lean** (AI `root` detached) | 584 KB | 135 KB | 207 ms first write in process, 12 ms repeated |
| 4 seats, turn 12 | full | 11.3 MB | 1.25 MB | 574–732 ms first, ~700 ms repeated |
| 4 seats, turn 12 | lean | 1.1 MB | 256 KB | 10 ms repeated |
| 4 seats, turn 24 | lean | 1.4 MB | 287 KB | 269 ms first write |

gzip took a further 18–215 ms. Reading a lean checkpoint in a cold JVM took 0.68–0.8 s,
including class loading; a 4-seat full checkpoint took 1.9 s. A 4-seat stream contained
about 875 distinct classes and **no serialized lambdas**. The JDK types seen were `ArrayList`,
`HashMap`, `LinkedHashMap/Set`, `LinkedList`, `ArrayDeque`, `EnumMap`,
`EnumSet$SerializationProxy`, `UUID`, `Date`, `AtomicInteger` and `ReentrantLock`.

### Restore

| Restore path | Result |
|---|---|
| `loaded.copy()` to reset transients | Plays on, but the copy constructor zeroes each AI's `maxNodes`/`maxThinkTimeSecs`, so the AI passes where it previously played lands (a1, d1, n1). Rejected. |
| Upstream `readObject` only ("raw") | NPE on `stackObjectsCheck` at the first resolution, then XMage's "Auto-restored … due game error" loop (d1). |
| Reflective rehydrate ("fixed": `stackObjectsCheck`, `gameStatesRollBack`, `ComputerPlayer` finals, `setCancellation`) | 7/7 restores (2- and 4-seat, full and lean, turns 3–24) had an **identical fingerprint** to the checkpoint. All played to a legal end, a win or the turn cap, with `getTotalErrorsCount()==0` in the live game. |
| "fixed" in a new process, before the exile fix | AI simulations hit 135 NPEs from `Exile.getPermanentExile()` being null (`static` random key). A live-game exile would fail the same way. The singleton `no sourceId` FATAL log appeared about 1,600 times in AI-simulation threads and never in uninterrupted runs. |
| "fixed" + re-keying `Exile.PERMANENT` | _Result pending; see the [log](#spike-log)._ |

The continuation after a restore is legal, but it is **not** the continuation the
uninterrupted game would have played. d1 matched the original for 89 priority fingerprints
(turns 10–14) and then diverged at an AI choice. a1 and p4 diverged at the first AI decision.
Two separate restores of the same checkpoint (d1, fixed) were identical to each other for the
whole game.

### Determinism (same seed twice)

`RandomUtil.setSeed(42)` was applied before deck loading. Some runs also used a patched
`java.util.UUID` (`--patch-module java.base`) that draws UUIDs from a seeded `Random`. The
AI's think time was 3600 s, so searches were bounded by nodes, not the clock. On this Mac no
run logged an AI timeout.

| Pair | Seeds | Result |
|---|---|---|
| d1 vs d2 | RNG + UUID | Identical for 154 priority fingerprints, then diverged in turn 8 (Alice casts Rishkar vs plays a land from the same fingerprint). |
| n1 vs n2 | RNG only | Identical until turn 11, then diverged at an AI choice. |
| d1 vs t1 (3 s think cap) | RNG + UUID | Identical for the full 17-turn game. |
| d1 vs n1 | seeded vs unseeded UUIDs | Diverged at the first mulligan decision. UUID values change outcomes. |

Likely sources, from reading. The AI keys `HashMap`s on objects without `hashCode`
(`ComputerPlayer.getSortedProducers` uses `HashMap<MageObject,Integer>`; `MageObjectImpl`,
`CardImpl`, `AbilityImpl` and `PermanentImpl` do not override `hashCode`), so iteration
follows identity hashes. The identity-hash sequence depends on which of the five shared
`AI-SIM-MAD` worker threads runs a search (hypothesis). The search is timed
(`task.get(maxThinkTimeSecs)`), and the mobile caps are 2–3 s, so a slower phone or a cold
start changes the explored tree. Tie-breaks call `RandomUtil.nextBoolean()`.

## Options

### 1. Engine checkpoint (serialize the live game) — recommended

- **Feasibility: high.** Verified on the JVM for 2 and 4 seats. XMage's own server saves
  games the same way (`GameController.saveGame` writes `Game` + `GameStates` to
  `ObjectOutputStream`). Resume at a priority point is an upstream code path.
- **Safe points.** Only the first wait inside a human seat's `priority()` call is a safe
  point. There the step part is `PRIORITY` and the state is between actions. Choices made in
  the middle of an action (targets and payment while casting, mid-resolution choices, mulligan,
  attackers and blockers in `PRE`, cleanup discard) are not safe: resuming there would repeat
  step-begin events or lose partially applied effects. On restore the player returns to their
  last priority decision, and any action they had started is undone. The AI re-thinks
  everything after that point.
- **Engine changes (forces a native rebuild on both platforms).**
  - `MobileHumanPlayer`: make `Channel` transient. Checkpoint on the first wait inside
    `priority()`. Rebuild each human after a read through the existing
    `HumanPlayer(PlayerImpl, PlayerResponse)` path, or set `response` reflectively.
  - `MobileAICancellation.CancellablePlayer`: rebind `cancellation`. Detach `root` before
    writing (lean). This also avoids serializing a search tree that a late upstream
    simulation thread may still be mutating.
  - Restore helper: reinitialize `stackObjectsCheck`, `gameStatesRollBack`, the
    `ComputerPlayer` finals and `MobileCommanderGame.cancellation`. Re-key the
    `Exile.PERMANENT` zone. Restore or deliberately re-seed `RandomUtil`. Re-add the table and
    query listeners. Rebuild `MatchMailbox`. Rebind `Match.games` or serialize the match
    wrapper.
  - A small upstream patch would be cleaner than reflection. It would make `Exile.PERMANENT`
    a fixed UUID and complete `GameImpl.readObject`; both are upstream bugs for any
    cross-process load. It needs an owner decision because the adapter keeps upstream
    changes minimal.
  - Protocol: `create` accepts a restore payload or path. A `checkpoint` op or event says when
    a new snapshot exists. Capabilities report `saveResume:true` only after device acceptance.
  - Header: upstream commit, `catalogueHash`, adapter/app build, engine protocol, seat
    configuration and SHA-256. Reject any mismatch; an app update ends saved games. Read with
    an `ObjectInputFilter` allowlist (`mage.*`, `io.magicmobile.xmage.*`, the JDK types above)
    and depth, reference and byte limits.
- **Native image (GraalVM 22.1, Gluon).** Java serialization needs every class that can
  appear in a stream registered through `-H:SerializationConfigurationFiles`. That is not
  just the 875 classes one game used: any card, ability, effect, watcher, filter or target can
  appear, which means roughly the Serializable subset of about 45k `Mage.Sets` and about 4.5k
  core classes, plus the JDK collection types. `NativeReflectionExporter` already walks this
  inventory and can emit `serialization-config.json`. The rehydrate fields need reflection
  entries with `allowWrite`, unless the upstream patch replaces them. The unknowns must be
  measured by a native probe before committing: image size, builder heap (4 GB locally, the
  10 GB CI profile) and build time. `build_native_desktop.sh` can probe first; then the
  multi-hour ARM64 CI build runs, which needs Caleb's go-ahead.
- **Risk: medium.**
  - Native serialization metadata cost is unmeasured.
  - Serialization speed in AOT code on a phone is unmeasured; JVM warm lean was 10–12 ms.
  - More hidden process-global state like `Exile.PERMANENT` may exist; for example, other
    static random IDs or singleton data. Test with exile-, token-, copy- and
    control-heavy decks.
  - Each upstream bump may add transient fields. A real-engine regression test must restore
    in a fresh process and finish games.
- **Hidden information.** A checkpoint contains libraries and every hand. Keep it local only
  (never to peers, per `packages/ondevice-engine/AGENTS.md`). Exclude it from backup (iOS
  `isExcludedFromBackup`; Android `noBackupFilesDir`), apply file protection, and delete it
  when the game ends or the player leaves.
- **UX.** On relaunch, offer "Resume your game (turn 12, saved 3 min ago)" or "Abandon". The
  player lands on their last priority decision with the same board, hands and library order.
  Restore time was about 1 s on the JVM; the device figure is still to be measured. AI moves
  after that decision may play out differently. Force-quit games stay resumable unless we
  decide otherwise. Because RNG state is not restored, a player could force-quit to re-roll
  later random events. Persisting the `RandomUtil` seed limits this but does not fully close
  it (see determinism).

### 2. Deterministic replay (seed + decks + accepted answers)

- **Feasibility: low for AI games.** Seeds alone do not reproduce games. Replay would need all
  of the following:
  - a seeded `RandomUtil`, which is easy;
  - seeded UUIDs, through a native `@Substitute` of `UUID.randomUUID` and a JVM test patch;
  - no clock-bounded AI search, which conflicts with the phone think caps in
    `MobileAICancellation`;
  - removal of identity-hash iteration in upstream AI and rules code, an unknown number of
    upstream sites;
  - or else logging every AI decision, which means wrapping the whole `Player` choice surface
    and replacing AI `priority()` actions.

  Recorded human answers are UUIDs, so they are meaningless without deterministic IDs.
- **Replay time.** The whole game is recomputed, including AI searches. On this Mac a 2-seat,
  17-turn game took 5–12 s and a 4-seat, ~30-turn game took 74–106 s. A phone would be
  slower, so resume would show a long catch-up.
- **Effort:** 12–25 days, low confidence. **Risk: high.** Any divergence loses the game
  anyway, so divergence detection is mandatory. Upstream changes to the rules code would be
  required.
- **Useful as** a debugging and test tool, not as the resume mechanism.

### 3. Hybrid: checkpoint plus an answer log since it

This replays the answers given after the last checkpoint, for example the targets of a
half-cast spell. It inherits option 2's determinism problems for that segment, including AI
responses. It saves the player one re-entered action at most. Not worth it for v1.

### 4. Platform mitigations

**iOS.**
- No sanctioned way exists to keep a game running in the background. Background audio used to
  stay alive would break App Review 2.5.4. `BGProcessingTask` is for deferrable work.
  `beginBackgroundTask` gives roughly 30 s, with no guarantee. That is enough to finish
  writing a checkpoint and possibly to let the AI reach the next human prompt.
- To lower the chance of termination, lower the footprint when backgrounded: purge artwork and
  image caches, stop and unload `GameAudio` buffers, and optionally ask the isolate to GC.
  Jetsam kills suspended apps largest-first.
- The isolate is created with default heap parameters (`graal_create_isolate(NULL, …)`).
  Device footprint is not yet measured; `TESTFLIGHT_ACCEPTANCE.md` already lists
  resident/peak memory as an acceptance measurement.
- A later option is to **hibernate** (tear down the isolate after a checkpoint when idle at a
  human prompt, restore on foreground). This frees all engine memory and runs the restore
  path on every return, at the cost of restore latency each time.
- Scene state restoration: `@SceneStorage` or `NSUserActivity` can bring the player back to
  the game screen, but they carry only UI state. The engine state must come from the
  checkpoint file.

**Android** (paused; the engine work is shared).
- `onSaveInstanceState`/`SavedStateHandle` hold only small UI state (Binder limit about
  1 MB), so they can carry a pointer to the checkpoint file, not the engine.
- Use `onStop`/`onTrimMemory` to flush a checkpoint and drop caches.
- A **foreground service** while a game is live must declare a type on Android 14+ and show a
  notification (POST_NOTIFICATIONS on 13+). The types fit poorly:
  - `shortService` stops after about 3 minutes. That is honest for "finish the AI turn and
    save after backgrounding".
  - `specialUse` needs a declared subtype, and Play review if the app is ever listed there.
  - `dataSync` does not describe a game, and Android 15 limits it to 6 h per day.
  - An FGS must be started while the app is in the foreground, and it does not stop OEM or
    low-memory kills.

  Distribution is a sideloaded APK today, so Play policy is not yet binding, but the OS rules
  are. Reserve an FGS for relay hosts, where other people depend on the process, and rely on
  checkpoints for solo games.

Engine change for either platform: none, unless the optional GC/trim op is added.

### 5. Multiplayer

Relay tables are the only candidates. A relaunched process cannot rejoin a `GKMatch`, so
Game Center tables end when the host dies.

- **Relay facts** (from reading `services/table-relay/src/index.js`):
  - Every peer, the host included, has `RESUME_GRACE_MS = 90_000` to reclaim its seat with its
    token. Messages for an away phone are held.
  - After 90 s the peer is `gone`, and both apps then fail the match for everyone
    (`OnDeviceMultiplayer` `onDisconnect`).
  - Because suspension drops the socket, a host backgrounded for more than 90 s already ends
    the table today, even if the process survives.
- **Host resume** would need all of the following:
  - option 1;
  - a checkpoint taken at every human seat's priority prompt, local and remote;
  - persisting the table code, resume token, lobby binding (peer → seat, names, decks) and
    match ID;
  - a relaunch within 90 s, or a relay change that extends the host's grace and marks the
    table as "host resuming";
  - a rebuilt mailbox, with a "resync" signal so guests with old cursors re-poll from 0.

  Guests' answers after the checkpoint are lost and re-asked, and guests see the board step
  back.
- **Guest resume** (a guest process killed) is cheaper and independent of engine
  serialization. Persist the relay token and seat, reclaim within 90 s, then fetch a full
  snapshot from the host.
- **Effort:** 6–10 days after option 1, plus relay changes and two-device acceptance.
  **Risk:** medium-high.

## Comparison

| Option | Feasibility | Effort (days) | Risk | Engine change / native rebuild | Player experience |
|---|---|---|---|---|---|
| 1. Engine checkpoint | High (JVM-verified) | Engine 5–7, native 3–5, iOS 4–6, acceptance 1–2 | Medium (native metadata size, device speed, hidden statics) | Yes / yes (iOS and Android .so) | Back at last priority decision, same hidden state, ~1 s restore (JVM) |
| 2. Deterministic replay | Low | 12–25 | High | Yes, plus upstream / yes | Long catch-up; may fail |
| 3. Hybrid | Low | Option 1 + 5–10 | High | Yes / yes | Marginally less redo |
| 4. Platform mitigations | High | iOS 1–2; Android FGS 1–2 | Low; FGS policy | No (optional GC op: yes) | Fewer kills, no resume |
| 5. Relay host resume | Medium | 6–10 after option 1 | Medium-high | Yes (option 1) + relay | Table pauses, then continues if host returns in time |

## Recommended plan

1. **Phase 0: app-only, no engine rebuild, ~1–2 days (iOS).**
   - On `.background`, purge caches and audio buffers.
   - Record a small "game in progress" marker so the next launch can explain that the game
     was lost instead of silently showing the menu.
   - Measure resident memory of a live game on a phone, foreground and background.
2. **Phase 1: engine checkpoint on the JVM, ~5–7 days.**
   - Implement option 1's adapter changes, header, filter and protocol.
   - Add real-engine tests: human seats, a checkpoint at a priority prompt, a restore in a
     fresh process, the same prompt kind, the game finished; include an exile/token/copy-heavy
     deck matrix.
   - Decide between upstream patches and adapter reflection.
3. **Phase 2: native probe, ~3–5 days plus CI wall time (needs approval).**
   - Generate the serialization and reflection config.
   - Run a desktop native build, then an ARM64 build.
   - Measure image-size delta, build heap, and serialize/deserialize times on a phone.
   - Stop if the size or heap cost is unacceptable.
4. **Phase 3: iOS integration and acceptance, ~4–6 days.**
   - Store the file in Application Support, excluded from backup and protected, written
     through `beginBackgroundTask`.
   - Build the relaunch Resume/Abandon flow and `@SceneStorage` navigation.
   - Clean up on end or leave.
   - Kill-test with the Xcode debugger, memory-pressure simulation, and the app switcher,
     then release the capability flag.
   - Optional: hibernate the isolate.
5. **Phase 4: Android, when resumed, ~2–4 days.**
   - Same store in `noBackupFilesDir`, flushed on `ON_STOP`/`onTrimMemory`.
   - Detect process death through saved state; kill-test with `adb shell am kill`.
   - Update the site warning.
6. **Phase 5: relay resume (optional), ~6–10 days.**
   - Guest seat resume first, then host resume with persisted relay state and a relay grace
     change.

Any engine phase must leave the paused Android artifact, its versionCode and its links
untouched until Android work resumes. After Phase 1, the iOS engine rebuild follows the
normal native release gates.

## Decisions needed

1. Approve Phase 1 (engine change, which leads to a native rebuild) and, separately, the
   Phase 2 ARM64 CI dispatch.
2. Upstream patch policy: two small patches (fixed `Exile.PERMANENT`, a complete
   `GameImpl.readObject`) or adapter-side reflection.
3. UX:
   - automatic resume or a Resume/Abandon prompt;
   - whether force-quit games stay resumable;
   - whether to persist RNG state to limit re-rolling.
4. Accept that the AI may play differently after a restore than it would have without the
   interruption.
5. Whether multiplayer resume is in scope, and if so, whether to change the relay's 90 s host
   grace.
6. For Android later: no foreground service, `shortService`, or `specialUse` for relay hosts.

## Verified vs. read

- **By experiment (desktop JVM, previous upstream pin, AI-only seats):**
  - `MobileHumanPlayer` is not serializable.
  - Full and lean checkpoint sizes and times.
  - A fresh-process restore reproduces the fingerprint exactly, including library order.
  - `copy()` breaks AI budgets.
  - The upstream `readObject` gap (NPE).
  - The reflective rehydrate plays games to a legal end.
  - The `Exile.PERMANENT` and singleton `sourceId` hazards.
  - A restored continuation differs from the uninterrupted game.
  - Same-seed games diverge.
  - A 4-seat stream has no serialized lambdas.
- **From reading:**
  - The upstream facts at the current pin listed above.
  - The GAME-thread prompt model and `resume()` path.
  - Relay grace and token handling.
  - App lifecycle code.
  - GraalVM 22.1 serialization requirements.
  - iOS and Android background and foreground-service policies (general platform knowledge,
    not re-verified against this week's documentation).
- **Not done:**
  - Native-image serialization.
  - Any device run.
  - Human-seat checkpoints through `MobileHumanPlayer`, which needs the adapter change.
  - Multiplayer.

## Spike log

- Harness: `build_output/spike/` in the delegate worktree (git-ignored).
  - `run.sh` (compile/probe/play/resume), `compare.py`, and `batch1–6.sh`.
  - `uuid-src`: the seeded `java.util.UUID` patch, used only for the determinism runs.
  - Runs are named a1, d1/d2, n1/n2, t1, p4, s2/s4/s4late and l2/l4.
- Exile re-key follow-up (batch 6): _pending at the time of writing; see the PR description._
