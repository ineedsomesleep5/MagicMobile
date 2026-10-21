# Web engine M1: real XMage in desktop Chrome through GraalVM Web Image

Milestone M1 of docs/WEB_ENGINE_OPTIONS.md, 2026-10-20 (Claude). It ships nothing to players. Branch
`claude/web-engine-m1`.

Question: can the real engine (pinned XMage `dac400b`, engine release C sources) run in a desktop browser through
GraalVM Web Image, with no game server, within the size, speed and memory gates?

**Verdict: go, with one condition.** The real engine (pinned XMage, release C adapter, full card pool) runs in desktop
Chrome as a 174 MB WebAssembly module, with no game server. It finishes 10 of 10 seeded games, and every measured gate
passes with room to spare. The condition was the build itself: it fit GitHub's free runner only with swap, peaking at
about 30 of the runner's 32 GB of RAM plus swap. **Update 2026-10-21:** it now builds free on the runner's 16 GB
without swap, on all-open-source tools (GraalVM Community Edition and the Web Image tool built from source with
memory fixes), and rebuilds by itself when the engine changes; see "Fitting the free runner". Firefox and Safari
have not been run yet.

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
| Build | about an hour on a GitHub runner | 44 min run (21.6 min native-image), needing a 24 GB builder heap: 15.4 GB RAM plus 14.9 GB of swap at the peak. With the builder patch (2026-10-21): 34 min (10.8 min native-image), 12 GB heap, no swap |

### The build, run by run

| Run | Change | Outcome |
|---|---|---|
| [39482806260](https://github.com/ineedsomesleep5/MagicMobile/actions/runs/39482806260) | first build, 10 GB heap, 4 threads | analysis passed (61,954 types, 346,743 methods); out of memory compiling |
| [39495674113](https://github.com/ineedsomesleep5/MagicMobile/actions/runs/39495674113) | 12 GB, 2 threads; `-Ob` fallback | compiled and laid out; out of memory creating the image, at -O2 and -Ob alike |
| [39511250420](https://github.com/ineedsomesleep5/MagicMobile/actions/runs/39511250420) | 14 GB on swap, no .wat comments, no Closure | the heap cap (12.7 GB usable) hit first, swap unused; watchdog stopped it after 43 min in `WasmGCHeapWriter.write` |
| [39546958975](https://github.com/ineedsomesleep5/MagicMobile/actions/runs/39546958975) | 24 GB heap over 16 GB swap, watchdog off | built in 12.6 min; Chrome refused it: one image-heap initializer function was 57.7 MB, over V8's 7,654,321-byte limit |
| [39599683802](https://github.com/ineedsomesleep5/MagicMobile/actions/runs/39599683802) | `-H:ImageHeapObjectsPerFunction=4000` | built (largest function 3.9 MB); loads and plays in Chrome |

What fills the build, and how it came to fit the free runner without swap: next section.

## Fitting the free runner (2026-10-21)

Branch `claude/web-engine-heap` (Claude). **The build fits GitHub's free 16 GB runner without swap, licence-clean**:
run [39657809739](https://github.com/ineedsomesleep5/MagicMobile/actions/runs/39657809739) built the engine in 37
minutes for the whole job with a 12 GB builder heap on G1, peaking at 13.2 GiB of builder memory (14.5 of the
runner's 16 GB in use, no swap); its live heap peaks at about 9 GB. The module also shrank from 174.4 MB to
136.8 MB. Two things made it fit:

1. **Fixes to GraalVM's Web Image builder**, which kept every compiled method's compiler graph, millions of unused
   comment strings and a field table per class (below). With the stock builder the same settings run out of heap
   (run [39628671876](https://github.com/ineedsomesleep5/MagicMobile/actions/runs/39628671876)).
2. **GraalVM Community Edition with the Web Image tool built from source.** Oracle ships Web Image only in Oracle
   GraalVM, licensed for use unmodified, so the fixes could not be used there for anything that ships. CE and the
   tool's source are GPLv2 with the Classpath Exception: the workflow builds the tool from oracle/graal at CE's own
   commit with the fixes in its source ("Community Edition" below). This is the default; Oracle GraalVM stays
   selectable.

### What fills the build (measured on run [39618901221](https://github.com/ineedsomesleep5/MagicMobile/actions/runs/39618901221), the M1 configuration)

**The engine.** 58,392 classes and 297,919 methods are reachable. Card classes (`mage.cards.*` and their inner
classes) are 84% of the classes and 82% of the methods; the rest of XMage is 10%, the JDK about 3%, the adapter 0.3%.
So the code itself cannot get much smaller without removing cards, and the per-class costs below scale with the card
pool (`-H:+PrintAnalysisCallTree` reports: `used_classes`, `used_methods`).

**The module (173.8 MB, `node packages/web-engine/wasm_report.mjs <wasm>`).** Web Image prints nothing for
`-H:+PrintHeapHistogram` or `-H:+PrintImageHeapPartitionSizes`, so this reads the module:

| Part | MB | What it is |
|---|---|---|
| Compiled methods | 55.4 | 349,355 functions in all (median 29 bytes) |
| Image-heap initializer code | 75.0 | 123 functions run at startup that fill the 768k image-heap objects |
| of which class hubs | 55.7 | 61,888 `java.lang.Class` objects at 900 bytes each: an unsafe-access dispatch array (2.82 million `array.set`s, about 34 MB), the vtable (4.4 million entries, about 13 MB), type-check slots (1.4 MB) and the fields |
| of which strings | 6.8 | 164,374 `String` objects |
| of which hub companions | 4.5 | 59,961 `DynamicHubCompanion`s |
| Data segment | 18.8 | primitive arrays: string bytes and the 9.8 MB of embedded resources |
| Element, type, export, global sections | 25.1 | the image-heap object table (9.0), WasmGC types (6.9), exports (5.2), globals (2.0) |

**The image heap (89.1 MB, build output).** `java.lang.Class` 38.4 MB and `DynamicHubCompanion` 10.4 MB (61,954
types), string bytes 9.9 MB and `String` 6.8 MB, embedded resources 9.8 MB, `ClassInitializationInfo` 2.3 MB and
its `ReentrantLock`s 1.4 MB (one per run-time-initialized class), reflection metadata 1.4 MB, `String[]` 1.4 MB,
`Object[]` 1.3 MB, 6.2 MB more over 6,098 types.

- *Reflection:* 1,645 types, 1,642 fields and 2,945 methods are registered (the phone exporter's 1,439 entries,
  mostly `mage.game` and watchers, plus the tracing agent's 75); 1.4 MB of metadata. Small; not cut.
- *Serialization:* nothing is registered (the exporter's 50,816 checkpoint classes are left out, and the tracing
  agent recorded none). The build still reports Java deserialization because about ten `ObjectInputStream` methods
  are reachable from a restore path the web never takes. Negligible; not cut.
- *Build-time-initialized data:* the phone list of XMage enums (`buildtime-enums.txt`) and ORMLite field types;
  every other XMage and adapter class initializes at run time.
- *Embedded resources:* `card-metadata.jsonl.gz` 7.2 MB, `set-catalogue.tsv.gz` 1.4 MB, `card-names.json.gz`
  1.1 MB. They are already compressed and cost the builder almost nothing (a data segment); moving them out would
  take 9.8 MB off the module but not off the download. Not moved (follow-up below).

**The builder's memory.** Live heap after full collections: 4.7 GB once the universe is built and **10.0 GB after
compiling**; while writing the image the heap in use rose to 14.4 GB (no full collection ran there), on top of which Web Image runs binaryen's `wasm-as` on a
3.8 GB `.wat` text file while the builder JVM still holds its heap. Reading Web Image's sources (oracle/graal commit
`95ce1499`, the one Oracle GraalVM 25.4.4.1.1 is built from) showed why:

1. **Every compiled method keeps its compiler graph to the end of the build.** `WebImageCompilationResult` stores
   the graph; every Wasm instruction's .wat comment is its Graal node (`WasmCodeGenTool.getNodeComment` returns the
   node unless comments are verbose, even with `-H:WasmComments=NONE`); each variable id (`ResolvedVar`) holds its
   node; loop and block labels hold the compiler's blocks; and the id factory keeps them in global maps. 229k graphs
   stay reachable until the module is written.
2. **Comments nobody prints.** The heap writer formats a comment string for every field of every image-heap object,
   and relocation processing one for every vtable and dispatch entry (about 7 million) at the build's peak.
3. **Dispatch arrays for every field of every class.** Each instantiated class's hub gets an array with an accessor
   for each of its fields, inherited ones included, for `Unsafe` accesses the compiler could not resolve: 2.82
   million entries and about 48,000 accessor functions. Besides about 34 MB of the module, the browser allocates them
   all at startup: 53,650 arrays with 19.0 million slots (76 MB; a card class's has 466).
4. **The text assembler step.** The 3.8 GB `.wat` and `wasm-as` need memory while the JVM's heap is still mapped.

### What changed (web build only; phone builds untouched)

| Change | Where | Effect |
|---|---|---|
| **Builder fixes**: compiled methods release their compiler graphs; no comment strings or nodes kept for the `.wat` with `-H:WasmComments=NONE`; no dispatch entries for fields of `mage.*` and `io.magicmobile.*` unless the analysis registered them as unsafe-accessed | `packages/web-engine/builder-patch/src` (8 classes of oracle/graal `95ce1499`, changes marked `MagicMobile`): compiled into the CE tool (the default), or patched into Oracle's builder at build time (`build_patch.sh`, experiments only) | heap in use at the peak ~14.4 → ~9 GB (6.3 GB after compiling, from 10.0); 2.78 million dispatch entries and ~48,000 accessor functions gone; module −37 MB |
| **GraalVM CE 25.4.4.1.1 with the Web Image tool built from source** | `packages/web-engine/ce/build_web_image_tool.sh` (mx 7.85.1 on labsjdk, ~1.5 min, cached), the workflow's default | all-open-source tools, so the fixes can ship |
| **`wasm-as` after the builder exits**: Web Image's `-H:WasmAsPath` points at `wasm_as_deferred.sh`, which records the final assembly; `build_web.sh` runs it once the JVM has exited | `packages/web-engine/wasm_as_deferred.sh`, `build_web.sh` | the assembler's 6.3 GB no longer adds to the builder's |
| **G1** for the builder instead of the driver's ParallelGC | `build_web.sh` (`MM_WEB_GC`) | the old generation can use nearly all of the heap |
| The options every working build needs (`-H:WasmComments=NONE`, `-H:ImageHeapObjectsPerFunction=4000`, `-H:-ClosureCompiler`) moved from the workflow into `build_web.sh`; the web engine identity now also covers `build_web.sh` and the patch | `build_web.sh`, `web_identity.py` | |

The dispatch-array cut is the one change with run-time meaning. Upstream gives every field an entry because an
`Unsafe` access the compiler couldn't resolve to a field goes through the array. Limiting entries to fields the
analysis registered as unsafe-accessed (reflection, VarHandles, field updaters and recomputed offsets register
theirs) is **not** enough: a probe image trapped on `AtomicReference.value`, which the JDK reaches through a VarHandle
without registering it. So the patch skips only packages that never make such accesses themselves, and
`builder-patch/check_skip_packages.py` fails the build if any class in `mage.*` or `io.magicmobile.*` ever references
`Unsafe`, `VarHandle` or a field updater (none of the 50,114 does today). A missed case would trap loudly ("Fatal
unsafe read error … No unsafe accessible fields available"), never misbehave quietly. Each patched class's
unmodified upstream copy compiles to the shipped bytecode (`javap -c`), `expected.sha256` pins the shipped classes,
and a probe image built with the patch matches the JVM's output.

### Community Edition with the Web Image tool built from source

GraalVM CE 25.4.4.1.1 (`graalvm/graalvm-ce-builds`, 2026-09-22) is built from the same oracle/graal commit as Oracle
GraalVM 25.4.4.1.1 (`95ce1499`). It ships Native Image and the Web Image API module (`org.graalvm.webimage.api`), but
not the Web Image tool (`lib/svm/tools/svm-wasm`); GraalVM's docs list Web Image as Oracle GraalVM only. The tool's
source is open in oracle/graal (`web-image/`), so `packages/web-engine/ce/build_web_image_tool.sh`:

1. fetches oracle/graal at the commit named in CE's `release` file, the mx version (7.85.1) and labsjdk
   (25.0.4.1.1-jvmci-25.4-b23, checksummed) pinned in its `common.json`;
2. copies the builder fixes from `builder-patch/src` into the source (it refuses if they were made for another
   commit; `builder-patch/rebase.sh` moves them);
3. builds `SVM_WASM`, `SVM_WASM_JIMFS`, `SVM_WASM_GUAVA` and the tool's generated `native-image.properties` with mx
   (about 1.5 minutes) and installs them into the CE home, as Oracle lays out the tool (without its enterprise jar).

One trap: CE's runtime image contains an empty placeholder module named `org.graalvm.extraimage.builder` (Oracle's has
none), and a module in the runtime image wins over the same name on the builder's module path. Without a fix,
`--tool:svm-wasm` quietly builds a native executable. The installed macro therefore puts the tool's jar on the
builder's `--upgrade-module-path`. The workflow pins the CE archive by checksum, caches the built tool by CE version
and fix sources, and checks every toolchain with a probe program (`ce/probe`) that must print the same in Wasm as on
the JVM. `build_web.sh` checks that the tool really contains the fixes (`MM_WEB_BUILDER_FIXES=builtin`).

### The runs

All on `ubuntu-24.04` (4 cores, 15.6 GiB, about 3 GB of swap of its own). "Heap" is the builder's `-Xmx`; "live" is
the heap left after full or mixed collections while the image is written; "peak memory" is the builder's peak
resident memory and the runner's RAM in use.

| Run | Builder | Heap, swap | native-image | Live peak | Peak memory | Wasm raw / gzip -9 | Outcome |
|---|---|---|---|---|---|---|---|
| [39618901221](https://github.com/ineedsomesleep5/MagicMobile/actions/runs/39618901221) A | stock, ParallelGC | 24 GB over 16 GB swap | 18m20s | ≤ 14.4 GB | 14.6 GiB RSS, 14.9 GB swap | 174.4 / 44.9 MB | built (baseline, with analysis reports) |
| [39621928534](https://github.com/ineedsomesleep5/MagicMobile/actions/runs/39621928534) B | patch: comments, dispatch | 24 GB over 16 GB swap, ParallelGC | 12m50s | ≤ 12.0 GB | 14.7 GiB RSS, 12.2 GB swap | 136.9 / 43.3 MB | built; 10 of 10 games in Chrome |
| [39626468418](https://github.com/ineedsomesleep5/MagicMobile/actions/runs/39626468418) C | full patch, deferred `wasm-as`, G1 | 24 GB over 16 GB swap | 9m47s | (G1 not pressed) | 14.8 GiB RSS; `wasm-as` 6.3 GB alone | 136.9 / 43.1 MB | built |
| [39626530141](https://github.com/ineedsomesleep5/MagicMobile/actions/runs/39626530141) **D** | full patch, deferred `wasm-as`, G1 | **12 GB, no swap** | 10m48s | ~9 GB | **13.2 GiB RSS**, 14.5 of 16 GB in use, 0 swap | 136.7 / 43.3 MB | **built; the target configuration** |
| [39628668397](https://github.com/ineedsomesleep5/MagicMobile/actions/runs/39628668397) E | stock, deferred `wasm-as`, G1 | 24 GB over 16 GB swap | 21m55s | ~12.3–12.9 GB | 14.7 GiB RSS, 12.7 GB swap; `wasm-as` 7.1 GB alone | 174.4 / 45.1 MB | built; GC 20% of the time |
| [39628671876](https://github.com/ineedsomesleep5/MagicMobile/actions/runs/39628671876) F | stock, deferred `wasm-as`, G1 | 13 GB, no swap | — | > 13 GB | 15.5 of 16 GB in use | — | `OutOfMemoryError: Java heap space` writing the image |
| [39628789815](https://github.com/ineedsomesleep5/MagicMobile/actions/runs/39628789815) G | stock at `-Os`, deferred `wasm-as`, G1 | 24 GB over 16 GB swap | 15m49s | ~16.4 GB | 14.8 GiB RSS, 11.3 GB swap | 174.3 / 45.0 MB | built; `-Os` saves nothing here |
| [39633234887](https://github.com/ineedsomesleep5/MagicMobile/actions/runs/39633234887) H | full patch, deferred `wasm-as`, G1 | 11 GB, no swap | 10m48s | 6.3 GB after compiling, ~8.4–9.3 GB writing | 12.3 GiB RSS, 13.6 of 16 GB in use, 0 swap | — | built; GC 5.8%, histograms |
| [39635835998](https://github.com/ineedsomesleep5/MagicMobile/actions/runs/39635835998) **final** | the committed workflow and branch, with the phone regressions | 12 GB, no swap | 10m36s | — | 13.2 GiB RSS, 14.5 of 16 GB in use, 0 swap | 136.8 / 43.2 MB | built; phone regressions passed; 39 min in all |
| [39652956935](https://github.com/ineedsomesleep5/MagicMobile/actions/runs/39652956935) S | Oracle with the patch (meant as stock: its commit body named the patch tag) | 12 GB, no swap | 9m55s | — | 13.3 GiB RSS, 0 swap | 137.0 / 43.0 MB | built; led to reading tags from the subject only |
| [39657809739](https://github.com/ineedsomesleep5/MagicMobile/actions/runs/39657809739) **CE** | **GraalVM CE + the tool built from source with the fixes**, deferred `wasm-as`, G1 | **12 GB, no swap** | 11m28s | — | **13.2 GiB RSS, 14.5 of 16 GB in use, 0 swap** | 136.8 / 43.1 MB | **built; the default from now on; 37 min in all (tool 1.5 min)** |

With the patch the live heap is 6.3 GB after compiling (10.0 GB stock: the released graphs) and about 8.4–9.3 GB at
its peak, while the image is written. The workflow uses 12 GB, leaving about 3 GB of heap for a growing card pool;
11 GB (run H) also works and leaves 2.4 GB of RAM free instead of 1.5. GC took 29 s of D's build (4.4%), against
167 s for A. The Web Image step took 12 minutes in D and 19 in A (22 in M1); the whole job about 34 minutes, of which
the JVM games that feed the tracing agent take 10–17.

### The fitted engine in Chrome

Headless Chrome 155 on the 8 GB Mac, `apps/web-play` bench, the same 10 seeded games as above (2-player seeds 1–5,
4-player 6–10): M1's engine, run D's (Oracle, patched) back to back, and the default CE engine (run CE) later
(`node scripts/bench.mjs --engine-dir <bundle> --ready-visits 2 --games 2p:1,…,4p:10`; metrics, git-ignored, in the
`sleepy-lumiere-f6745e` worktree's `packages/web-engine/build/metrics/chrome-games-10-{m1-rerun,fitted,ce,run-b}.json`):

| | M1 engine (Oracle, stock) | Run D (Oracle, patched) | **Run CE (the default)** |
|---|---|---|---|
| Wasm, raw / gzip -9 | 173.8 / 45.0 MB | 136.7 / 43.3 MB | **136.8 / 43.1 MB** |
| Engine ready, first visit / cached | 3.14 / 3.06 s | 2.63 / 2.11 s | **1.91 / 1.76 s** |
| Wasm fetch and compile, first visit / cached | 2.96 / 2.88 s | 2.38 / 1.99 s | **1.75 / 1.61 s** |
| Seeded games finished | 10 of 10 | 10 of 10 | **10 of 10** |
| AI turn median / p95 / max | 1.03 / 4.31 / 8.0 s | 1.05 / 4.24 / 16.5 s | **1.05 / 4.81 / 9.2 s** |
| Board update median / p95 | 30 / 55 ms | 28 / 56 ms | **26 / 52 ms** |
| Game start, 2-player / 4-player median | 119 / 125 ms | 92 / 163 ms | **90 / 122 ms** |
| Renderer memory: after boot / peak in games | 0.81 / 0.91 GB | 0.63 / 0.96 GB | **0.71 / 0.92 GB** |

All three pass every gate. The fitted engines start 1–1.4 s sooner (a smaller module to compile, 1.3 MB of dispatch
arrays instead of 76 MB). AI turns have the same median; CE's p95 is about half a second higher, within the spread
of these runs. Oracle GraalVM's compiler has optimizations CE lacks, and AI searches are time-budgeted, so a slower
engine would explore fewer positions rather than take longer: the web AI calibration (M5) should run on the CE
engine. Peak memory during games varies with the game more than with the engine. An earlier pass over run B's
engine, with another session's simulator running, finished 10 of 10 as well (AI median 1.09 s, p95 5.65 s).

### Rebuilding by itself

`.github/workflows/magicmobile-web-image.yml` now:

- **Starts on engine changes on `main`**: pushes touching `packages/ondevice-engine/{engine,platform,native,scripts}`,
  `packages/ondevice-engine/upstream.lock.json` (so an XMage update), `packages/web-engine/` or the workflow. On
  `claude/web-engine-*` branches it still needs `[web-image]` in the commit message (with `[phone-regressions]` it also
  runs `test_real_engine.sh`). Dispatch, with its options, works once the workflow is on `main`.
- **Skips inputs it has already built.** A one-minute `plan` job hashes git's tree ids of those paths into a 16-hex
  key and looks for an unexpired `web-engine-bundle-<key>` artifact; if there is one, nothing rebuilds (dispatch with
  `force` to rebuild). This matters because Web Image builds are not byte-for-byte reproducible: an unchanged engine
  rebuilt would get new file names and every browser would download 45 MB again. Checked: run
  [39647712333](https://github.com/ineedsomesleep5/MagicMobile/actions/runs/39647712333), a commit with the final
  run's input trees on another parent (as a merge to `main` would be), stopped after the one-minute plan job.
  (Re-running a run rebuilds: GitHub deletes an earlier attempt's artifacts.)
- **Pins its toolchain.** The default is GraalVM CE 25.4.4.1.1 by archive checksum (`CE_VERSION` in the workflow)
  with the tool built from its commit, so engine updates rebuild on unchanged tools. Moving to a newer GraalVM is a
  deliberate step: change `CE_VERSION` and `CE_ARCHIVE`, run `builder-patch/rebase.sh <its commit>` (it merges
  cleanly onto oracle/graal master of 2026-10-21) and check the probe and a build. The Oracle route takes the latest
  Oracle 25.4 (`setup-graalvm`); its patched experiment refuses a builder that no longer matches
  `builder-patch/expected.sha256`.
- **Lets you pick the toolchain.** `[oracle]` in the commit subject (or dispatch `toolchain`) builds with Oracle
  GraalVM's stock builder over 16 GB of swap; `[builder-patch]` with Oracle's builder patched (not for players).
  Each gets its own bundle name (`-oracle`, `-oracle-patched`), so nothing stands in for the default bundle. Tags
  count only in the subject line.
- **Names the engine by its content.** The bundle holds `engine-<16 hex of sha256>.js` and `.wasm` and a
  `manifest.json` (`files`, `engineBuild`, `buildKey`, `builderPatch`, sizes) that pages fetch uncached; the engine
  files can be cached for good. `apps/web-play` reads `manifest.files` and falls back to the old `engine.js` and
  `engine.js.wasm` of earlier bundles. The bundle artifact is kept 90 days (the evidence 30), named by the key.
- Publishing the bundle to a host stays M3's step (Vercel needs Caleb).

### The licence question

Web Image ships only in Oracle GraalVM, under the GraalVM Free Terms and Conditions (read 2026-10-21). Their licence
grant covers use of "the unmodified Programs"; bundled source is for reference only unless other terms allow
changes; and Native Image output counts as an unmodified Program only when the unmodified Program produced it. So
the builder fixes could not be used with Oracle GraalVM for anything that ships, even though they are Oracle's own
open-source code (this is not legal advice).

Caleb's call (2026-10-21, through the coordinating session): whatever is best, works and is free. Considered:

| Option | Licence | Cost | Result |
|---|---|---|---|
| **GraalVM CE + the Web Image tool built from source with the fixes** | GPLv2 with the Classpath Exception throughout | free, 37 min, no swap | **the default** (run CE) |
| Oracle GraalVM, stock builder over swap | GFTC, unmodified | free, about 40–44 min, almost no headroom | works (runs A, E); kept as `[oracle]` |
| Oracle GraalVM with the builder patched | outside GFTC's grant | free, 34 min, no swap | experiments only (`[builder-patch]`, `-oracle-patched` bundles) |
| GraalVM CE as released | GPL | — | ships no Web Image tool |
| Report the fixes upstream | — | free | issue texts drafted in `docs/upstream/graal-web-image-memory.md`; posting needs Caleb's OK |
| A 64 GB machine for the stock builder | GFTC, unmodified | about €1.30–1.80 per build (Hetzner CCX43) | not needed |

Bundles from runs B, C, D, H, final and S were built with Oracle's builder patched and are not for players; M3 was
told to use licence-clean bundles (`builderPatch` in `manifest.json` names the fixes, and `toolchain` the edition).

## What was built

| Path | What it is |
|---|---|
| `packages/web-engine/web_sources.py` | Copies the adapter and platform sources plus three upstream files and rewrites 18 places for the web threading mode. Each rewrite must match exactly as often as listed, or the build fails. `packages/ondevice-engine/` is only read, so phone builds are byte-for-byte unchanged. |
| `packages/web-engine/src/` | Web-only Java: `WebThreads` (deferred GAME executor, inline CALL executor, the human wait), `WebHost` (the request loop), `WebMain` (Web Image entry, `@JS` bridge), `WebJvmMain` (the same mode on HotSpot), `WebInflate` and `WebCrc32` (plain-Java gzip and CRC-32), `mage.util.MobileWebInterrupt` (the AI stop flag). |
| `packages/web-engine/src-svm/` | A `Thread.start` substitution that throws, so a stray thread start fails loudly instead of silently running nothing. |
| `packages/web-engine/web_identity.py` | The web engine's build identity (`web-1:sha256:…`): the phone identity plus every web-only input and the toolchain. |
| `packages/web-engine/build_web.sh` | Stages `sources`, `jvm`, `metadata`, `wasm`, `bundle`. The `wasm` stage needs a ~10 GB builder heap: CI only. |
| `packages/web-engine/builder-patch/` | The Web Image builder fixes (2026-10-21): `src/` (8 classes of oracle/graal `95ce1499`), `rebase.sh` (moves them to another commit), `check_skip_packages.py`; for the Oracle experiment, `build_patch.sh` (`--check`, `--patch-module`) and `expected.sha256`. |
| `packages/web-engine/ce/` | `build_web_image_tool.sh`: builds the Web Image tool from oracle/graal into GraalVM CE with the fixes; `probe/`: the toolchain smoke test. |
| `packages/web-engine/wasm_as_deferred.sh` | `-H:WasmAsPath` wrapper: records the module's assembly so `build_web.sh` runs `wasm-as` after the builder exits. |
| `packages/web-engine/builder_watch.sh` | CI diagnostics: RAM, swap and builder memory every 30 s; heap histograms at stages 6–8. |
| `packages/web-engine/wasm_report.mjs` | What a module is made of: sections, compiled methods against image-heap initializers, bytes per initializer template. |
| `packages/web-engine/patch_wrapper.py` | Adapts the generated `engine.js`: Wasm URL from the worker, `instantiateStreaming` (Chrome's Wasm code cache), boot timing marks. |
| `.github/workflows/magicmobile-web-image.yml` | The build: `build_jvm.sh`, the toolchain (GraalVM CE with the tool built from source, cached; or Oracle GraalVM), the probe, web sources, two web-mode games on GraalVM's JVM with the tracing agent (reachability metadata), the Web Image build, the bundle artifact. Starts on engine changes on `main` (skipping inputs already built), on dispatch, or on a push to a `claude/web-engine-*` branch whose commit message has `[web-image]` ("Rebuilding by itself"). |
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
# Browser: download a CI artifact web-engine-bundle-<key> (engine-<hash>.js/.wasm, manifest.json, decks) into
# packages/web-engine/build/web (or pass --engine-dir), then
npm install && npm run build
node scripts/bench.mjs --ready-visits 2 --games 2p:1,4p:2
```

## Not done

- **Firefox and Safari smoke runs** (see the gate table). To run one by hand: `cd apps/web-play && npm run build &&
  node scripts/serve.mjs`, then open `http://127.0.0.1:5178/bench.html?games=2p:1` in the browser; the tab title
  shows the status.
- **A cheaper build:** done (2026-10-21, "Fitting the free runner"): GraalVM CE with the Web Image tool built from
  source with the builder fixes, free, licence-clean, no swap. Follow-ups: post the drafted upstream reports
  (`docs/upstream/graal-web-image-memory.md`, needs Caleb's OK); move to a newer GraalVM only deliberately
  (`CE_VERSION` plus `builder-patch/rebase.sh`); load the 9.8 MB of card catalogues at run time instead of embedding
  them, so card-data changes need no engine rebuild.
- **Updates without a full rebuild** (researched 2026-10-20 by the coordinating session): engine-code changes need a
  rebuild. Native Image layers exist for native targets but are undocumented for Web Image, and a run-time bytecode
  interpreter (Crema) would be far too slow for AI search. Data updates (catalogue, precons) and UI changes ship
  without one. So the plan is a free, automatic rebuild with each phone engine release, served under a
  content-hashed name so browsers download only a changed engine (done 2026-10-21, "Rebuilding by itself"). Today the
  card catalogues are embedded in the image, so a catalogue change does rebuild it.
- **Toolchain:** Oracle GraalVM 25.4.4.1.1 is the newest release (25.5 is due about 2026-10-27). XMage stays at the
  phones' pin, `dac400b` with release C: changing it would break cross-play identity with phones, and it goes
  through the normal XMage update flow.
- **Production questions** for M3: serving 174 MB from Vercel (CLI upload limit 100 MB; a Git build or chunks plus
  `compileStreaming`), Cache API storage keyed by engine identity, and Vercel Hobby's transfer budget.
