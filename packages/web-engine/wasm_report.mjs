#!/usr/bin/env node
// What a Web Image (WasmGC) module is made of (docs/WEB_ENGINE_M1.md, "Fitting the free runner"): section sizes,
// compiled methods against the image-heap initializer functions, and inside those, the bytes per initializer
// template (one call per image-heap object; the class hubs' template is the one called once per type). Web Image's
// own -H:+PrintHeapHistogram and -H:+PrintImageHeapPartitionSizes print nothing, so this reads the module itself.
//   node packages/web-engine/wasm_report.mjs <engine.wasm>
import { readFileSync } from "node:fs";

const b = readFileSync(process.argv[2]);
let p = 8;
const leb = () => { let r = 0, s = 0, x; do { x = b[p++]; r += (x & 0x7f) * 2 ** s; s += 7; } while (x & 0x80); return r; };
const skipLeb = () => { while (b[p++] & 0x80); };
const heapType = () => { const x = b[p]; if (x >= 0x40 && x < 0x80) p++; else skipLeb(); };
const valType = () => { const x = b[p++]; if (x === 0x63 || x === 0x64) heapType(); };
const NAMES = { 1: "type", 2: "import", 3: "function", 4: "table", 6: "global", 7: "export", 8: "start", 9: "element", 10: "code", 11: "data", 13: "tag" };
const sections = [];
let code;
while (p < b.length) {
  const id = b[p++], size = leb(), begin = p;
  if (id === 10) code = begin;
  sections.push([NAMES[id] ?? `section ${id}`, size]);
  p = begin + size;
}
p = code;
const count = leb();
const fns = [];
for (let i = 0; i < count; i++) { const size = leb(); fns.push({ start: p, size }); p += size; }

// The initializer functions are the large straight-line ones: constants, struct/array allocation and template calls.
// Decoding stops at the first opcode outside that set, which leaves out ordinary compiled methods.
const GC_ONE = new Set([0, 1, 6, 7, 11, 12, 13, 14, 16]), GC_TWO = new Set([2, 3, 4, 5, 8, 9, 10, 17, 18, 19]);
function initializerCalls(f) {
  p = f.start; const end = f.start + f.size, calls = [];
  const groups = leb(); for (let i = 0; i < groups; i++) { skipLeb(); valType(); }
  let since = p;
  while (p < end) {
    const op = b[p++];
    if (op === 0x41 || op === 0x42) skipLeb();
    else if (op === 0x43) p += 4; else if (op === 0x44) p += 8;
    else if (op === 0x10) { const callee = leb(); calls.push([callee, p - since]); since = p; }
    else if (op >= 0x20 && op <= 0x26 || op === 0xd2) skipLeb();
    else if (op === 0xd0) heapType();
    else if (op === 0x0b || op === 0x1a || op === 0x01) {}
    else if (op === 0xfc) { const s = leb(); if ([9, 13, 15, 16, 17].includes(s)) skipLeb(); else if (s === 12 || s === 14) { skipLeb(); skipLeb(); } else return null; }
    else if (op === 0xfb) { const s = leb(); if (GC_ONE.has(s)) skipLeb(); else if (GC_TWO.has(s)) { skipLeb(); skipLeb(); } else if (s >= 20 && s <= 23) heapType(); else return null; }
    else return null;
  }
  return calls;
}
const perTemplate = new Map();
let initBytes = 0, initFns = 0;
for (const f of fns) {
  if (f.size < 100_000) continue;
  const calls = initializerCalls(f);
  if (!calls) continue;
  initBytes += f.size; initFns++;
  for (const [callee, bytes] of calls) { const e = perTemplate.get(callee) ?? { calls: 0, bytes: 0 }; e.calls++; e.bytes += bytes; perTemplate.set(callee, e); }
}
const mb = (n) => (n / 1e6).toFixed(1).padStart(7) + " MB";
console.log(`${process.argv[2]}: ${mb(b.length)}`);
for (const [name, size] of sections) if (size > 100_000) console.log(`  ${name.padEnd(10)} ${mb(size)}  ${(size / b.length * 100).toFixed(1).padStart(5)}%`);
const codeBytes = fns.reduce((a, f) => a + f.size, 0);
console.log(`  code: ${fns.length.toLocaleString()} functions; image-heap initializers ${mb(initBytes)} in ${initFns} functions, everything else ${mb(codeBytes - initBytes)}`);
console.log("  initializer bytes by template (calls ≈ image-heap objects of that kind):");
for (const [callee, e] of [...perTemplate].sort((x, y) => y[1].bytes - x[1].bytes).slice(0, 8))
  console.log(`    func ${String(callee).padEnd(7)} ${e.calls.toLocaleString().padStart(9)} calls ${mb(e.bytes)}  ${Math.round(e.bytes / e.calls).toString().padStart(5)} bytes each`);
