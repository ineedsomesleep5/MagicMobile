# Deck Helper

Caleb's idea (2026-10-26): a deck-building helper in the app that finds cuts, says what raises a deck's power and
rates the deck, built on rules and the Deck Power work, with no AI and no API calls at play time. Ideas are tried on
the test-bed page first (below) and only then ported.

## What already exists

- **Deck Studio Insights** (iOS, `DeckStudio/Core/DeckStudioRoleAnalysis.swift`): counts, curve, pips, opening-hand
  probabilities, and roles from Scryfall's curated oracle tags baked into `ondevice-catalogue.json`
  (`ramp, cardFlow, interaction, boardWipe, protection, graveyardHate, recursion, tutor`; 15,797 of 31,959 cards
  tagged), with conservative text patterns for the rest, user-reviewed roles and personal target ranges that start
  off ("there is no universal ideal Commander deck").
- **Brackets** (`Ranked/CommanderBrackets.swift`, `commander-brackets.json`, rules of 2026-02-09): 53 Game Changers,
  37 mass land denial cards, 54 extra-turn cards, 49 two-card combos with an `early` flag, chained extra turns at 3.
- **Deck Power** (`docs/DECK_POWER.md`, `scripts/ranked/deck_power.py`, on `main`): a 1–10 rating of the AI decks from
  nine parts (speed, mana, interaction, consistency, threats, synergy, commander, combos, resilience). The fitted
  weights (mana 0.34, commander 0.31, threats 0.17, interaction 0.13, the rest near 0) describe what the XMage AI
  plays well, and the ratings the apps ship come from each deck's games, not the formula. Card counts alone carried
  limited signal (leave-one-out 0.53 log-odds against 0.58 for "every deck is average").

So the helper is mostly new rules on top of data the app already carries. Nothing needs a network call: Scryfall
only serves the test bed.

## Research digest

**The cut video** (DeckTechsForDecks, "How to Cut the Last 10 Cards From Your Commander Deck", 2026-10-25):

1. Sort the list into ramp, card advantage, removal, then win cons and "the thing" cards. Those first three never
   go on the block ("the amount of times I see someone cut a Llanowar Elves to fit in their eight drop … is not
   zero"); cut from the smaller remaining pile. Lands are not cut either: an MDFC replaces a basic so a removal
   spell can go.
2. Sorting shows the bloated category: four Craterhoof effects, twenty ramp cards. Cut inside it.
3. The if-then test: a card that needs a board state before it does anything (Doubling Season) must either win the
   game or put you in a winning position. If it only makes the plan a little better, it goes. A card that does
   something the turn it lands stays.
4. Top end: look at the 5+ and 6+ drops together and take seven down to three or four; a five-drop "has to do a
   lot". Prefer the four-mana version of an effect (Parallel Lives over Doubling Season).
5. Cut ten ruthlessly, goldfish, see what is slow and what the real bottleneck is (his Muxus deck wanted haste
   enablers, not more damage triggers).

**Command Zone template (2025):** 38 lands (MDFCs count), 10 ramp, 12 card advantage, 12 targeted disruption,
6 mass disruption, 30 plan cards; cards may count twice. Reddit's pushback: 6 mass disruption is high for most
tables (2–3 wipes is common), the template pushes decks toward midrange, and it is a starting point for a first deck.

**Reddit cut methods** (r/EDH threads 2023–2025): rank within a category and cut its worst; cut by mana value first
(the ten most expensive, "merciless on the 5 slot", counts at 3, 4 and 5 should fall); compare cards at the
commander's mana value against casting the commander; cut single-purpose cards unless they are excellent; cut cards
that need two or three other pieces; an under-represented subtheme goes whole; tutors change the math (the worst
card in a tutored category is never found); cut a land last; one in, one out past 100; keep a maybeboard; play the
cut candidates against each other and keep the one you'd rather draw; "does it help you win or help you catch up?".

**Brackets (WotC, October 2025 and February 2026 updates):** 1 Exhibition and 2 Core allow no Game Changers,
3 Upgraded up to three, 4 Optimized and 5 cEDH any number; mass land denial and chained extra turns are bracket 4;
tutor limits were dropped in October 2025; Farewell and Biorhythm joined the list in February 2026. The app's
`CommanderBrackets.swift` already encodes this.

**One opponent (forum consensus, already in Deck Power):** goad, group hug, symmetric effects and taxes are weak;
spot removal beats sweepers; fast mana counts more (a turn-1 Sol Ring wins 62% of 1v1 games on playgroup.gg).

## Design

Four questions, all answered by rules over the bundled catalogue:

1. **Where does it stand?** Template bars (lands, ramp, card advantage, targeted removal, mass disruption, plan
   cards) with targets by table size, the curve and the effective curve (Deck Power's cheat-out discount), colored
   pips against sources, tapped lands, and the bracket report the app already makes.
2. **How strong is it?** Two numbers, shown side by side because they measure different things:
   - **Table Power** (1–10): a human-scale heuristic: 4 for a tidy precon, plus template coverage, fast mana, tutors,
     Game Changers (diminishing after three), two-card combos, a low effective curve, untapped mana and cheap
     interaction. Bands follow the brackets (3–4 Core, 5–6 Upgraded, 7–8 Optimized). A guess to tune by play.
   - **AI Power** (1–10): the Deck Power formula with the fitted weights, so a player can see which Ranked tier's AI
     decks their deck's raw materials match. The page says plainly that it describes what the XMage AI plays well.
3. **What do I cut?** Lands, the commander, and ramp, draw and removal at or under target are protected. The rest
   score: needs a board state (+2, unless it is a finisher), 6+ mana (+2) or 5 mana (+1) discounted by the deck's
   cheat-outs, the third or later copy of a narrow effect (+1: overrun, extra combat, anthem, haste, doubler), off
   the commander's plan (+1), weak with one opponent (+1.5 at the MagicMobile table), over a category's target (+1),
   conditional wording (+0.5), rarely played by EDHREC rank (+0.5 to +1); cheap cards, tutors, fast mana and
   finishers score lower. The player says how many cuts they need and gets that many, each with its reasons.
4. **What raises it?** Levers with their effect on both numbers (two cheap rocks, untapped lands, tutors,
   instant-speed removal, three 6-drops to 2-drops, evasive bodies, a Game Changer, a combo), and staple suggestions
   in the deck's colors per template line, Game Changers marked so the bracket consequence is visible.

Plus a sample hand (draw seven, then one at a time), since the video's last step is goldfishing.

### EDHREC (added 2026-10-26, Caleb: "Claude did well because it knew EDHREC")

What made an LLM's cut advice feel informed was EDHREC's per-commander knowledge, so the test bed carries it as data:
`scripts/deck-helper/fetch-edhrec.py` fetches the commander page of every commander with 1,000+ decks in EDHREC's
past two years (1,687 pages, 1,649 with card lists, on 2026-10-26, plus the AI-deck commanders) from `json.edhrec.com`, the same source and
manners as `scripts/ranked/build_ai_decks.py`, and trims each to: inclusion and synergy per card (about 220 cards
across its lists), average type counts (lands, basics, creatures…), theme tags, bracket split and similar
commanders. One file per first letter (about 20 MB in all); the page loads the commander's letter.

**Deck first, EDHREC as tie-breaker (Caleb, 2026-10-26: it must not become "EDHREC says these are the best"; the
calls come from what is in your deck and its categories).** Since then:

- The deck's plan is read from the deck itself: the commander's themes plus any theme a fifth of the nonland cards
  share (tribe, tokens, go-wide, +1/+1 counters, lifegain, attack…), and "choose a creature type" cards count for a
  tribal deck. EDHREC no longer decides whether a card is on plan.
- Cut scores are the deck's own rules; EDHREC adds at most ±0.5 and shows as a separate grey line. On Krenko the top
  five cuts are identical with EDHREC on or off; on Edgar it reorders only cards whose deck scores sit within half a
  point.
- Adds are ranked by the deck: short categories first (+2 and more the shorter), shares the plan (+1.5), cheap when
  the deck lacks early plays, a finisher when it has under two; minus for overfilled categories, a full top end,
  board-state-only cards off plan and multiplayer cards at a one-opponent table. EDHREC widens the candidate pool and
  nudges ties (≤ 0.5); EDHREC's own popular list sits last, collapsed, labelled "not judged a fit".
- An **EDHREC** setting (Tie-breaker only / Off) shows the deck-only read for comparison.

The original use (superseded by the above):

- **Fit:** average inclusion of the 99 among that commander's decks, and how many cards sit in its lists at all
  (the EDHREC-average AI decks score 100% listed, a sanity check).
- **Cuts:** under 3% inclusion +1, under 10% +0.5, not in its lists +0.5, played less with this commander than
  elsewhere (synergy ≤ −10%) +0.5; a staple at 35%+ −1, synergy ≥ +25% −0.5. EDHREC evidence overrides the text
  theme heuristic (Impact Tremors reads "off plan" by text and is in 85% of Krenko decks).
- **Upgrades:** the most-played cards you don't run, high-synergy cards you don't run, then per template gap the
  EDHREC candidates whose classifier role fills it (ramp, draw, removal, wipes). Format staples are the fallback for
  a commander without a page.
- **Lands:** target land count from the commander's average build; tapped lands to swap, each with up to three
  untapped lands in your colors (ranked by colors made weighted by your pips, EDHREC inclusion, price); untapped
  lands you don't run; the commander's utility lands by inclusion; basics split by pips.

**Licensing.** EDHREC's numbers are EDHREC's. The repo's precedent is build-time use for the AI decks, and this page
is private. Shipping inclusion and synergy inside the app, or a derived form of them, is a decision for Caleb and
probably a question for EDHREC; the earlier Deck Studio decision kept EDHREC as a website view for that reason.
The rest of the helper (template, cuts by rule, brackets, Power, lands by cycle) needs no EDHREC data.

### Where it would live in the app

A fourth Deck Studio tab beside Cards / Ideas / Analysis / Playtest, or inside Analysis. Roles come from the
catalogue's curated tags plus the user's reviewed roles (already stored per deck), so the text patterns on the test
bed are only a stand-in. The commander's theme is derived from its type line and oracle text. The EDHREC rank
signal needs the rank baked into the catalogue at build time (Scryfall's `edhrec_rank`), or dropped.

### Open questions for Caleb

- Should players see AI Power at all, or only Table Power with "this matches a Gold AI deck" phrasing? Deck Power
  is hidden today by design.
- Cut suggestions name real cards from the player's deck. Is a reason chip enough, or should each cut show the
  category count it fixes?
- Table Power's bands and the cut weights are first guesses. The plan is to run the AI decks and a few of Caleb's
  own decks through the test bed and tune until the ordering feels right, then port.

## Screens (redesign of 2026-10-26, Caleb: "super user friendly and intuitive, with images of the cards")

Paste once, then five screens under a sticky bar that shows the commander's art, the read in one line, and the running
tally of your Cut and Add marks with a "Copy new list" button:

1. **Overview**: the commander card, a one-sentence read ("Krenko reads as an Upgraded deck, built the way most Krenko
   decks are. It is light on ramp, light on card draw…"), four or five plain numbers, **Do this first** (the top
   actions, each with an Open button to the right screen), the template bars, curve and colors, the fastest levers,
   what EDHREC knows, a sample hand with card images.
2. **Cuts**: card images with the score as a badge and up to three reasons under each, Cut / Keep buttons; safe
   cards in a strip. The count defaults to whatever reaches 100.
3. **Adds**: card images with inclusion pills and synergy lines; sections by what the deck lacks; Add buttons.
4. **Lands**: each tapped land with its three best untapped swaps beside it, untapped lands you don't run, the
   commander's utility lands, basics by pips with the current count as a badge.
5. **All cards**: thumbnails, roles, EDHREC numbers; tap any card for the big image and the role editor.

Decisions persist per commander in the browser; "Copy new list" writes the list minus cuts plus adds.

**Card images need a local server.** The artifact sandbox blocks every outside image (that is why the board prototype
had to bundle a fixed set), and 32,000 cards cannot be bundled, so the image-rich version is served from the Mac:
`python3 scripts/deck-helper/serve.py` (or the `deck-helper` entry in `.claude/launch.json`, which the desktop app's
browser pane starts) serves `build_output/deck-helper` with Scryfall's card images loading live from
`cards.scryfall.io`. The same page published as the artifact works without images (they hide themselves).

## Test bed

The "MagicMobile Deck Helper" artifact (published 2026-10-26 from `scripts/deck-helper/`): paste a list from
Archidekt or Moxfield, pick the table (one opponent or a pod), the number of cuts wanted and a commander strength,
and read the six sections. Tap any card to correct its roles; corrections persist in the browser and rerun the
analysis. The page embeds `commander-brackets.json` and `deck-power-weights.json` from `main`. Card data is built
once, not fetched: `scripts/deck-helper/classifier.js` runs the rules over Scryfall's bulk oracle-cards file (every
Commander-legal card, 32,116 on 2026-10-26) and `build-cards.js` writes one compact shard per first letter (3.8 MB in
all) that the page loads beside itself; `build.py` assembles the page from `deck-helper.template.html`. That is the
app's own shape: roles baked at build time, arithmetic on the device. The artifact sandbox blocks outbound fetches
anyway, so a page that called Scryfall live could not work. The two example lists are the Krenko and Edgar Core AI
decks, whose measured Power (6.4 and 7.9) is a check on the AI estimate.

To change a rule: edit `classifier.js` (roles, flags, theme tokens) or the template (targets, cut scores, Table
Power, EDHREC weights, land ranking), rebuild with `build.py --out <dir> --bulk oracle-cards.jsonl --edhrec-cache
<cache>` (after `fetch-edhrec.py fetch --cache <cache>`, about an hour the first time, cached after), and republish
`deck-helper.html` with the `cards/` and `edhrec/` files beside it. The bulk file, the cache and the shards stay out
of the repo.
