# Remaining gates for the runtime-hardened candidate

Start with [current continuation](LOCAL_CONTINUATION_STATUS.md),
`implementation-status.json`, and [PR #9](https://github.com/ineedsomesleep5/MagicMobile/pull/9).
Do not treat the older 2026091301 release as proof of the new runtime repairs.

## GitHub source/build gates

The final functional source is `d04f9cac88d680af10fe7174fab85f624e5ad491`.
Full ARM64 run **34872508758** and paired native-linked unsigned Release product
run **34883826069** both passed. Their artifacts were downloaded/hash-checked;
all required job steps passed. Exact identities and 51-file native provenance are
in [current status](LOCAL_CONTINUATION_STATUS.md). Non-simulator **34871098576**,
CI **34871103720**, and package **34871103725** passed on that same source.
The new archive contains the mana validation repair; the earlier `f8e1680`
archive is historical only. The agreed pre-phone implementation/check matrix is
complete; signing, native execution and physical acceptance below remain separate.

The original compiler call-range, Apple linker layout, Color/AWT, token resource
and desktop-catalogue problems have targeted repairs and regression evidence.
The runtime-hardened candidate crossed the native compilation and unsigned
product-link gates. See the current machine-readable status for exact evidence;
the remaining signing, native execution and phone gates below are unexecuted.

## Desktop signing and distribution

Only after separate release authorization, desktop Codex must select an unused build number,
regenerate and verify the native Release product, sign/archive/export it, verify
the exported binary and UUID-matched dSYM/code layout/Game Center entitlement,
and perform an authorized internal TestFlight validation/upload. Apple processing
and tester availability must be checked separately. No new upload or signing is
performed by this GitHub continuation. Keep prior signed archives and receipts.

## Physical acceptance remains separate

Caleb must test normal native startup through starting-player and mulligan,
a complete offline game, mana/commander/complex prompts, AI responsiveness and
memory/thermal behavior, repeated close/new match, accessibility and rotation,
and real 2–4-phone Game Center games with interruptions. See
[the exact checklist](TESTFLIGHT_ACCEPTANCE.md); issue #7 remains open until
recorded device results exist. No simulator result is used for this task.

Durable game restore, host migration, guaranteed reconnect, nested/chained turn
control, draft and tournament construction remain outside this Commander MVP.
Do not promise them or disguise their absence as a completed feature. Successful
builds and a handful of JVM games do not establish exhaustive card/phone parity.

Prior blocker chronology is preserved in
[Git history](https://github.com/ineedsomesleep5/MagicMobile/blob/7992311b4a41720f9a37858e44dbd5122ae5bdb2/packages/ondevice-engine/docs/NATIVE_BLOCKERS.md).
The narrow Color adaptation and its limits are documented in
[NATIVE_COLOR_COMPATIBILITY.md](NATIVE_COLOR_COMPATIBILITY.md).
