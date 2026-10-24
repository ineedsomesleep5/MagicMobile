# Deck Power

Design agreed with Caleb on 2026-10-24. Formula v1 exists as a script (below); no app picks decks by Power yet, and the
first targeted calibration games are running in a cloud session.

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

Parts are 0–1; Observed is the measured strength with its 95% interval, where games exist.

| Deck | Bracket | Power | Speed | Mana | Interaction | Consistency | Threats | Synergy | Commander | Combos | Resilience | Observed |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| ai-the-ur-dragon-optimized | 4 | **7.8** | 0.53 | 0.88 | 0.30 | 0.80 | 0.83 | 0.62 | 0.90 | 0.83 | 0.75 |  |
| ai-the-ur-dragon-upgraded | 3 | **7.5** | 0.37 | 0.85 | 0.38 | 0.80 | 0.86 | 0.74 | 0.90 | 0.50 | 0.62 |  |
| ai-gishath-suns-avatar-optimized | 4 | **7.1** | 0.43 | 0.85 | 0.28 | 0.95 | 0.74 | 0.69 | 0.70 | 0.50 | 0.88 |  |
| ai-the-ur-dragon-core | 2 | **7.0** | 0.41 | 0.76 | 0.30 | 0.78 | 0.89 | 0.85 | 0.90 | 0.00 | 0.62 | +0.54 ±0.19 |
| ai-gishath-suns-avatar-exhibition | 1 | **6.9** | 0.42 | 0.89 | 0.42 | 0.91 | 0.80 | 0.81 | 0.70 | 0.00 | 0.50 |  |
| ai-gishath-suns-avatar-upgraded | 3 | **6.9** | 0.32 | 0.84 | 0.47 | 0.95 | 0.78 | 0.72 | 0.70 | 0.17 | 0.62 |  |
| ai-edgar-markov-upgraded | 3 | **6.8** | 0.89 | 0.59 | 0.35 | 0.43 | 0.49 | 0.70 | 0.85 | 1.00 | 0.25 |  |
| ai-gishath-suns-avatar-core | 2 | **6.7** | 0.38 | 0.85 | 0.33 | 0.98 | 0.76 | 0.74 | 0.70 | 0.00 | 0.50 | +0.46 ±0.17 |
| ai-edgar-markov-optimized | 4 | **6.6** | 0.84 | 0.54 | 0.25 | 0.56 | 0.45 | 0.64 | 0.85 | 1.00 | 0.25 |  |
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
| chaos-incarnate | 2 | **4.0** | 0.37 | 0.49 | 0.72 | 0.54 | 0.37 | 0.00 | 0.30 | 0.00 | 0.12 | -0.58 ±0.24 |

## Ladder coverage (provisional, formula only)

| Tier | Target | Allowed brackets | Decks in reach today |
|---|---|---|---|
| Bronze | 3–4 | ≤ 2 | Chaos Incarnate 4.0 only: **thin** |
| Silver | 4–5 | ≤ 2 | Token Triumph 4.4, Grave Danger 4.6, Wilhelt Core 4.7 |
| Gold | 5–6 | ≤ 3 | many (Krenko, Lathril, First Flight, Draconic, Wilhelt Upgraded, Edgar Core) |
| Platinum | 6–7 | ≤ 3 | Edgar Core and Upgraded, Gishath Core/Exhibition/Upgraded, Ur-Dragon Core |
| Diamond | 7–8 | ≤ 4 | Ur-Dragon Core/Upgraded/Optimized, Gishath Optimized: **one commander, mostly** |
| Mythic | 8–9 | ≤ 4 | **none** (strongest is Ur-Dragon Optimized, 7.8) |

Brackets and Power disagree inside commanders: Gishath Exhibition (bracket 1) rates 6.9 and Krenko Optimized
(bracket 4) 5.6, because the commander's archetype matters more to the AI than the upgrades. No Exhibition, Upgraded
or Optimized deck has been measured yet; the cloud batches below are the first.

## Proposals (for Caleb, after the cloud numbers)

1. **Blend measured games into Power.** For each deck, Power = the formula, moved toward its measured strength in
   proportion to how many games it has (precision-weighted: the formula counts like about 20–25 games). Decks with
   hundreds of games are rated by their games; a new deck starts from the formula. This is what fixes Edgar, Lathril
   and Wilhelt, and it makes the full gauntlet worth running.
2. **Fill the ends of the ladder** (decks for `build_ai_decks.py`, proactive creature plans the AI plays well):
   Mythic (bracket 4, Power 8–9): Kaalia of the Vast (cheats evasive Angels, Demons and Dragons into play on attack),
   Winota, Joiner of Forces, The First Sliver (cascade slivers), Najeela, the Blade-Blossom (extra combats).
   Bronze (Power 3–4, bracket 1–2): gentler Exhibition decks with slow mana and few evasive threats; or, cheaper,
   lower Bronze's target to the precons' 4.0–4.5. Diamond also needs a second commander besides The Ur-Dragon.
3. **Ladder targets follow the scale.** The formula's range today is 4.0–7.8; once proposal 1 rates decks by games,
   set the tier targets on that scale (one Power point ≈ 59% against a deck one point lower).

## Calibration

- Done: the formula against 2,986 earlier games (above).
- Running: cloud session `power-calib-1`, skill 3 against 3, phone budget, against three reference precons
  (First Flight, Token Triumph, Grave Danger): batch 1, 192 games on Ur-Dragon Optimized, Gishath Exhibition,
  Krenko Optimized and Edgar Optimized; then batch 2, 96 games on Lathril and Wilhelt Optimized. Results go to
  `docs/cloud/power-results/` and `docs/cloud/reports/power-1.md` on `claude/deck-power-design`.
  `ai_calibration.py run --against` plays each target deck against the references only.
- Not started: the full gauntlet (every AI deck against the three references, about 780 games). It needs Caleb's
  go-ahead.

## Build order (when approved)

1. Formula and weights as shared data plus parity cases (one JSON every platform tests against, as deck sync does).
2. Power for every AI deck, computed at data-prep time and shipped with `ai-decks.json` and the precons.
3. `AIDeckPool.pick` on iOS, Android and web takes a target Power and keeps the bracket rule above.
4. Ranked: target Power from the rank position. Quick Match: Easy / Medium / Hard with the Advanced toggle.
5. Calibrate, retune the data, add AI decks where the ladder has gaps.
