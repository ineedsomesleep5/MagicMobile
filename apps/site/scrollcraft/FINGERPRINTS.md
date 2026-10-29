# Fingerprints

Every site you build with **scroll-craft** gets one row here, appended after it
ships. The registry exists so your next build can prove it is a different page
rather than a re-skin of one you already made.

This file is **yours**. It starts empty on purpose: the gate is about not
repeating *yourself*, so it has nothing to say until you have built something.

The rules and the gate live in the skill's
`references/uniqueness.md`. Short version:

**A new build must differ from EVERY row below on at least 4 of the 6
dimensions.** Four against each row individually, not four on average across the
table. If a planned build fails, change the plan. Never edit a row to make room
for it.

The six dimensions are: **grammar**, **nav treatment**, **hero device**,
**act-sequence shape**, **close pattern**, **signature move**.

Dimension 6 is free, because a signature move is unique by definition. So the
gate really asks for three more out of the remaining five, and a build that
changes only grammar and world will fail it.

---

## The registry

| Build | Grammar | Nav treatment | Hero device | Act-sequence shape | Close pattern | Signature move | World | Port |
|---|---|---|---|---|---|---|---|---|
| The opening hand (2026-09/10, superseded) | custom: opening hand | floating destination dock | layered 3D card hand over a two-line headline | dimensional open, quiet bridge, pinned peak, flow proof, flow close | platform desk with a picker | cards gather into the app | Walnut & Ember tavern | Vite + React + Three.js |
| Hall and Cut (2026-10-24) | cutlist into gallery | loud full-width bar with the three screens; medallion index in the hall | one hard cut: a commander and one word | three short cuts, one long sideways pin, one held peak, full-bleed close, flow | the three screens on art, then rows | the bar's real D20 rolls for first | Arena | Vite + React + Three.js |

---

## What is taken

Add a bullet here whenever a build claims something a later build should avoid
reusing: a grammar, a nav treatment, a close pattern, a signature move, an
act-count-and-length band. The shared columns are what the next build inherits
as a constraint, so writing them down is the whole point.

- Opening-hand grammar, the floating destination dock, the cards-into-the-app signature (The opening hand).
- The nav-bar die that leaves the bar for the peak, and the commander gallery walk with a colour-identity regrade
  (Hall and Cut).

---

## Appending a row

After shipping, add one line to the table and one bullet to **What is taken** if
the build claimed something new. Fill every column. Say what the build shares
with existing rows.

Rows are append-only. A build that has been superseded stays in the table,
because the space it occupies is still occupied.

---

## Worked example

The skill's author kept a registry of twelve builds across eight page grammars.
If you want to see what a filled-in table looks like, and which shapes tend to
collide, read `EXAMPLES.md` in the scroll-craft repository. Treat it as
illustration only: those rows are somebody else's builds and they do **not**
constrain yours.
