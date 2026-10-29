# Deck Power

Design agreed with Caleb on 2026-10-24. Since 2026-10-25 every AI deck is rated by its own games (below); no app picks
decks by Power yet, and the numbers wait for Caleb's approval.

Power is a hidden 1–10 rating of how strongly an **AI deck** plays, beyond its bracket. Players never see it. It
decides which deck the AI brings: in Ranked it climbs with your rank; in Quick Match you choose Easy, Medium or Hard.

## Rules

1. **Brackets stay the gate for players.** Your rank decides the strongest bracket you may queue with
   (`RankTier.maxDeckBracket`: Bronze and Silver 2, Gold and Platinum 3, Diamond and Mythic 4). Power never looks at
   your deck: a Gold player faces the same Power whether they bring a weak or a strong legal deck.
2. **Only AI decks are rated.** The pool is a fixed list (the 5 precons and `ai-decks.json`), so Power can be
   calibrated once, carefully, and shipped as data.
3. **Ranked: Power is a ladder.** Each rank has a target Power. The AI's deck is the deck nearest that target, picked
   at random among the closest few so it doesn't repeat, from **your tier's bracket or any lower one, never higher**.
   When no allowed deck reaches the target, the AI takes the strongest allowed one. Those gaps are where new AI decks
   are needed.
4. **Quick Match: Easy, Medium, Hard.** Each sets the AI deck's Power band and the AI's skill together, because a strong
   deck played badly doesn't feel hard. An **Advanced** toggle keeps today's exact controls (opponent bracket, a
   specific deck, skill 1–10).
5. **Unchanged:** never your own commander, not a deck you faced recently, Bronze keeps the gentlest precons
   (`AIDeckPool.gentlestPrecons`).

## The ladder (first guess, to calibrate)

| Tier | Target Power | AI deck brackets allowed |
|---|---|---|
| Bronze | 3–4 | 2 and below |
| Silver | 4–5 | 2 and below |
| Gold | 5–6 | 3 and below |
| Platinum | 6–7 | 3 and below |
| Diamond | 7–8 | 4 and below |
| Mythic | 8–9 | 4 and below |

Within a tier the target steps up by division (IV to I), so the ladder climbs smoothly.

| Quick Match | AI deck Power | AI skill |
|---|---|---|
| Easy | 3–4 | about 2 |
| Medium | 5–6 | 3 (today's default) |
| Hard | 7–8 | about 5 |

## What Power measures

Each part scores 0–1 against normal Commander numbers; a weighted mix maps to 1–10. The weights live in one shared
data file so retuning never needs code changes on three platforms.

| Part | Measures | Source |
|---|---|---|
| Speed | the **effective** curve (below) and cheap plays | mana values in the catalogue |
| Mana | ramp, land count, and land quality (penalty for lands that enter tapped) | role tags, type lines, oracle text |
| Interaction | removal, counterspells, wipes; bonus for instant speed | role tags |
| Consistency | card draw, tutors | role tags |
| Threats | big creatures, evasion, finishers (Craterhoof-style) | type lines, power, keywords |
| Synergy | cards that share the commander's type or theme | type lines and oracle text |
| Commander | how strong the commander is on its own | EDHREC rank or a curated list |
| Combos | known combos (Commander Spellbook, as the bracket already checks) | bracket analysis |
| Resilience | protection and recursion | role tags |

**Cheating things out (Caleb).** A high curve isn't slow when the deck rarely pays full price. The effective curve
discounts big cards by the deck's enablers:
- free casting: cascade, discover, ripple, "without paying its mana cost";
- putting onto the battlefield: Sneak Attack, Natural Order, Elvish Piper, Through the Breach;
- reanimation: Reanimate, Animate Dead, Entomb and self-mill feeding them;
- cost reduction: reducers, convoke, affinity, delve, improvise;
- bursts of mana: rituals, Cabal Coffers.

## Power v2: rated by games (2026-10-25)

The gauntlet (docs/cloud/reports/power-1.md, 1,236 games) showed that card counts cannot rate these decks on their
own: refit on all 33 decks, the formula's leave-one-out error is 0.53 log-odds against 0.58 for calling every deck
average. Higher brackets do not play stronger in the AI's hands (Edgar Core 69% against the references, Edgar
Optimized 48%; only Krenko's Optimized deck keeps up), and Game Changers and combos fit to zero weight. So Power now
comes from each deck's games:

- `python3 scripts/ranked/deck_power.py rate` combines each deck's measured strength (Bradley-Terry over every game in
  `docs/cloud/c3-results`, `c4-results` and `power-results`) with the formula's estimate, weighted by precision: the
  formula counts like about 15–20 games, so decks with hundreds of games are rated by them and a new deck starts from
  the formula with a wide range. `--write` saves `scripts/ranked/deck-power-ratings.json`, the data the apps would ship.
- **Scale:** the reference precons (First Flight, Token Triumph, Grave Danger) average 6.0, and one Power point is
  0.27 log-odds, so a deck beats one a point below it 57% of the time, and a Mythic deck (8.5) beats a Bronze deck
  (3.5) about 79% of the time. The scale is in `scale` in the weights file.
- **Formula weights refit** on 33 decks (`weights`): mana 0.34, commander 0.31, threats 0.17, interaction 0.13, the
  rest about 0. The formula only matters for decks without games.
- Skill-3 games with the AI's deliberate mistakes off (docs/cloud/reports/power-2.md, batch C) barely changed these
  decks' results, so the ratings are not an artefact of the mistakes; skill 5 (batch D) is still running and is kept
  out of the ratings (`docs/cloud/skill-results/`).

| Deck | Bracket | Power (95% CI) | Formula | Games |
|---|---|---|---|---|
| ai-kaalia-of-the-vast-optimized | 4 | **8.4** (6.5–10.0) | 8.2 | 48 |
| ai-the-ur-dragon-core | 2 | **8.3** (7.6–9.0) | 7.8 | 537 |
| ai-miirym-sentinel-wyrm-optimized | 4 | **8.2** (6.3–10.0) | 7.6 | 48 |
| ai-krenko-mob-boss-optimized | 4 | **7.9** (6.0–9.9) | 6.0 | 47 |
| ai-gishath-suns-avatar-core | 2 | **7.9** (7.3–8.5) | 7.4 | 689 |
| ai-edgar-markov-core | 2 | **7.9** (7.4–8.5) | 6.9 | 692 |
| ai-gishath-suns-avatar-exhibition | 1 | **7.8** (5.8–9.7) | 7.7 | 48 |
| ai-the-ur-dragon-optimized | 4 | **7.6** (5.7–9.5) | 8.0 | 48 |
| ai-edgar-markov-upgraded | 3 | **7.5** (5.4–9.6) | 6.6 | 36 |
| ai-the-ur-dragon-upgraded | 3 | **7.4** (5.3–9.5) | 8.1 | 36 |
| ai-gishath-suns-avatar-upgraded | 3 | **7.2** (5.1–9.3) | 7.6 | 36 |
| ai-krenko-mob-boss-upgraded | 3 | **7.0** (4.9–9.1) | 6.0 | 36 |
| ai-krenko-mob-boss-exhibition | 1 | **6.7** (4.6–8.8) | 6.0 | 36 |
| first-flight | 2 | **6.6** (6.1–7.0) | 5.8 | 1017 |
| ai-lathril-blade-of-the-elves-exhibition | 1 | **6.6** (4.5–8.7) | 5.9 | 36 |
| ai-krenko-mob-boss-core | 2 | **6.4** (5.6–7.3) | 5.9 | 300 |
| ai-lathril-blade-of-the-elves-upgraded | 3 | **6.4** (4.3–8.5) | 5.5 | 35 |
| token-triumph | 2 | **6.1** (5.6–6.6) | 4.9 | 861 |
| draconic-destruction | 2 | **6.1** (5.4–6.7) | 6.4 | 536 |
| ai-gishath-suns-avatar-optimized | 4 | **5.9** (3.8–8.0) | 7.3 | 36 |
| ai-edgar-markov-optimized | 4 | **5.9** (4.0–7.8) | 6.3 | 48 |
| ai-winota-joiner-of-forces-optimized | 4 | **5.8** (3.9–7.7) | 6.8 | 48 |
| grave-danger | 2 | **5.3** (4.9–5.8) | 5.3 | 1124 |
| ai-wilhelt-the-rotcleaver-upgraded | 3 | **5.3** (3.2–7.4) | 5.6 | 36 |
| ai-lathril-blade-of-the-elves-core | 2 | **5.2** (4.6–5.8) | 5.7 | 648 |
| ai-wilhelt-the-rotcleaver-core | 2 | **4.4** (3.8–4.9) | 5.0 | 726 |
| chaos-incarnate | 2 | **3.8** (3.0–4.6) | 4.6 | 359 |
| ai-lathril-blade-of-the-elves-optimized | 4 | **3.8** (1.9–5.8) | 5.2 | 48 |
| ai-wilhelt-the-rotcleaver-optimized | 4 | **3.6** (1.6–5.6) | 6.0 | 48 |
| ai-marisi-breaker-of-the-coil-exhibition | 1 | **3.5** (1.5–5.4) | 4.0 | 48 |
| ai-tormod-the-desecrator-core | 2 | **3.2** (1.2–5.2) | 3.9 | 48 |
| ai-kynaios-and-tiro-of-meletis-exhibition | 1 | **2.4** (1.0–4.5) | 4.3 | 46 |
| ai-the-first-sliver-optimized | 4 | **2.2** (1.0–4.5) | 6.5 | 47 |

Ranges are 95% intervals. Decks with 36–48 games are known to about ±2 points; the precons and Core decks to ±0.5.

### The ladder at these ratings

`deck_power.py ladder`: for each division's target (the tier's band split in four), the three nearest decks the tier's
bracket allows. Every division now has decks within 0.5 of its target.

| Tier | Division | Target | Max bracket | Nearest allowed decks (Power) | Gap |
|---|---|---|---|---|---|
| Bronze | IV | 3.12 | 2 | tormod-the-desecrator-core 3.2, marisi-breaker-of-the-coil-exhibition 3.5, chaos-incarnate 3.8 | 0.1 |
| Bronze | III | 3.38 | 2 | marisi-breaker-of-the-coil-exhibition 3.5, tormod-the-desecrator-core 3.2, chaos-incarnate 3.8 | 0.1 |
| Bronze | II | 3.62 | 2 | marisi-breaker-of-the-coil-exhibition 3.5, chaos-incarnate 3.8, tormod-the-desecrator-core 3.2 | 0.1 |
| Bronze | I | 3.88 | 2 | chaos-incarnate 3.8, marisi-breaker-of-the-coil-exhibition 3.5, wilhelt-the-rotcleaver-core 4.4 | 0.1 |
| Silver | IV | 4.12 | 2 | wilhelt-the-rotcleaver-core 4.4, chaos-incarnate 3.8, marisi-breaker-of-the-coil-exhibition 3.5 | 0.3 |
| Silver | III | 4.38 | 2 | wilhelt-the-rotcleaver-core 4.4, chaos-incarnate 3.8, lathril-blade-of-the-elves-core 5.2 | 0.0 |
| Silver | II | 4.62 | 2 | wilhelt-the-rotcleaver-core 4.4, lathril-blade-of-the-elves-core 5.2, grave-danger 5.3 | 0.2 |
| Silver | I | 4.88 | 2 | lathril-blade-of-the-elves-core 5.2, grave-danger 5.3, wilhelt-the-rotcleaver-core 4.4 | 0.3 |
| Gold | IV | 5.12 | 3 | lathril-blade-of-the-elves-core 5.2, grave-danger 5.3, wilhelt-the-rotcleaver-upgraded 5.3 | 0.1 |
| Gold | III | 5.38 | 3 | grave-danger 5.3, wilhelt-the-rotcleaver-upgraded 5.3, lathril-blade-of-the-elves-core 5.2 | 0.1 |
| Gold | II | 5.62 | 3 | grave-danger 5.3, wilhelt-the-rotcleaver-upgraded 5.3, lathril-blade-of-the-elves-core 5.2 | 0.3 |
| Gold | I | 5.88 | 3 | token-triumph 6.1, draconic-destruction 6.1, krenko-mob-boss-core 6.4 | 0.2 |
| Platinum | IV | 6.12 | 3 | token-triumph 6.1, draconic-destruction 6.1, krenko-mob-boss-core 6.4 | 0.0 |
| Platinum | III | 6.38 | 3 | krenko-mob-boss-core 6.4, lathril-blade-of-the-elves-upgraded 6.4, first-flight 6.6 | 0.0 |
| Platinum | II | 6.62 | 3 | first-flight 6.6, lathril-blade-of-the-elves-exhibition 6.6, krenko-mob-boss-exhibition 6.7 | 0.0 |
| Platinum | I | 6.88 | 3 | krenko-mob-boss-upgraded 7.0, krenko-mob-boss-exhibition 6.7, first-flight 6.6 | 0.1 |
| Diamond | IV | 7.12 | 4 | gishath-suns-avatar-upgraded 7.2, krenko-mob-boss-upgraded 7.0, the-ur-dragon-upgraded 7.4 | 0.1 |
| Diamond | III | 7.38 | 4 | the-ur-dragon-upgraded 7.4, edgar-markov-upgraded 7.5, gishath-suns-avatar-upgraded 7.2 | 0.0 |
| Diamond | II | 7.62 | 4 | the-ur-dragon-optimized 7.6, edgar-markov-upgraded 7.5, gishath-suns-avatar-exhibition 7.8 | 0.0 |
| Diamond | I | 7.88 | 4 | krenko-mob-boss-optimized 7.9, gishath-suns-avatar-core 7.9, edgar-markov-core 7.9 | 0.0 |
| Mythic | IV | 8.12 | 4 | miirym-sentinel-wyrm-optimized 8.2, the-ur-dragon-core 8.3, krenko-mob-boss-optimized 7.9 | 0.1 |
| Mythic | III | 8.38 | 4 | kaalia-of-the-vast-optimized 8.4, the-ur-dragon-core 8.3, miirym-sentinel-wyrm-optimized 8.2 | 0.0 |
| Mythic | II | 8.62 | 4 | kaalia-of-the-vast-optimized 8.4, the-ur-dragon-core 8.3, miirym-sentinel-wyrm-optimized 8.2 | 0.2 |
| Mythic | I | 8.88 | 4 | kaalia-of-the-vast-optimized 8.4, the-ur-dragon-core 8.3, miirym-sentinel-wyrm-optimized 8.2 | 0.5 |

| Quick Match | Power band | Decks in the band |
|---|---|---|
| Easy | 3–4 | 5: chaos-incarnate, lathril-blade-of-the-elves-optimized, wilhelt-the-rotcleaver-optimized, marisi-breaker-of-the-coil-exhibition, tormod-the-desecrator-core |
| Medium | 5–6 | 6: gishath-suns-avatar-optimized, edgar-markov-optimized, winota-joiner-of-forces-optimized, grave-danger, wilhelt-the-rotcleaver-upgraded, lathril-blade-of-the-elves-core |
| Hard | 7–8 | 9: krenko-mob-boss-optimized, gishath-suns-avatar-core, edgar-markov-core, gishath-suns-avatar-exhibition, the-ur-dragon-optimized, edgar-markov-upgraded, the-ur-dragon-upgraded, gishath-suns-avatar-upgraded, krenko-mob-boss-upgraded |

### Decisions for Caleb

1. **Approve these ratings and the scale** (one point = 57%, references at 6).
2. **Bronze:** the design keeps Bronze on the gentlest precons. By Power, Bronze's 3–4 is Tormod 3.2, Marisi 3.5 and
   Chaos Incarnate 3.8; Grave Danger (5.3) and Token Triumph (6.1) play like Gold. Recommendation: let Power pick for
   Bronze too (bracket ≤ 2), dropping the precons-only rule.
3. **Drop The First Sliver** (bracket 4, plays like 2.2), unless skill 5 shows the AI can play it: Ranked would never
   pick it, and a player choosing it as an Optimized deck would get the weakest deck in the pool. Lathril and Wilhelt
   Optimized (3.8, 3.6) are in the same spot: Ranked never reaches them (the tiers that want 3–4 allow bracket 2
   at most), so only Quick Match Easy would use them.
4. **Optional top-up** (about 100 games each for the decks Mythic and Bronze lean on: Kaalia, Miirym, Krenko
   Optimized, Tormod, Marisi, Kynaios and Tiro) would narrow their ±2 to about ±1. Not needed to ship.

## Power v3: games against people too (2026-10-29)

Caleb: "use real games and AI games as results for the AI decks". AI-vs-AI strength did not predict how a deck does
against people: 254DADDY's Miirym deck went 15–6 against Diamond's AI, and Tiamat (7.5) lost 13 of 15 games to people.

- **Data.** `docs/cloud/ranked-results/*.csv`: each player's record with each commander against each AI deck, from
  `player_games` (ranked, quick and casual games against one AI). Players are numbered, no account ids or deck names.
  The first export (2026-10-29) holds 354 games from four players, about half of them 254DADDY's. Refresh it with:

  ```sql
  with p as (select user_id, 'player' || dense_rank() over (order by min(played_at)) label from player_games group by user_id)
  select p.label player, pg.mode, coalesce(pg.commanders[1], '?') human_commander, pg.opponents->0->>'name' ai_deck,
         count(*) filter (where pg.result = 'win') human_wins, count(*) filter (where pg.result = 'loss') ai_wins,
         count(*) filter (where pg.result = 'draw') draws
  from player_games pg join p using (user_id)
  where pg.mode in ('ranked', 'quick', 'casual') and jsonb_array_length(pg.opponents) = 1 and (pg.opponents->0->>'ai')::boolean
  group by 1, 2, 3, 4 order by 1, 2, 3, 4;
  ```

  Save it as a new CSV with those columns (`player, mode, human_commander, ai_deck, human_wins, ai_wins, draws`) and
  remove the older export, since each holds every game so far. Rows naming a deck outside the pool are reported and
  skipped.
- **Method** (`human_fit` in `deck_power.py`). A deck's AI-vs-AI rating (with the formula) is its starting point,
  widened by `scale.humanShiftLogOdds` (0.5 log-odds, about 1.9 Power points): how far a deck's strength against
  people may stand from its AI-vs-AI strength. Its games against people then move it, in a Bradley–Terry fit where each
  player-and-commander has its own strength, so a strong player's wins don't mark a deck down. 0.5 predicted held-out
  games best of 0–2.5 (five folds). Draws are left out. The AI's skill is not modelled: lower tiers' AIs make mistakes,
  so decks played mostly there may be rated a little low.
- **Moves** (Power before → after, the AI's record against people): Tiamat 7.5 → 5.6 (2–13), Edgar Upgraded
  7.5 → 6.6 (7–17), Old Gnawbone 7.4 → 6.9 (7–16), Gishath Core 7.9 → 7.5 (2–6); up: Atarka's Draconic Destruction
  6.1 → 9.2 (8–1), Krenko Exhibition 6.7 → 9.3 (11–4), Hakbal 6.8 → 8.2 (8–10), The Ur-Dragon Upgraded 7.4 → 8.7
  (9–9). Decks with few games against people keep wide ranges (`powerRange`).
- **Ships** in `ai-decks.json` with the next iOS and Android builds and the next web deploy, like v2.

## Formula v1 (2026-10-24)

`scripts/ranked/deck_power.py` rates every AI deck; `scripts/ranked/deck-power-weights.json` holds every weight and
norm, so retuning is a data change. Cards come from the iOS catalogue (types, oracle text, mana value, Scryfall role
tags). Creature power and toughness, which the catalogue lacks, come from `scripts/ranked/card-stats.tsv`, taken from
pinned XMage's `Utils/mtg-cards-data.txt` (`deck_power.py stats --card-data …` refreshes it when decks change).

```
python3 scripts/ranked/deck_power.py table     # every AI deck's parts and Power (--json for the numbers)
python3 scripts/ranked/deck_power.py check     # Power against every AI-vs-AI game in docs/cloud/*-results
python3 scripts/ranked/deck_power.py fit       # search the weights against those games (--write saves them)
```

| Part | Weight | As built |
|---|---|---|
| Speed | 0.12 | effective mana value of nonland cards (4.6 → 0, 2.6 → 1) and plays of 2 or less |
| Mana | 0.22 | ramp, with cheap non-creature ramp (Sol Ring, Signets, Rampant Growth) ×2 and mana creatures ×0.5; land count against 37 minus 0.15 per ramp card; share of lands that enter tapped |
| Interaction | 0.07 | removal and counters, +0.5 at instant speed; a sweeper-only card counts 0.5 |
| Consistency | 0.07 | tutors (65%) and card draw (35%) |
| Threats | 0.23 | evasive creatures (40%), power 5 or more (25%), creature count (25%), finishers (10%) |
| Synergy | 0.03 | share of cards on the commander's theme (its tribe, or the theme words in the weights file) |
| Commander | 0.14 | a curated strength per commander in the weights file |
| Combos | 0.10 | known two-card combos (2 points each) and Game Changers (1 point for each of the first 3, 0.5 after) |
| Resilience | 0.02 | protection; recursion counts 0 (below) |

- **Cheat-outs (effective curve).** Cards of mana value 5 or more cost less by up to 60% of what they cost above 4,
  scaled by the deck's enablers: free casting (cascade, discover, "without paying"), putting creatures onto the
  battlefield (Sneak Attack, Natural Order, Gishath, The Ur-Dragon), reanimation, cost reducers and rituals. A
  commander's own enabler counts three times. Convoke, affinity, delve and improvise discount that card by 2.
- **Two-player penalty.** Goad, group hug, symmetric draw and taxes ("unless that player pays") are weak with one
  opponent (forum consensus below): −0.1 Power each, at most −0.6. Chaos Incarnate has four.
- **Commander strengths were set by hand with C3 and C4's results in view**, so they partly encode measured AI
  performance per commander. They carry across a commander's four decks, which is their use; they are not
  independent evidence.

## What the games say

All earlier AI-vs-AI CSVs (C3's round robin, baseline, C2 and tuning runs, C4) hold **2,986 decided games on the
eleven Core decks**, not just C3's 200, every pairing with both deck assignments and seatings. `check` fits one
strength per deck (Bradley-Terry log-odds, mean 0) with a going-first term (+0.51, worth more than most deck gaps)
and one seat term per CSV for its skill gap.

**C3's precon round robin: all five inside their intervals, in C3's order.**

| Precon | Power | Predicted | Measured (95% CI) |
|---|---|---|---|
| draconic-destruction | 5.5 | 59% | 62% (52–72) |
| first-flight | 5.3 | 56% | 56% (45–67) |
| grave-danger | 4.6 | 48% | 45% (35–56) |
| token-triumph | 4.4 | 46% | 50% (39–61) |
| chaos-incarnate | 4.0 | 41% | 36% (27–47) |

**All eleven Core decks.** The larger set reorders the precons: Draconic Destruction beats precons (62%) but loses to
the Core AI decks (15% against The Ur-Dragon, 25% against Gishath), so overall it is mid-pack. Power orders the eleven
with Spearman +0.77 and agrees on 33 of 38 clearly separated pairs; 6 of 11 fall inside their intervals. One Power
point is worth about 0.37 log-odds (59% against a deck one point lower).

| Deck | Power | Measured strength (95% CI) | Power's line |
|---|---|---|---|
| ai-the-ur-dragon-core | 7.0 | +0.54 (+0.35 to +0.73) | +0.59 |
| ai-edgar-markov-core | 6.0 | +0.47 (+0.31 to +0.64) | +0.24 **under** |
| ai-gishath-suns-avatar-core | 6.7 | +0.46 (+0.29 to +0.63) | +0.49 |
| first-flight | 5.3 | +0.20 (+0.03 to +0.37) | −0.02 **under** |
| ai-krenko-mob-boss-core | 5.3 | +0.00 (−0.26 to +0.26) | −0.01 |
| token-triumph | 4.4 | −0.02 (−0.21 to +0.18) | −0.33 **under** |
| draconic-destruction | 5.5 | −0.08 (−0.26 to +0.11) | +0.07 |
| grave-danger | 4.6 | −0.22 (−0.38 to −0.06) | −0.28 |
| ai-lathril-blade-of-the-elves-core | 5.3 | −0.29 (−0.46 to −0.12) | −0.02 **over** |
| ai-wilhelt-the-rotcleaver-core | 4.7 | −0.50 (−0.66 to −0.34) | −0.23 **over** |
| chaos-incarnate | 4.0 | −0.58 (−0.82 to −0.33) | −0.52 |

**What predicts strength in the AI's hands** (rank correlation with measured strength, eleven decks): cheap
non-creature ramp +0.71, evasive creatures +0.54, tutors +0.45, creature count +0.40; speed (curve) about 0;
interaction −0.25, card draw −0.39, **graveyard recursion −0.65** (Wilhelt and Grave Danger). The XMage AI wins with
proactive creature decks that ramp early; it gets little from removal, draw or graveyard lines. Recursion is
therefore weighted 0 and interaction kept small.

**How far card counts go.** Refitting the weights on ten decks and predicting the eleventh (leave-one-out), the
formula's error is 0.28 log-odds against 0.37 for calling every deck average (0.22 with today's weights, but those
were set with all eleven in view). Card counts carry real but limited
signal; the misses above (Edgar, Lathril, Wilhelt) are about how the AI plays a commander's plan, which a card count
cannot see. Measured games have to finish the job (proposal 1 below).

## Forum and data-site research (2026-10-24)

- A deck's own record beats its label: on playgroup.gg (404k logged, mostly four-player human games) a deck's
  first-half results predict its second half far better than its bracket, and about 20 games is enough to beat the
  label. https://playgroup.gg/commander/power-level
- Fast mana counts more in duels: a turn-1 Sol Ring wins 62% of 1v1 games against 50% without (+12.7 points), but only
  +3.7 points in four-player games. https://playgroup.gg/commander/turn-1-sol-ring
- Game Changers give diminishing returns: 0 cards −4.3%, 1–3 +3.3%, 4 or more +10.9% against an average deck in the
  same pods. Finishers like Craterhoof are worth about one point at deck level. https://playgroup.gg/commander/power-level,
  https://playgroup.gg/commander/staples
- Players scale a deck up or down mainly by tutors, fast mana, two-card combos, the curve and tapped lands; mana base
  and budget matter less, strategy most. https://blog.cardkingdom.com/how-to-scale-a-decks-power-level/,
  https://www.reddit.com/r/EDH/comments/ohighs/how_to_lower_your_decks_powerlevel/
- With one opponent, goad is called "absolutely horrendous", and group hug, symmetric effects and taxes weaken;
  spot removal beats sweepers, and cheap commanders that give value at once do best.
  https://www.reddit.com/r/EDH/comments/1c0l81o/what_cards_are_more_powerful_in_1v1_and_which/,
  https://draftsim.com/duel-commander-mtg/
- Published calculators (EDHcheck, Disciple of the Vault's formula, Cardsrealm) weight tutors and cheap ramp most and
  interaction least, and none credit recursion.
- **Where forums and our games disagree:** players value removal density; the AI's games don't. That is likely the
  AI misusing interaction, so it keeps a small weight with an instant-speed bonus rather than zero.

## Every AI deck (formula v1)

33 decks: the 5 precons, the first 21 AI decks, and 7 added on 2026-10-24 to widen the range (Kaalia, Winota, The
First Sliver and Miirym at bracket 4; Marisi and Kynaios and Tiro at bracket 1; Tormod at bracket 2; built by
`scripts/ranked/build_ai_decks.py` from EDHREC's average decks, the first 21 unchanged). Parts are 0–1; Observed is
the measured strength with its 95% interval, where games exist.

| Deck | Bracket | Power | Speed | Mana | Interaction | Consistency | Threats | Synergy | Commander | Combos | Resilience | Observed |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| ai-kaalia-of-the-vast-optimized | 4 | **7.9** | 0.67 | 0.89 | 0.57 | 0.49 | 0.83 | 0.40 | 0.85 | 0.83 | 1.00 |  |
| ai-the-ur-dragon-optimized | 4 | **7.8** | 0.53 | 0.88 | 0.30 | 0.80 | 0.83 | 0.62 | 0.90 | 0.83 | 0.75 |  |
| ai-the-ur-dragon-upgraded | 3 | **7.5** | 0.37 | 0.85 | 0.38 | 0.80 | 0.86 | 0.74 | 0.90 | 0.50 | 0.62 |  |
| ai-gishath-suns-avatar-optimized | 4 | **7.1** | 0.43 | 0.85 | 0.28 | 0.95 | 0.74 | 0.69 | 0.70 | 0.50 | 0.88 |  |
| ai-miirym-sentinel-wyrm-optimized | 4 | **7.0** | 0.49 | 0.84 | 0.57 | 0.56 | 0.71 | 0.49 | 0.75 | 0.67 | 0.25 |  |
| ai-the-ur-dragon-core | 2 | **7.0** | 0.41 | 0.76 | 0.30 | 0.78 | 0.89 | 0.85 | 0.90 | 0.00 | 0.62 | +0.54 ±0.19 |
| ai-gishath-suns-avatar-exhibition | 1 | **6.9** | 0.42 | 0.89 | 0.42 | 0.91 | 0.80 | 0.81 | 0.70 | 0.00 | 0.50 |  |
| ai-gishath-suns-avatar-upgraded | 3 | **6.9** | 0.32 | 0.84 | 0.47 | 0.95 | 0.78 | 0.72 | 0.70 | 0.17 | 0.62 |  |
| ai-edgar-markov-upgraded | 3 | **6.8** | 0.89 | 0.59 | 0.35 | 0.43 | 0.49 | 0.70 | 0.85 | 1.00 | 0.25 |  |
| ai-the-first-sliver-optimized | 4 | **6.8** | 0.92 | 0.73 | 0.12 | 0.72 | 0.41 | 0.72 | 0.85 | 0.83 | 0.62 |  |
| ai-gishath-suns-avatar-core | 2 | **6.7** | 0.38 | 0.85 | 0.33 | 0.98 | 0.76 | 0.74 | 0.70 | 0.00 | 0.50 | +0.46 ±0.17 |
| ai-edgar-markov-optimized | 4 | **6.6** | 0.84 | 0.54 | 0.25 | 0.56 | 0.45 | 0.64 | 0.85 | 1.00 | 0.25 |  |
| ai-winota-joiner-of-forces-optimized | 4 | **6.3** | 1.00 | 0.61 | 0.42 | 0.22 | 0.51 | 0.28 | 0.90 | 0.33 | 1.00 |  |
| ai-wilhelt-the-rotcleaver-optimized | 4 | **6.1** | 0.93 | 0.68 | 0.72 | 0.52 | 0.37 | 0.63 | 0.50 | 0.67 | 0.25 |  |
| ai-edgar-markov-core | 2 | **6.0** | 0.80 | 0.66 | 0.47 | 0.30 | 0.49 | 0.80 | 0.85 | 0.00 | 0.12 | +0.47 ±0.17 |
| ai-lathril-blade-of-the-elves-optimized | 4 | **5.7** | 0.80 | 0.51 | 0.17 | 0.68 | 0.35 | 0.63 | 0.55 | 0.67 | 0.62 |  |
| ai-krenko-mob-boss-optimized | 4 | **5.6** | 1.00 | 0.55 | 0.62 | 0.32 | 0.22 | 0.56 | 0.75 | 0.33 | 0.50 |  |
| draconic-destruction | 2 | **5.5** | 0.39 | 0.43 | 1.00 | 0.38 | 0.69 | 0.61 | 0.60 | 0.00 | 0.25 | -0.08 ±0.19 |
| ai-krenko-mob-boss-upgraded | 3 | **5.5** | 1.00 | 0.52 | 0.62 | 0.30 | 0.27 | 0.70 | 0.75 | 0.17 | 0.50 |  |
| ai-lathril-blade-of-the-elves-exhibition | 1 | **5.5** | 0.69 | 0.67 | 0.35 | 0.61 | 0.38 | 0.89 | 0.55 | 0.00 | 0.50 |  |
| ai-wilhelt-the-rotcleaver-upgraded | 3 | **5.4** | 0.84 | 0.60 | 0.57 | 0.24 | 0.40 | 0.78 | 0.50 | 0.17 | 0.50 |  |
| ai-krenko-mob-boss-exhibition | 1 | **5.4** | 1.00 | 0.53 | 0.68 | 0.23 | 0.26 | 0.87 | 0.75 | 0.00 | 0.38 |  |
| ai-krenko-mob-boss-core | 2 | **5.3** | 1.00 | 0.52 | 0.60 | 0.28 | 0.25 | 0.84 | 0.75 | 0.00 | 0.38 | +0.00 ±0.26 |
| ai-lathril-blade-of-the-elves-upgraded | 3 | **5.3** | 0.68 | 0.57 | 0.30 | 0.48 | 0.38 | 0.69 | 0.55 | 0.17 | 0.88 |  |
| first-flight | 2 | **5.3** | 0.44 | 0.52 | 0.70 | 0.47 | 0.64 | 0.56 | 0.45 | 0.00 | 0.12 | +0.20 ±0.17 |
| ai-lathril-blade-of-the-elves-core | 2 | **5.3** | 0.62 | 0.62 | 0.35 | 0.48 | 0.39 | 0.85 | 0.55 | 0.00 | 0.75 | -0.29 ±0.17 |
| ai-wilhelt-the-rotcleaver-core | 2 | **4.7** | 0.72 | 0.51 | 0.35 | 0.20 | 0.36 | 1.00 | 0.50 | 0.00 | 0.25 | -0.50 ±0.16 |
| grave-danger | 2 | **4.6** | 0.37 | 0.47 | 0.57 | 0.24 | 0.41 | 0.86 | 0.50 | 0.00 | 0.25 | -0.22 ±0.16 |
| token-triumph | 2 | **4.4** | 0.54 | 0.55 | 0.30 | 0.53 | 0.31 | 0.20 | 0.40 | 0.00 | 0.25 | -0.02 ±0.20 |
| ai-tormod-the-desecrator-core | 2 | **4.4** | 1.00 | 0.28 | 0.33 | 0.48 | 0.32 | 1.00 | 0.35 | 0.00 | 0.00 |  |
| ai-kynaios-and-tiro-of-meletis-exhibition | 1 | **4.3** | 0.79 | 0.74 | 0.33 | 1.00 | 0.17 | 0.37 | 0.20 | 0.00 | 0.12 |  |
| ai-marisi-breaker-of-the-coil-exhibition | 1 | **4.0** | 0.84 | 0.42 | 0.45 | 0.47 | 0.33 | 0.00 | 0.35 | 0.00 | 0.62 |  |
| chaos-incarnate | 2 | **4.0** | 0.37 | 0.49 | 0.72 | 0.54 | 0.37 | 0.00 | 0.30 | 0.00 | 0.12 | -0.58 ±0.24 |

## Ladder coverage (formula only, superseded by Power v2)

| Tier | Target | Allowed brackets | Decks in reach today |
|---|---|---|---|
| Bronze | 3–4 | ≤ 2 | Chaos Incarnate 4.0, Marisi 4.0 (new); Kynaios and Tiro 4.3, Tormod 4.4 (new) just above: **thin** |
| Silver | 4–5 | ≤ 2 | Token Triumph 4.4, Grave Danger 4.6, Wilhelt Core 4.7, plus the three new gentle decks |
| Gold | 5–6 | ≤ 3 | many (Krenko, Lathril, First Flight, Draconic, Wilhelt Upgraded, Edgar Core) |
| Platinum | 6–7 | ≤ 3 | Edgar Core and Upgraded, Gishath Core/Exhibition/Upgraded, Ur-Dragon Core |
| Diamond | 7–8 | ≤ 4 | Ur-Dragon Core/Upgraded/Optimized, Gishath Optimized, Miirym 7.0 and Kaalia 7.9 (new) |
| Mythic | 8–9 | ≤ 4 | **none by formula** (Kaalia 7.9, Ur-Dragon Optimized 7.8) |

The formula compresses the top: no EDHREC average deck maxes most parts at once, so even the new bracket-4 decks rate
6.3–7.9. Whether they play at Mythic strength is for the games to show; if the ladder keeps the formula's numbers, its
targets need to move down to the range the pool covers (proposal 3).

Brackets and Power disagree inside commanders: Gishath Exhibition (bracket 1) rates 6.9 and Krenko Optimized
(bracket 4) 5.6, because the commander's archetype matters more to the AI than the upgrades. No Exhibition, Upgraded
or Optimized deck has been measured yet.

## Proposals (for Caleb, after the cloud numbers)

1. **Blend measured games into Power.** For each deck, Power = the formula, moved toward its measured strength in
   proportion to how many games it has (precision-weighted: the formula counts like about 20–25 games). Decks with
   hundreds of games are rated by their games; a new deck starts from the formula. This is what fixes Edgar, Lathril
   and Wilhelt, and it makes the full gauntlet worth running.
2. **Fill the ends of the ladder.** Done as a first step (Caleb, 2026-10-24): seven decks added, chosen from 17
   EDHREC candidates rated by the formula: proactive creature decks the AI should play well for the top (Kaalia,
   Winota, The First Sliver, Miirym), and plans the AI plays weakly with one opponent for the bottom (Marisi's goad,
   Kynaios and Tiro's group hug, Tormod's graveyard). The gauntlet decides whether they stay. They already join the
   bracket pools the apps pick from today (bracket 4 for the top four), so each needs its games before a release.
3. **Ladder targets follow the scale.** The formula's range today is 4.0–7.8; once proposal 1 rates decks by games,
   set the tier targets on that scale (one Power point ≈ 59% against a deck one point lower).

## Calibration

- The formula against 2,986 earlier games (C3, C4).
- **Gauntlet, 2026-10-25:** 1,236 games, every AI deck against First Flight, Token Triumph and Grave Danger at skill 3
  (brief `docs/cloud/power-gauntlet.md`, report `docs/cloud/reports/power-1.md`, data `docs/cloud/power-results/`).
- **Skill test:** nine decks at skill 3 without mistakes (batch C, 324 games, done) and at skill 5 (batch D, running);
  brief `docs/cloud/power-skill-test.md`, report `docs/cloud/reports/power-2.md`, data `docs/cloud/skill-results/`
  (kept out of the ratings).
- Rerun `deck_power.py rate --write` after any new games in `power-results/`.

## Built (2026-10-25, branch `claude/deck-power-design`, not released)

Caleb: "do what is best and get … around 5 per rank".

- **Data.** `deck_power.py rate --write` writes `scripts/ranked/deck-power-ratings.json` and the `power` block of
  `apps/ios/MagicMobile/Resources/ai-decks.json` (each deck's Power, the tier bands, Quick Match's levels, `closest`);
  `build_ai_decks.py` keeps that block when it rebuilds the decks. iOS, Android and web already bundle the file.
- **Picking** (`AIDeckPool.pick(targetPower:)` on iOS, `AIDeckPool.pickByPower` on Android and web): decks with a
  Power and a bracket at most the tier's (none for Quick Match), never your commander and not a recent deck while
  others remain, then a random one of the three nearest the target. `parity/power-cases.json` holds the shared cases.
- **Ranked:** each division aims at its tier's band (Bronze IV 3.1 … Diamond I 7.9, Mythic 8.5) with the tier's AI
  skill. Bronze picks by Power too; the precons-only rule is only the fallback for a pool without Power data.
- **Tuned on the server (2026-10-26):** `ranked_ai_tuning` (Supabase) holds each tier's Power band and the AI's mistake
  chance from division IV to I. The ranked ticket (`mm_ranked_ai_start2`) carries the game's `aiSkill`,
  `aiMistakePercent` and `aiPower`; apps that read it pick the AI deck by that Power and send `aiMistakePercent` to the
  engine (an existing per-seat override, no engine change). Bundled bands are the fallback for older apps and offline
  play. Retune with one row update, no build:
  `update public.ranked_ai_tuning set power_low=…, power_high=…, mistakes_division_iv=…, mistakes_division_i=…, updated_at=now() where tier=2;`
  First tuning: Gold 5.5–6.5 (was 5–6), mistakes 8% at Gold IV down to 5% at Gold I (was 10%), after Gold players won
  59–72% against skills 1–3. Second tuning, same day (a player climbed Gold in hours): Gold 6–7 with mistakes 5% at
  Gold IV down to 2% at Gold I, Platinum 7–8 (was 6–7), Diamond 7.5–8.5 (was 7–8). Review after about 50 games. Third tuning (2026-10-28, 254DADDY: "getting out of Platinum is too hard"): he won 45 of 82 Platinum games
  against Power 7.1–7.4 with no mistakes and still lost two pips (23 of his 37 losses were crushing), so Platinum runs
  6.75–7.75 (IV 6.88 … I 7.63, from Gold I to Diamond IV) with mistakes 2% at IV down to 0% at I, and a crushing loss
  costs one pip there (docs/RANKED.md). Hardest for him: The Ur-Dragon (he went 4–6) and Gishath (8–8). Web reads the ticket now; iOS and Android from their next
  build (iOS 62 and Android 40 keep the bundled values, which the record check still accepts).
  Fourth tuning (2026-10-29, migration `ranked_diamond_retune`): 254DADDY's Miirym deck won 27 of 39 against Platinum
  and 15 of 21 against Diamond, so Diamond played no harder. The table gained `ai_skill` (null keeps the ladder's
  skill); Diamond plays at skill 6 with Power 8–9 (IV 8.13 … I 8.88), and Mythic runs 8.75–9.75 (9.25) to stay above it.
- **Quick Match:** Easy (Power 3.5, skill 2), Medium (5.5, skill 3, the default) or Hard (7.5, skill 5) as pill gems;
  Advanced shows today's bracket gems, deck row and skill stepper.
- **Decks:** 41 AI decks. The eight added on 2026-10-25 (Tiamat, Lathliss, Old Gnawbone, Phelddagrif, Zedruu,
  Karador, Meren, Marisi Core) are rated by the formula alone until `docs/cloud/power-new-decks.md` runs, and the
  formula overrates gentle decks, so that run is needed before a release.

Checks: web 316 tests; Android `RankedParityTest` and `RankedStandingTest` (22) and the app compile; iOS app and test
bundle compile for the simulator (`RankedParityTests` not run: no simulator booted). No phone or UI check yet.
