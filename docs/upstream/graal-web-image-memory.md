# Draft: oracle/graal issues for Web Image builder memory (not posted)

Drafts for github.com/oracle/graal, written 2026-10-21 from the measurements in `docs/WEB_ENGINE_M1.md` ("Fitting the
free runner"). Nothing here has been posted: Caleb decides whether and when. Checked against oracle/graal `master` of
2026-10-21: the code below is unchanged there, and no open issue covers it. The two drafts are the plain bugs; the
dispatch arrays and the assembler step are design questions, noted at the end for a later issue if wanted.

---

## Issue 1

**Title:** [Web Image] Builder keeps every compiled method's compiler graph until the image is written

**Body:**

With `--tool:svm-wasm` (WasmGC backend), each method's `StructuredGraph` stays reachable after the method has been
lowered to Wasm instructions, so the builder's live heap grows by the graphs of all compiled methods and only drops
when the build ends. On a large application this decides whether the build fits a machine.

Seen on Oracle GraalVM 25.4.4.1.1 (oracle/graal `95ce1499c8c96ab7d5a6697c5b4bf42160f3b68b`), Linux x64, an
application with 61,954 reachable types and 346,743 reachable methods (228,990 compilation units): live heap after
compiling 10.0 GB; 6.3 GB once the references below are released. The output is unchanged in behaviour: the module
size is the same within a few kilobytes, and the application and a probe program run the same.

The graph stays reachable through several paths, any one of which is enough:

1. `WebImageBackend.emitBackEnd` stores the graph in `WebImageCompilationResult.graph`. The Wasm backends lower the
   graph inside `WebImageWasmBackend.emitBackEnd` and do not read it afterwards (the JS backend does, in
   `WebImageJSCodeGen`), but the result keeps it.
2. `WasmCodeGenTool.getNodeComment(Node)` returns the node itself unless comments are `VERBOSE`, and `genInst` stores
   it as the instruction's comment, also with `-H:WasmComments=NONE`, where `WasmPrinter` never prints it.
3. `WebImageWasmIds.NodeVariable` holds its `ResolvedVar`, which holds its `Node`; every id is kept in
   `WasmIdFactory.allIds`.
4. `WebImageWasmIds.LoopLabel` holds its `HIRBlock` and `BlockLabel` its `LabeledBlock`, although both only need their
   name (`"looplabel_" + id`, `LabeledBlock.getLabel()`, fixed when created).
5. `WasmIdFactory.loopLabels`, `blockLabels` and `localVars` are global maps keyed by those blocks and variables,
   though they are only used while one method is lowered on one thread.

A fix that worked for us: in `WebImageWasmBackend.emitBackEnd`, after `lowerFunction`, release the variables' nodes
(a `VariableMap.releaseNodes()` that nulls `ResolvedVar.node`), clear per-method label and variable maps (made
thread-local in `WasmIdFactory`) and `setGraph(null)`; give the labels their names instead of the blocks; and return
`null` from `getNodeComment` when comments are off.

---

## Issue 2

**Title:** [Web Image] WasmGC heap writer and relocation pass build comment strings with -H:WasmComments=NONE

**Body:**

With comments off, the WasmGC backend still formats a comment string for every image-heap object field and every
relocation and stores it on the instruction, where `WasmPrinter` skips it. On the application in issue 1 (767,914
image-heap objects; 4.4 million vtable entries and 2.8 million dispatch entries resolved as relocations) these
strings are created at the build's memory peak, while the image is written.

Places (oracle/graal `95ce1499`, unchanged on master):

- `WasmGCHeapWriter.getArgumentForField`: `.setComment(field.format("%T %h.%n"))` for every field argument;
  `initializeObjects`, `fillObject` and `fillArray`: `commentForObject(data)`; `getHubIndex`: `"Table index for hub: "
  + clazz.toJavaName()`; `registerAndFillStaticFields`: `"Static Field " + field.format(...)`.
- `WebImageWasmGCCodeGen.processRelocations`: `methodPointer.getMethod().format("Method pointer for: %H.%n(%P)")` and
  `"Function id for: " + function` for every relocation.

Guarding these with `WebImageWasmOptions.genComments()` removes them. Together with issue 1 it took the build's peak
heap in use from about 14.4 GB to about 9 GB, and a build that needed a 24 GB heap over 16 GB of swap fits a 12 GB
heap without swap.

---

## Not drafted yet (design questions)

- **Access dispatch arrays** (`WasmGCHeapWriter.createHubAccessDispatchArray`): every instantiated type gets an entry
  for each read or written field, inherited ones included: 2.82 million entries, about 48,000 accessor functions and
  34 MB of the module here, and 76 MB of arrays allocated at startup in the browser. Limiting entries to fields the
  analysis registered as unsafe-accessed is not enough: `AtomicReference.value` is reached through the dispatch path
  (a probe trapped with "No unsafe accessible fields available") without being registered, which may itself be the
  bug to report (VarHandle field accesses in the JDK not registered as unsafe-accessed for Web Image).
- **Assembler step**: `wasm-as` runs on a multi-gigabyte `.wat` (3.8 GB here) as a child of the builder while the
  builder JVM still holds its heap; the two need memory at once. Running it after the builder exits (our
  `-H:WasmAsPath` wrapper) or writing the binary directly would avoid that.
