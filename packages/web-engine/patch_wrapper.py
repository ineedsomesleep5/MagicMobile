#!/usr/bin/env python3
"""Adapts the JavaScript wrapper Web Image generates (engine.js) for apps/web-play's engine worker.

    patch_wrapper.py <generated engine.js> <output engine.js>

- The worker passes its configuration in globalThis.mmEngineConfig (the Wasm URL: the wrapper would otherwise look
  for "<worker script>.wasm").
- The module is compiled with WebAssembly.instantiateStreaming where fetch exists, so Chrome compiles while it
  downloads and keeps a code cache for the next visit; plain instantiate otherwise (Node).
- globalThis.mmEngineMarks gets performance.now() marks around fetch and instantiation (bench timings).
Each edit must match exactly once, so a changed wrapper fails here rather than at run time.
"""
import sys
from pathlib import Path

EDITS = [
    ('const config = new GraalVM.Config();',
     'const config = Object.assign(new GraalVM.Config(), globalThis.mmEngineConfig || {}); // MOBILE_WEB'),
    ('''    const file = await runtime.fetchData(wasmPath);
    const result = await WebAssembly.instantiate(file, wasmImports);
''',
     '''    // MOBILE_WEB: streaming compile (and V8's Wasm code cache) in browsers; boot marks for the bench.
    const marks = globalThis.mmEngineMarks || (globalThis.mmEngineMarks = {});
    marks.fetchStart = performance.now();
    let result;
    if (typeof fetch === "function" && typeof WebAssembly.instantiateStreaming === "function" && typeof process !== "object") {
        result = await WebAssembly.instantiateStreaming(fetch(wasmPath), wasmImports);
    } else {
        const file = await runtime.fetchData(wasmPath);
        marks.fetched = performance.now();
        result = await WebAssembly.instantiate(file, wasmImports);
    }
    marks.instantiated = performance.now();
'''),
]


def main() -> None:
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    text = Path(sys.argv[1]).read_text(encoding='utf-8')
    for old, new in EDITS:
        count = text.count(old)
        if count != 1:
            sys.exit(f'patch_wrapper.py: expected one match, found {count}: {old[:60]!r}')
        text = text.replace(old, new)
    Path(sys.argv[2]).write_text(text, encoding='utf-8')


if __name__ == '__main__':
    main()
