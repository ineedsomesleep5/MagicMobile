// SPIKE ONLY. Messages between the page and the CheerpJ engine worker.
export type WorkerInbound =
  // javaVersion: CheerpJ runtime (17 or 11), from the bundle manifest's javaRelease.
  // unsafeNatives: install the JavaScript Unsafe natives (default: only on the Java 17 runtime).
  | { type: "init"; loaderUrl: string; jarBase: string; jars: string[]; javaProperties?: string[]; javaVersion?: number; unsafeNatives?: boolean }
  | { type: "request"; id: number; json: string }
  | { type: "resources"; id: number };

export type ReadyTimings = {
  loaderMs: number;
  cheerpjInitMs: number;
  runLibraryMs: number;
  entryClassMs: number;
  totalMs: number;
};

export type WorkerOutbound =
  | { type: "ready"; timings: ReadyTimings }
  | { type: "fatal"; message: string }
  | { type: "reply"; id: number; json?: string; error?: string; javaMs: number; bridgeCalls?: number }
  | { type: "resources"; id: number; summary: ResourceSummary };

/** What the worker fetched (CheerpJ runtime from the CDN, jars from this origin). */
export type ResourceSummary = {
  count: number;
  transferBytes: number;
  byHost: Record<string, { count: number; transferBytes: number; bodyBytes: number }>;
};
