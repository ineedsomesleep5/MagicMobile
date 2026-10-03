---
name: MagicMobile download site
description: Walnut & Ember. A candlelit tavern table, tactile cards, and a cinematic path into the native app.
colors:
  walnut: "#1b120b"
  walnut-deep: "#110a05"
  leather: "#29140b"
  leather-raised: "#3a2416"
  enamel: "#6b120d"
  brass: "#dba34d"
  brass-light: "#ffe08f"
  brass-dark: "#5c3814"
  ember: "#ff8058"
  ember-light: "#ff9d7e"
  parchment: "#f2e0bd"
  parchment-ink: "#f3e6c8"
  parchment-soft: "#cfb994"
  ink: "#2b1a0d"
  ink-soft: "#5b3d22"
  plaque-ink: "#ffe8a8"
  hairline: "#dba34d57"
gradients:
  gild: "linear-gradient(180deg, #ffe7a6 0%, #f2c46e 36%, #d0943d 70%, #a9692a 100%)"
materials:
  walnut: "/tavern/walnut.webp, 340px tile under a dark wash"
  leather: "/tavern/leather.webp, 171px tile (3 px per point)"
  parchment: "/tavern/parchment.webp, 256px tile"
  ember-glass: "/tavern/ember.webp, stretched, top highlight and bottom shade"
  brass-rim: "/tavern/capsule.webp border-image 63 66 / 21px 22px, rivets repeat as it widens"
  brass-rim-thin: "/tavern/capsule-thin.webp border-image 30 33 / 10px 11px"
  brass-frame: "/tavern/frame.webp border-image 72 / 24px (12px for the dock)"
typography:
  display:
    fontFamily: "Source Serif 4 Variable, Georgia, serif"
    fontSize: "clamp(76px, 11.4vw, 184px)"
    fontWeight: 800
    lineHeight: 0.9
    letterSpacing: "-0.035em"
  headline:
    fontFamily: "Source Serif 4 Variable, Georgia, serif"
    fontSize: "clamp(44px, 5.7vw, 86px)"
    fontWeight: 760
    lineHeight: 1
    letterSpacing: "-0.025em"
  body:
    fontFamily: "Source Serif 4 Variable, Georgia, serif"
    fontSize: "16-18px"
    lineHeight: 1.6
  action:
    fontFamily: "Source Serif 4 Variable, Georgia, serif"
    fontSize: "21px"
    fontWeight: 700
  label:
    fontFamily: "Source Serif 4 Variable, Georgia, serif"
    fontSize: "13-14px"
    fontWeight: 650
    letterSpacing: "0.14em"
    textTransform: uppercase
rounded:
  plaque: "22px"
  plaque-thin: "12px"
  panel: "12px"
  dock: "14px"
  card: "10px"
  phone: "42px"
spacing:
  compact: "12px"
  control: "16px"
  section-copy: "24px"
  copy-break: "30px"
components:
  download-action:
    material: "ember-glass in brass-rim"
    textColor: "{colors.plaque-ink}"
    typography: "{typography.action}"
    rounded: "{rounded.plaque}"
    padding: "14px 32px"
  secondary-plaque:
    material: "leather in brass-rim (brass-rim-thin when compact)"
    textColor: "{colors.parchment}"
  destination-dock:
    material: "leather in brass-frame at 12px, ember-glass download link"
    textColor: "{colors.parchment}"
    rounded: "{rounded.dock}"
    padding: "9px"
  parchment-panel:
    material: "parchment in brass-frame"
    textColor: "{colors.ink}"
    labelColor: "{colors.enamel}"
    rounded: "{rounded.panel}"
  hand-tool:
    material: "leather in brass-rim-thin"
    textColor: "{colors.parchment}"
    rounded: "{rounded.plaque-thin}"
  platform-choice:
    material: "leather in brass-rim; selected adds an ember glow and brass-light text"
    textColor: "#f2e0bdbd"
---

# Design System: MagicMobile download site

## Overview

**Creative North Star: "A hand dealt by candlelight"**

The site wears the app's **Walnut & Ember** brand, approved by Caleb for the iOS app on 2026-10-01/02: a candlelit fantasy tavern table seen from above. Carved dark walnut, worn tooled leather, polished brass trim with rivets, parchment cream and ember-orange firelight. It should feel physical, warm and premium, like a game's menus rather than a flat tech page. Ember stays the single action colour; brass and gilding mark headings and trim.

Source of truth for the brand is the app: `apps/ios/MagicMobile/BrandUI.swift` (`BrandTheme`, `BrandButtonStyle`) and `TavernPalette`, `TavernFill`, `TavernCapsuleRim` and `TavernBrassFrame` in `apps/ios/MagicMobile/Board/BoardChrome.swift`. The web materials are the same rendered brass parts and fills from `Assets.xcassets/tavern-ui-*`, converted to WebP under `public/tavern/` (see [ASSETS.md](ASSETS.md)).

This records the current site implementation, not production deployment. Page choreography belongs in [SURFACE.md](SURFACE.md). The earlier charcoal/coral "tech" look (Archivo and Manrope) is retired.

**Key Characteristics:**

- Serif voice throughout: Source Serif 4 (the Android app's serif; iOS uses Apple's New York), self-hosted, with optical sizing.
- Real materials: walnut, leather, parchment and ember glass textures; brass rims and frames drawn with `border-image` from the app's own renders.
- Genuine card scans, real app screenshots labeled as previews, scroll-driven depth with static and reduced-motion fallbacks.

## Colors

Walnut is the page ground; leather is the ground of the download desk, dock and plaques; parchment is the surface for dense information (capability ledger, platform details) and takes dark ink with oxblood enamel labels. Brass (`#dba34d`) is used for small labels, rules, icons and rims; the gild gradient fills accent words in headlines and the wordmark. Ember (`#ff8058`) owns actions: the download plaque, the dock's Download link, focus rings and selection. On ember glass, text is warm cream `#ffe8a8` with a dark shadow.

Contrast (WCAG ratios, measured 2026-10-02): parchment ink on walnut about 10:1 to 15:1; secondary parchment text on walnut 9.7:1; brass labels on walnut 8.2:1 and about 6:1 over the darkened leather table; ink on parchment 9.7:1, enamel labels 7.1:1, secondary ink 5.7:1; cream on ember glass 8.8:1 on average. Ember glass has bright veins, so its text is bold, shadowed and either large (the download action) or on a darker wash (the dock link).

## Typography

Source Serif 4 Variable (opsz axis) carries display, headings, body, controls and labels; Georgia is the fallback. Headings are sentence case ("Make your next move.") like the app's menu title, with balanced wrapping and a soft cast shadow; accent words are gilded. Small labels are uppercase, tracked 0.12–0.16em, in brass. No text is set below 12px.

The display role describes the desktop hero; phones use `clamp(52px, 14.6vw, 88px)`. Body copy stays within (44ch), FAQ copy (65ch).

## Layout

Unchanged structure: full-width scenes, desktop gutters (4vw) to (8vw), gameplay in two equal columns plus a full-width landscape table, the download desk at (1fr 1.3fr). The destination dock is fixed bottom center.

At (900px) the app-reveal caption moves below the sideways phone. At (650px) content becomes one column with (16–20px) gutters, the hero copy sits above a pair of equal download plaques, and the platform picker becomes a horizontal pair.

## Elevation & Depth

Depth comes from the modeled card hand, a warm ember glow behind it, rising ember sparks in the hero, phone shells with a brass hairline and warm shadow, and broad dark shadows under parchment panels. The hero backdrop is the app's tavern wall (`menu-backdrop-tavern`), the app reveal sits on the board's leather table.

The card scene fans with scroll, rotates its central card and responds to a fine pointer; card faces are tinted slightly toward candlelight. Flip and ambient-motion pause controls remain explicit. Reduced motion fixes the hand pose, removes the sparks and the plaque shine, and lays the app reveal out in normal flow.

## Shapes

Plaques use the app's riveted capsule rim (rounded ends, rivets tiling along the long edges); compact controls use the thin rim. Panels use the riveted brass frame. Phones keep generous curved shells. Rules between rows are brass hairlines, not boxes.

## Components

- **Download action:** ember glass plaque in the riveted brass rim, full width on the parchment card, with a slow shine sweep (motion allowed only). Hover brightens; activation sinks (1px).
- **Secondary plaques:** leather in the rim: hero downloads, header link, Obtainium steps, card tools.
- **Destination dock:** leather in a small brass frame; the Download link is ember glass. Its highlight identifies the action, not the current section.
- **Platform picker:** two large leather plaques; selection uses `aria-pressed`, brass-light text, an ember-lit logo and glow; details update politely.
- **Parchment panels:** the capability ledger and platform details, brass-framed, ink text, enamel labels.
- **App frames and FAQ:** real screenshots inside dark phone shells with captions that say "development preview, not a live match". FAQ rows are native disclosures on leather with brass rules.

Interactive elements use visible offset focus outlines: ember on dark surfaces, enamel inside parchment panels. Preserve the skip link and text alternatives. `forced-colors` drops the gilding and rims for plain system borders.

## Do's and Don'ts

- Do match the app: walnut, leather, parchment, brass, ember; serif type; riveted rims.
- Do keep ember for actions and brass for trim and labels.
- Do preserve labeled app imagery, explicit motion controls and static fallbacks.
- Don't bring back the flat charcoal/coral look or sans display type.
- Don't make important content depend on hover or continuous animation.
- Don't turn development previews into implied live-match evidence.
