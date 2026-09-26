# iOS 0.1.1 build 13 — board effects

Apple reports build `8f681fea-15d3-4083-ae1d-252af49f094c` as `VALID` with Beta App Review `APPROVED`, and the Internal and External groups assigned, on September 23, 2026 UTC. The External invitation remains https://testflight.apple.com/join/2mSHE8rZ. These states do not prove a completed physical-phone game.

## Changes

- Board FX phases 1–4 ([PR #24](https://github.com/ineedsomesleep5/MagicMobile/pull/24), [PR #27](https://github.com/ineedsomesleep5/MagicMobile/pull/27)): event timeline from successive snapshots; spell-cast showcase with foil, rune ring and name banner; arrival flights with landing glow; graveyard/exile dissolve shaders; attack lunge; damage flashes, counter sparkle and floating life changes; viewer-hit shake and haptics; five CC0 Kenney impact sounds. Settings: Board Effects (Full / Reduced / Off, capped by Reduce Motion) and Effect Sounds. See `docs/BOARD_FX_ROADMAP.md`.
- Includes build 12's new icon and turn-based shared D20 ([PR #23](https://github.com/ineedsomesleep5/MagicMobile/pull/23)). Android unchanged.
- Marketing version stays `0.1.1`; build `13` was confirmed as App Store Connect's next build number before preparation.

## Verification

- Signed source: `ffe6e599051121b628fe926e2696f4b222939e1d` (`main` at `63dedce` plus the build-13 number bump).
- `ios-fast` preflight passed 11/11 on the integrated board FX source; PR #27 CI (swift, real-jvm, boundary, checks, previews) passed against main.
- Board FX walkthrough verified on the iPhone 17 Pro simulator in portrait with the DEBUG `board-fx` preview. No real-engine game, landscape run or physical-phone check for this build yet.
- Native engine reused, unchanged from build 12: artifact `10674460689` (engine archive SHA-256 `cc30f89075fca4e413147b9159b07e665603eaea9bfa3cb0bb09e7adf4809daf`), staged as APFS clones into the `MagicMobile-board-fx` worktree; installed-hash verification passed.

## Signed artifact and Apple distribution

- Release controller run `ios-0.1.1-13`, fingerprint `1665032fa676ac650fb1a73aa62b014b2ce95169372a69fb04b0cde13928baae`, state `completed`.
- IPA SHA-256 `1dcb994be17e69dfaf90883f39b02836a2210da35a85c4d667fab9e642c4f730`; Apple validation passed.
- Build ID `8f681fea-15d3-4083-ae1d-252af49f094c`. Groups: Internal `dd37d7bb-26d8-4a0c-b8a3-7811d648a699` (all builds) and External `72b71a7a-bf62-43b5-8eda-b12a62e5c3eb` (added). Beta App Review `APPROVED`.
