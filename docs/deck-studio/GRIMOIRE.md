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
   | Deck, Cards | the head, the title plate and the rail | the cards, with the index tabs on its edge |
   | Deck, Ideas | the head; combos | EDHREC |
   | Deck, Analysis | the head; the deck at a glance | roles |
   | Deck, Playtest | the head; the rules check and a sample hand | game history |
   | Importer | the list goes in | it is reviewed and saved |

   Each page scrolls by itself. Nothing is drawn in the middle of the navigation bar either (the title would
   sit on the fold). At the accessibility text sizes iOS keeps one page, so large type has the full width.
3. **Moving between screens turns the page.** Library to a deck or the importer is a turn forward; Done turns
   back.
4. **A deck's chapters are index tabs** on the binder's edge (ribbon markers until October 6): Cards, Ideas,
   Analysis, Playtest. Tapping a tab turns to it. A
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

## The collector's binder (October 6, 2026)

After trying TestFlight build 30, Caleb liked the cards but found the portrait page thin and the tabs and buttons
still "looked like apple ui". Codex painted three directions (`build_output/grimoire-concepts/`); he chose
**concept B, the collector's binder**, kept the mana filter and the other filters, asked to choose between
looking at the deck's cards and cards to add, asked that anything new be made with Meshy, and then that no top
tabs or headers look like the iPhone's: every piece of text sits on the parchment or in one of our own parts.

- **The binder.** Oxblood leather under the whole screen (`BinderCover`). Each page is parchment held in the
  binder with a stitched seam and brass corner mounts (`BinderPage`). The film still opens the book; inside, the
  pages sit in the binder.
- **Head.** Done is a leather strap with a brass buckle, Save a brass plaque, then the tags plaque and the ⋯
  plaque, on the leather above the page (`BinderHead` on the library and importer). There is no system bar.
- **Chapters are index tabs** (`BinderIndexTabs`): leather tabs with an icon and the chapter's name, standing out
  of the binder's outer edge; the chosen one is red and stands further out. They replace the ribbons and never
  scroll; a chapter change still lands on the chapter's own top with the title plate scrolled away. Each tab is
  the Meshy-made stitched leather tab (`tavern-binder-tab`, image-to-3D from a painted reference, Caleb, October
  6: "make the tabs on the right look more like tabs maybe a 3d effect"), 9-sliced so its rounded corner and
  rivet stay whole and only plain leather stretches to the tab's height. The leather runs 12 points in under the
  page (`BinderIndexTabs.tuck`, `Binder.tabTuck`), and the page sits above the tabs (zIndex), so the page's edge
  and shadow lie over them; the rivet just shows at the page's edge. The chosen tab is the leather's own red
  with a deep shadow; the others are dyed down to oxblood. Only the leather is tucked: each tab's button is the
  part that stands out, so taps and the UI tests' frames start at the page's edge.
- **Title plate** (`binderPlate`): the commander's art in brass, the name (tap to fold), a brass gauge of the
  count against 100, the save state, Play as ember glass in brass with an ember jewel, and the quick check.
- **Rail** (`BinderRail`): *My deck* or *All cards* (`BinderShelfSwitch`), the search well, brass tools (Filter,
  Group, Sort, list or grid, Select, Undo, Redo; on a narrow page Group, Sort, layout and Select fold into
  Filter's menu) and the mana value coins 0 to 7+ (`BinderManaFilter`). The coins and the colour filter apply to
  both shelves; *All cards* also filters by type and keeps to the commander's colours unless turned off.
- **Sleeves** (`BinderSleeve`): every card, the deck's, the catalogue's and the search sheet's, sits in a
  translucent sleeve with brass corner mounts and a strip under it: a brass minus, the count and a brass plus.
  The card's own right and left halves still add and take away. The minus is absent at zero.
- **All cards** (`DeckStudioBinderCatalogue`): the local catalogue through the rail's search, coins, type and
  colour, up to 120 sleeves; the plus adds a copy to the main deck. Online search stays behind Add cards.
- **Sideways**: the left page holds the head, the title plate and the rail; the right page holds the cards with
  Quick Add at its foot; the index tabs stand out of the right page's edge.
- **Sheets are loose leaves with the binder's own head** (`binderLeaf`): the title on the parchment over an inked
  rule, with brass plaques for Cancel, Done, Save or Apply. Toggles are the tavern's brass switch
  (`BinderToggleStyle`), disclosures turn a brass chevron (`BinderDisclosureStyle`), counts use brass coins
  (`BinderStepper`), menu choices are brass plaques naming the choice (`BinderMenuPicker`), and choices that were
  inked chips are the binder's switch (`GrimoireChoice`). Each is drawn and touched as our own part, and
  VoiceOver and the UI tests see the system control it stands for (`accessibilityRepresentation`). A nearly
  invisible system control laid over the face, as `TavernToggle` does, did not take taps inside a form's rows.
  System alerts and context menus remain the system's.
- **Chapter swipes are watched by UIKit.** A SwiftUI drag gesture over the whole screen swallowed the first tap
  after the page had scrolled (an index tab did nothing until tapped again). `grimoireSwipe` now adds a pan
  recognizer to the window that recognizes alongside everything and never delays or cancels a touch.
- **Page turns move only the paper.** Each `BinderPage` reports its frame for its screen; `GrimoireStage`
  cuts its pictures to the newest screen's pages, so the leather, head and tabs stay still while a page swings.
- **Meshy parts.** The buckle and Play's jewel are Meshy text-to-3D models
  (`~/Movies/motion-assets/magicmobile-brand/meshy/binder/`), rendered straight on in Blender by
  `scripts/brand/binder_parts.py` and installed as `tavern-binder-*` images by `scripts/brand/install_binder_parts.sh`
  (Android copies them as `tavern_binder_*`). The code draws stand-ins if an image is missing.
- **Corners are real L-shaped pieces** (Caleb, October 6: "we want an L shape corner", "a real nice corner
  piece"). Meshy would not make a flat corner guard from words (it made a shelf bracket, a hook and a frame), so
  each corner was painted as a reference (`meshy/binder/l-ref/`) and built by Meshy's image-to-3D: an ornate L
  with filigree, domed rivets and scroll finials for pages and plates (`tavern-binder-corner`), and a slimmer L
  with an engraved line and small scrolls for cards and the commander's art (`tavern-binder-card-corner`). Each
  render leaves no margin, so the crisp outer corner sits flush on the corner it guards; the code mirrors one image
  for all four corners.
- **No system-styled marks either** (Caleb, October 6, of the salmon Playing capsule: "no iphone looking ui
  anywhere and we have are style everywhere"). Tags are `BinderTag`: the deck chosen for play is ember glass in
  a thin brass rim with Play's jewel, and a deck check is leather with a coloured jewel. They are sized exactly
  like the bracket's `TavernTag` (22 points tall, 10-point serif) so the two tags on a deck match; Caleb asked
  that Playing be no bigger than the bracket. The library's Now playing
  row is a band of the binder's leather with the jewel and a brass coin; the Now playing notice is a leather slip
  in brass. A deck's favourite star and ⋯ are brass coins (`BinderCoin`, the star lit with ember once chosen).
  The quick check uses the brass gauge and leather chips (`BinderChip`, ember when chosen), ruled off the title
  plate. Notices are notes on the page with a brass-stamped symbol (`BinderNote`), empty shelves are empty pages
  in the book's hand (`BinderEmptyLeaf`, in place of the system's empty-state view), and the artwork invitation
  is a plate with a brass Turn on plaque.

## Where it lives

| Piece | iOS | Android |
| --- | --- | --- |
| Film and page turns | `MagicMobile/Grimoire/GrimoireStage.swift` | `studio/GrimoireStage.kt` |
| Paper, gutter, headings, swipe | `MagicMobile/Grimoire/GrimoireChrome.swift` | `studio/GrimoireChrome.kt` |
| The binder: cover, pages, tabs, rail, sleeves, plaques | `MagicMobile/Grimoire/GrimoireBinder.swift` | `studio/GrimoireBinder.kt` |
| Leaf heads, switches, disclosures, steppers, menu plaques | `MagicMobile/Grimoire/GrimoireBinderControls.swift` | `studio/StudioTheme.kt`, `StudioSheetBar` |
| Tags, coins, chips, notes, empty pages | `MagicMobile/Grimoire/GrimoireBinderControls.swift` | end of `studio/GrimoireBinder.kt` |
| All cards shelf | `DeckStudio/Builder/DeckStudioBinderCatalogue.swift` | `binderCatalogue` in `studio/DeckStudioWorkspace.kt` |
| Meshy parts (buckle, jewel, corners, index tab) | `scripts/brand/binder_parts.py`, `install_binder_parts.sh` | same images |
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
- **Card grid.** `BinderSleeve` draws the art in its sleeve and the strip under it; the strip's minus and plus
  ("Remove one X", "Add one X") are what VoiceOver, TalkBack and the UI tests press, and the card's halves are
  plain buttons hidden from accessibility. (Halves made with tap gestures did not respond inside the search
  sheet's list; buttons do.) `deckStudio.cards.layout.v1` defaults to `Grid`; the UI tests that check the list's own
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

- `GrimoireUITests` runs with motion on (`MAGICMOBILE_UI_TEST_GRIMOIRE_MOTION=1`): the book opens, an index tab and
  swipes turn chapters, Done closes it; and in landscape it checks that the library's heading and the deck's
  rail stays on the left page, the cards are the right page and the index tabs stand out of its edge. Every other UI test runs with the film and
  turns off, so their timings are unchanged.
- `GrimoireUITests` also adds a card and checks that the right half of its tile adds a copy, the left half
  takes one away, and the last copy removes it.
- Index tabs keep the old tab buttons' labels and selected state, so existing Deck Studio tests drive them as before.
- With the system bars gone, tests press the binder's identifiers: `deckStudio.close`, `deckStudio.save`,
  `deckStudio.more`, `deckStudio.library.close`, `deckStudio.import.cancel`, `deckStudio.rename.done`,
  `deckStudio.basics.apply`, `deckStudio.cards.filter`; sheet titles are static texts.

## Not verified

Seen on the iPhone 17 Pro Max simulator and the API 35 emulator only. Film smoothness, the hand-off time on a
real phone and how the turns feel under a finger are still to be judged on a device.
