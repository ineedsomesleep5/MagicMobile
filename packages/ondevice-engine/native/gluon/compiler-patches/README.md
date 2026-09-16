# Pinned AArch64 far-call backport

Issue #4's old full-engine build completed compilation and failed while patching a B/BL direct call. Gluon 22.1's LIR code cache has no veneers; its assembler correctly rejects a displacement outside the signed 26-bit, four-byte-scaled field. More heap cannot change that encoding.

This proposed build-time backport preserves every compiled method and its body. It iteratively places 12-byte ADRP/ADD/BR veneers after a caller when a callee is too far away. The instruction sequence uses Graal's existing AArch64 assembler, reserved scratch register, and hosted patcher, following the later upstream 22.3 implementation. Runtime metadata and symbol extents include the added code. Non-AArch64 compilation keeps the original layout. No branch offset is truncated and no card registry is pruned.

`FarCallPlanner.java` is the exact independent planner used by the patched compiler. Its tests cover both branch limits, forward/backward calls, shared targets, multi-pass growth, overflow, oversized callers, and 500 deterministic randomized layouts. Passing these tests is not native instruction execution.

`prepare_gluon_far_calls.py` extracts a fresh copy of the checksum-pinned official Intel compiler into an owned build directory. It downloads the three exact upstream source files, verifies each before and after applying `far-calls.patch`, compiles with that SDK, and replaces classes only in the private copied builder JAR. It never changes the installed/previous SDK. The manifest records source, patch, original/patched JAR and individual class hashes.

## Acceptance

1. Planner unit tests pass.
2. The three classes compile against the actual pinned Gluon SDK.
3. A separate toolchain-only ARM64 probe forces a small distance, reports nonzero veneers, and links without signing or execution.
4. The unpruned AI-inclusive XMage engine builds an ARM64 archive and the existing iOS product links against its matching headers and dependencies.
5. Native runtime and phone gameplay are separately checked by desktop Codex/TestFlight.

Until a gate has been executed successfully, it remains unproven. Never count the probe as XMage or use its archive as the product.

## Upstream and license

Sources are pinned to Oracle Graal commit `da6a62d607552fc958ccb63f4ca1d81e1817cadc` (`vm-22.1.0`). The reference veneer implementation is `AArch64HostedTrampolineSupport.java` in `vm-22.3.0`. See `upstream-sources.json` for exact paths and hashes.

The compiler patch and planner are GPL-2.0-only WITH Classpath-exception-2.0. Oracle's copyright and license headers are preserved in the patched sources. The original compiler distribution contains the complete license; the verification artifact retains the corresponding source/license. This build-time compiler adaptation does not change the XMage source license.
