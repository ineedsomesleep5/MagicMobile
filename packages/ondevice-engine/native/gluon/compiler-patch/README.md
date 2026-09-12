# Pinned ARM64 builder backport

This is **compiler tooling**, not an alternate rules engine and not an engine
runtime test. The 22.1 code cache patches every direct call with one instruction.
The full image can exceed ARM64's signed imm26 × 4 call reach. The preserved
failure is in that exact direct-call patch, after method compilation.

`prepare_graal_trampolines.py` preserves the checksum-pinned Gluon Java 17/iOS
runtime and adapts only its build-time LIR code-cache class. It verifies the
original distribution, exact Oracle input blob, generated class set and patched
jar. It never changes a system compiler. No unsupported `-H` option is guessed.

The planner appends a shared veneer per far callee beside each caller, iterates
until no new veneers are needed, verifies every final call distance and rejects
integer overflow or a single method too large for its nearby veneer. The emitter
uses Graal's own ARM64 scratch-register allocator and ADRP/ADD/JMP patcher. Native
method bodies, card factories, reflection, AI, headers and static JDK are retained.
A compiler marker reports actual veneer count, code size and layout iterations.

Sources reviewed:
- Oracle `vm-22.1.0`, `substratevm/src/com.oracle.svm.hosted/src/com/oracle/svm/hosted/image/LIRNativeImageCodeCache.java`, git blob `f9ba40a80afae95789fb685f268c1d80c5852570`.
- Oracle `vm-22.2.0`, same file, blob `ce4463e220d52f0c4457ffbab9f6fd1b4a051adf` (append-only trampoline layout).
- Oracle `vm-22.2.0`, `substratevm/src/com.oracle.svm.hosted/src/com/oracle/svm/hosted/code/aarch64/AArch64HostedTrampolineSupport.java`, blob `80c2732ffe2c74b5112aea784bf997a0b8373abb` (emission).

The generated upstream source retains Oracle's GPL-2.0-only with Classpath
exception notice; the original distribution contains its license. The independent
planner and its tests are MIT-licensed. Keep the generated source, patch manifest
and compiler artifact hashes with build evidence.

`test_graal_trampolines.sh` exercises layout arithmetic and cascades. A small
non-XMage ARM64 compile/link with a deliberately reduced builder-only call limit
exercises the actual emitter; it must report nonzero veneers. Neither check
proves native XMage execution. Only a fresh full-catalogue + AI ARM64 archive and
unsigned product link can establish the compiler/build milestone. Native runtime,
offline gameplay and multi-phone acceptance remain separate device gates.
