# iOS 0.1.1 build 14 — game feel pass

Apple reports build `6098d8e2-2d4c-499b-b14a-b2fcc4d9906b` as `VALID` with Beta App Review `APPROVED`, and the Internal and External groups assigned, on September 24, 2026 UTC. The External invitation remains https://testflight.apple.com/join/2mSHE8rZ. These states do not prove a completed physical-phone game.

## Changes

- Board FX build 14 ([PR #29](https://github.com/ineedsomesleep5/MagicMobile/pull/29)), from Caleb's build 13 notes:
  - Life changes are drawn once.
  - Spell showcases hold long enough to read.
  - Permanents land only after their spell finishes.
  - Attackers hold a stance, blockers pair up with a tether, and at combat damage attackers charge their target, with damage, deaths and life landing on impact.
- Also in PR #29:
  - Big moments: a showcase for permanents that resolve before they are ever seen on the stack; commander cast and entrance; a turn-start ribbon; a victory/defeat screen; a board flash for spells with mana value 6+.
  - Hand and cards: a fanned hand with lift under the finger; a breathing playable glow; a legendary gold edge; foil on the held inspection card; color-identity particles.
  - The phase card is now a small pill under the top HUD.
- Prompts:
  - Mana, tap and `{this}` render as symbols or names in buttons; XMage object IDs are removed.
  - Long options become full-width rows, and primary buttons have higher contrast.
  - Mode choices are titled "Choose mode", and the tapped-card ability popup lists full ability text.
- Marketing version stays `0.1.1`. Build `14` was prepared with `scripts/ios/testflight-build-number.mjs` after build 13. Android is unchanged.

## Verification

- Signed source: `8171ebd8953bd8ef69292300501d6696424af340`, which is `main` at `cfb49c1` plus the build-14 number bump.
- Tests and CI:
  - `ios-fast` preflight passed 11/11.
  - Portable Swift tests passed 67/67.
  - The generic iPhone compile was clean.
  - PR #29 CI (swift, real-jvm, boundary, checks, previews) passed.
- Simulator: the board FX walkthrough was verified on the iPhone 17 Pro simulator in portrait, using an optimized Debug build and the DEBUG `board-fx` and `mode-choice` previews.
- Presentation-smoke UI tests: library choices and modal offer glows pass in both orientations. Two failures also occur on `main`: the Deck Studio history test, and the phase-announcement hand-button hittable check.
- Not yet verified: a real-engine game, landscape combat visuals, or a physical-phone check for this build.
- Native engine reused, unchanged from builds 12–13: artifact `10674460689` (engine archive SHA-256 `cc30f89075fca4e413147b9159b07e665603eaea9bfa3cb0bb09e7adf4809daf`).

## Signed artifact and Apple distribution

- Release controller run `ios-0.1.1-14`, fingerprint `4ff4afffe16470de05cf9e37ef61a66750c41b6bafa68a187ca9a3ed96e4b7e4`, state `completed`.
- IPA SHA-256 `98ef78eff257afd37f43d581cfc10324df6531a71b789d1162efc184c18c37f4`; Apple processing `VALID`.
- Build ID `6098d8e2-2d4c-499b-b14a-b2fcc4d9906b`.
- Groups: Internal `dd37d7bb-26d8-4a0c-b8a3-7811d648a699` (all builds) and External `72b71a7a-bf62-43b5-8eda-b12a62e5c3eb` (added).
- Beta App Review `APPROVED`.
