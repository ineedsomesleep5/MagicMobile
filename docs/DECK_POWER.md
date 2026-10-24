# Deck Power

Design agreed with Caleb on 2026-10-24. Nothing here is built yet, and no calibration run has started.

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

## Prototype (2026-10-24)

A first formula (speed by plain average mana value, ramp, draw, interaction, tutors, resilience, game changers; no
threats, synergy, commander, land quality or cheat-outs yet) rated the AI decks 3.6–7.7, rising with bracket. It did
**not** match the C3 precon round robin (`docs/cloud/reports/c3.md`: Draconic Destruction 62% down to Chaos Incarnate
36%): it put Chaos Incarnate near the top and Draconic in the middle. Card-role counts alone miss what wins in the AI's
hands, so the threats, synergy and cheat-out parts matter, and the weights need real games.

Coverage today: nothing reaches Mythic's 8–9 and the gentle end is thin, so a few AI decks will likely be added.

## Calibration (not started)

- Start from data we have: C3's 200 precon games, and finished AI games already stored on the server (deck,
  opponent, result).
- Then small targeted runs (`scripts/ai_calibration.py`), about 50 games on the decks that look wrong, before
  any full gauntlet. The full gauntlet (each AI deck against three reference precons, about 780 games) needs Caleb's
  go-ahead.
- Fit the weights to win rates; Power ordering should match observed strength within the confidence intervals.

## Build order (when approved)

1. Formula and weights as shared data plus parity cases (one JSON every platform tests against, as deck sync does).
2. Power for every AI deck, computed at data-prep time and shipped with `ai-decks.json` and the precons.
3. `AIDeckPool.pick` on iOS, Android and web takes a target Power and keeps the bracket rule above.
4. Ranked: target Power from the rank position. Quick Match: Easy / Medium / Hard with the Advanced toggle.
5. Calibrate, retune the data, add AI decks where the ladder has gaps.
