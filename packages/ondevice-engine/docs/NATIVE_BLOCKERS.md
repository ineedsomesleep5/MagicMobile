# Remaining native/runtime gates — 2026-09-12

## New candidate in progress

Opening-selection cancellation race was reproduced, fixed in `a34fb08`, and the
complete real JVM suite passed. New ARM64 run **34723517045** is required: the old
archive/upload below cannot represent changed production engine source. Physical
acceptance must use the replacement candidate, not build 2026091201.

## Resolved source/build blockers

The full XMage+MAD ARM64 archive passed in run **34673638060**, artifact
**10292778783**. The later Apple final-link `arm64_b26` failure was reproduced
and fixed by placing the intact Graal image first and using seven ARM64 far-call
veneers. No cards/AI were removed and no rules fallback was introduced.

Actual unsigned product Release `62789b0` passed. Archive, distribution export,
signature, Game Center entitlement and Apple validation/upload passed for
internal **0.1.0 (2026091201)**. Processing is **VALID** with internal state
**MISSING_EXPORT_COMPLIANCE**; that initial candidate is superseded.
See [current status](LOCAL_CONTINUATION_STATUS.md) for exact hashes/artifacts.

## Remaining gates

| Gate | Evidence now | Still required |
|---|---|---|
| Registry | 32,275 card factories, 587 sets, 92,166 printings; no unregistered printing references | Reviewed exclusions are not universal card/gameplay proof |
| Rules/AI | Real JVM Commander, query/control/privacy, lifecycle, MAD play/cancellation and five exact precons passed | Genuine native iPhone execution |
| Native image | Complete ARM64 engine compiled; actual product links; code/922 relocations/seven veneers inspected | Runtime class initialization, reflection/resources and real card paths on iOS |
| Product UI | Native entrypoint, setup and prompt/zone adapters; 108 portable app tests; SDK build | Rendered portrait/landscape, accessibility and touch acceptance |
| Ownership | C ASan/UBSan, Swift cleanup fixtures and real JVM busy/resolving/AI tests passed | Repeated native isolate start/leave/restart and busy retry |
| Game Center | Authenticated routing/correlation/suspension source and portable tests; distribution entitlement verified | Real 2–4-phone matches across networks and interruptions |
| Performance | No native measurements | Phone RAM, thermal, battery, AI latency and crash evidence |
| Distribution | Internal-only upload succeeded | Apple processing and actual tester install/launch |

## Explicit limitations

Durable match restore, host migration, draft/tournament construction and nested
turn control are not implemented. Backgrounding suspends submissions; it is not
checkpointing or guaranteed continued hosting. Host termination may lose the
match. The UI must say so, not imply reconnect/resume works.

## Runtime risks to exercise

- Native image success does not prove every reachable AWT, repository, Gson,
  reflection, serialization or resource path works on iOS. Keep real failing
  card/prompt evidence; never substitute approximate rules to silence it.
- Shutdown ABI v2 retains ownership on busy/failure and exposes retry. Never tear
  down an isolate while a worker owns it. Ambiguous final teardown may deliberately
  retain allocations until process exit; explicitly close/retry in the lifecycle.
- Keep C/Swift fixture outputs outside Gluon's reserved `build/native` directory.
  Do not accidentally include host-platform fixture objects in native artifacts.
- Preserve source/blob/compiler hashes and all paired generated/static inputs.
  A changed upstream needs reviewed regeneration and fresh gates, not relaxed checks.

All physical checks are **NOT RUN**. Track them in
[TESTFLIGHT_ACCEPTANCE.md](TESTFLIGHT_ACCEPTANCE.md), independently from issue #4
source/build completion.
