# Web engine spike: real XMage in the browser via CheerpJ

Status: spike, September 25, 2026. It ships nothing to players.

Question: can the real XMage engine (the same adapter the iOS app embeds) run inside a
browser tab through [CheerpJ](https://cheerpj.com/), fast enough for web solo play?

**Verdict: no-go for CheerpJ 4.3.** The real engine boots in the browser (17–26 s first visit,
13–17 s cached), but no game reaches its first prompt. The Java 17 runtime lacks natives that JDK
reflection needs, and JavaScript natives could not stand in for them. Details and numbers below.

## What was built

| Path | What it is |
| --- | --- |
| `packages/web-engine/WebEntryPoints.java` | Static `request(String) -> String` that lazily creates `EngineService` over `new XmageEngine("web-cheerpj")`. Same JSON protocol as `EngineCli` and `NativeEntryPoints`. |
| `packages/web-engine/build_web.sh` | Builds git-ignored `packages/web-engine/build/web/`: 33 jars, resolved precon decks and `manifest.json` (sizes, SHA-256, upstream commit, catalogue hash, shadowed classes, `javaRelease`). `--java 11` builds the Java 11 variant into `build/web-java11/` (see Java 11 follow-up). |
| `packages/web-engine/java11_sources.py` | Copies the adapter sources into `build/java11/src` and rewrites their six Java 16+ lines there, so they compile with `--release 11`. Fails if any line no longer matches. |
| `packages/web-engine/shadow/mage/watchers/Watcher.java` | Web-only copy of upstream `Watcher` whose `copy()` moves field values with `sun.misc.Unsafe` plain accessors instead of reflection (CheerpJ workaround, see Results). Compiled into `magicmobile-engine.jar`, which is first on the browser classpath. iOS, Android and the JVM baseline keep upstream's class. |
| `packages/web-engine/WebUnsafe.java` | Static plain `Unsafe` accessors that the worker's JavaScript natives call (CheerpJ workaround, see Results). |
| `packages/web-engine/export_precons.py` | Resolves the five bundled iOS precons (`PreconCatalog.swift`) against this build's catalogue with `resolve_deck.py`'s printing rule. |
| `apps/web-play/src/engine.worker.ts` | Classic Web Worker: `importScripts` the CheerpJ 4.3 loader, `cheerpjInit({version})` with the bundle manifest's `javaRelease` (17 or 11; for 17 also JavaScript implementations of six missing `Unsafe` natives), `cheerpjRunLibrary` over the jars, then forwards JSON requests to `WebEntryPoints.request`. |
| `apps/web-play/src/engineClient.ts` | Promise client with the Swift `EngineClient` operations: `capabilities`, `validateDeck`, `create`, `poll`, `respond`, `concede`, `destroy` (+ `shutdown`). |
| `apps/web-play/src/autoplay.ts` | Transport-agnostic driver: seat 0 is a scripted human (land, castable spells, attack with all, never block), other seats are XMage AI. |
| `apps/web-play/bench.html` | Boots the engine, plays the requested games (default a 1v1 and a 4-player Commander game) and shows timings live. |
| `apps/web-play/scripts/bench.mjs` | Headless Playwright run in the installed Google Chrome (`channel: "chrome"`); writes a metrics JSON. |
| `apps/web-play/scripts/serve.mjs` | Local static server: byte ranges, no compression (CheerpJ reads jars lazily with Range requests). |
| `apps/web-play/scripts/jvm-baseline.mjs` | Same driver and plan against the same compiled engine on HotSpot (`EngineCli`), for a same-machine reference. |

`packages/ondevice-engine/` is not modified. The build reads its sources and scripts and writes
only under `packages/web-engine/build/`.

### Upstream reuse

The existing Maven build in `MagicMobile-ondevice` is at upstream `8aea65ae`, but current main pins
`4825513287ba6c42c32fd205d227f4a5fc44c2f3` (`upstream.lock.json`, changed in 9453fe6). The jars could
not be reused, so `build_web.sh upstream` shallow-fetches the pinned commit into
`packages/web-engine/build/upstream/mage`, applies the repo's checked patches with
`prepare_upstream.py`, and runs `mvn package` (not `install`, so the shared `~/.m2` `org/mage`
artifacts other checkouts use are untouched). This took 2 min 14 s and about 600 MB on disk.
The generated catalogue hash is `f9b5676c…07bf`, the same as the shipped
`apps/ios/MagicMobile/Resources/ondevice-catalogue.json`.

## How to run

Needs JDK 17 (`/opt/homebrew/opt/openjdk@17` by default, or set `JAVA_HOME`), Maven, Node 22 and
Google Chrome. Every step except `npm install` is a heavy workload on an 8 GB Mac; run it behind
the machine-wide lock.

```sh
packages/web-engine/build_web.sh            # all stages; or: upstream | engine | shadow | package
cd apps/web-play
npm install                                 # own lockfile; not part of the pnpm workspace
npm run build                               # tsc + vite build -> dist/
npm run serve                               # http://127.0.0.1:5178/bench.html (Range, no gzip)
node scripts/bench.mjs --ready-visits 2     # cold + cached engine boot, headless Chrome
node scripts/bench.mjs --ready-visits 1 --games 2p:1,4p:2 --cap 900 --out <file>.json
node scripts/jvm-baseline.mjs --games 2p:1,4p:2 --cap 900 --out <file>.json
# Java 11 variant (after the Java 17 upstream + engine stages):
packages/web-engine/build_web.sh --java 11  # -> packages/web-engine/build/web-java11/
node scripts/bench.mjs --engine-dir ../../packages/web-engine/build/web-java11 --ready-visits 1 --games 2p:1,4p:2
```

`bench.html` parameters: `games` (`<players>p:<seed>` list), `cap` (seconds per game), `skill`
(XMage AI skill), `loader` (CheerpJ loader URL), `engine` (same-origin path of `build/web`),
`debug=1` (engine stack traces to the console). `bench.mjs --debug` sets it. Metrics JSON files
from this spike's runs are under the git-ignored `packages/web-engine/build/metrics/`.
Seeds drive deck order, which precons meet, and the scripted human's choices. XMage's own
shuffles and AI scheduling are not seeded, so two runs of one seed are not identical games.

## Results

Machine: an **8 GB MacBook** shared with two other agents' iOS/Android builds, so every number
is from a loaded laptop, not a quiet one. Google Chrome 153 headless (playwright-core,
`channel: "chrome"`, a fresh on-disk profile per run), CheerpJ 4.3 Java 17 runtime from the
CheerpJ CDN, jars from the local server with byte ranges and no compression.

### Engine boot works

The unmodified adapter boots in CheerpJ: all 33 jars on the classpath, `XmageEngine` constructed
with the generated set registry and platform card catalogue, `capabilities` answered with the
same catalogue hash as iOS (`f9b5676c…07bf`). Across runs:

| Run | Visit | Engine ready | CheerpJ worker ready | `capabilities` (XmageEngine construction) | Jar bytes from origin |
| --- | --- | --- | --- | --- | --- |
| probe-1 | first visit | 26.0 s | 10.0 s | 16.0 s | 73.8 MB (476 range requests) |
| probe-2 | first visit | 23.7 s | 7.3 s | 16.4 s | 73.8 MB (476 range requests) |
| probe-2 | second visit, jars `no-cache` | 20.3 s | 3.4 s | 16.9 s | 73.5 MB (revalidated) |
| run-1 | first visit | 18.6 s | 5.6 s | 13.0 s | 73.5 MB |
| run-1 | second visit, jars cacheable | 14.8 s | 1.8 s | 12.9 s | 0 at ready |
| run-2 | first visit | 21.4 s | 5.9 s | 15.4 s | 73.5 MB |
| run-2 | second visit, jars cacheable | 16.9 s | 2.3 s | 14.4 s | 0 at ready |
| run-3 | first visit | 21.4 s | 6.2 s | 15.1 s | 73.5 MB |
| run-3 | second visit, jars cacheable | 16.9 s | 2.0 s | 14.8 s | 0 at ready |
| run-4 | first visit | 16.7 s | 5.6 s | 11.1 s | 73.5 MB |
| run-4 | second visit, jars cacheable | 13.0 s | 1.4 s | 11.5 s | 0 at ready |
| run-5 | first visit | 16.7 s | 6.2 s | 10.4 s | 73.5 MB |

Of the 93 MB of jars, about 74 MB are read at boot (CheerpJ reads jars lazily by range). The
CheerpJ runtime itself comes from `cjrtnc.leaningtech.com`; its bytes are not visible to
Resource Timing (no `Timing-Allow-Origin`), so they are not counted. A cached visit fetches
nothing, yet stays at 13–17 s because 11–15 s of it is Java executing `XmageEngine`'s
construction (set registry and catalogue), which caching cannot remove. HotSpot on this machine
takes 8.8 s from process start to ready (`jvm-baseline.mjs`), so CheerpJ is not the only cost.

### Games: CheerpJ runtime gaps

The first game never reached its first prompt. Each finding below is from the engine's own
local diagnostics report, captured by the bench (`magicmobile.debug=true`).

1. **Missing natives.** The first snapshot died with
   `java.lang.UnsatisfiedLinkError: Java_jdk_internal_misc_Unsafe_getBooleanVolatile` in
   `Field.get`, called from XMage's `Watcher.copy` (`GameState.copy` → `Watchers.copy`).
   CheerpJ 4.3's Java 17 runtime lacks the `get/put{Boolean,Byte,Short,Char,Float,Double}Volatile`
   natives, and JDK 17 core reflection uses them for **every final field**
   (`UnsafeQualified*FieldAccessorImpl`). Any reflective read of a final primitive field fails.
2. **JavaScript natives calling the raw `Unsafe` object fail.** Implementing the missing natives
   through `cheerpjInit({natives})` by calling `self.getBoolean(o, offset)` on the `Unsafe`
   instance gave `ArithmeticException`, then CheerpJ's "Java code still running, check for a
   missing 'await'", and the Java thread hung (game stalled at 180 s, the next `create` refused with
   `match_limit`). The offset arrives as a `BigInt`.
3. **Shadowing `Watcher.copy` works.** A web-only `Watcher` whose `copy()` uses
   `sun.misc.Unsafe`'s plain accessors got past the game copy. The same failure then came from
   Gson serializing `mage.view.GameView` (`ViewProjector.project` → `GameView.toJson`), which
   reflects over final primitive fields in `GameView`, `PlayerView`, `PermanentView` and others.
   Shadowing every reflective caller (Gson included) is not practical.
4. **Natives through a Java helper.** The natives then called a static helper,
   `io.magicmobile.web.WebUnsafe`, through the `lib` object the native receives. That `lib`
   belongs to `Unsafe`'s bootstrap loader and cannot see app classes (`ClassNotFoundException`),
   and the exception stopped the Java thread.
5. **Natives through the app library.** Calling `WebUnsafe` through the library returned by
   `cheerpjRunLibrary` instead: CheerpJ rejected the re-entry with "Java code still running,
   check for a missing 'await'", which also failed the outer engine call, the match's `destroy`
   and every later `create`.
6. **Natives through their own `lib`, bootstrap classes only.** In the documented pattern, the
   native calls `jdk.internal.misc.Unsafe.getUnsafe().getBoolean(o, offset)` through the `lib`
   it receives. The first call failed the same way: "Java code still running", then "Error
   while handling user native". The game thread hung (a 180 s stall), and the next `create` was
   refused with `match_limit` (run-5).

In CheerpJ 4.3 library mode, a user native invoked on a running Java thread could not call back
into Java in any form tried. The bundle still has the last variant, so the failure reproduces
with `bench.mjs --debug`.

No game in this spike reached its first human prompt, so board-update, AI-turn and game-length
numbers do not exist for CheerpJ. For scale, the same driver, decks and compiled engine on
HotSpot on this machine (`jvm-baseline.mjs`, 2 games) finished 2/2: create 0.3–1.5 s, 4-player
start 0.3 s, board update median 27 ms / p95 44 ms, AI turn median 1.0 s / p95 11.3 s, games of
12 and 39 turns in 7 s and 101 s.

### Against the pass targets

CheerpJ 4.3, Chrome 153 headless, **8 GB MacBook** under other agents' build load. Sample: 15 page
visits across 9 bench runs (probe-1 to probe-4, run-1 to run-5), and 15 recorded 2-player and
4-player game attempts. None reached its first prompt.

| Target | Measured | Result |
| --- | --- | --- |
| Engine ready, first visit ≤ 45 s | 16.7–26.0 s | pass |
| Engine ready, cached ≤ 10 s | 13.0–16.9 s with cacheable jars (20.3–22.4 s with `no-cache`) | **miss** (Java construction time, not download) |
| 4-player game start ≤ 10 s | never reached a first prompt; the first `create` on a page alone took 10.2–16.4 s | **fail** |
| Board update ≤ 1 s typical, ≤ 3 s p95 | no game got that far | **fail** (not measurable) |
| AI turn median ≤ 5 s, p95 ≤ 15 s | no game got that far | **fail** (not measurable) |
| 10/10 seeded games finish | 0 of 15 attempted games reached a first prompt (seeds 1–3; per-game cap 300–900 s; a 180 s no-progress stall counts as a failure) | **fail** |
| No main-thread stall over 100 ms | engine boot and every engine call: none (engine is in a worker); one 60–109 ms task at page load (t ≈ 20–30 ms, before CheerpJ starts) in three visits | pass for the engine; page load borderline |
| Tab memory under 2 GB | renderer peak 1.14 GB; whole Chrome process tree peak 1.87 GB | pass (renderer) |

## Go / no-go

**No-go for CheerpJ 4.3 (Java 17 runtime) as MagicMobile's web engine.**

- It is broken, not slow. The engine boots, but no game reaches its first prompt. CheerpJ 4.3's
  Java 17 runtime lacks the `Unsafe` natives JDK 17 reflection uses for every final field. XMage
  hits them on every game copy (`Watcher.copy`), and the adapter's view projection hits them on
  every snapshot (Gson over `mage.view`). One upstream class can be shadowed, but not every
  reflective caller. The documented escape hatch, JavaScript natives, could not call back into
  Java in any of the four forms tried: the raw `self`, a helper through the native's own `lib`,
  bootstrap classes through that `lib`, and the app library.
- Even with that fixed, the cached boot misses the target. It spends 11–15 s constructing
  `XmageEngine` in Java before the first request.
- By the spike's rule, broken threads/runtime point to **GraalVM Web Image or hosted play**, not
  to a slower CheerpJ build. The cheapest route to real web play is **hosted web solo**: run the
  same engine on the server that already hosts XMage for multiplayer (`apps/multiplayer-server`)
  and give the browser the same JSON protocol. HotSpot plays these games in seconds on this
  laptop.
- Not ruled out. If CheerpJ stays interesting, try these short experiments first:
  1. CheerpJ's older, more mature **Java 11 runtime**, which may implement these natives. It needs
     the six-line `--release 11` change below, made on a copy.
  2. Ask Leaning Technologies whether a newer release adds the narrow `*Volatile` natives, or
     supports calling Java from a native on a running thread.
  A GraalVM Web Image spike would test whether an AOT-compiled engine avoids both the reflection
  gap (reflection is configured at build time) and the boot cost.
- The license adds its own constraint (next section). Community use needs attribution, loading
  the runtime from Leaning Technologies' CDN, and MagicMobile staying a one-person or FOSS
  project.

## CheerpJ license (checked September 25, 2026)

From [cheerpj.com/docs/licensing](https://cheerpj.com/docs/licensing):

- The **Community License** covers individuals, including one-person companies (personal projects,
  revenue-generating or not), FOSS projects, and technical evaluations (an application no internal
  or external user sees).
- Condition: "Give appropriate credits". `bench.html` credits CheerpJ and Leaning Technologies.
- It allows unlimited, unmetered use of the runtime from `cjrtnc.leaningtech.com` (or npm).
  Self-hosting the runtime needs a Commercial License.
- Business use by a company with more than one person, self-hosting, redistribution/OEM and
  support need a Commercial License (contact sales; no public price).

This spike is a technical evaluation. Shipping web solo play under the Community License
would depend on MagicMobile staying a one-person project, loading the runtime from
Leaning Technologies' CDN (a third-party runtime dependency at play time), and crediting it.
Current version: CheerpJ 4.3 (April 21, 2026), loader
`https://cjrtnc.leaningtech.com/4.3/loader.js`, runtimes for Java 8, 11 and 17
([changelog](https://cheerpj.com/docs/changelog.html)). Java 17 arrived as a preview in 4.1 and was
improved in 4.2 and 4.3.

## Java 11 target (next CheerpJ experiment)

CheerpJ's Java 11 runtime is the older, more mature one. The adapter compiles with
`--release 17`; upstream XMage targets Java 8 and needs nothing. A `--release 11` adapter build
needs exactly six source lines changed (not edited in this spike):

| File:line | Java 16+ feature | Java 11 form |
| --- | --- | --- |
| `engine/xmage/.../MobileHumanPlayer.java:78` | `instanceof MobileCommanderGame mobile` pattern | explicit cast after `instanceof` |
| `engine/xmage/.../ViewProjector.java:38` | `Stream.toList()` | `collect(Collectors.toList())` (mutable; the lists are only read) |
| `engine/xmage/.../ViewProjector.java:102` | `instanceof String artworkName` pattern | explicit cast |
| `engine/xmage/.../ViewProjector.java:123` | `Stream.toList()` | `collect(Collectors.toList())` |
| `engine/xmage/.../ViewProjector.java:155` | `Stream.toList()` | `collect(Collectors.toList())` |
| `engine/xmage/.../ViewProjector.java:156` | `Stream.toList()` | `collect(Collectors.toList())` |

The build-time tools (`RegistryExporter` uses a `record` and `HexFormat`) run on the build JDK and
are not part of the runtime, so they can stay on 17. `build_web.sh` would take a `--release 11`
switch for the core, generated and adapter sources, and the worker would call
`cheerpjInit({version: 11})`. These files are the guarded native-engine input, and changing them
in place would force a native rebuild. A follow-up spike should patch copies under
`packages/web-engine/build/` instead. The Java 17 runtime has now proved unworkable (see
Go / no-go), so this is the next CheerpJ experiment. Whether the Java 11 runtime has the narrow
`*Volatile` natives is not verified.
