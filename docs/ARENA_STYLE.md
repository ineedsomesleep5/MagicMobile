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
- **Buttons (Caleb chose option A, 2026-10-22):** one face for every Arena button, `ArenaButtonFace` in
  `Menus/ArenaMenuKit.swift`. The call to action is an orange pill (`ArenaMenuStyle.orange`, `#ffb24a` → `#f47a1c` →
  `#c9420d`) with a thin warm rim (`orangeRim`), a lit top edge and a soft glow. The other choice is a dark glass pill
  edged in a pale line; danger is a deep red pill; `cool` is Arena's blue pill (Mulligan beside Keep). No brass,
  rivets, leather or stitching. Styles on top of it: `ArenaButtonStyle` (menus; same options as `TavernButtonStyle`),
  `ArenaPlayButtonStyle` (Play, with a slow shine), `ArenaPlaqueButtonStyle` and `ArenaPillStyle` (the board's corner),
  `ArenaPillButtonStyle` and `BinderPlaque` (chips). `TavernButtonStyle` draws the Arena face wherever
  `\.arenaBoard` is true (the menus, and views both boards share on the Arena board), so the Hearth board keeps its
  plaques and nothing else shows them.
- **Dim:** browsers dim the table to about 0.7 black; questions 0.72; panels 0.55.
- **Counts:** `ArenaCountBadge`, a white number on a dark oval in a thin gold line (piles, the stack's size, the order
  of cards). `TavernCoin` is the Hearth board's.
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

Arena's mix (Caleb, 2026-10-22): the serif display face for titles, names on plates, buttons and big numbers; a clean
sans for labels, rows, captions and body.

- `ArenaMenuStyle.font(size, weight)`: from 17 pt up it is the serif title face; below, the system sans.
  `ArenaMenuStyle.title(size, weight)` sets a smaller serif heading on purpose. Use these, not
  `.system(..., design: .serif)`, in anything Arena draws. Deck Studio no longer sets `.fontDesign(.serif)`.
- Titles: serif bold, 22–34 pt, light text with a black shadow.
- Instructions: rare (cut helper text, see Copy below); sans medium 13–14 pt, 0.75 opacity, one line.
- Labels on glass: sans heavy 10–13 pt capitals with tracking (zone names, "RESOLVES NEXT").
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
| A menu (the gear's, the skip choices) | `ArenaMenuCard`: glass rows with an icon, a title and a line under it, drawn on the table (never a pop-over) | same |
| The game log | `GameLogDrawer`'s Arena look: a gold serif title, turn dividers, an icon per event, smart pass's lines dimmed, gold card links | `Board/GameLogAndStyles.swift` |
| Buttons in panels (Concede, Start New, Quit…) | `CompactActionButtonStyle`'s Arena look: glass rows, oxblood glass for a destructive one | same |
| Running loop | `ComboLoopOverlay.runningBar` | `ComboLoopViews.swift` |

Every browser sits in `ArenaBrowserFrame` with its answers in `ArenaAnswerRow`. Abilities are drawn as `ArenaAbilityCard`: the source's art crop on top, its name, a type line ("Ability", "Mode 2"),
the text below, and a loyalty badge for planeswalker abilities.

## Game screens (references in `build_output/arena-game-reference/`)

- **Starting roll** (`MultiplayerD20View` with `\.arenaBoard`): the dice roll on the board itself. `D20TableView`'s
  `onBoard` hides the tavern table and renders on a clear background, `StartingRollCover` dims the board to 0.4 instead
  of covering it, and there is one large serif line ("Your roll", "You go first") with Skip at its end, glass seat
  plates and the orange Roll pill. Arena itself has no roll; it names the first player on the mulligan screen, which
  ours does too.
- **Opening hand** (`OpeningHandOverlay`, references `mulligan-*.jpg`): "You Go First" / "<name> Goes First"
  (`GameSnapshot.startingPlayerHeading`) over a thin rule, XMage's question under it, the hand fanned across the board
  inside the screen, the blue Mulligan pill beside the orange Keep, words only.
- **Result** (`ArenaGameResultView`, references `victory-*.jpg`, `draw-result-japanese.jpg`): the board dims and one
  word lands on a flare behind the MagicMobile mark (orange Victory, cold steel Defeat, violet Draw); after a moment or
  a tap the word rises over your medallion, your rank, three numbers and Main Menu / New Game. View Battlefield lifts
  it. Never Arena's Planeswalker sigil (Wizards' mark).
- **Zone browsers:** as many columns as cards (up to three), centred both ways; scroll only when they don't fit. A
  plaque under a card is exactly the card's width.

## Browser anatomy (all full-table screens)

0. **Safe area (Caleb, 2026-10-22):** a full-table layer's dim ignores the safe area, but its content never does.
   - Titles start at `ArenaSafeArea.top(minimum)`: below the camera cutout upright, and below the opponent's medallion
     and plaque in landscape (minimum 50).
   - In landscape the content keeps `ArenaSafeArea.side` on both sides, so cards never slide under the cutout.
   - View Battlefield and Skip sit left of the gear in landscape (trailing 120), padded before they are placed.
   - Use the helper, not fixed numbers.
1. Dim the table to about 0.8 (0.86 under the result); hide the corner buttons, caption and stack card (`browserOpen` in
   `NativeGameView+Arena.swift`).
2. Title at the top (portrait: below "View Battlefield"); a line under it only for what the table can't show ("No
   cards", "Choose a card").
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
- Portrait: a glass ▲ tab at the hand's left lays the hand out in one flat row of whole cards over a soft shade, just
  over the rail (`ArenaHandPosture.spread`); four show at once, and a sideways swipe moves along a bigger hand (a thin
  gold track shows where). Tap a card to pop it, slide it up to play it, hold to read. ▼ (now above the cards), a tap on the table, playing a card or a
  new turn tucks it; a payment, a target or combat puts it aside until it's done.
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
| A board wipe (3+ leaving at once) | one after another, 0.16 s apart, the whole cascade within 1.2 s; the caption names the spell and what went |
| Attack / block marks | 0.25 / 0.3 s |
| Turn banner | 0.9 s, during the draw |
| Draw | 0.5 s out of the deck, 0.4 s on show, 0.2 s into the hand |
| Hand up / down | 0.22 s / 0.18 s |

Effects never change what XMage is asked or when; they only set how long smart pass waits before passing for you
(`BoardPresentationHold`, at most 4–5 s). Holding a card open to read it holds the pass until you close it (at most a
minute). An opponent's spell that destroys, exiles, bounces or takes your permanents stops for you even when you can't
answer it (Stop for Removal, on by default), and a skip that passes responses stops for it too.

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

## Menus (every page outside a game)

Caleb's rule (2026-10-22): **every menu page follows Arena's design and UI, nothing carried over** from the Walnut
Tavern pages, while the 3D tavern room stays behind the home page. The menus are Arena's whatever board the player
chose: `OnDeviceRootView` sets `\.arenaBoard` true over everything, and a game resets it to its own board (the Hearth
board keeps its leather in a game; the starting roll follows the board). Reference frames:
`build_output/arena-menus-reference/` and `~/Movies/motion-assets/yt/MB2ZTtCtJJA/` (home, Play, deck select, events);
Arena's deck boxes, shut and open: `~/Movies/motion-assets/yt/ZvNnTWRy3xU/f/` (`open-big.png`, `closed-big.png`).

- **Shell:** `ArenaTopBar` on every page (the mark; Home, Profile, Decks, Ranked, Learn as engraved emblems with a
  label; rank chip, messages with a diamond pip, news, downloads and the gear on the right; portrait keeps messages
  and the gear, news and downloads move to the home page's corner). Pages sit under it over `ArenaRoomBackdrop`
  (dimmed 0.55 behind a page, 0.72 behind Decks, undimmed on home). A page inside the shell leaves its own backdrop
  out (`\.arenaMenuBackdrop`).
- **Home** (`ArenaHomeView`): the featured panel (pages turn on their own and follow a swipe; a kicker and a title, no
  detail line; a dark band only behind the words) and three tiles in the middle, medallions on a gold rail with ticks
  (deck, rank, season), friends in the lower left, the orange Play pill (`ArenaPlayButtonStyle`) in the lower right.
  Nothing scrolls. The art ships in the app (`home-art-*` in the asset catalog, `ArenaHomeArt` with a focus point,
  drawn by `ArenaFocusedArt`). Each is Scryfall's 626 px art crop, upscaled 2× (Real-ESRGAN x4plus at 4×, then
  Lanczos to 1252 px), because a card image's art window is about 408 px and goes soft at 3×.
  - The big panel: The Ur-Dragon (Jaime Jones, CMM 361), Edgar Markov (Volkan Baǵa, INR 234), Y'shtola, Night's
    Blessed (Magali Villeneuve, FIC 7) and Atraxa, Praetors' Voice (Victor Adame Minguez, 2XM 190). Caleb chose the
    first three.
  - The tiles: Krenko, Mob Boss (Lie Setiawan, FDN 204), Miirym, Sentinel Wyrm (Kekai Kotaki, CLB 284) and Giada, Font
    of Hope (Kai Carpenter, FDN 141).
- **Play** (`ArenaPlayPanel`): the room 0.78 dark, the decks as boxes on the left (shelves, scrolled to the chosen
  deck's shelf), the blade on the right with its burning seam (`ArenaSeam`): Find Match, Friends, Recently Played tabs;
  Quick, Ranked, Custom gems; diamond option rows (`ArenaOptionRow`) fading out above the footer; Play in the footer.
  In portrait the blade is a sheet along the bottom. **The options fit without scrolling or fading**: Quick's bracket
  is a row of five gems with the chosen one named in the heading, the opponent's deck one picker row, then skill and
  who goes first; Ranked is the standing, one line and two pills. **A search waits in the blade**: Play turns into
  Cancel under "Searching… 0:12" with Play the AI now, and the options fold away; never a centred pop-up. Friends rows
  are chosen like options and Play is named for the choice. Recently Played shows tall tiles of the last tables, or one
  quiet line ("No tables yet") with the blade's plaque leading to Find Match. Tabs are words with a glowing gold bar
  (`ArenaTabBar`), never blue.
- **Deck boxes** (`ArenaDeckBox`): a black box seen nearly straight on (front 1.34 times as wide as tall), a lid band
  stamped MAGICMOBILE, the commander's art on the front, a dark side with a clasp, the pips at the foot of the front
  and fully clear of the black one-line name plate (with Arena's pencil where the deck can be edited). Choosing a deck
  opens its box: the lid stands raised and tilted back with the art on top, the front folds to half height with a lit
  lip, and the commander card rises in front of two card backs. Rows leave room for an open lid. "+" is a dark tile.
- **Opened boxes hold the app's own card backs** (`ArenaBoxCardBack`: walnut, a gold frame line, the M mark), never
  the Magic back.
- **Custom Table:** Arena's event page on two glass plates: your open deck box, its bracket and check, your name
  written on the plate (a gold line and pencil while it can be edited; no field capsule) and Change deck on the left;
  player tiles, seat slots (deck boxes; × empties one, a "+" seat adds an AI), an AI skill slider and Who goes first
  tiles on the right. Below the plates, never over them, a solid strip with the status and the ember Start (Find
  players for Game Center).
- **Decks** (Arena's decks-1): Deck Studio under the top bar, over the dimmed room (no NavigationStack: it paints an
  opaque page): search and pill filters, every deck as a box across the page (the first tap opens its box and scrolls it
  into view, a second opens it for editing; the pencil shows on the chosen box only), and the chosen deck on a one-row
  strip along the foot (sideways about 50 pt): art, name, pips, bracket, then Edit Deck and Play at the right. Deck Studio's binder parts (`Grimoire*`, `Binder*`) draw glass, pills and plaques now; the page
  curl and the book film are off (`GrimoireStage.curlEnabled`).
- **Deck builder** (Arena's deckbuilder-1/2): sideways (`arenaBuilder`), two panes: the cards to add fill the left
  under ONE filter line (shelf, a short "Search", the mana values 0–7+ first, then the tools, running on to the right);
  a read-only deck shows its own cards there. The deck stands on the right as a 330 pt column: Save (or Edit a copy),
  tags and ⋯ at its head, the chapters (Cards · Ideas · Analysis) as a tab strip, the commander's round art, name and
  quick check, the cards by type (count, name, cost; − and + at a line's end while editable), the gold mana curve
  closing the list, and **Done beside Play at its foot**. Upright: one scrolling page, the tab strip under the head,
  one filter strip under the search, a read-only deck as name bars, and Done with Play in a bar along the foot. The
  quick check is one honest line ("Quick check · No issues found", XMage named for VoiceOver). The editor is a
  full-screen cover, outside the shell, so it draws its own dimmed room.
- **Panels, not sheets:** Options, Updates, Downloads, How to Play, the welcome, the bracket, the error report and
  questions (`ArenaPromptPanel`) open as glass panels over the dimmed menu (`arenaPanel`), below the top bar and, with
  `fitsContent`, only as tall as their page. Friends slides in along the leading edge, full height, held either way. A
  page closes itself with `\.arenaPanelClose` (fall back to `dismiss` only outside a panel). No system alerts or
  action sheets in the menus.
- **Updates** is Arena's inbox (inbox-1): a blade from the right (`placement: .trailing`, the burning seam on its inner
  edge) with ◆ rows, the newest lit with an orange "New" and a narrow flare at the row's far edge; a row opens in place
  (art banner, text). The build and links live in its last row. **Downloads** opens on a readout ("0 of 31,959 stored"
  with Check on that line, a gold bar, the state once).
- **Options** (`ArenaOptionsView`, Arena's options-1): a centred serif title, one centred column of compact pills
  (Gameplay, Board, Audio, Display & Artwork, Performance), Support and About as underlined links along the foot. Each
  page opens in the same panel with a back chevron and lays its settings flat on the glass in columns (Arena's
  options-gameplay-1); Sound Lab and Phase Stops are pages too. Controls: `ArenaCheckbox` (off a dim diamond, on an
  orange tick), `ArenaSlider` (a gold diamond on a drawn track), `ArenaStepper`, `ArenaSegmented` (a tab strip). They
  draw nothing of the system control: a real Toggle/Slider/Stepper reaches VoiceOver and UI tests only through
  `.accessibilityRepresentation` (a 2% opacity overlay still showed its track).
- **Profile** (Arena's profile-1..3): the player's name as the headline, the season rank, a progression row, the
  commander as full-height hero art, and an Overview / Customization tab strip; title and portrait are chosen from a
  grid. **Ranked** (ranked-1): the title with "Season ends in N days" in ember, a stair of tier plaques (what each
  allows, which you reached) and a Current Rank column; Play Ranked, Leaderboard and Profile beside the title. Pages use
  glass cards (`arenaCard`), a back chevron only below a tab root, and fade at their foot.
- **The top bar** lights the icon of the utility whose panel is open (gear, news, downloads, friends) instead of a tab.
- **Dimming** (a search running): a scrim over the whole deck side, never opacity on the boxes (they turn see-through).
  Behind any panel the home page steps away entirely; only the room shows under the scrim.
- **Wins and losses:** gold and a muted rose (`ArenaMenuStyle.win/loss`), never web green and red.
- **Copy** (AGENTS.md): no taglines, helper lines or secondary labels; a state line shows only when it says something
  (an invalid name, offline profiles, a search running). Real Arena reference shots for these pages are in
  `build_output/arena-menus-reference/more/` (see its INDEX.md).

Fixtures for screenshots (DEBUG, `--ondevice-setup-ui-test` with `MAGICMOBILE_UI_TEST_SOCIAL=1`):
`MAGICMOBILE_UI_TEST_OPEN=` `play`, `play-ranked`, `play-custom`, `play-friends`, `play-recent`, `queue`, `play-cycle`
(boxes opening in turn, for a recording), `custom`, `decks`, `deck`, `profile`, `rankedHall`, `leaderboard`,
`friends`, `settings[:page]`, `updates`, `downloads`, `learn`, `learn-table`. GameAudio is silent under the UI-test flag
and with `MAGICMOBILE_MUTE_AUDIO=1` (a stalled simulator audio device otherwise holds the app on its launch screen).
