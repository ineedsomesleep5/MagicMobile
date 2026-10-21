# Arena style

The Arena board mode (`BoardMode.arena`) plays like the reference game, MTG Arena, on our Walnut Tavern table. Caleb's
rule (2026-10-20): **every screen in Arena mode looks like Arena. Nothing in it may be iOS system UI or Hearth-board
leather.** Read this before you build or change anything the Arena board shows. The Hearth board follows
`docs/TAVERN_STYLE.md`; Arena keeps the tavern's table, plaques and coins, and dresses everything else the Arena way.

Reference footage and frames: `~/Movies/motion-assets/yt/arena-browsers` (gameplay videos, frame sheets and crops)
and `build_output/arena-amounts-reference.jpg`. When Arena has a screen for something, copy its layout. When we found
no footage, design it in the same language (below) and say so in the PR.

## Principles

1. **The table is the interface.** A choice is made on or over the table, never in a sheet, alert, popover or form.
   Short questions sit over the dimmed board; answers about cards on the table are given by tapping those cards.
2. **Cards are the content.** Show the card: the spell being cast, the ability (as an ability card), the permanents
   being chosen, the cards in a pile. Text lists are a last resort.
3. **One decision on screen.** A browser takes the whole table and hides the corner buttons, the board caption and
   the stack card, so nothing competes with it. "View Battlefield" steps it aside.
4. **Say what to do in one line.** A serif title names the effect ("Scry", "Assign damage", "Choose a pile"), and one
   line of instructions sits under it. XMage's message is the fallback, cleaned of ids and counters.
5. **The source stands beside the choice.** The spell or ability asking (the stack top, or the card the prompt names)
   stands on the right in landscape.
6. **Answers are plaques.** The main answer is an ember (orange) plaque, others are leather. Done is enabled only when
   the choice is legal.
7. **Nothing in a sheet, nothing via `dismiss`.** Panels that must exist (game log, settings, phase stops) open on the
   table in glass (`boardSheet` / `ArenaPanelOverlay`) and close with `boardPanelClose`.
8. **Same answers as Hearth.** An Arena screen sends exactly the commands the Hearth panel sends, so the engine never
   changes for a look.

## Materials and colour

- **Glass:** dark smoked glass in a gold hairline (`ArenaGlass.top/bottom/hairline/text`, `ArenaGlassPanel`,
  `ArenaGlassRow`, `ArenaGlassBackground`). Light text (`ArenaGlass.text`), gold labels
  (`Color(red: 0.98, green: 0.84, blue: 0.52)`).
- **Plaques:** `ArenaPlaqueButtonStyle` (ember primary, leather secondary, quiet waiting). Pills: `ArenaPillStyle`.
- **Dim:** browsers dim the table to about 0.7 black; questions 0.72; panels 0.55.
- **Coins:** `TavernCoin` numbers order (1 resolves first, stack positions, picks).
- **Highlights:** chosen cards rise about 10 pt in a gold glow (`Color(red: 1, green: 0.82, blue: 0.4)`); the next to
  resolve is lit gold. Cards you can't choose dim to about 0.42.
- **The glow border** (`ArenaOutlineGlow`, Caleb's pick from the web board, memory `frame-outline-glow`): light that
  follows the card's own outline, never a box or a coloured line. With Card Frames on it traces the tavern frame, crest
  and corners included; with them off it traces the reference's card or a token's arch; in the hand it traces the
  printed card. Colours: playable cyan `#7ff0ff` (it breathes in the hand; lands you could tap glow softer), target
  `#c6f8ff`, selected `#ffe08f`, attacking `#ff5a2e`, blocking `#ffd38a`, and orange while a payment is open. No badges
  or arrows on playable cards.
- **Tapped:** the tile tilts 12° and greys by a multiply (grayscale 0.75, brightness 0.62, the prototype's), under a
  translucent tap arrow, so dark art still reads.
- **Never:** system blue tint, `.sheet` or `.popover` chrome, `confirmationDialog`, `Form`/`List` look, parchment or
  leather panels, SF symbol rows as the main content.

## Type

- Titles: system serif, bold, 22–26 pt, light text with a black shadow.
- Instructions: serif medium, 13–14 pt, 0.8 opacity, at most two lines.
- Labels on glass: serif heavy 10–13 pt capitals with tracking (zone names, "RESOLVES NEXT").
- Card text stays the card's own (CardTile / ArenaAbilityCard).

## Components

| Need | Component | Where |
|---|---|---|
| Choose an ability, order triggers | `ArenaAbilityBrowser` | `Board/ArenaBoardViews.swift` |
| See the whole stack | `ArenaStackBrowser` | same |
| Scry, surveil, search, top-N picks, separate piles | `BoardCardChoiceView.arenaStage` | `BoardCardChoiceView.swift` |
| Modes of a modal spell | `ArenaModeBrowser` | `Board/ArenaBoardViews.swift` |
| Yes/no, "you may", two or three answers | `ArenaQuestionStage` + `CompactPromptPopup(stage:)` | same, `Board/CompactPromptPopup.swift` |
| A list of named choices (replacement effects, creature types, colours) | `ArenaChoiceBrowser` | `Board/ArenaBoardViews.swift` |
| Choose a player (who starts, target player lists) | `ArenaPlayerChoice` | same |
| X and other numbers | `ArenaAmountPill` (corner) | same |
| Damage, counters or mana split | `ArenaSplitBrowser` | same |
| Choose a pile | `ArenaPileBrowser` | same |
| Read a card | `CardInspector` (its Arena look, `arenaBody`) | `Board/CardInspector.swift` |
| Panels (log, settings, phase stops) | `boardSheet` / `ArenaPanelOverlay` | same |
| A zone (graveyard, exile, command, revealed) | `ArenaZoneBrowser`: cards, an ember plaque under each one you can use, Done | `Board/ArenaBoardViews.swift` |
| A player's life, counters and zones | `ArenaPlayerCard`, opened from their medallion | same |
| Library, graveyard and exile piles | `ArenaPileStack`: leaning, thickness by count, the count always shown, the top card face up without badges | same |
| What a spell or ability targets | `ArenaStackArc` and `ArenaTargetReticle` from the stack card | same |
| Running loop | `ComboLoopOverlay.runningBar` | `ComboLoopViews.swift` |

Every browser sits in `ArenaBrowserFrame` with its answers in `ArenaAnswerRow`. Abilities are drawn as `ArenaAbilityCard`: the source's art crop on top, its name, a type line ("Ability", "Mode 2"),
the text below, and a loyalty badge for planeswalker abilities.

## Browser anatomy (all full-table screens)

1. Dim the table; hide the corner buttons, caption and stack card (`browserOpen` in `NativeGameView+Arena.swift`).
2. Title and one line of instructions at the top (portrait: below "View Battlefield").
3. The cards in the middle: one row in landscape (scrolls sideways), a grid of two or three columns in portrait.
4. Zones when cards go to places (Bottom | Top, Graveyard | Library, Pile 1 | Pile 2): wells in a gold hairline with
   gold capital labels; a tap moves a card across.
5. The source card on the right (landscape).
6. Answers at the bottom: plaques, the primary one ember; counts on the primary ("2 OF 3").
7. "View Battlefield" top right.
8. Hold any card to read it (`CardInspector`'s Arena look: the card large, glass notes beside it for its live state,
   keyword meanings from `ArenaKeywordGlossary`, rules when the picture can't show them, and attachments).
9. Accessibility: the browser is modal, each card one element with its name, state and a tap action.

## The corner and the hand

- Controls live in one corner: phase strip, primary and secondary plaques, the pass-ahead pill. A number choice (X)
  replaces them with the amount pill: [−5] [−] [Pay X = n] [+] [+5], Cancel under it, as in the reference.
- The hand rests tucked. A tap or a slide pops one card whole; a slide moves one card at a time, each card owning the
  strip of it that shows at the finger's height (`ArenaHandFan.scrubCard`). Carry a card up to play it, starting on
  the popped card itself if you like; hold to read.
- A carried card plays anywhere on the table above the hand except the controls corner, once carried up 24 pt or
  80 pt in any direction (`ArenaLayout.drops`), so a short slide puts it back. Over the table, the table's edge lights
  warm; nothing draws a box.

## The stack card

The top of the stack stands on the right, under the opponent's piles and above the corner. A tab on its left edge
opens the whole stack and shows how many objects it holds. An arc runs from the card to each target, a spell's as well
as an ability's, with a reticle on each target while it waits (cyan for yours, red for the opponent's). A spell lands
with a settle, a bloom of its colour behind the card, a shine and a few motes; there are no light rays. The printed card
shows its own power and toughness, so no badges go over it. An opponent's spell is revealed larger toward the middle
without covering their piles.

## Timing (the reference's pace)

Measured from Arena gameplay video at 30 fps (`~/Movies/motion-assets/yt/_-awmu2U83w/GAP_ANALYSIS.md` §2) and kept in
`BoardFXScheduler.arenaDuration` (`BoardFXPace.arena`). The Hearth board keeps its slower, centre-stage timings.

| Moment | Arena |
|---|---|
| Your spell onto the stack card | 0.35 s, then it stays readable there; its landing light 0.55 s |
| An opponent's spell | revealed larger toward the middle for ~1.3 s, settles in 0.3 s (1.6 s; smart pass waits for it) |
| Ability or trigger to the stack | 0.5 s, with the arc to its target |
| A card arriving (from the stack or hand) | 0.6 s |
| A card leaving | 0.8 s |
| Strikes | 0.45 s each, one after another, 0.38 s apart |
| Attack / block marks | 0.25 / 0.3 s |
| Turn banner | 0.9 s, during the draw |
| Draw | 0.5 s out of the deck, 0.4 s on show, 0.2 s into the hand |
| Hand up / down | 0.22 s / 0.18 s |

Effects never change what XMage is asked or when; they only set how long smart pass waits before passing for you
(`BoardPresentationHold`, at most 4–5 s).

## Gating a new Arena screen

A screen that takes over a prompt must use the same gate as the pop-up or panel it replaces:
`CompactPromptPopup.shouldShow`, not a payment (`InlinePaymentPromptState`, `isManaPaymentPrompt`), not the opening
hand or starting roll, and not another browser's prompt. Add it to `browserOpen`, and filter
`boardDetailChoiceKey` so the glass detail panel doesn't open over it. Hearth keeps its own screens.

## Checklist for an Arena screen

- No `.sheet`, `.popover`, `.alert`, `confirmationDialog`, `Form` or `List`; no system blue.
- Title, one instruction line, cards, plaques, View Battlefield, the source on the right.
- Same command as the Hearth panel; Hearth unchanged.
- Gate as above; corner, caption and stack hidden while open.
- A design fixture (`GameBoardPreviewFixtures`) and a line in an Arena UI test.
- Portrait and landscape screenshots checked.
