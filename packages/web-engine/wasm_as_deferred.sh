#!/usr/bin/env bash
# The Web Image builder's assembler (-H:WasmAsPath, set by build_web.sh). Web Image prints the module as a .wat text
# file (gigabytes for the full engine) and runs binaryen's wasm-as on it while the builder JVM still holds its whole
# heap, so the two processes' memory adds up. This passes every other call through to wasm-as (its version check
# and test assembly) but only records the command for the module itself (MM_WASM_AS_DEFER: the .wat path) in
# MM_WASM_AS_DEFER.args, one argument per line, and leaves an empty output file; build_web.sh runs the recorded
# command after the builder has exited.
set -euo pipefail
real=${MM_WASM_AS:-wasm-as}
deferred=${MM_WASM_AS_DEFER:-}
if [[ -n $deferred && " $* " == *" $deferred "* ]]; then
  printf '%s\n' "$@" > "$deferred.args"
  for arg in "$@"; do [[ $arg == --output=* ]] && : > "${arg#--output=}"; done
  echo "wasm_as_deferred.sh: recorded the assembly of $deferred for after the builder exits"
  exit 0
fi
exec "$real" "$@"
