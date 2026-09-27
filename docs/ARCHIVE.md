# Where archived material lives

Old material is kept in one of two places. Material that is only a historical record
stays in the tree in an `archive/` folder, so links keep working. Large or obsolete
files are removed from `main` and kept at an annotated `archive/*` git tag.

## Archive folders (still in the tree)

| Folder | Contents |
| --- | --- |
| [docs/archive](archive/README.md) | Web-era documents, the July 2026 design QA record (`design-qa-2026-07.md`) and the Rive CLI assessment |
| [packages/ondevice-engine/docs/archive](../packages/ondevice-engine/docs/archive) | Dated engine TestFlight, diagnostic and direct-install notes from September 12–15, 2026 (builds 2026091203–2026091504) |
| [release/testflight/archive](../release/testflight/archive) | Dated TestFlight notes for 0.1.0 builds, September 15–19, 2026 (2026091502, 2026091601, 5000000001). Version 0.1.1 builds are recorded in `release/RELEASE_*.md` |

Current release records stay where they are: `release/RELEASE_*.md`,
`release/testflight/build-ledger.json`, the `ExportOptions*.plist` files and
`release/testflight/BUILD_NUMBER_POLICY.md`.

## Archive tags (removed from `main`)

| Tag | Contents |
| --- | --- |
| [`archive/design-2026-09`](https://github.com/ineedsomesleep5/MagicMobile/tree/archive/design-2026-09) | `docs/design/` (July 2026 design screenshots), `design/magic-path/` (June 2026 MagicPath board handoff), `outputs/` (delegate handoff notes), the unused `mage-mobile-logo.imageset`, and the one-time `packages/ondevice-engine/scripts/install_into_magicmobile.py` with its tests |
| [`archive/legacy-web`](https://github.com/ineedsomesleep5/MagicMobile/tree/archive/legacy-web) | The web stack: `apps/web`, `apps/mobile`, `apps/xmage-gateway`, `apps/engine-worker` and the TypeScript packages |
| `archive/issue-4-mvp`, `archive/issue-4-native-mvp`, `archive/issue-4-release-audit`, `archive/native-runtime-audit-20260914`, `archive/deck-studio-2-native-validation` | Unmerged branches, kept before the September 2026 branch cleanup |

To get a file or folder back without switching branches:

```sh
git fetch origin 'refs/tags/archive/*:refs/tags/archive/*'
git show archive/design-2026-09:docs/design/reference-gameplay-portrait.png > reference.png
git checkout archive/design-2026-09 -- design/magic-path   # restores into the working tree
```
