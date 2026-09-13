# MagicMobile working agreement

## Scope and completion

- Work in the checkout selected for this task. Verify its root, branch and relevant diff before editing or releasing; do not switch between MagicMobile copies based on a skill's default path.
- For an implementation request, complete the requested behavior, run proportionate checks, fix task-caused failures and rerun affected checks before handing back. A first patch or passing build alone is not completion.
- Treat the user's approved request as approval of settled requirements and routine implementation choices. State low-risk assumptions and continue. Ask only when an unresolved decision materially changes behavior, scope, cost, security, data handling or an incompatible public interface.
- Read-only reviews, diagnosis-only requests and explicit pause instructions remain read-only or paused. Do not turn them into implementation, deployment or configuration changes.
- Keep changes surgical. Simplify the code being changed; do not rewrite adjacent code for line count, start an architectural redesign or add a new workflow without a task need.

## Skills and discovery

- Use the smallest applicable workflow. Routine behavior fixes are not requests for visual redesign, a design interview, a PRD, issue-tracker setup or a new task.
- For an approved implementation, skill planning steps may use the already-approved interface and behavior; do not ask for the same approval again. Ask about genuinely unresolved product decisions.
- Read domain/context docs when terminology matters, architecture/ADRs when changing component boundaries, and deployment docs when preparing a release. Do not load a document stack before every edit or reread unchanged references within the same task.
- Prefer an available graph indexed for this checkout for semantic discovery. If unavailable, stale or insufficient, use rg immediately. Index repair is not a prerequisite for ordinary work.
- Use systematic debugging for non-obvious failures. For straightforward errors, use a focused diagnosis/fix/regression loop. When reproduction is expensive or unavailable, investigate existing logs and source, label hypotheses, and keep runtime confirmation explicitly pending.
- Delegate isolated work when useful, with a scoped objective and file ownership. Review outputs. Intervene when repeated attempts make no progress, not merely because the first build fails.
- Continue in the current task unless a separate task is requested. Do not depend on unavailable slash commands or mandatory session changes.

## Verification and resource use

- Choose checks for the changed components and actual release path. Documentation/instruction edits need content, link and configuration validation, not an app build.
- Safe local fixture tests may be rerun for task-caused failures without repeated approval after checking they do not access production. A test command is not automatically safe just because it is called a test.
- Reuse passing evidence only when its relevant source, configuration and dependencies are unchanged; record what ran and what did not.
- Do not automatically boot simulators after every code edit. For explicitly requested simulator validation, discover an available device and boot at most one if needed, unless the user says otherwise. Do not erase devices or boot simulators during non-simulator tasks.
- For iOS compilation use the current project's path and /Applications/Xcode.app/Contents/Developer. Generic device builds can check compilation without a simulator; compiling tests is not executing them.
- Keep local Docker/Colima off by default. Run gateway/Docker checks when the changed or shipped path depends on them, not for an unrelated native-only change. Do not silently use a remote machine or paid runner instead.
- Bound discretionary visual polishing; that limit does not justify leaving known task-caused functional or build failures unresolved.
- Report source review, fixture/JVM tests, iOS compilation/linkage, native execution, phone acceptance and TestFlight availability separately. Never weaken tests, expose hidden information or assert an unavailable capability to obtain a green result.

## Releases and permissions

- Checking a build number or release status is read-only. Preparing a build number is a local mutation. Uploading, distributing and changing store/provider configuration require authorization for that action.
- Before release, verify the selected source and artifact, existing com.calebfeliciano.magicmobile identity, build-number availability, and applicable native, signing, privacy and runtime gates. Keep real-engine evidence separate from toy probes and fixtures.
- Preserve the user's chosen route: direct phone installation and TestFlight are different workflows. Lack of USB is not a blocker for a TestFlight request; it remains a blocker for an actual requested direct install.
- Preserve unrelated work and data. Do not delete artifacts, change production, spend money, publish commits/issues or alter permissions solely because a skill suggests doing so. Apply the user's authorization to the exact action and target.

## On-device package (when present and relevant)

- Follow packages/ondevice-engine/AGENTS.md for native engine changes.
- In packages/ondevice-engine/docs/, use LOCAL_CONTINUATION_STATUS.md and NATIVE_BLOCKERS.md for native continuation/release status; historical observations must be verified before acting.
- In that same docs directory, use PORTRAIT_INTEGRATION.md for board integration and PROTOCOL.md for transport/prompt changes.
