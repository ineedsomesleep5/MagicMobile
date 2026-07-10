# Native iOS Design QA

## Comparison target

- Source visual truth:
  - `docs/design/reference-home-setup.png`
  - `docs/design/reference-gameplay-portrait.png`
  - `docs/design/reference-gameplay-landscape.png`
- Rendered implementation:
  - `docs/design/implementation-home-portrait.jpg`
  - `docs/design/implementation-setup-portrait.jpg`
  - `docs/design/implementation-gameplay-portrait.jpg`
  - `docs/design/implementation-gameplay-landscape.jpg`
- Device and viewport: iPhone 17 Pro Max Simulator `6CC574DD-C83E-4839-905C-CF51F29B4ADA`; 440 x 956 points, captured at 1320 x 2868 portrait and 2868 x 1320 landscape.
- States: connected Commander home, setup step 1 of 3, normal battlefield priority, and a commander-replacement decision.

The gameplay references use a mulligan prompt while the closest deterministic implementation fixture uses a commander-replacement prompt. Both exercise the same two-choice decision hierarchy, but copy and card counts are intentionally not treated as pixel-match evidence.

## Full-view comparison evidence

- Home and setup: `docs/design/qa-home-setup-comparison.jpg`
- Portrait gameplay: `docs/design/qa-gameplay-portrait-comparison.jpg`
- Landscape gameplay: `docs/design/qa-gameplay-landscape-comparison.jpg`

## Findings

No actionable P0, P1, or P2 findings remain.

- Fonts and typography: native serif display type creates the intended medieval hierarchy while system body/control type remains readable. Titles, step labels, HUD numbers, and decision copy do not clip at the tested standard Dynamic Type size.
- Spacing and layout rhythm: home, setup, prompt, hand, HUD, stack, and action regions have consistent brass-edged spacing. Core controls meet the 44-point target. Portrait and landscape preserve the same board information while recomposing it for the available geometry.
- Colors and visual tokens: charred oak, leather, iron, parchment, brass, emerald priority, and arcane blue are mapped through the shared theme. Contrast is strong without covering card art.
- Image quality and asset fidelity: the implementation uses the existing menu/board artwork, bundled mana/XMage symbols, SF Symbols for standard controls, and real card art in gameplay. The generated setup target contains invented deck portraits that are not source assets; the implementation intentionally uses a clear native deck picker rather than fabricating replacements.
- Copy and content: home actions, setup steps, prompt language, server state, asset state, and timing controls are coherent outside the design brief. Technical server/cache detail has been moved out of the primary play hierarchy.
- Interaction and accessibility: Play Commander was tapped in the live Simulator and opened setup step 1. Quick Battle, resume, deck, settings, server, cache, and game callbacks remain wired. The native accessibility tree exposes labeled primary controls and 44-point settings/zone actions.
- Responsive behavior: the tested Pro Max portrait and landscape layouts do not overlap or hide persistent game controls. Scroll fallback remains available for menu/setup content and larger text.

## Focused region evidence

- Player HUD after correction: `docs/design/qa-player-hud-focused.jpg`
- The focused crop was necessary because the life total is too small to judge reliably in the full-board comparison.
- The final crop shows the complete `37` life value, zone shortcut, and six compact stats with no clipping.

## Comparison history

### Pass 1

- [P2] The compact portrait player HUD truncated the life total as `37...`.
- Impact: a core Commander resource appeared ambiguous in the primary gameplay HUD.
- Fix: made the life value horizontally fixed, removed the redundant tiny `LIFE` suffix from the compact HUD, and added an explicit accessibility label.
- Earlier evidence: `/tmp/magicmobile-player-hud-crop.png`.

### Pass 2

- Post-fix evidence: `docs/design/implementation-gameplay-portrait.jpg` and `docs/design/qa-player-hud-focused.jpg`.
- Result: the life total renders as `37` without truncation, including in the commander-replacement prompt state.
- No new P0, P1, or P2 differences were found in the home/setup, portrait gameplay, or landscape gameplay comparisons.

## Primary interactions tested

- Home rendered after live XMage bridge health completed.
- Play Commander opened guided setup step 1.
- Portrait rotation preserved the gameplay hierarchy.
- Commander replacement displayed both legal choices and the action dock without a conflicting Pass action.
- Landscape displayed the latest-event log access, phase/priority, hand, HUDs, stack, and timing controls.

## Implementation checklist

- [x] Central rustic-medieval theme and design tokens
- [x] Focused Commander home
- [x] Dedicated settings and compact asset status
- [x] Guided three-step setup
- [x] Adaptive portrait and landscape gameplay
- [x] On-demand game log with latest-event summary
- [x] Coherent prompt/action dock
- [x] 44-point controls and accessibility labels
- [x] Simulator build, install, launch, interaction, and screenshot proof
- [x] Clean iOS test run

## Follow-up polish

- [P3] Add curated, rights-cleared deck/commander thumbnails if the product later ships a stable artwork manifest for precon selection.
- [P3] Repeat the visual matrix at accessibility text sizes as a separate accessibility hardening pass.

final result: passed
