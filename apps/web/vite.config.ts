import { defineConfig } from "vitest/config";
import react from "@vitejs/plugin-react";

export default defineConfig({
  plugins: [react()],
  build: { rollupOptions: { output: { manualChunks: { three: ["three"] } } } },
  test: { include: ["test/**/*.test.ts"], environment: "node" },
});
