# MagicMobile

MagicMobile is a native iOS Commander game powered by an embedded XMage rules
engine. The active product is the SwiftUI app in `apps/ios`, with portrait and
landscape play, local deck building/import, and on-device games against XMage AI.
XMage owns rules, legal choices, priority, the stack and authoritative game state.

## Start here

- [iOS application](apps/ios/MagicMobile): gameplay, Deck Studio, card inspection,
  phase/life feedback, diagnostics and the Updates menu.
- [Embedded engine](packages/ondevice-engine/README.md): Java/XMage adapter,
  native iOS compilation and Swift transport.
- [Native architecture](packages/ondevice-engine/docs/ARCHITECTURE.md) and
  [app/board integration](packages/ondevice-engine/docs/PORTRAIT_INTEGRATION.md).
- [Latest recorded release](release/testflight/COMMANDER_POLISH_20260916.md):
  build 0.1.0 (2026091601), verification, screenshots and known limitations.
  Apple review status in release records is a dated observation.
- [Release records](release) and
  [native continuation](packages/ondevice-engine/docs/LOCAL_CONTINUATION_STATUS.md).
- [Run a multiplayer server on your own PC](apps/multiplayer-server/selfhost/README.md):
  checksum-pinned Windows/macOS/Linux launcher and the remaining online setup requirements.

The signed product uses `apps/ios/native-engine.yml` and the existing
`com.calebfeliciano.magicmobile` identity. `apps/ios-ondevice` is an engineering
inspection harness. Fixture previews exercise the real presentation code with
prepared states; they do not establish real-engine gameplay acceptance.

## Local development

Use `/Applications/Xcode.app/Contents/Developer` for Xcode tooling. Lightweight
presentation and protocol checks can run without launching a simulator:

```sh
swift test --package-path apps/ios --jobs 2
swift test --package-path packages/ondevice-engine/swift --jobs 2
```

For native linking, follow the engine documentation and use the verified native
artifact preparation/release scripts. Regenerate the native project, when needed,
with `xcodegen generate --spec apps/ios/native-engine.yml`. A native app requires
a compatible compiled engine; a successful presentation test is not a substitute.
Docker and the old hosted gateway are not prerequisites for the native product.

## XMage updates and news

The app's **Updates** menu shows its installed version/XMage revision, bundled
release notes, and links to upstream XMage news. New upstream cards and abilities
arrive through a tested app release, not automatic executable downloads.

The [maintenance workflow](.github/workflows/magicmobile-upstream-maintenance.yml)
runs detection weekly on Mondays at 09:23 UTC when enabled on `main`. Manual
`detect` runs use the same path. It inspects pinned upstream Git objects and
produces a change report without executing the new engine. The separate Codex
heartbeat provides review/notification follow-up.

The [maintenance guide](scripts/magicmobile-maintenance/README.md) documents the
remaining sequence: review the report, prepare a candidate, regenerate and review
the catalogue, validate engine/app compatibility, publish a draft PR, then review,
merge and release. Candidate builds, PR publication, native signing and TestFlight
delivery are explicit steps; the weekly job does not automatically merge or ship.

## Repository layout

| Path | Role |
| --- | --- |
| `apps/ios` | Active native iOS product and its unit/UI tests |
| `apps/android` | Native Android (Compose) port of the iOS app |
| `packages/ondevice-engine` | Embedded XMage engine, native bridge and verification |
| `apps/ios-ondevice` | Engineering inspection harness |
| `apps/multiplayer-server`, `services/table-relay`, `supabase` | Online play: self-hosted engine server, cross-play table relay and matchmaking schema |
| `apps/site` | Download website |
| `scripts/ios`, `scripts/release`, `release/` | Release tooling and delivery records |
| `scripts/magicmobile-maintenance` | Upstream detection and reviewed update preparation |

The earlier web app, hosted XMage gateway and TypeScript packages were removed; they are preserved at the [`archive/legacy-web`](https://github.com/ineedsomesleep5/MagicMobile/tree/archive/legacy-web) tag, with their docs in [docs/archive](docs/archive/README.md).

The on-device workflow runs engine/protocol and portable app checks for native
changes on PRs and `main`. Full simulator and native release gates remain separate.

## Verification boundaries

Simulator fixtures, real JVM games, native compilation/linkage, physical iPhone
play, multiplayer acceptance and TestFlight availability are recorded separately.
See the release report for remaining device checks. EDHREC currently uses an
explicit website handoff; deck paste supports Moxfield and Archidekt text exports.
