#!/usr/bin/env node
// Lists a Wasm module's largest functions and how many exceed V8's 7,654,321-byte function limit (docs/LESSONS.md).
//   node packages/web-engine/wasm_functions.mjs packages/web-engine/build/web/engine.js.wasm
import { readFileSync } from "node:fs";
const b = readFileSync(process.argv[2]);
let p = 8;
const leb = () => { let r = 0, s = 0, x; do { x = b[p++]; r += (x & 0x7f) * 2 ** s; s += 7; } while (x & 0x80); return r; };
let imports = 0;
while (p < b.length) {
  const id = b[p++], size = leb(), end = p + size;
  if (id === 2) { // count function imports
    let q = p; const savedP = p; const n = leb();
    for (let i = 0; i < n; i++) { const ml = leb(); p += ml; const fl = leb(); p += fl; const kind = b[p++]; if (kind === 0) { leb(); imports++; } else if (kind === 1) { p++; const f = b[p++]; leb(); if (f & 1) leb(); } else if (kind === 2) { const f = b[p++]; leb(); if (f & 1) leb(); } else if (kind === 3) { p++; p++; } else if (kind === 4) { p++; leb(); } }
    p = savedP;
  }
  if (id === 10) {
    const n = leb(); const sizes = [];
    for (let i = 0; i < n; i++) { const start = p; const s = leb(); sizes.push([s, imports + i, start]); p += s; }
    sizes.sort((a, c) => c[0] - a[0]);
    console.log("functions", n, "imports", imports, "over 7654321 bytes:", sizes.filter((x) => x[0] > 7654321).length);
    for (const [s, idx, off] of sizes.slice(0, 12)) console.log(`func ${idx} size ${s} at ${off}`);
  }
  p = end;
}
