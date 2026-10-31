# TestFlight 0.1.1 (74): cooler menus, a smooth profile, blockers that make sense

Uploaded October 31, 2026 and distributed to Internal and External testers. Released with Android build 52
(`release/RELEASE_ANDROID_0.1.1_BUILD52.md`) and the web deploy `dpl_8FRrXrrSTfwM363iSkjLi97mau2D`, from PRs #273, #274 and #275.

## What changed
- **Heat and frame rate (#273):** the menu's flames and sparks share one clock and slow down when hot, effects and menu loops are capped, and shadows moved to their shapes. The game report records the state a game began in, charging and Low Power Mode.
- **Fear and Intimidate (#274):** the inspect view explains them.
- **Blockers (#275):** the block prompt lights only creatures that can block an attacker, using XMage's own `CombatGroup.canBlock`. This is the engine change.

## Release
- **Source:** `codex/ios-build-74` in `~/Documents/MagicMobile-release-40` = main `453b8d1c` + `prepare`, xcodegen.
- **Engine:** identity `sha256:caaa30a0…1be1`, candidate `88bfdbe2`, gate 41234794326, far-calls 41236836681, added to `ranked_engine_builds`.
- **Run:** `ios-0.1.1-74`, fingerprint `a81b7dc6…`, delivery `f5812621…`, VALID about 5 minutes after upload. Preflight `ios-fast` passed 14 of 14, equivalent-source.
- **Built with:** Xcode 27.2.

## Verification
- CI on the three PRs, including the real-card `legal-blockers` test (Marrow-Gnawer and a Rat).
- iPhone 16 Pro Max traces on build 73 source against #273, plugged in, 10 s each (`docs/LIGHTER_ENGINE_PLAN.md`): profile scroll 362 slow frames to 1, idle menu CPU reading 46% to 16%.
- **Not verified on a phone:** this build itself, the new engine on an iPhone, Fear showing on a Rat in a live game, and how hot long games run.
