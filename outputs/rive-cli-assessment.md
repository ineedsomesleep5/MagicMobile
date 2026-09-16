# Rive CLI assessment for MagicMobile

Research checked 2026-09-15. Selected checkout: `MagicMobile-runtime-hardening`; observed native freeze `fca652a80f643d4a88fe2f8f0ac781be1fd096a4`. This assessment changes no app, engine, dependency, or build configuration. No installer or Rive binary was executed; no builds, uploads, account changes, or purchases were performed.

## Recommendation

Use native SwiftUI for immediate life-number changes, phase emphasis, and combat selection. Evaluate the **official Rive CLI** after the current release as an authoring tool for one bounded, decorative life-change effect. It is now a real first-party RML authoring/build tool, not just a proposed workflow. Do not introduce it into the frozen release or replace game controls with a Rive canvas.

The biggest unresolved shipping question is not whether it generates `.riv`: it does. It is the supported, licensed, unwatermarked production-export route. Current documentation describes unsigned builds as local-use output and says all published builds currently carry a watermark while account-file binding is unfinished. Ask Rive to confirm the native commercial path rather than treating technical export capability as permission. [Official getting started](https://rive.app/docs/cli/getting-started)

## Official versus third-party

| | Official Rive CLI | George-RD project |
|---|---|---|
| Publisher | Rive, linked from its downloads page | Independent `George-RD/rive-rs-cli` repository |
| Executable | `rive` | `rive-cli` |
| Authoring | XML RML plus `rive.yaml` | JSON SceneSpec/AuthoringSpec |
| Build | `rive project --once` | `rive-cli generate scene.json -o out.riv` |
| Inspection | Schema, resolved scene, screenshots, data dumps, script tests | Schema, validation, decompilation, rendered-frame comparison |
| License evidence | Apple runtime MIT; do not infer the CLI has that license | Repository advertises MIT |

George-RD's renderer uses headless Chromium/CDP. Its browser evidence does not establish Apple Metal compatibility. Prefer the official tool for this exploration; the commands, schemas, and licensing are not interchangeable. [Official downloads](https://rive.app/downloads), [third-party source](https://github.com/George-RD/rive-rs-cli)

## What the official tool can do today

The live distribution manifest reports **CLI 1.0.3**, with macOS ARM64, Linux x64, and Windows x64 artifacts. [Release manifest](https://releases.rive.app/cli/latest/manifest.json)

RML represents shapes, fills, timelines, state machines, assets, and view models using Rive's object types. References use document-wide IDs; animation properties can use numeric property keys, so schema inspection matters. Multiple RML files can compile together. Files are discovered by extension; all discovered Luau scripts and WGSL shaders compile even when unreferenced, whereas unused image/font assets need not embed. Keep experimental scripts out of a production project or explicitly exclude them. [RML](https://rive.app/docs/runtimes/advanced-topic/rml), [project configuration](https://rive.app/docs/cli/reference/project-config)

The workflow covers scaffolding, watched preview, unsigned runtime output, signed publishing, editor-file export/import, and headless inspection. `.riv` is runtime content; `.rev` is an editable editor document. `rive create project --from-rev=input.rev` extracts an existing editor document into a new local project. This is not live bidirectional editor synchronization: that capability is still described as forthcoming. [Overview](https://rive.app/docs/cli/overview), [getting started](https://rive.app/docs/cli/getting-started)

Useful commands for a later approved experiment—not executed here:

```sh
rive create life-effect
rive life-effect
rive life-effect --verify --format=json
rive life-effect --once --format=json
rive inspect life-effect --json
rive life-effect --screenshot=life-effect/build/impact.png --advance=250ms
rive life-effect --test --format=json
```

Capture supports viewport sizing, ordered data/pointer changes and time advancement. Data dumps expose bound values; script tests exercise authored logic. `--bench` measures CLI advance/render behavior, not iPhone performance. Beware documented silent failures: unknown artboard names fall back, unknown data paths can log and continue, and unknown flags can be ignored. Assert output properties and inspect actual images; exit zero alone is insufficient. PNG capture is documented; this assessment found no basis to promise a general CLI MP4/GIF export pipeline. [Command reference](https://rive.app/docs/cli/reference/commands)

## Account, price, and licensing

Local creation, preview, verification, unsigned builds, captures, and tests work offline without signing in. `--publish` and `--rev` require login. Publishing signs through Rive's API; web files containing scripts need that signing. The documentation's web restriction does not by itself establish native unsigned-file shipping rights. Publishing currently watermarks even script-free content until binding via the not-yet-available `rive push`. Paying for a plan should not be assumed to remove this CLI limitation. [CLI account/export details](https://rive.app/docs/cli/getting-started)

Current documented editor plans: Free $0; Cadet $17/seat monthly or $108/seat/year prepaid; Voyager $39 monthly or $304/year prepaid. Runtime exports begin with Cadet; higher plans add collaboration/hosting capabilities. No separate CLI fee was established by the inspected docs. Recheck checkout pricing before purchase. [Official pricing documentation](https://rive.app/docs/account-admin/pricing), [pricing page](https://rive.app/pricing)

The Apple runtime is MIT, including commercial use with its notice requirements; that is distinct from editor/CLI service terms and licenses for artwork, fonts, or marketplace content. No independently verified MIT license for the official CLI binary was found in this assessment. Obtain written clarification on distributing local CLI-generated unsigned assets and on an unwatermarked `.rev` → paid-editor-export route before selecting either for production. [Apple runtime license](https://github.com/rive-app/rive-ios/blob/6.27.0/LICENSE), [service terms](https://rive.app/docs/legal/terms-of-service)

## Installer inspection—not execution

Read the official shell installer as text from [releases.rive.app](https://releases.rive.app/cli/install.sh). It fetches a latest or version-pinned manifest and archive, checks SHA-256 against that manifest, validates archive paths, rejects selected symlink cases, installs executable/docs/samples under a user-owned Rive directory, and maintains cached versions. It requires curl, tar, Python 3 and a SHA-256 utility. Its Unix platforms are macOS ARM64 and Linux x64; Windows uses a separate installer, not reviewed here.

It supports `RIVE_VERSION`, `RIVE_HOME`, `RIVE_INSTALL_DIR`, and a distribution-base override. It does not require sudo or itself edit the shell profile, but replaces installation content and **removes the macOS quarantine attribute** from installed executables. Same-CDN checksums provide integrity checking, not independent signature attestation. These observations are not a security certification.

For a future approved installation: retain/review the exact script, pin the version, use the official distribution, and avoid piping an unreviewed download into a shell. The observed macOS 1.0.3 archive checksum is `504f3ec8c51cc800c2197098702d2ee1f559322f59519855e84ea99a608483be`; no archive was downloaded or verified here. Configure analytics off for the experiment (`RIVE_ANALYTICS=off`). Avoid login, publishing, or serving previews unless separately needed and authorized. [Manifest](https://releases.rive.app/cli/latest/manifest.json), [CLI environment/settings](https://rive.app/docs/cli/reference/commands)

## Apple integration and stability

Latest GitHub release observed: **6.27.0**, published September 15, 2026. Its package supplies a checksum-pinned binary XCFramework, Swift tools 5.10, and iOS 14+ support (also other Apple platforms). Swift Package Manager is the documented preferred integration. Bundle approved `.riv` assets locally; a server or Rive account is not part of the app playback architecture. [Release](https://github.com/rive-app/rive-ios/releases/tag/6.27.0), [pinned package manifest](https://github.com/rive-app/rive-ios/blob/6.27.0/Package.swift), [Apple guide](https://rive.app/docs/runtimes/apple/apple)

The current Swift-first API uses `Worker`, `File`, `Rive`, and SwiftUI representables. Async initialization and worker processing do not make app-facing APIs arbitrary-thread-safe: they remain main-actor isolated. Share a worker/cache files rather than repeatedly constructing them in SwiftUI body evaluation. Each independently animated player needs independent presentation state. The migration guide recommends data binding; the new API does not preserve legacy direct-input/event-listener APIs and requires state machines rather than directly targeting linear animations. Do not copy an old `RiveViewModel` example into a new-API design without checking this distinction. [Migration guide](https://rive.app/docs/runtimes/apple/migrating-from-legacy)

Release 6.27.0 fixes an iOS Metal drawable-disposal crash and reports an iOS ARM64 binary reduction from 6.18 to 4.60 MiB. This demonstrates active maintenance, not proven stability in MagicMobile; the release's minimal-app size figures are not our app's incremental download size. Pin and test an exact version. Native playback, framework linkage with the existing native engine, lifecycle stability, and actual device cost remain untested. [Release evidence](https://github.com/rive-app/rive-ios/releases/tag/6.27.0)

Rive renders through Metal. Compare total resource cost, including the app and relevant render-server process, not only an app CPU gauge. Use one small effect, no idle loop, bounded overlap, cached resources, and pause/unmount when inactive or backgrounded. Start a device experiment at 30 fps and compare visual quality and cost against 60; measure rather than presume either is optimal. Avoid 3D/GPU Canvas for this 2D use case; that opt-in is unnecessary here. [Resource usage](https://rive.app/docs/runtimes/apple/resource-usage), [frame-rate/pause APIs](https://rive.app/docs/runtimes/apple/apple), [GPU Canvas](https://rive.app/docs/runtimes/apple/gpu-canvas)

## Accessibility and proposed motion scope

Reduced motion is **not automatic**. Pass the system preference through a bound property or select a static alternative; update it when the preference changes. Prefer no moving effect over freezing a burst midway. Keep real life totals and phase labels as native accessible text. Rive's Apple semantics are opt-in, new-runtime-only, and still documented as early-access/experimental—do not make them the only accessibility path for gameplay. [Reduced motion](https://rive.app/docs/editor/accessibility/reduced-motion), [Apple semantics](https://rive.app/docs/runtimes/apple/semantics)

Proposed choices, not implemented or performance claims:

| Surface | Practical choice | Constraint |
|---|---|---|
| Life decrease/increase | Native signed delta and immediate number update; optional short Rive impact/ring | A decrease is not necessarily damage; never invent cause from a number change |
| Phase change | Native brief emphasis on the actual active phase | No forced delay, perpetual glow, or animation-owned phase state |
| Combat | Native selected-card outlines/arrows; optional one-shot emblem | Animate only authorized public state; no hidden lookup or animation-driven attack resolution |
| End-of-game/menu polish | Optional authored Rive flourish | Dismissible, reduced-motion equivalent, no gameplay input interception |

The app—not the animation—must deduplicate effects by authoritative update identity, establish an initial baseline without fake damage, avoid replay on reconnect/resync, and bound simultaneous effects. Never infer several damage events from one coalesced snapshot. A future data-binding contract could include effect kind, magnitude, color/theme and reduced-motion preference; it must contain no private card data. Keep the decorative overlay non-hit-testing and out of VoiceOver's tree while native controls retain semantics.

## Approval and validation gates

1. Confirm commercial export rights and an unwatermarked route with Rive. No account creation, paid plan, or cloud upload is authorized by this research.
2. After release, approve a pinned CLI/runtime experiment and isolated asset directory; author a simple script-free 2D effect with a static alternative.
3. Validate compiler diagnostics, named artboard/state-machine/property contracts, snapshots across start/impact/end, repeated events, and reduced motion. A successful CLI screenshot is not Apple-runtime evidence.
4. Separately compile/link the pinned Apple runtime, execute on a representative physical iPhone, and measure idle/active CPU, GPU, memory, energy, and scrolling responsiveness alongside the real engine. Exercise background/foreground, rapid navigation, rotation, resource teardown, and load failure fallback.
5. Only integrate after those gates pass. No native-engine rebuild should be inferred from this assessment; any eventual app dependency change needs its own app release validation.

Evidence here is documentation, installer-text, release/package-source inspection, and read-only checkout checks only. No Rive asset, playback behavior, or performance result was produced. Current native freeze is preserved.
