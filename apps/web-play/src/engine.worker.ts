/// <reference lib="webworker" />
// SPIKE ONLY. Runs the real XMage adapter (WebEntryPoints over EngineService) inside CheerpJ,
// off the main thread. Classic worker: CheerpJ's loader is loaded with importScripts().
import type { ResourceSummary, WorkerInbound, WorkerOutbound } from "./protocol.ts";

type JavaClass = { request(json: string): Promise<string> };
type CheerpJLibrary = { io: { magicmobile: { web: { WebEntryPoints: Promise<JavaClass> } } } };
declare function cheerpjInit(options?: Record<string, unknown>): Promise<void>;
declare function cheerpjRunLibrary(classPath: string): Promise<CheerpJLibrary>;

const scope = self as unknown as DedicatedWorkerGlobalScope;
// CheerpJ fetches many jar ranges; keep every entry so the bench can total the bytes.
performance.setResourceTimingBufferSize(100_000);
let entry: JavaClass | null = null;
// One Java call at a time: the protocol is request/response and the driver is sequential.
let queue: Promise<unknown> = Promise.resolve();

function post(message: WorkerOutbound) {
  scope.postMessage(message);
}

async function init(message: Extract<WorkerInbound, { type: "init" }>) {
  const t0 = performance.now();
  scope.importScripts(message.loaderUrl);
  const tLoader = performance.now();
  await cheerpjInit({ version: 17, status: "none", javaProperties: ["java.awt.headless=true"] });
  const tInit = performance.now();
  // "/app/" is CheerpJ's read-only mount of this origin; jars are fetched lazily with Range requests.
  const classPath = message.jars.map((jar) => "/app" + message.jarBase + jar).join(":");
  const library = await cheerpjRunLibrary(classPath);
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
      post({ type: "reply", id: message.id, json, javaMs: performance.now() - started });
    } catch (error) {
      post({ type: "reply", id: message.id, error: String((error as Error)?.stack ?? error), javaMs: performance.now() - started });
    }
  });
};
