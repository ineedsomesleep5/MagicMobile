# MagicMobile 0.3.0

Shared user-facing release version for iOS and Android. Platform build numbers remain independent and monotonic. Do not claim parity from matching version strings alone.

## Approved scope

- Preserve the commander-led design while extending surfaces to phone safe areas.
- Keep ordinary deck-row controls alongside wrapping long names; preserve accessibility layouts.
- Illustration-focused deck covers, full cards for inspection and gameplay.
- Show engine-report access only when a report exists; temporary, dismissible notification without blocking menu navigation.
- Cards-first combos with prerequisites, exact numbered provider steps and results. Concise analysis and playtest workflows.
- Six shared battlefield options: Stone Arena, Midnight, Classic Wood, Moss Sanctuary, Obsidian Ember, Tidal Slate. No painted-in seats or health UI.
- Android current feature parity (prior multiplayer exclusion awaiting confirmation), signed downloadable APK, iOS TestFlight, updated website links, and safe main-branch integration.

## Verification gates

Separate portable/domain tests, iOS simulator interactions, signed native artifacts, Android runtime/device evidence, store processing/review, website link availability and actual phone acceptance. Preserve prior evidence only for unchanged components.

Screens: portrait and landscape menu/setup, long-name deck row, combo ordering, analysis/playtest, six themes and crowded battlefield. Artwork: existing consent/storage/quality/token/face behavior must remain intact.

## Design references

- EDHREC combo structure: https://edhrec.com/combos/izzet/147-5726 — cards, prerequisites, ordered steps, results. Rules text remains provider data, not generated advice.
- Background assets and exact built-in generation prompts: `apps/ios/BATTLEFIELD_BACKGROUNDS.md`.

## Release records

Pending verification and publication. iOS prepared: 0.3.0 (5000000002). Android artifact, Apple delivery/availability, website deployment and main merge will be recorded after they are verified.

## Current verification

- Portable iOS domain suite: 338 tests, 2 optional skips, 0 failures (`/tmp/magicmobile-v03-portable.log`).
- Native Swift protocol/privacy/transport suite: 34 tests passed; this is not native XMage gameplay (`/tmp/magicmobile-v03-native-swift.log`).
- Simulator: long-name deck controls passed in portrait and landscape; report absence, expiry, retained report and return-to-menu passed. Edge-to-edge menu screenshot inspected.
- Background bundle tests: six stable choices, five square material assets and the native Midnight gradient passed.
- Additional background/combo simulator coverage passed: all six selections, twelve portrait/landscape battlefield captures, and cards/prerequisites/ordered steps/results. The initial run exposed missed synthesized taps and an incorrect test assumption that a horizontally offscreen card occupied a second row; those checks were corrected without changing app behavior. Result: `build_output/presentation-review/v03-backgrounds-combos-rerun.xcresult`.
- Website candidate: production build and mobile/desktop rendering passed; candidate links are not deployed until artifacts are available.
- Apple filtered group discovery returned HTTP 500; app-scoped discovery returned both existing groups. Release discovery now paginates the app-scoped endpoint and validates/filter groups locally, preserving all membership gates.
- Distribution helper regressions: 17 offline tests passed, including incomplete discovery, all-internal membership and review failure cases.
