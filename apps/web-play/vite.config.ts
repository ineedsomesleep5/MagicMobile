import { defineConfig } from "vite";

// The engine worker must be a classic worker: the Web Image wrapper (engine.js) is pulled in with
// importScripts(), which module workers do not have.
export default defineConfig({
  base: "./",
  worker: { format: "iife" },
  build: {
    target: "es2022",
    rollupOptions: { input: { bench: "bench.html" } },
  },
});
