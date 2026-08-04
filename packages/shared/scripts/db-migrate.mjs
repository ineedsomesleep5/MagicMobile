import { spawnSync } from "node:child_process";

const result = spawnSync(
  "npx",
  ["--yes", "supabase@2.109.1", "db", "push"],
  { cwd: new URL("../../..", import.meta.url), stdio: "inherit" }
);

if (result.error) throw result.error;
process.exitCode = result.status ?? 1;
