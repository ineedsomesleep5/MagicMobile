# Deck Studio as a spell book ("grimoire")

Caleb asked on October 5, 2026 for Decks to open like a spell book: a 3D book opens, and every Deck Studio
screen is a parchment page you turn and swipe through. This is how it is built, on both platforms.

The code calls it the **grimoire**, because `Spellbook…` already names the Commander Spellbook combo service
(`SPELLBOOK_INTEGRATION.md`). Players only ever see a spell book.

## What the player sees

1. **Decks** on the menu (or any "edit decks" button) plays a 1.4 s film: the grimoire on the tavern table
   unclasps, the cover swings open, leaves turn in a drift of light, and the camera comes straight down onto a
   blank page. The film fades into the live page. **Done** on the library plays it backwards.
2. **Every screen is a page**: grained parchment, the shadow of the gutter by the spine, the cut edges of the
   leaves at the fore-edge, serif type. Upright, the spine is the left edge.
   **Sideways the book lies open as a spread of two pages, and each page has its own content. Nothing runs
   across the fold** (Caleb, October 5: "each page should have its own list"):

   | Screen | Left page | Right page |
   | --- | --- | --- |
   | Library | Now playing, the heading, Create and Import, search and filters | the decks |
   | Deck, Cards | ribbons; the card search while editing (iOS, with room), else the title page | the deck's cards |
   | Deck, Ideas | ribbons; combos | EDHREC |
   | Deck, Analysis | ribbons; the deck at a glance | roles |
   | Deck, Playtest | ribbons; the rules check and a sample hand | game history |
   | Importer | the list goes in | it is reviewed and saved |

   Each page scrolls by itself. Nothing is drawn in the middle of the navigation bar either (the title would
   sit on the fold). At the accessibility text sizes iOS keeps one page, so large type has the full width.
3. **Moving between screens turns the page.** Library to a deck or the importer is a turn forward; Done turns
   back.
4. **A deck's chapters are ribbon markers**: Cards, Ideas, Analysis, Playtest. Tapping a ribbon turns to it. A
   sideways swipe anywhere on the page turns to the next or previous chapter; swiping back past Cards returns
   to the library (asking about unsaved changes first, like Done).
5. **Cards are their full art.** A deck's cards (and the card search's results) are a grid of whole card
   images that scrolls down the page. While a deck is being edited, **tapping the right half of a card adds a
   copy and tapping the left half takes one away** (Caleb, October 5); taking the last copy away removes the
   card, and Undo brings it back. Small minus and plus discs in the card's bottom corners say so, and the
   count sits in its top corner. A long press shows the card large, with every other action. A read-only
   deck's cards open on a tap. The list is still there: the layout button in the Cards toolbar switches.
6. **The page's own hand.** Choices that the system would draw as a grey segmented control (Combos or EDHREC,
   Paste, Link or Scan, local or online search) are inked chips, the chosen one filled, like the library's
   filters. Sections of the deck's cards are run-in headings in small capitals over an inked rule. Until the
   first tap changes a card's count, an italic line says what a tap does.
7. **Sheets are loose leaves** of the same paper, with no spine. (On Android, Deck Studio's sheets had been
   drawn on dark leather with dark ink since the tavern-sheet change and were unreadable; `BoardSheet(paper =
   true)` gives them the book's paper.)

Reduce Motion (iOS) or animations switched off (Android) skips the film and the turns: the change just happens.

## Where it lives

| Piece | iOS | Android |
| --- | --- | --- |
| Film and page turns | `MagicMobile/Grimoire/GrimoireStage.swift` | `studio/GrimoireStage.kt` |
| Paper, gutter, ribbons, headings, swipe | `MagicMobile/Grimoire/GrimoireChrome.swift` | `studio/GrimoireChrome.kt` |
| The film clips | `Resources/Grimoire/grimoire-{open,close}-{portrait,landscape}.mp4` | copied to `res/raw` by `prepareBrandAssets` |
| The 3D book | `scripts/brand/grimoire.py` (Blender), `scripts/brand/install_grimoire.sh` (encode) | same clips |

- **Film.** iOS plays it in a window above the whole app (`AVPlayerLayer`), so it covers the menu and the
  full-screen cover alike. Deck Studio is presented underneath, without its own animation, as soon as the film
  covers the screen; building its first page is hidden behind the film. Android plays it in a `TextureView`
  over the root (`GrimoireFilmLayer`).
- **Page turns.** iOS pictures the key window (`snapshotView`) and swings that picture about the spine while
  the real screen changes underneath. Android records Deck Studio into a `GraphicsLayer` (`GrimoirePages`) and
  swings the bitmap. On a spread the far half of the old spread lifts and the near half of the new one lands.
- **Paper.** One opaque tile per tone (the page and the lighter "plate" used by panels) with the tavern's
  parchment grain baked in. iOS bakes it once (`GrimoirePaperTile`); blending the grain live would cost an
  offscreen pass per surface on every scrolled frame. Nothing is drawn over the middle of a page, so card art
  keeps its colours. The tile is drawn as a `Rectangle().fill(ImagePaint(...))` made once per tone.
- **Section headings.** `GrimoireSubheading` is the plain row (title, spacer, count) with its ink rule drawn
  as an overlay underneath. An earlier version laid the rule out as a flexible element between title and
  count; inside the deck page's lazy list, with the card search sheet's keyboard up, that kept the list
  re-measuring and the app never went idle (`DeckStudioReleaseUITests/testNewDraftSearchAddInspectRotateAndDiscard`
  hung; found by bisecting with that test). Keep flexible decoration out of lazy-list section headers.
- **Spread.** `Grimoire.isSpread` decides it (wider than tall). `GrimoireSpread` (iOS) lays out the two pages
  with `foldInset` kept clear either side of the fold; each screen has a `spread` branch that puts its own
  parts on the two pages (`spreadWorkspace`, `libraryIntro`/`libraryShelf`, `entry`/`reviewed`). Android does
  the same with a `Row` of two columns in each screen.
- **Swipes.** The swipe is only watched, never taken. One that starts on something that scrolls sideways (a
  row of cards, the mana curve) or on a slider or text field belongs to that control and turns nothing.
- **Card grid.** `DeckStudioCardGridTile` draws the art, the count and the corner hints; the screen lays two
  invisible buttons over its halves ("Remove one X", "Add one X"), which is also what VoiceOver, TalkBack and
  the UI tests press. `deckStudio.cards.layout.v1` defaults to `Grid`; the UI tests that check the list's own
  layout pin `List` with a launch argument. In the iOS search list each list row is one row of cards (a lazy
  grid inside a single self-sizing list row sends UIKit into a layout loop).
- **Type.** iOS sets `.fontDesign(.serif)` on the page and draws navigation titles itself (`grimoireTitle`).
  Android's Deck Studio files use the package's own `sf`, which defaults to the serif family.

## Remaking the film

```
blender -b -P scripts/brand/grimoire.py -- --out-dir build_output/tavern/grimoire
zsh scripts/brand/install_grimoire.sh
```

About 34 s a frame on the 8 GB Mac (45 minutes for both orientations). `--preview` renders half-size drafts in
about 7 minutes; `--frames 0,20,39` renders single frames.

The last frames settle on `PAGE_LINEAR`, the live page's colour, so the hand-off shows no jump. It was tuned
by comparing a simulator screenshot of the film's last frame with one of the live page. If the page's tone or
grain changes, measure again and adjust `PAGE_LINEAR`.

## Tests

- `GrimoireUITests` runs with motion on (`MAGICMOBILE_UI_TEST_GRIMOIRE_MOTION=1`): the book opens, a ribbon and
  swipes turn chapters, Done closes it; and in landscape it checks that the library's heading and the deck's
  ribbons stay on the left page and the decks and cards are the right page. Every other UI test runs with the film and
  turns off, so their timings are unchanged.
- `GrimoireUITests` also adds a card and checks that the right half of its tile adds a copy, the left half
  takes one away, and the last copy removes it.
- Ribbons keep the old tab buttons' labels and selected state, so existing Deck Studio tests drive them as before.

## Not verified

Seen on the iPhone 17 Pro Max simulator and the API 35 emulator only. Film smoothness, the hand-off time on a
real phone and how the turns feel under a finger are still to be judged on a device.
