# Web engine M1: real XMage in desktop Chrome through GraalVM Web Image

Milestone M1 of docs/WEB_ENGINE_OPTIONS.md, 2026-10-20 (Claude). It ships nothing to players. Branch
`claude/web-engine-m1`.

Question: can the real engine (pinned XMage `dac400b`, engine release C sources) run in a desktop browser through
GraalVM Web Image, with no game server, within the size, speed and memory gates?

**Verdict: go, with one condition.** The real engine (pinned XMage, release C adapter, full card pool) runs in desktop
Chrome as a 174 MB WebAssembly module, with no game server. It finishes 10 of 10 seeded games, and every measured gate
passes with room to spare. The condition is the build itself: it fits GitHub's free runner only with swap: the builder peaked at about
30 of the runner's 32 GB of RAM plus swap. The next engine work (shrinking the image heap, below) should come before
anything depends on rebuilding it routinely. Firefox and Safari have not been run yet.

## Results against the gates

Headless Google Chrome 155 on the 8 GB MacBook (shared with other sessions), the engine served from localhost by
`apps/web-play/scripts/serve.mjs` (COOP/COEP, no compression). Build: run
[39599683802](https://github.com/ineedsomesleep5/MagicMobile/actions/runs/39599683802), engine identity
`web-1:sha256:d1756e3e…f98`. Metrics: `packages/web-engine/build/metrics/chrome-boot-1.json`, `chrome-games-10.json`.

| Gate | Target | Measured | Result |
|---|---|---|---|
| Engine size, raw | ≤ 300 MB | 173.8 MB (`engine.js.wasm`) plus a 112 KB JS wrapper | **pass** |
| Engine size, compressed | ≤ 100 MB | 45.0 MB at gzip -9 (Brotli on a site would be smaller) | **pass** |
| Engine ready, first visit | ≤ 45 s | 3.0–3.1 s from localhost: Wasm compile and instantiate 2.9 s, XmageEngine construction 87 ms. Adding the 45 MB download: about 10 s at 50 Mbit/s, 17 s at 25 Mbit/s (estimate) | **pass** |
| Engine ready, cached | ≤ 10 s | 2.6–2.9 s (compile 2.4 s) | **pass** |
| 4-player game start | ≤ 10 s | median 0.11 s, max 0.14 s (5 games) | **pass** |
| AI turn | median ≤ 5 s, p95 ≤ 15 s | median 0.99 s, p95 4.4 s, max 10.5 s (217 AI turns) | **pass** |
| Seeded games | 10 of 10 finish | 10 of 10 (2-player seeds 1–5, 4-player seeds 6–10; 12–51 turns, 5–105 s each) | **pass** |
| Tab memory | ≤ 2 GB | renderer peak 1.04 GB; whole Chrome process tree 1.31 GB | **pass** |
| Board update | ≤ 1 s, p95 ≤ 3 s (spike target) | median 27 ms, p95 52 ms (2,774 updates) | **pass** |
| Main-thread stall | none over 100 ms | no long task in any visit | **pass** |
| Firefox and Safari smoke | a smoke run | not run: Playwright's browser download times out from this Mac, Firefox isn't installed, and driving Safari needs a macOS automation permission | **open** |

For scale, the same Java sources in the web threading mode on HotSpot (`WebJvmMain`, same Mac) play AI turns at a median
of 0.19 s, p95 0.98 s: the browser build is about 5× slower per AI turn. AI searches have a time budget (skill × 3 s),
so web turns take about as long as phone turns but explore fewer positions. A calibration run (M5) will show whether
the web AI plays weaker.

### Estimates against measurements

| | Estimated (WEB_ENGINE_OPTIONS.md) | Measured |
|---|---|---|
| Raw Wasm | 150–250 MB | 173.8 MB |
| Compressed | 55–90 MB | 45.0 MB (gzip -9) |
| First visit | 20–60 s | 3 s plus download (about 10–17 s at 25–50 Mbit/s) |
| Cached visit | 5–15 s | 2.6–2.9 s |
| Tab memory | 0.5–1.5 GB | 1.0 GB renderer, 1.3 GB whole browser |
| AI speed vs native | 45–70% of native | about 20% of HotSpot's speed on AI turns (0.99 s vs 0.19 s median), all within the time budgets |
| Build | about an hour on a GitHub runner | 44 min run (21.6 min native-image), needing a 24 GB builder heap: 15.4 GB RAM plus 14.9 GB of swap at the peak |

### The build, run by run

| Run | Change | Outcome |
|---|---|---|
| [39482806260](https://github.com/ineedsomesleep5/MagicMobile/actions/runs/39482806260) | first build, 10 GB heap, 4 threads | analysis passed (61,954 types, 346,743 methods); out of memory compiling |
| [39495674113](https://github.com/ineedsomesleep5/MagicMobile/actions/runs/39495674113) | 12 GB, 2 threads; `-Ob` fallback | compiled and laid out; out of memory creating the image, at -O2 and -Ob alike |
| [39511250420](https://github.com/ineedsomesleep5/MagicMobile/actions/runs/39511250420) | 14 GB on swap, no .wat comments, no Closure | the heap cap (12.7 GB usable) hit first, swap unused; watchdog stopped it after 43 min in `WasmGCHeapWriter.write` |
| [39546958975](https://github.com/ineedsomesleep5/MagicMobile/actions/runs/39546958975) | 24 GB heap over 16 GB swap, watchdog off | built in 12.6 min; Chrome refused it: one image-heap initializer function was 57.7 MB, over V8's 7,654,321-byte limit |
| [39599683802](https://github.com/ineedsomesleep5/MagicMobile/actions/runs/39599683802) | `-H:ImageHeapObjectsPerFunction=4000` | built (largest function 3.9 MB); loads and plays in Chrome |

What fills the build: the image heap is 89 MB of 767,914 objects, mostly class metadata for 61,954 types
(`java.lang.Class` 38.4 MB, `DynamicHubCompanion` 10.4 MB) and strings (16.7 MB), plus 9.8 MB of bundled catalogue
resources. Writing it as Wasm initializer code is what needs ~17 GB of builder heap. The debug `.wat` text is 3.8 GB.

## What was built

| Path | What it is |
|---|---|
| `packages/web-engine/web_sources.py` | Copies the adapter and platform sources plus three upstream files and rewrites 18 places for the web threading mode. Each rewrite must match exactly as often as listed, or the build fails. `packages/ondevice-engine/` is only read, so phone builds are byte-for-byte unchanged. |
| `packages/web-engine/src/` | Web-only Java: `WebThreads` (deferred GAME executor, inline CALL executor, the human wait), `WebHost` (the request loop), `WebMain` (Web Image entry, `@JS` bridge), `WebJvmMain` (the same mode on HotSpot), `WebInflate` and `WebCrc32` (plain-Java gzip and CRC-32), `mage.util.MobileWebInterrupt` (the AI stop flag). |
| `packages/web-engine/src-svm/` | A `Thread.start` substitution that throws, so a stray thread start fails loudly instead of silently running nothing. |
| `packages/web-engine/web_identity.py` | The web engine's build identity (`web-1:sha256:…`): the phone identity plus every web-only input and the toolchain. |
| `packages/web-engine/build_web.sh` | Stages `sources`, `jvm`, `metadata`, `wasm`, `bundle`. The `wasm` stage needs a ~10 GB builder heap: CI only. |
| `packages/web-engine/patch_wrapper.py` | Adapts the generated `engine.js`: Wasm URL from the worker, `instantiateStreaming` (Chrome's Wasm code cache), boot timing marks. |
| `.github/workflows/magicmobile-web-image.yml` | Manual build: `build_jvm.sh`, web sources, two web-mode games on GraalVM's JVM with the tracing agent (reachability metadata), the Web Image build, the bundle artifact. Starts on dispatch, or on a push to a `claude/web-engine-*` branch whose commit message has `[web-image]`. |
| `apps/web-play/` | The spike's bench, moved to Web Image: `engine.worker.ts` (classic worker, SharedArrayBuffer channel), `engineClient.ts`, `bench.ts`/`bench.html`, `scripts/bench.mjs` (headless Chrome), `scripts/serve.mjs` (COOP/COEP), `scripts/jvm-baseline.mjs` (`--web` runs `WebJvmMain`). Games now pass the engine seed and AI seeds. |

## The web threading mode

Web Image runs one thread. The engine's thread boundaries become:

| Phone | Web | Rewrite |
|---|---|---|
| GAME thread (`XmageEngine.Running.worker`) | A task deferred until `create` has replied, then run on the worker's own thread by `WebHost` | `WebThreads.deferred()` |
| A human question waits on `answers.poll(250 ms)` | `WebThreads.awaitAnswer`: serves the page's requests (blocking in `Atomics.wait`, at most 250 ms per wait) until an answer is queued | `MobileHumanPlayer.waitForResponse` |
| CALL thread delivers answers (`MatchMailbox.delivery`) | Delivered inline, inside the `respond` request | `WebThreads.inline()` |
| Polls answered any time | Answered while the human waits, and one waiting request after each published snapshot (so AI turns show live) | `Running.snapshot()` |
| AI search: `FutureTask` on `threadPoolSimulations`, `task.get(maxSeconds)`, `cancel(true)` | Runs inline. The deadline is checked at every game copy and node (`AISearchMemory`); past it, `MobileWebInterrupt` is set, upstream's stop checks read it, the search unwinds, and the result is read as a timeout | `ComputerPlayer6`, `AISearchMemory`, `GameImpl.checkIfGameIsOver`, `PlayerImpl.canRespond` |
| `close` interrupts the GAME thread | Never interrupts (it would hit the request loop); the game stops at `hasEnded()`; `destroy` during a game answers `engine_busy_shutdown` until the game has unwound | `Running.close` |
| `saveResume` from the serialization self-test | `false`, no self-test (Java serialization traps the instance) | `Checkpoints.available` |
| `GZIPInputStream`, `CRC32` | Plain Java (no native zip library in Web Image) | catalogues, `GameRecorder` |

`create`, `restore` and `shutdown` that arrive while a game is on the stack are held until it returns, so one game
never runs inside another's stack. Logging is set to WARN (reload4j's default DEBUG with no appender builds and drops
every message; nothing reads it). AI searches get a fixed 1 GiB reading of available memory for `AISearchMemory`'s cap.

### Web Image runtime facts measured on this Mac (Oracle GraalVM 25.4.4.1.1, Node 22, Chrome 155)

Small probe images (15–80 s builds, about 0.7 GB builder memory each):

| API | Result |
|---|---|
| `Thread.interrupt()` on the current thread | **no-op** (`isInterrupted()` stays false) |
| `GZIPInputStream`, `Inflater`, `CRC32` | **`UnsatisfiedLinkError`: no library `zip`** |
| `ArrayBlockingQueue`/`LinkedBlockingQueue` timed `poll` | **`IllegalMonitorStateException`**; untimed `offer`/`poll`/`clear` work |
| `ReentrantLock` | `lock`/`unlock` work; `Condition.await` throws "Unsafe.park" |
| `FutureTask.run` | works alone; after a `Thread.interrupt()` it once trapped the instance ("Fatal unsafe read error … FutureTask") |
| `ConcurrentHashMap`, `ConcurrentLinkedQueue`, `CopyOnWriteArrayList`, `ConcurrentSkipListMap`, atomics, `VarHandle` CAS, `ThreadLocal`, `synchronized`/`wait(1)`, parallel streams, `UUID`, `String.format`, `MessageDigest` | work |
| `AtomicReferenceFieldUpdater` | NPE (needs reflection metadata; XMage doesn't use it) |
| `java.awt.Color` | works unchanged (no JNI bootstrap problem, unlike GraalVM 22.1 on phones) |
| `@TargetClass(Thread.class) @Substitute start()` in user code | accepted; a stray start then throws |
| `@JS` natives, `JS.Coerce` with `String` and `boolean` | work; need `args={...}` without `javac -parameters` |
| `Atomics.wait` in the worker inside a Java → JS call, `postMessage` from the blocked worker | work (Node worker_threads and Chrome) |

### Checks

- **Phone builds unchanged:** `git diff main -- packages/ondevice-engine` is empty. `test_real_engine.sh` on the JVM:
  passed (exit 0, 163 PASS lines, 141 s of the final suite; 2026-10-20).
- **gzip and CRC-32:** `test/WebZipTests.java` against `java.util.zip`: 40 checks, including the three real catalogues
  (81.4 MB card metadata in 805 ms on HotSpot) and stored, fixed and dynamic blocks.
- **Web mode on HotSpot** (`WebJvmMain`, same Java sources as the image; `jvm-baseline.mjs --web`, 8 GB Mac shared with
  other sessions): **87 of 92 seeded games ended**, and the engine started no thread (the harness exits 3 on any new
  thread). AI turn median 0.19 s, p95 0.98 s, max 6.8 s (985 turns); board update median 7 ms, p95 21 ms; 4-player
  game start 55–83 ms. The 5 failures are one pre-existing engine bug, below.
- **Browser plumbing:** a stub image (the real `WebHost`, `EngineService`, JSON and CRC-32 over a stub engine, 9.6 MB)
  in headless Chrome 155: engine ready 0.5 s first visit, 0.3 s cached; Wasm compile 185 ms.

### Engine bug found (phones too)

A game copy that ends calls `GameImpl.end()`, which aborts the copy's players; a `MobileHumanPlayer` copy shares the
live player's input channel, so the live human's channel closes. Upstream `CombatUtil.willItSurviveSimple` (the AI
choosing blocks) runs state-based actions on such a copy. From then on every question to the human throws, XMage rolls
back and asks again, and the game ends without the human. It is not threading-related, so phones have it too. It is
not fixed in this branch: an engine change ships in its own release. The fix is on local branch
`claude/engine-copy-abort-channel` (commit `ccd1365a`, with a test; `test_real_engine.sh` passed, 164 PASS), not pushed.

## Engine identity and ranked

- The web build reports `engineBuild` = `web-1:sha256:…` from `web_identity.py`: the phone identity, the toolchain
  (`native-image --version`) and every web-only input (the rewriter, `src/`, `src-svm/`). It never reports a phone
  build's identity, so `ranked_engine_builds` cannot mistake it for one.
- The web AI differs from phones in ways the identity must capture: searches are inline (no parallel simulation
  threads), search speed differs (WebAssembly in Chrome), and the stop checks read a flag instead of an interrupt. The
  seeded parts of a game (shuffles, mistake rolls) are the same.
- Before ranked (M5): a web calibration run (`tools/ai-calibration`) against the phone numbers, then a
  `ranked_engine_builds` row labelled for example `web-1 Web Image 25.4`. Tampering in a browser is easier; keep the web
  unranked until that is accepted.

## How to run

```sh
# JVM input (once), then the web mode on HotSpot
zsh scripts/dev/heavy.sh "build_jvm" -- bash packages/ondevice-engine/scripts/build_jvm.sh
MM_WEB_TOOLCHAIN=local bash packages/web-engine/build_web.sh sources && bash packages/web-engine/build_web.sh jvm
python3 packages/web-engine/export_precons.py --catalogue packages/ondevice-engine/build/generated/catalogue.jsonl \
  --swift apps/ios/MagicMobile/PreconCatalog.swift --output packages/web-engine/build/decks
cd apps/web-play && node scripts/jvm-baseline.mjs --web --games 2p:1,4p:2   # MM_WEB_TRACE=1 traces each request
# Browser: download the CI artifact web-engine-bundle-<sha> into packages/web-engine/build/web, then
npm install && npm run build
node scripts/bench.mjs --ready-visits 2 --games 2p:1,4p:2
```

## Not done

- **Firefox and Safari smoke runs** (see the gate table). To run one by hand: `cd apps/web-play && npm run build &&
  node scripts/serve.mjs`, then open `http://127.0.0.1:5178/bench.html?games=2p:1` in the browser; the tab title
  shows the status.
- **A cheaper build.** The free runner works only with swap and little to spare. Before routine rebuilds, shrink the
  image heap: class metadata for 62k types is most of it. Then the build should fit 16 GB without swap, and the module
  and its startup also shrink. If it can't be shrunk enough, a 64 GB machine for one build costs about €1.30–1.80
  (Hetzner CCX43, €0.4431/h, 2026-10-21 price); a workflow could create and delete it per build.
- **Updates without a full rebuild** (researched 2026-10-20 by the coordinating session): engine-code changes need a
  rebuild. Native Image layers exist for native targets but are undocumented for Web Image, and a run-time bytecode
  interpreter (Crema) would be far too slow for AI search. Data updates (catalogue, precons) and UI changes ship
  without one. So the plan is a free, automatic rebuild with each phone engine release, served under a
  content-hashed name so browsers download only a changed engine.
- **Toolchain:** Oracle GraalVM 25.4.4.1.1 is the newest release (25.5 is due about 2026-10-27). XMage stays at the
  phones' pin, `dac400b` with release C: changing it would break cross-play identity with phones, and it goes
  through the normal XMage update flow.
- **Production questions** for M3: serving 174 MB from Vercel (CLI upload limit 100 MB; a Git build or chunks plus
  `compileStreaming`), Cache API storage keyed by engine identity, and Vercel Hobby's transfer budget.
