/// <reference lib="webworker" />
// SPIKE ONLY. Runs the real XMage adapter (WebEntryPoints over EngineService) inside CheerpJ,
// off the main thread. Classic worker: CheerpJ's loader is loaded with importScripts().
import type { ResourceSummary, WorkerInbound, WorkerOutbound } from "./protocol.ts";

type JavaClass = { request(json: string): Promise<string> };
type CheerpJLibrary = { io: { magicmobile: { web: { WebEntryPoints: Promise<JavaClass>; WebUnsafe: Promise<unknown> } } } };
declare function cheerpjInit(options?: Record<string, unknown>): Promise<void>;
declare function cheerpjRunLibrary(classPath: string): Promise<CheerpJLibrary>;

const scope = self as unknown as DedicatedWorkerGlobalScope;
// CheerpJ fetches many jar ranges; keep every entry so the bench can total the bytes.
performance.setResourceTimingBufferSize(100_000);
let entry: JavaClass | null = null;
// One Java call at a time: the protocol is request/response and the driver is sequential.
let queue: Promise<unknown> = Promise.resolve();

// CheerpJ 4.3's Java 17 runtime has no natives for Unsafe get/put<narrow>Volatile, which JDK 17
// reflection uses for every final field: Field.get on a final boolean threw UnsatisfiedLinkError
// (XMage's Watcher.copy, then Gson serializing mage.view.GameView). These natives forward to the
// plain accessors: preferably io.magicmobile.web.WebUnsafe through the app library (the `lib` a
// native receives belongs to Unsafe's bootstrap loader and cannot see app classes:
// ClassNotFoundException), else jdk.internal.misc.Unsafe.getUnsafe() through that `lib`.
// Calling methods on the raw `self` Unsafe object failed (ArithmeticException, then "Java code
// still running"). The hot per-game-copy caller, Watcher.copy, is also shadowed in the web bundle
// so AI simulations do not cross this bridge. Crossings are counted for the bench.
type Native = (...args: unknown[]) => Promise<unknown>;
type Callable = Record<string, (...args: unknown[]) => Promise<unknown>>;
type BootLibrary = { jdk: { internal: { misc: { Unsafe: Promise<{ getUnsafe(): Promise<Callable> }> } } } };
const bridge = { calls: 0, path: "" };
let appLibrary: CheerpJLibrary | null = null;
function unsafeNatives(): Record<string, Native> {
  const targets: { name: string; target: Callable }[] = [];
  let resolving: Promise<void> | null = null;
  const resolve = (lib: unknown) =>
    (resolving ??= (async () => {
      if (appLibrary) {
        try {
          targets.push({ name: "WebUnsafe via app library", target: (await appLibrary.io.magicmobile.web.WebUnsafe) as unknown as Callable });
        } catch (error) {
          console.log(`[unsafe-natives] WebUnsafe via app library unavailable: ${String(error)}`);
        }
      }
      try {
        const unsafe = await (await (lib as BootLibrary).jdk.internal.misc.Unsafe).getUnsafe();
        targets.push({ name: "jdk.internal.misc.Unsafe via native lib", target: unsafe });
      } catch (error) {
        console.log(`[unsafe-natives] jdk.internal.misc.Unsafe via native lib unavailable: ${String(error)}`);
      }
    })());
  const call = async (lib: unknown, method: string, args: unknown[]) => {
    bridge.calls++;
    await resolve(lib);
    while (targets.length) {
      const { name, target } = targets[0];
      try {
        const result = await target[method](...args);
        if (bridge.path !== name) console.log(`[unsafe-natives] using ${(bridge.path = name)}`);
        return result;
      } catch (error) {
        console.log(`[unsafe-natives] ${name} failed on ${method}: ${String(error)}`);
        targets.shift();
      }
    }
    throw new Error("No working Unsafe accessor for " + method);
  };
  const natives: Record<string, Native> = {};
  for (const type of ["Boolean", "Byte", "Short", "Char", "Float", "Double"]) {
    natives[`Java_jdk_internal_misc_Unsafe_get${type}Volatile`] = async (lib, _self, o, offset) => await call(lib, `get${type}`, [o, offset]);
    natives[`Java_jdk_internal_misc_Unsafe_put${type}Volatile`] = async (lib, _self, o, offset, value) => {
      await call(lib, `put${type}`, [o, offset, value]);
    };
  }
  return natives;
}

function post(message: WorkerOutbound) {
  scope.postMessage(message);
}

async function init(message: Extract<WorkerInbound, { type: "init" }>) {
  const t0 = performance.now();
  scope.importScripts(message.loaderUrl);
  const tLoader = performance.now();
  await cheerpjInit({
    version: 17,
    status: "none",
    javaProperties: ["java.awt.headless=true", ...(message.javaProperties ?? [])],
    natives: unsafeNatives(),
  });
  const tInit = performance.now();
  // "/app/" is CheerpJ's read-only mount of this origin; jars are fetched lazily with Range requests.
  const classPath = message.jars.map((jar) => "/app" + message.jarBase + jar).join(":");
  const library = await cheerpjRunLibrary(classPath);
  appLibrary = library;
  const tLibrary = performance.now();
  entry = await library.io.magicmobile.web.WebEntryPoints;
  const tClass = performance.now();
  post({
    type: "ready",
    timings: {
      loaderMs: tLoader - t0,
      cheerpjInitMs: tInit - tLoader,
      runLibraryMs: tLibrary - tInit,
      entryClassMs: tClass - tLibrary,
      totalMs: tClass - t0,
    },
  });
}

scope.onmessage = (event: MessageEvent<WorkerInbound>) => {
  const message = event.data;
  if (message.type === "init") {
    init(message).catch((error: unknown) => post({ type: "fatal", message: String((error as Error)?.stack ?? error) }));
    return;
  }
  if (message.type === "resources") {
    const summary: ResourceSummary = { count: 0, transferBytes: 0, byHost: {} };
    for (const entry of performance.getEntriesByType("resource") as PerformanceResourceTiming[]) {
      const host = new URL(entry.name).host;
      const row = (summary.byHost[host] ??= { count: 0, transferBytes: 0, bodyBytes: 0 });
      row.count++;
      row.transferBytes += entry.transferSize;
      row.bodyBytes += entry.encodedBodySize;
      summary.count++;
      summary.transferBytes += entry.transferSize;
    }
    post({ type: "resources", id: message.id, summary });
    return;
  }
  queue = queue.then(async () => {
    const started = performance.now();
    try {
      if (!entry) throw new Error("Engine is not initialized");
      const json = await entry.request(message.json);
      post({ type: "reply", id: message.id, json, javaMs: performance.now() - started, bridgeCalls: bridge.calls });
    } catch (error) {
      post({ type: "reply", id: message.id, error: String((error as Error)?.stack ?? error), javaMs: performance.now() - started });
    }
  });
};
