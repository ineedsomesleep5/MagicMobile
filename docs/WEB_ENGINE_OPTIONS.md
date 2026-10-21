# Web engine options: XMage for desktop browsers, with no game server

Research and decision doc, 2026-10-20 (Claude). Nothing here ships to players and no app code changed.
Question: how should a desktop-only web version of MagicMobile run the rules engine on the player's own
computer? Allowed hosting: the static site (Vercel), the existing Supabase project and the existing table
relay. Any route that needs new hosting counts against it.

## Recommendation

1. **Run XMage itself in the browser, compiled with GraalVM Web Image** (Oracle GraalVM 25.1 or later,
   experimental), inside a Web Worker. It is the only in-browser route that passed the checks that broke
   CheerpJ: reflection on final fields and Gson both work. It is single-threaded, and Java serialization
   crashes it (both measured below). So the engine needs a web-only threading mode, and web games have no
   save/resume at first. First milestone: one full game in Chrome (M1, about 2 weeks).
   **M1 outcome (2026-10-21): go.** The real engine runs in Chrome and passes every measured gate; see the M1
   outcome under Plan and `docs/WEB_ENGINE_M1.md`.
2. **Online play goes through the existing relay.** A browser can already join a phone-hosted table: the
   relay doesn't check origins, so joining needs no engine. Hosting from a browser needs an engine and a
   small CORS change to the relay.
3. **Fallback if M1 fails its gates:** a Tauri desktop app that bundles a JVM. It's the fastest and least
   risky engine, but it's an install, not a web page.
4. **Not recommended:** CheerpJ (broken in the spike, no fix since), TeaVM (more gaps than Web Image),
   CheerpX (32-bit x86 only, 5–10× slower), the older Java-to-Wasm compilers, a localhost helper, and
   switching to another engine.

## What the spike branch proved (`codex/web-engine-spike`, Sept 25–26, 2026)

The spike (`docs/WEB_ENGINE_SPIKE.md` on that branch, head `bd6b6d88`) ran the real engine adapter in a
browser through CheerpJ 4.3. **Verdict: no-go on both the Java 17 and Java 11 runtimes.**

- **Boot works.** All 33 jars (93 MB, about 74 MB read at boot) and the unmodified adapter started in a
  Web Worker. `capabilities` answered with the same catalogue hash as iOS.
  - First visit: 17–26 s.
  - Cached visit: 13–17 s. 11–15 s of that was Java constructing `XmageEngine` (set registry and
    catalogue), not download.
- **No game reached its first prompt.** CheerpJ lacks the `Unsafe` `get/put<narrow>Volatile` natives,
  which JDK reflection uses for every final field. Two callers hit them:
  - upstream `Watcher.copy`, on every game copy;
  - Gson in `ViewProjector`, on every snapshot.

  JavaScript natives could not call back into Java in any of the four forms tried.
- **Reusable pieces for the next spike:**
  - `WebEntryPoints.request(String) → String` over the normal JSON protocol;
  - a Promise engine client (`apps/web-play/src/engineClient.ts`);
  - a transport-agnostic autoplay driver (`autoplay.ts`);
  - a Playwright bench with pass targets (`bench.mjs`);
  - a HotSpot baseline on the same machine (`jvm-baseline.mjs`). Board update: median 27 ms, p95 44 ms.
    AI turn: median 1.0 s, p95 11.3 s.
- The spike's next options were hosted solo on `apps/multiplayer-server` or a GraalVM Web Image spike.
  Hosted solo needs a game server, so this brief rules it out. That leaves Web Image.

## What any route must give XMage

| Need | Where in the engine | Notes |
|---|---|---|
| A GAME thread that blocks until the human answers | upstream `HumanPlayer` (`response.wait()`, about line 337); `XmageEngine` runs each game on a single-thread executor | Answers arrive from another thread (`MatchMailbox`'s CALL thread) |
| AI searches with a wall-clock timeout | `ComputerPlayer6`: `FutureTask` on `threadPoolSimulations`, then `task.get(maxSeconds)` and `cancel(true)` | Think time is skill × 3 s; release C stops searches at game copies (`AISearchMemory.Stopped`) |
| Reflection over final fields | upstream `Watcher.copy`; Gson over `mage.view` in `ViewProjector` | This is what broke CheerpJ |
| Java serialization | only save/resume checkpoints (`Checkpoints.java`); no game path uses `mage.util.Copier` | Solo save/resume depends on it |
| Size | phone engine: 202 MB of AOT code plus 167 MB of image heap (GraalVM 22.1, before release C's cuts), 48,739 card classes | `docs/cloud/engine-size.md` |
| Memory | JVM live heap about 147 MB in long-game profiles; release C cut the start-up heap from 26.5 to 4.5 MB | One AI search reached 1.9 GB before release C's fix (`docs/LESSONS.md`) |

## Measurements taken for this doc (2026-10-20)

A throwaway probe (about 150 lines of Java, kept in the session's scratch area only) checked each need above.
It also timed a synthetic deep copy: 20,000 objects with their lists and maps, copied 50 times, which is what
XMage's AI repeats at every search node. Setup:

- **Source and toolchain:** the same source on every runtime. Reflection metadata came from the standard
  native-image tracing agent and worked unchanged for Web Image.
- **Machine:** an 8 GB MacBook with 6 cores, shared with another session's iOS preflight. Each run went
  through `scripts/dev/heavy.sh`.
- **Versions:** Oracle GraalVM 25.4.4.1.1 (2026-09-22), Chrome 155.0.8059.85 headless, Node 22.23.1
  (which needs `--experimental-wasm-exnref`).

| Check | HotSpot (OpenJDK 25) | Native image (macOS) | **Web Image in Chrome** | Web Image in Node |
|---|---|---|---|---|
| `UUID`/SecureRandom, `String.format`, `ConcurrentHashMap`, `ThreadLocal`, `Class.forName` | pass | pass | pass | pass |
| Reflection on final `int`/`boolean` fields | pass | pass | **pass** | pass |
| Gson to/from JSON (final fields, no no-arg constructor) | pass | pass | **pass** | pass |
| `Thread.start()` + `join()` | pass | pass | **runs nothing, no error** | same |
| `Object.wait(50)` / `Thread.sleep(20)` | 57 / 26 ms | 57 / 25 ms | **return after 0 ms** | same |
| wait/notify across threads | pass | pass | **notifier never runs**; an unbounded wait loop spins forever | same |
| `FutureTask.get(300 ms)` then `cancel` | pass | pass | **`IllegalThreadStateException`** | same |
| Java serialization round trip | pass | pass | **fatal:** "Detected off-heap memory access. This is currently not supported", then a Wasm `unreachable` trap that kills the instance | same |
| Deep copy, ms per copy (lower is faster) | 2.30–2.64 | 4.06 | **5.76–8.74** | 13.50–16.98 |
| 512 MB of live objects | pass | pass | pass (`maxMemory` 4,096 MB) | pass |
| `availableProcessors` | 6 | 6 | 1 | 1 |

Sizes and builds:

| Output | Size | Build time | Builder peak RSS |
|---|---|---|---|
| Web Image `.wasm` | 11.26 MB (4.20 MB at `gzip -9`), plus a 108 KB JS wrapper | 45 s | 1.18 GB |
| macOS native executable | 18.8 MB | 69 s | 1.02 GB |

The probe reached 4.6k types.

Hosting checks against live services:

- **Relay:** the CORS preflight for `POST /v1/tables` returned `405` with no `Access-Control-Allow-Origin`.
  A browser page cannot open a table today. Joining is a WebSocket, which needs no CORS.
- **GitHub release assets** (where the APKs live): neither the redirect nor the file sends
  `Access-Control-Allow-Origin`, so a web page cannot fetch an engine from Releases. It must come from the
  site itself.
- **Scryfall:** `cards.scryfall.io` and `api.scryfall.com` send `Access-Control-Allow-Origin: *`. Card art
  therefore still loads with `crossorigin="anonymous"` on a cross-origin-isolated page (COEP
  `require-corp`).

Caveats:

- The copy benchmark is synthetic, not XMage, and comes from two or three samples on a loaded machine.
- Firefox and Safari were not run, since there is no driver for them on this Mac.
- Nothing was measured on a phone.

## Estimates (not measured)

- **Engine download.** The probe's Wasm is about 0.6× its native binary, and the phone engine was about
  370 MB before release C. That suggests roughly **150–250 MB of raw Wasm, or 55–90 MB compressed**.
  Dropping the checkpoint serialization registrations (50,816 classes) should help, since the web build
  can't use them.
- **Start-up.**
  - First visit: about 20–60 s (download, compile, engine construction).
  - Cached visit: about 5–15 s.
  - Release C removed the set install, which cost 10.5 s on a cold JVM and was most of the spike's cached
    boot.
- **Memory.** About 0.5–1.5 GB per tab. WasmGC objects live in V8's heap, which is capped at about 4 GB per
  renderer process [S17], so a runaway AI search crashes the tab rather than swapping.
- **AI think time.** Each search has a fixed time budget (skill × 3 s), so turns take as long as on phones.
  What changes is how many search nodes fit into that budget: about 45–70% of a native build on the same
  laptop, judging by the copy benchmark. Single-threaded Wasm also gets no parallel simulation threads.
  How this compares with a phone is unmeasured: M1 and a calibration run would show whether web AI plays
  weaker.
- **Realistic size limit.** Browsers accept Wasm modules up to 1 GiB [S16]. The practical ceiling is about
  **100 MB compressed (about 300 MB raw)**, for two reasons:
  - At 100 MB, a first visit takes over a minute on average broadband.
  - Vercel Hobby includes 100 GB of transfer a month [S19], which covers about 1,000 such downloads, and
    every engine update triggers a fresh download.

  A 300 MB *compressed* download is not realistic on the current plan.

## Comparison

### In-browser engines

Sources are in brackets ([S…]) and listed at the end.

| Route (status, date) | Threads and AI timeout | Reflection / Gson | Save/resume | Size and start-up | Speed | Cross-origin headers | Licence | Verdict |
|---|---|---|---|---|---|---|---|---|
| **GraalVM Web Image**: Oracle GraalVM 25.1+, experimental; latest is 25.4.4.1.1 from 2026-09-22 [S1–S3]. CE support is unclear [S5, S6] | Single-threaded (measured): needs a web-only threading mode (see M1) | Pass (measured) | No: serialization traps (measured) | 55–90 MB compressed (estimate) | 1.4–2.2× slower than native in Chrome (synthetic, measured) | Only if the answer wait uses `Atomics.wait`; a Service Worker fallback needs none | GFTC: free, including redistribution not for a fee [S4] | **Recommended: M1** |
| **TeaVM** 0.16.0, 2026-10-02 [S7] | Green threads in Wasm GC since 0.13, but no `ExecutorService` or `FutureTask` [S8] | Only for classes declared reflectable; Gson and `Watcher.copy` are unproven | None (no `ObjectOutputStream`) [S8] | Unknown | Unknown | Not needed | Apache-2.0 | No: more gaps than Web Image; its own docs say it isn't for large existing codebases [S8] |
| **CheerpJ** 4.3, 2026-04-21, still the latest [S9] | Real Java threads | **Fails**: missing `Unsafe` natives (spike) | Unknown | 74 MB of jars at boot; cached boot 13–17 s (spike) | No game finished | Not needed | Free Community licence covers individuals and FOSS, with the runtime loaded only from Leaning's CDN; self-hosting needs a commercial licence [S10] | **Ruled out**: no fix in the changelog; Java 17 at most |
| **CheerpX** (x86 Linux in the browser) running a 32-bit JDK | Real | Real | Real | Disk image 300–600 MB (estimate) | 5–10× slower than native, by the vendor's own claim [S11] | Required [S11] | Like CheerpJ | **Ruled out**: 32-bit only, the x86-32 JDK port is removed in JDK 25 [S12], and there's no HotSpot example |
| J2CL Wasm, Bytecoder, JWebAssembly, DoppioJVM | None | None | None | — | — | — | — | Ruled out: source-level JRE emulation, or dormant [S13] |

Web Image runs on browsers with WasmGC and exception handling: Chrome and Edge 137+, Firefox 131+,
Safari 18.4+ [S14].

### Other routes

| Route | What it gives | What it can't do, and what it costs | Verdict |
|---|---|---|---|
| **Browser as relay guest only** | Plays at phone-hosted relay tables today (the WebSocket join needs no CORS); no engine download | No solo against the AI, no hosting, no Game Center tables. Ranked play only when the phone hosts. The host phone must stay in the foreground | **Build it** (M2); also needed by every other route |
| **Tauri desktop app with a jlink'd JRE and the jars** | The unmodified engine with real threads, save/resume and HotSpot speed (fastest in the probe) | An install, not a page. About 150 MB (estimate: JRE about 50 MB plus jars about 90 MB). Static updates from GitHub Releases [S21]. macOS Developer ID is included in the existing Apple membership; Windows signing is $9.99/month, or unsigned with SmartScreen warnings [S22] | **Fallback** |
| Tauri with a native-image sidecar | Same, with an AOT engine | Slower than HotSpot (probe), and native-image builds per OS | Fallback variant only |
| Web page plus a localhost engine helper | Web UI with a local JVM | Still an install. Chrome asks a Local Network Access permission (142+, WebSockets from 147) [S23]. Safari blocks `http`/`ws` to 127.0.0.1 from https pages [S23] | No |
| Forge or another engine | — | Forge is Java (GPL-3.0) with no browser build. Browser-native engines are Rust rewrites with thousands of cards still missing: phase-rs, the Rust port of Forge in Manabrew, DeepScry [S24]. Switching means a new adapter, AI calibration, ranked records and parity goldens, and cross-play with phones breaks | No; nothing beats XMage's coverage (over 32,000 cards [S24]) |

## The relay: how it works and what a browser needs

- **It isn't a game server.** `services/table-relay` is a Cloudflare Worker on the free plan, with one
  Durable Object per table. The host phone runs XMage. The relay only passes packets along, stamps each one
  with the sender's relay-assigned ID, keeps messages for a dropped phone for 90 s, and deletes a table
  after 30 idle minutes. It's already deployed, so it stays within the brief.
- **Joining from a browser works today.** Browsers can offer the `magicmobile.1` subprotocol and the relay
  never checks `Origin`.
  - The guest must present the relay identity: upstream commit, catalogue hash, and
    `ondevice-0.1/relay-1/rollstep-2/room-1/concede-1/emote-1/chat-1/clock-1`
    (`OnDeviceRootView.swift`, `relayIdentity`).
  - The web build must ship the matching card catalogue, and redeploy the same day as each phone engine
    update. Alternatively it can also ship the previous catalogue so it can still meet phones that haven't
    updated.
  - Through `HostRouter`, guests can only send `hello`, `poll`, `respond` and `concede`, and see only their
    own seat.
- **Hosting from a browser** needs two things:
  - an engine in the page;
  - `OPTIONS` plus `Access-Control-Allow-Origin` for the site on `POST /v1/tables`, a small change that
    shipped apps won't notice.

  Keeping a host tab open in the background may throttle timers: test this in M4.
- **Ranked PvP.** The matched host opens the table (`docs/RANKED.md`). A guest-only browser must never be
  given the host role, and two engine-less players must never be paired. That's a client rule plus a
  queue flag in Supabase.

## What's shared with the apps

- **Accounts.**
  - The `mm_*` RPCs are plain REST with the publishable key and work from a browser. The account model is
    the same: anonymous first, then linked to Apple or Google.
  - Web sign-in needs dashboard changes: the site's redirect URL in Supabase Auth, an Apple Services ID
    with a return URL for Sign in with Apple on the web, and the existing Google web client ID.
  - Cross-origin isolation (COOP `same-origin`) breaks OAuth pop-ups, so sign-in must use the redirect
    flow.
- **Ranked engine identity.**
  - `ranked_engine_builds.engine_build` is the SHA-256 that `scripts/engine_build_identity.py` takes over
    the adapter sources (`engine/core`, `engine/xmage`, `platform/java`), the upstream lock and the patch
    scripts. The runtime isn't part of it.
  - Web-only shims kept outside those trees would leave the hash unchanged. A web build would then claim a
    phone build's identity while its AI behaves differently.
  - **Rule:** the web build hashes its shim sources too and gets its own row (for example label
    `web-1 Web Image 25.4`), added only after a web AI calibration run.
  - `mm_ranked_ai_record_check` (seed, depth and mistakes per skill, record grammar) applies unchanged.
  - Tampering is easier in a browser (devtools) than in a store app. Keep web unranked until that's
    accepted.
- **Protocol and logic.**
  - Same JSON protocol v1 (`PROTOCOL.md`), snapshot schema, answer kinds, `HostRouter` rules, packet
    chunking, turn clock and chat rules.
  - `apps/android/core` is pure Kotlin: 62 files, 15.8k lines, using kotlinx.serialization and coroutines,
    with only a few `java.*` imports. It can become Kotlin Multiplatform with a JS or Wasm target, as
    `docs/HANDOFF_WEB_PLAYTEST.md` already planned, or be ported to TypeScript and checked against the
    shared parity JSON cases.
  - The card catalogue (`ondevice-catalogue.json`) and deck resolution are shared as well.

## Risks

1. **Web Image is experimental and Oracle-only for now** [S1, S2]. There are monthly feature releases, and
   behaviour may change. It means a second toolchain beside Gluon (phones move to JDK 23 in release D;
   Web Image needs GraalVM 25.1+ [S1, S2]).
2. **The threading rework touches upstream classes** (`HumanPlayer`, `ComputerPlayer6`) and the adapter
   (`XmageEngine`, `MatchMailbox`). It must be a switch that leaves phones byte-for-byte unchanged and is
   covered by `test_real_engine.sh`. Because `Thread.start` silently does nothing on Web Image, the web
   build should make any thread start fail loudly.
3. **Serialization traps instead of throwing.** The `capabilities` save/resume self-test would kill the web
   engine, so it must be off at build time. Web solo games can't be resumed until another approach lands,
   such as replaying the game record.
4. **The full engine's Wasm size, compile time, and Firefox and Safari WasmGC speed are unmeasured.** The
   phone build's analysis used about 9.8 GB of a 10 GB builder heap, so the Web Image build needs a
   GitHub-hosted runner, not this Mac.
5. **Memory:** a 4 GB per-process heap cage [S17]. AI search limits (`AISearchMemory`) must hold on the web.
6. **Hosting:** Vercel Hobby's 100 GB/month and its "non-commercial personal use" rule [S19]; check the
   site's tip link against that. The CLI upload limit is 100 MB; a Git-built site can fetch the engine at
   build time, or the engine can be split into chunks and streamed into `WebAssembly.compileStreaming`.
   Serving a single 150–250 MB file from Vercel needs a test deploy.
7. **Caching:** Safari deletes script-written storage, including the Cache API and OPFS, after 7 days of
   browser use without a visit [S18], so Safari players who come back late download again.
8. **Version lockstep:** relay identity, phone engine updates (weekly XMage watch) and web deploys must
   move together.
9. **Card IP:** a public web page is more visible than TestFlight and APK links. `HANDOFF_WEB_PLAYTEST.md`
   advises keeping it free, on private links, and ready to take down.

## Plan

**M1: Web Image engine spike.** About 2 weeks of agent time, plus GitHub Actions builds (about an hour
each, estimated).

> **Outcome, 2026-10-21: go** (`docs/WEB_ENGINE_M1.md`). Measured in headless Chrome 155 on the 8 GB Mac:
>
> - Size: 173.8 MB raw Wasm, 45.0 MB at gzip -9.
> - Engine ready: 3.0 s first visit from localhost, 2.6–2.9 s cached. With the download, about 10–17 s at 25–50
>   Mbit/s (estimated).
> - 4-player start: 0.11 s.
> - AI turn: median 0.99 s, p95 4.4 s.
> - Seeded games: 10 of 10 finished.
> - Tab memory: renderer 1.04 GB, whole browser 1.31 GB.
>
> Not yet run: the Firefox and Safari smoke runs.
>
> Build cost: free, on a GitHub runner, in 44 min. It only fits with a 24 GB builder heap spilling into 16 GB of
> swap, and peaked near the limit. Two Web Image limits needed workarounds:
>
> - **Writing the image heap needs ~17 GB.** The heap is 89 MB, mostly class metadata for 62k types.
> - **V8 caps a Wasm function at 7.65 MB.** The fix is `-H:ImageHeapObjectsPerFunction=4000`.
>
> The threading mode is built from rewritten copies of the sources, so phone builds are unchanged. It also needs
> plain-Java gzip and CRC-32, and an AI stop flag (on Web Image, `Thread.interrupt()` is a no-op).
>
> **Next, before M3 relies on routine rebuilds:**
>
> - Shrink the image heap so the build fits 16 GB without swap. **Done 2026-10-21** with a patch to the Web Image
>   builder (12 GB heap, no swap, 34 min; 137 MB module), which raises an Oracle licence question for Caleb; the
>   workflow now rebuilds by itself for engine changes (`docs/WEB_ENGINE_M1.md`, "Fitting the free runner").
> - Run the Firefox and Safari smoke runs.
> - Then M3 and an AI calibration run. The web AI explores about 5× fewer positions per second than HotSpot.
>
> Engine updates still need a full rebuild. Make it free and automatic with each phone engine release, and serve
> the engine under a content-hashed name. Data and UI updates ship without a rebuild.
>
> F (Tauri) is no longer needed as the fallback for the engine.

- Build the adapter and pinned XMage (release C sources) with Oracle GraalVM 25.x `--tool:svm-wasm` in CI.
  Reachability metadata comes from the tracing agent run over the real-engine tests; checkpoint
  serialization registration is off.
- Add a web threading mode behind a switch that's off on phones:
  - The game runs on the worker's own thread.
  - A human question blocks in a JS import using `Atomics.wait` on a SharedArrayBuffer (COOP/COEP on
    `/play`). A Service Worker sync channel is the fallback.
  - AI searches run inline with a deadline checked at every game copy, instead of on the pool.
  - The mailbox delivers synchronously, and polls are answered from the last published snapshot.
  - `saveResume` is false.
- Reuse the spike's `apps/web-play` bench and its targets, and add size gates:

  | Gate | Target |
  |---|---|
  | Engine size | ≤ 300 MB raw and ≤ 100 MB compressed |
  | Engine ready | ≤ 45 s on the first visit, ≤ 10 s cached |
  | 4-player game start | ≤ 10 s |
  | AI turn | median ≤ 5 s, p95 ≤ 15 s |
  | Seeded games | 10 of 10 finish |
  | Tab memory | ≤ 2 GB |
  | Other browsers | a smoke run in Firefox and Safari |

- **Unblocks:** the in-browser go/no-go, web solo (M3), web hosting (M4) and the ranked identity design.
  If it fails, go to F.

**M2: web guest client.** About 3–4 weeks. It touches no engine files, so it can run beside M1, but one
heavy job at a time on this Mac.

- What it covers:
  - the Duel Board prototype fed with real snapshots;
  - relay join;
  - the shared core (Kotlin Multiplatform or TypeScript);
  - Supabase accounts and sign-in;
  - deck import.
- **Unblocks:** browser players at phone-hosted tables, and friend challenges where the phone hosts.

**M3: web solo against the AI** (after M1 passes). About 3–4 weeks.

- What it covers:
  - the engine in a worker;
  - caching keyed by engine identity in the Cache API or OPFS, plus `navigator.storage.persist()`;
  - COOP/COEP headers on `/play` in `vercel.json` [S20];
  - Deck Studio;
  - Edge, Firefox and Safari passes.

**M4: hosting from the web.** About 1–2 weeks: the relay CORS change, `HostRouter` and the turn clock on the
web, and background-tab behaviour.

**M5: ranked on the web.** About 1–2 weeks, plus migration approval: the web identity row, AI calibration,
and the queue's host rule.

**F (fallback): Tauri desktop app** with a jlink'd JRE. About 2–3 weeks, plus signing setup.

## Needs Caleb's decision

1. Approve M1, including GitHub Actions time for full-engine Web Image builds and Oracle GraalVM (GFTC) as
   a second engine toolchain.
2. Start M2 (the guest client) now, or wait for M1?
3. Who gets the web version: a private link or anyone? (Card IP; Vercel Hobby's non-commercial rule and its
   100 GB/month.)
4. Accept no save/resume for web solo games at first?
5. Keep the web unranked until calibration, or plan M5 now?
6. If M1 fails: the Tauri app, and paid Windows signing ($9.99/month) or unsigned?
7. Later dashboard actions only Caleb can take: Supabase Auth redirect URLs and an Apple Services ID for
   web sign-in; deploying the relay CORS change (M4).

## Sources

Dates are publication or update dates. Where a page has no date, the date given is when it was fetched
(2026-10-20). Some sources are older than 2026; their dates are shown.

- S1 GraalVM Web Image reference, fetched 2026-10-20: https://www.graalvm.org/latest/reference-manual/web-image/
  and API guide https://www.graalvm.org/dev/reference-manual/web-image/api-guide/
- S2 GraalVM 25.1.3 release notes (2026-06-30), "Web Image … experimental … Oracle GraalVM 25.1 or later":
  https://www.graalvm.org/release-notes/25.1/
- S3 GraalVM 25.4.4.1.1 release notes (2026-09-22) and downloads: https://www.graalvm.org/release-notes/25.4/,
  https://www.graalvm.org/downloads/
- S4 GraalVM Free Terms and Conditions (updated 2023-06-12) and FAQ:
  https://www.oracle.com/downloads/licenses/graal-free-license.html, https://www.graalvm.org/faq/
- S5 myTunes Web Image notes: single-threaded, Oracle GraalVM only; about 2026-10-14:
  https://github.com/patbaumgartner/mytunes
- S6 julc Web Image build notes (2026): https://github.com/bloxbean/julc/blob/main/julc-playground/BUILD_FROM_SOURCE.md
- S7 TeaVM releases: 0.16.0 (2026-10-02), 0.13.0 with Wasm GC coroutines (2025-11-03):
  https://github.com/konsoletyper/teavm/releases
- S8 TeaVM class-library report and overview, fetched 2026-10-20:
  https://teavm.org/jcl-report/recent/packages/java.util.concurrent.html, https://teavm.org/docs/intro/overview.html
- S9 CheerpJ changelog, 4.3 (2026-04-21) is the latest: https://cheerpj.com/docs/changelog
- S10 CheerpJ licensing and FAQ, fetched 2026-10-20: https://cheerpj.com/docs/licensing, https://cheerpj.com/docs/faq
- S11 CheerpX 1.0 (2024-12-04) and getting started: https://labs.leaningtech.com/blog/cx-10,
  https://cheerpx.io/docs/getting-started
- S12 JEP 503, Remove the 32-bit x86 Port (JDK 25, 2025): https://openjdk.org/jeps/503
- S13 J2CL Wasm (experimental) https://github.com/google/j2cl/blob/master/docs/getting-started-j2wasm.md;
  JWebAssembly (last release 2022-03-20) https://github.com/i-net-software/JWebAssembly;
  DoppioJVM (last commit 2021-08-04) https://github.com/plasma-umass/doppio; Bytecoder (last release 2024-05-10)
- S14 WebAssembly feature status, fetched 2026-10-20: https://webassembly.org/features/
  - WasmGC: Chrome 119, Firefox 120, Safari 18.2.
  - exnref: Chrome 137, Firefox 131, Safari 18.4.
  - Memory64: Chrome 133, Firefox 134, Safari behind a flag.
- S15 MDN COEP (2026-09-04) https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Cross-Origin-Embedder-Policy;
  COEP `credentialless` is not supported in Safari, fetched 2026-10-20:
  https://caniuse.com/mdn-http_headers_cross-origin-embedder-policy_credentialless
- S16 WebAssembly JS API implementation limits (1 GiB module, 1,000,000 functions) (2019-12-05):
  https://www.w3.org/TR/wasm-js-api-1/
- S17 V8 9.2, a pointer-compression cage shared per process (2021-07-16): https://v8.dev/blog/v8-release-92
- S18 MDN storage quotas and eviction (2026-01-05)
  https://developer.mozilla.org/en-US/docs/Web/API/Storage_API/Storage_quotas_and_eviction_criteria;
  WebKit storage policy (2023-08-10) https://webkit.org/blog/14403/updates-to-storage-policy/
- S19 Vercel limits (page from September 2026, fetched 2026-10-20) https://vercel.com/docs/limits; Hobby plan
  and fair use (2026-09) https://vercel.com/docs/plans/hobby, https://vercel.com/docs/limits/fair-use-guidelines
- S20 `vercel.json` headers (2026-08-14): https://vercel.com/docs/project-configuration/vercel-json
- S21 Tauri sidecar (2026-06-15) https://v2.tauri.app/develop/sidecar/; updater (2025-11-28)
  https://v2.tauri.app/plugin/updater/
- S22 Apple Developer Program https://developer.apple.com/programs/enroll/; Azure Artifact Signing pricing
  https://azure.microsoft.com/en-us/products/artifact-signing and quickstart (2026-05-21)
  https://learn.microsoft.com/en-us/azure/artifact-signing/quickstart
- S23 Chrome Local Network Access https://developer.chrome.com/blog/local-network-access (2025-06-09),
  WebSockets from Chrome 147 https://developer.chrome.com/release-notes/147; WebKit's localhost block
  https://bugs.webkit.org/show_bug.cgi?id=173161 (2017)
- S24 XMage README, fetched 2026-10-20: https://github.com/magefree/mage. Forge missing-cards wiki, fetched
  2026-10-20: https://github.com/Card-Forge/forge/wiki/Missing-Cards-in-Forge. Manabrew (2026-06-24):
  https://manabrew.app/blog/play-magic-in-your-browser/. phase-rs: https://phase-rs.dev/. DeepScry:
  https://deepscry.net/
- Internal:
  - spike doc on `codex/web-engine-spike` (`bd6b6d88`, 2026-09-26);
  - `docs/cloud/engine-size.md`;
  - `packages/ondevice-engine/docs/PROTOCOL.md`;
  - `services/table-relay/README.md`;
  - `supabase/migrations/20261016120000_ranked_ai_records.sql`;
  - `packages/ondevice-engine/scripts/engine_build_identity.py`;
  - `docs/LESSONS.md`.
