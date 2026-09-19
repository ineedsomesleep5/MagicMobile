---
name: MagicMobile download site
description: Heavy typography, tactile cards, and a cinematic path into the native app.
colors:
  canvas: "#141518"
  ink: "#f3f1ec"
  ember: "#ff8058"
  silver: "#e9e8e2"
  silver-ink: "#191a1d"
  rust: "#a74429"
  gameplay: "#25262a"
  download-ink: "#221713"
  download-label: "#fff3e9"
  dock: "#27282cf5"
  dock-border: "#45464a"
typography:
  display:
    fontFamily: "Archivo Variable, sans-serif"
    fontSize: "clamp(84px, 12.8vw, 205px)"
    fontWeight: 850
    lineHeight: 0.86
    letterSpacing: "-0.075em"
  headline:
    fontFamily: "Archivo Variable, sans-serif"
    fontSize: "clamp(42px, 5.7vw, 86px)"
    fontWeight: 850
    lineHeight: 1
    letterSpacing: "-0.06em"
  body:
    fontFamily: "Manrope Variable, sans-serif"
    fontSize: "15px"
    lineHeight: 1.6
  action:
    fontFamily: "Manrope Variable, sans-serif"
    fontSize: "17px"
    fontWeight: 700
  navigation:
    fontFamily: "Manrope Variable, sans-serif"
    fontSize: "12px"
    fontWeight: 650
rounded:
  control: "4px"
  dock: "6px"
  card: "10px"
  phone: "39px"
  tool: "100px"
spacing:
  compact: "12px"
  control: "16px"
  section-copy: "24px"
  copy-break: "30px"
components:
  download-action:
    backgroundColor: "{colors.download-ink}"
    textColor: "{colors.download-label}"
    typography: "{typography.action}"
    rounded: "{rounded.control}"
    padding: "20px 24px"
  destination-dock:
    backgroundColor: "{colors.dock}"
    textColor: "{colors.ink}"
    rounded: "{rounded.dock}"
    padding: "6px"
  hero-download:
    backgroundColor: "#25262b"
    textColor: "{colors.ink}"
    rounded: "{rounded.control}"
    padding: "12px 16px"
  hand-tool:
    backgroundColor: "#171614da"
    textColor: "#fff8ef"
    rounded: "{rounded.tool}"
    padding: "0 13px"
  platform-choice:
    backgroundColor: "transparent"
    textColor: "#532a1d"
    padding: "22px 12px"
---

# Design System: MagicMobile download site

## Overview

**Creative North Star: "The opening hand"**

Heavy, tightly set headlines and physical card imagery give MagicMobile a direct, energetic presence. Charcoal grounds the scene; silver reveals the app; ember supplies emphasis and the download surface. Motion makes the cards feel handled, while controls remain compact and legible.

This records the current site implementation, not user acceptance or production deployment. The restrained forest-and-serif direction was explicitly rejected. Page choreography belongs in [SURFACE.md](SURFACE.md); these rules apply to this website, not the native app.

**Key Characteristics:**

- Oversized Archivo headlines paired with precise Manrope controls.
- Genuine card textures and labeled app imagery.
- Scroll-driven depth with a static fallback and reduced-motion treatment.

## Colors

Primary ember is both a headline accent and a full-background action color. On ember, use the dark download ink and inverse warm action label. On silver, rust supplies the darker headline accent.

Neutral charcoal and gameplay surfaces support warm white text. Silver and its dark ink make app imagery a distinct visual event. The dock has its own translucent dark surface and visible border. Frontmatter values are normative; contextual secondary text and borders remain defined in the source stylesheet.

## Typography

Archivo Variable supplies the dense, heavy display voice; Manrope Variable supplies body copy, navigation, and controls. Both fall back to sans-serif. Headings use balanced wrapping and slightly expanded word spacing; paragraphs use a comfortable reading line height.

The display role describes the desktop hero; mobile uses `clamp(53px, 14vw, 85px)` with a (0.91) line height. Supporting headlines vary by scene. Body copy typically stays within (44ch), shortening to (35ch) on mobile; FAQ copy allows (65ch). Labels remain small and sentence case except the card-tool caption.

## Layout

Full-width tonal scenes alternate with spacious content. Desktop gutters range from (4vw) to (8vw); gameplay uses two equal columns, and the download desk uses (1fr 1.3fr). The invitation alone has an (1100px) maximum content width. The destination dock is fixed at the bottom center.

At (900px), intermediate spacing and headline adjustments apply. At (650px), content becomes one column with mostly (24px) gutters, the platform picker becomes a horizontal pair, and the hero retains its headline above the card hand. Card tools adapt separately at (700px). Mobile shortens the pinned scenes and uses smaller phone frames rather than removing the visual narrative.

## Elevation & Depth

Depth comes from modeled cards, perspective, overlapping images, rotations, and broad shadows beneath physical objects. Content sections and the platform desk are flat. The dock has a modest floating shadow. Exact shadow and motion values live in the extension sidecar.

The card scene fans with scroll, rotates its central card, and responds to a fine pointer. Flip and ambient-motion pause controls remain explicit. Reduced motion fixes the hand pose and removes continuous ambient movement; a textured image hand covers loading or unavailable WebGL.

## Shapes

Small rectangular control corners contrast with rounded card silhouettes and generously curved phone frames. Round pill forms are reserved for card tools. Dividing rules structure the capability ledger, platform picker, and FAQ; they do not become boxes around every paragraph.

## Components

- **Download action:** broad dark link with warm text, trailing arrow, and small corners. Fine-pointer hover darkens to a brown surface; activation shifts down (1px).
- **Hero downloads:** compact bordered dark links; mobile preserves (44px) minimum height while simplifying icons.
- **Destination dock:** three compact links with ember highlighting the download destination. Its highlight identifies the action, not the current scroll section.
- **Card tools:** compact pills with (44px) minimum dimensions, explicit flip and ambient pause actions, and a warm hover border.
- **Platform picker:** ruled text rows on desktop, paired choices on mobile. Selection uses `aria-pressed`, darker text, and a translucent white fill; the adjacent details update politely for assistive technology.
- **App frames and FAQ:** real imagery sits inside curved phone shells with platform captions. Native disclosure rows expose installation detail without adding another visual surface.

Interactive elements use visible offset focus outlines. Ember outlines become dark on the ember download surface; card tools use their own warm outline. Preserve the skip link and text alternatives when extending the scene.

## Do's and Don'ts

- Do pair heavy Archivo headlines with Manrope reading and control text.
- Do preserve labeled app imagery, explicit motion controls, and static fallbacks.
- Do use broad shadows for physical cards and phone frames.
- Don't restore the rejected forest-and-serif visual direction.
- Don't make important content depend on hover or continuous animation.
- Don't turn development previews into implied live-match evidence.
