#!/usr/bin/env python3
"""Deck Power: a hidden 1-10 rating of how strongly each AI deck plays (docs/DECK_POWER.md).

Only AI decks are rated: the five precons (PreconCatalog.swift) and ai-decks.json. Each part scores 0-1
between the norms in deck-power-weights.json, and the weighted mix maps to 1-10. Cards come from the iOS
catalogue (types, oracle text, mana value, Scryfall role tags); creature power and toughness, which the
catalogue lacks, come from card-stats.tsv (pinned XMage's Utils/mtg-cards-data.txt, see `stats`).

  rate    each deck's Power from its own games, the formula filling in (--write saves deck-power-ratings.json)
  ladder  the decks each Ranked division and Quick Match level would bring at those ratings
  table   Markdown table of every AI deck's formula parts and formula Power (--json for the numbers)
  check   formula Power against AI-vs-AI results (docs/cloud/*-results CSVs): a Bradley-Terry strength per deck
  fit     search the weights for the best match to those results (--write saves them)
  stats   refresh card-stats.tsv from an XMage checkout's mtg-cards-data.txt
"""
from __future__ import annotations
import argparse, collections, csv, json, math, random, re, sys
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent
WEIGHTS = HERE / 'deck-power-weights.json'
STATS = HERE / 'card-stats.tsv'
RATINGS = HERE / 'deck-power-ratings.json'
RESOURCES = REPO / 'apps/ios/MagicMobile/Resources'
RESULTS = [REPO / 'docs/cloud/c3-results', REPO / 'docs/cloud/c4-results', REPO / 'docs/cloud/power-results']
PARTS = ('speed', 'mana', 'interaction', 'consistency', 'threats', 'synergy', 'commander', 'combos', 'resilience')

# Cheating big cards out (Caleb): what makes a high curve play faster than it looks.
FREE = re.compile(r'cascade|discover \d|ripple|without paying (its|their) mana cost', re.I)
CHEAT = re.compile(r'put (a|an|any number of|up to \w+|that|those|target)[^.]*?(creature|permanent|Dragon|Dinosaur|Elf|'
                   r'Goblin|Zombie|Vampire)[^.]*?cards?[^.]*? onto the battlefield|'
                   r'search your library for [^.]*creature cards?[^.]* put (it|them|that card) onto the battlefield', re.I)
REANIMATE = re.compile(r'(return|put) target creature card[^.]*graveyard[^.]*(to|onto) the battlefield|'
                       r'creature cards? from (your|a|all) graveyards?[^.]*onto the battlefield', re.I)
SELF_REDUCE = re.compile(r'convoke|affinity for|delve|improvise|(this spell|\{this\}) costs? \{\w+\} less', re.I)
REDUCE = re.compile(r'spells? you cast costs? \{\d\} less|spells? (you cast )?cost \{\d\} less', re.I)
RITUAL = re.compile(r'(?m)^Add \{[WUBRGC]\}\{[WUBRGC]\}|Add \{[WUBRGC]\} for each')
# A keyword line (no full stop) with an evasion keyword, or an unblockable clause.
EVASION = re.compile(r'(?mi)^[^.\n]*\b(flying|trample|menace|shadow|intimidate|fear|horsemanship)\b[^.\n]*$|can\'t be blocked')
FINISHER = re.compile(r'creatures you control (get \+|gain (trample|double strike|flying))|additional combat|'
                      r'each opponent loses (\d+|X) life', re.I)
# Cards that are weak with one opponent (forum consensus, docs/DECK_POWER.md): goad, group hug, symmetric draw, taxes.
MULTIPLAYER = re.compile(r"\bgoad|myriad|each player draws|unless (that player|they|its controller) pays?|will of the council|"
                         r"council's dilemma|\btempt\b|each opponent may draw|each other player (may|discards)", re.I)
TAPPED = re.compile(r'enters (the battlefield )?tapped', re.I)
CONDITIONAL = re.compile(r'unless|you may pay|you may reveal|if you control', re.I)


def lin(value: float, zero: float, one: float) -> float:
    """0 at `zero`, 1 at `one` (either direction), clamped."""
    return max(0.0, min(1.0, (value - zero) / (one - zero)))


def mix(values, shares) -> float:
    return sum(v * s for v, s in zip(values, shares)) / sum(shares)


def load_decks() -> list[dict]:
    """The AI pool as the apps ship it: precons first, then ai-decks.json."""
    decks = []
    swift = (REPO / 'apps/ios/MagicMobile/PreconCatalog.swift').read_text()
    for match in re.finditer(r'id: "([^"]+)",\s*name: "([^"]+)",.*?commander: "([^"]+)",.*?rawList: """\n(.*?)"""', swift, re.S):
        deck_id, name, commander, raw = match.groups()
        cards = []
        for line in raw.splitlines():
            if line.strip():
                count, card = line.strip().split(' ', 1)
                cards.append((card, int(count)))
        decks.append({'id': deck_id, 'name': name, 'commander': commander, 'bracket': 2, 'precon': True, 'cards': cards})
    if len(decks) != 5:
        raise SystemExit('Expected the 5 precons in PreconCatalog.swift; the parser needs updating')
    for deck in json.loads((RESOURCES / 'ai-decks.json').read_text())['decks']:
        decks.append({'id': deck['id'], 'name': deck['name'], 'commander': deck['commander'], 'bracket': deck['bracket'],
                      'precon': False, 'cards': [(e['name'], e['quantity']) for e in deck['entries']]})
    return decks


class Cards:
    def __init__(self):
        catalogue = json.loads((RESOURCES / 'ondevice-catalogue.json').read_text())
        self.meta, self.aliases = catalogue['cardMetadata'], catalogue.get('nameAliases') or {}
        self.stats = {}
        if STATS.exists():
            for line in STATS.read_text().splitlines()[1:]:
                name, power, toughness = line.split('\t')
                self.stats[name] = (power, toughness)
        rules = json.loads((RESOURCES / 'commander-brackets.json').read_text())
        self.game_changers, self.combos = set(rules['gameChangers']), rules['combos']

    def card(self, name: str) -> dict:
        for candidate in (name, self.aliases.get(name, ''), name.split(' // ')[0]):
            if candidate in self.meta:
                return self.meta[candidate]
        raise SystemExit(f'{name} is not in the catalogue')

    def power(self, name: str) -> int:
        stat = self.stats.get(name) or self.stats.get(name.split(' // ')[0])
        if stat is None:
            raise SystemExit(f'No power for creature {name}: run `deck_power.py stats --card-data <mtg-cards-data.txt>`')
        return int(stat[0]) if stat[0].lstrip('-').isdigit() else 0


def analyse(deck: dict, cards: Cards, config: dict) -> dict:
    """Counts, then each part's 0-1 score."""
    norms = config['norms']
    commander = config['commanders'].get(deck['commander'], config['defaultCommander'])
    theme = re.compile(r'\b(' + '|'.join(commander.get('theme') or [deck['commander'].split(',')[0]]) + r')', re.I)
    c = collections.Counter()
    nonland = []
    for name, quantity in deck['cards']:
        meta = cards.card(name)
        text, types, roles = meta.get('oracleText') or '', meta['types'], set(meta.get('roles') or [])
        if 'LAND' in types:
            c['lands'] += quantity
            if TAPPED.search(text):
                c['tapped'] += quantity * (0.5 if CONDITIONAL.search(text) else 1)
            continue
        is_commander = name == deck['commander']
        copies = quantity * (norms['cheats']['commanderCopies'] if is_commander else 1)
        creature = 'CREATURE' in types
        nonland.append((meta['manaValue'], creature, bool(SELF_REDUCE.search(text)), quantity))
        c['cheap'] += quantity if meta['manaValue'] <= 2 else 0
        if 'ramp' in roles:
            c['ramp'] += quantity
            # Cheap rocks and land spells (Sol Ring, Signets, Rampant Growth) are the reliable ramp; mana creatures die.
            kind = 'creatureRamp' if creature else 'cheapRamp' if meta['manaValue'] <= 2 else 'otherRamp'
            c[kind] += quantity
        if 'interaction' in roles or 'boardWipe' in roles:
            # Spot removal and counters beat sweepers with one opponent; a wipe-only card counts part.
            c['interaction'] += quantity * (1 if 'interaction' in roles else norms['interaction']['wipeFactor'])
            c['instant'] += quantity if 'INSTANT' in types or re.search(r'(?m)^Flash', text) else 0
        for role, key in (('cardFlow', 'draw'), ('tutor', 'tutors'), ('protection', 'protection'), ('recursion', 'recursion')):
            c[key] += quantity if role in roles else 0
        if creature:
            c['creatures'] += quantity
            c['big'] += quantity if cards.power(name) >= norms['threats']['bigPower'] else 0
            c['evasive'] += quantity if EVASION.search(text) else 0
        c['finishers'] += quantity if FINISHER.search(text) else 0
        if not is_commander and (theme.search(meta.get('typeLine') or '') or theme.search(text) or 'Changeling' in text):
            c['themed'] += quantity
        for pattern, key in ((FREE, 'free'), (CHEAT, 'cheat'), (REANIMATE, 'reanimate'), (RITUAL, 'ritual')):
            c[key] += copies if pattern.search(text) else 0
        c['reduce'] += copies if REDUCE.search(text) and not SELF_REDUCE.search(text) else 0
        c['gameChangers'] += quantity if name in cards.game_changers else 0
        c['multiplayer'] += quantity if MULTIPLAYER.search(text) else 0
    names = {name for name, _ in deck['cards']}
    c['combos'] = sum(1 for combo in cards.combos if set(combo['cards']) <= names)

    # The effective curve: big cards cost less when the deck cheats them out or reduces their cost.
    k = norms['cheats']
    share = lambda enablers: k['maxShare'] * min(1.0, enablers / k['saturation'])
    creature_share = share(c['reduce'] + c['cheat'] + c['reanimate'] + c['free'] + c['ritual'])
    other_share = share(c['reduce'] + c['free'] + c['ritual'])
    total = weight = 0.0
    for mana_value, creature, self_reduce, quantity in nonland:
        effective = max(1, mana_value - k['selfDiscount']) if self_reduce else mana_value
        if mana_value >= k['bigManaValue'] and effective > k['keep']:
            effective -= (effective - k['keep']) * (creature_share if creature else other_share)
        total += effective * quantity
        weight += quantity
    c['nonland'] = int(weight)
    c['effectiveManaValue'] = total / weight
    c['manaValue'] = sum(m * q for m, _, _, q in nonland) / weight

    n = norms
    ideal_lands = n['mana']['idealLands'] - n['mana']['landsPerRamp'] * c['ramp']
    parts = {
        'speed': mix([lin(c['effectiveManaValue'], *n['speed']['effectiveManaValue']), lin(c['cheap'], *n['speed']['cheapPlays'])],
                     n['speed']['mix']),
        'mana': mix([lin(c['cheapRamp'] * n['mana']['cheapRampFactor'] + c['otherRamp'] + c['creatureRamp'] * n['mana']['creatureRampFactor'],
                         *n['mana']['ramp']),
                     1 - min(1.0, abs(c['lands'] - ideal_lands) / n['mana']['landSpread']),
                     1 - lin(c['tapped'] / max(1, c['lands']), *n['mana']['tappedShare'])], n['mana']['mix']),
        'interaction': lin(c['interaction'] + n['interaction']['instantBonus'] * c['instant'], *n['interaction']['count']),
        'consistency': mix([lin(c['draw'], *n['consistency']['draw']), lin(c['tutors'], *n['consistency']['tutors'])],
                           n['consistency']['mix']),
        'threats': mix([lin(c['evasive'], *n['threats']['evasive']), lin(c['big'], *n['threats']['big']),
                        lin(c['finishers'], *n['threats']['finishers']), lin(c['creatures'], *n['threats']['creatures'])],
                       n['threats']['mix']),
        'synergy': lin(c['themed'] / weight, *n['synergy']['themeShare']),
        'commander': commander['strength'],
        # Game Changers give diminishing returns past the first few (playgroup.gg: +3% for 1-3, +11% for 4+).
        'combos': lin(c['combos'] * n['combos']['comboPoints'] + min(c['gameChangers'], n['combos']['gameChangersFull'])
                      + n['combos']['gameChangerBeyond'] * max(0, c['gameChangers'] - n['combos']['gameChangersFull']),
                      *n['combos']['points']),
        'resilience': mix([lin(c['protection'], *n['resilience']['protection']), lin(c['recursion'], *n['resilience']['recursion'])],
                          n['resilience']['mix']),
    }
    penalty = config['penalties']['multiplayerCards']
    return {'counts': dict(c), 'parts': parts, 'penalty': min(penalty['max'], penalty['perCard'] * c['multiplayer'])}


def power(parts: dict, weights: dict, penalty: float = 0.0) -> float:
    total = sum(weights[p] for p in PARTS)
    return max(1.0, 1 + 9 * sum(parts[p] * weights[p] for p in PARTS) / total - penalty)


def rate_all(config: dict) -> list[dict]:
    cards = Cards()
    rated = []
    for deck in load_decks():
        result = analyse(deck, cards, config)
        rated.append({'id': deck['id'], 'name': deck['name'], 'commander': deck['commander'], 'bracket': deck['bracket'],
                      'precon': deck['precon'], **result,
                      'power': round(power(result['parts'], config['weights'], result['penalty']), 2)})
    return rated


# Observed strength: AI-vs-AI games on the JVM engine (scripts/ai_calibration.py CSVs).

def read_games(roots=RESULTS) -> list[dict]:
    games = []
    for root in roots:
        for path in sorted(root.rglob('*.csv')) if root.exists() else []:
            with path.open() as stream:
                for row in csv.DictReader(stream):
                    if row.get('end') == 'ended' and row['winner'] in ('A', 'B'):
                        games.append({**row, 'file': str(path.relative_to(REPO))})
    return games


def bradley_terry(games: list[dict], iterations: int = 400) -> dict:
    """Deck strengths (log-odds, mean 0) with a going-first term and one seat-A term per CSV (its skill gap).

    Newton steps on the diagonal; returns strength and a standard error per deck."""
    decks = sorted({g['deck_a'] for g in games} | {g['deck_b'] for g in games})
    files = sorted({g['file'] for g in games})
    s = {d: 0.0 for d in decks}
    seat = {f: 0.0 for f in files}
    first = 0.0
    for _ in range(iterations):
        grad = collections.Counter(); hess = collections.Counter()
        for g in games:
            sign = 1 if g['first'] == 'A' else -1
            x = s[g['deck_a']] - s[g['deck_b']] + first * sign + seat[g['file']]
            p = 1 / (1 + math.exp(-x))
            y = 1 if g['winner'] == 'A' else 0
            w = p * (1 - p)
            for key, direction in ((g['deck_a'], 1), (g['deck_b'], -1), ('first', sign), ('file:' + g['file'], 1)):
                grad[key] += (y - p) * direction
                hess[key] += w
        for d in decks:
            s[d] += grad[d] / (hess[d] + 0.5) - 0.01 * s[d]  # a weak prior keeps unbeaten decks finite
        first += grad['first'] / (hess['first'] + 0.5)
        for f in files:
            seat[f] += grad['file:' + f] / (hess['file:' + f] + 0.5)
        mean = sum(s.values()) / len(s)
        s = {d: v - mean for d, v in s.items()}
    info = collections.Counter(); count = collections.Counter()
    for g in games:
        sign = 1 if g['first'] == 'A' else -1
        p = 1 / (1 + math.exp(-(s[g['deck_a']] - s[g['deck_b']] + first * sign + seat[g['file']])))
        for d in (g['deck_a'], g['deck_b']):
            info[d] += p * (1 - p)
            count[d] += 1
    return {'strength': s, 'se': {d: 1 / math.sqrt(info[d]) for d in decks}, 'games': dict(count), 'first': first}


def slope_fit(rated: list[dict], observed: dict) -> tuple[float, float]:
    """Least-squares line from Power to observed strength, weighted by precision."""
    points = [(r['power'], observed['strength'][r['id']], observed['se'][r['id']]) for r in rated if r['id'] in observed['strength']]
    w = [1 / se ** 2 for _, _, se in points]
    mx = sum(wi * p for wi, (p, _, _) in zip(w, points)) / sum(w)
    my = sum(wi * o for wi, (_, o, _) in zip(w, points)) / sum(w)
    sxx = sum(wi * (p - mx) ** 2 for wi, (p, _, _) in zip(w, points))
    sxy = sum(wi * (p - mx) * (o - my) for wi, (p, o, _) in zip(w, points))
    slope = sxy / sxx if sxx else 0.0
    return slope, my - slope * mx


def spearman(xs, ys) -> float:
    def ranks(v):
        order = sorted(range(len(v)), key=lambda i: v[i])
        out = [0.0] * len(v)
        for rank, i in enumerate(order):
            out[i] = rank
        return out
    rx, ry = ranks(xs), ranks(ys)
    n = len(xs)
    mx, my = sum(rx) / n, sum(ry) / n
    num = sum((a - mx) * (b - my) for a, b in zip(rx, ry))
    den = math.sqrt(sum((a - mx) ** 2 for a in rx) * sum((b - my) ** 2 for b in ry))
    return num / den if den else 0.0


def wilson(wins: int, n: int, z: float = 1.96) -> tuple[float, float]:
    if not n:
        return 0.0, 1.0
    p = wins / n
    d = 1 + z * z / n
    centre = (p + z * z / (2 * n)) / d
    half = z * math.sqrt(p * (1 - p) / n + z * z / (4 * n * n)) / d
    return centre - half, centre + half


def round_robin(rated: list[dict], slope: float) -> list[str]:
    """C3's precon round robin (docs/cloud/reports/c3.md): each precon's predicted win rate, from Power alone, against
    the measured one and its interval. Each pairing has both seatings equally, so going first cancels."""
    games = [g for g in read_games([REPO / 'docs/cloud/c3-results'])
             if g['file'].endswith('precon-round-robin.csv')]
    power_of = {r['id']: r['power'] for r in rated}
    lines = ['| Precon | Power | Predicted | Measured (95% CI) | Fits |', '|---|---|---|---|---|']
    decks = sorted({g['deck_a'] for g in games} | {g['deck_b'] for g in games}, key=lambda d: -power_of[d])
    fits = 0
    for deck in decks:
        mine = [g for g in games if deck in (g['deck_a'], g['deck_b'])]
        wins = sum(1 for g in mine if (g['deck_a'] if g['winner'] == 'A' else g['deck_b']) == deck)
        opponents = [g['deck_b'] if g['deck_a'] == deck else g['deck_a'] for g in mine]
        predicted = sum(1 / (1 + math.exp(-slope * (power_of[deck] - power_of[o]))) for o in opponents) / len(opponents)
        low, high = wilson(wins, len(mine))
        fit = low <= predicted <= high
        fits += fit
        lines.append(f'| {deck} | {power_of[deck]:.1f} | {predicted:.0%} | {wins / len(mine):.0%} ({low:.0%}–{high:.0%}) | '
                     f'{"yes" if fit else "**no**"} |')
    lines.append(f'\n{fits} of {len(decks)} precons inside their interval.')
    return lines


def check(config: dict, quiet: bool = False) -> dict:
    rated = rate_all(config)
    observed = bradley_terry(read_games())
    slope, intercept = slope_fit(rated, observed)
    measured = [r for r in rated if r['id'] in observed['strength']]
    inside = 0
    lines = ['| Deck | Power | Observed strength (95% CI) | From Power | Games | Fits |', '|---|---|---|---|---|---|']
    for r in sorted(measured, key=lambda r: -observed['strength'][r['id']]):
        o, se = observed['strength'][r['id']], observed['se'][r['id']]
        predicted = slope * r['power'] + intercept
        fit = abs(predicted - o) <= 1.96 * se
        inside += fit
        lines.append(f"| {r['id']} | {r['power']:.1f} | {o:+.2f} ({o - 1.96 * se:+.2f} to {o + 1.96 * se:+.2f}) | {predicted:+.2f} | "
                     f"{observed['games'][r['id']]} | {'yes' if fit else '**no**'} |")
    # Pairs the games separate clearly: Power must order them the same way.
    pairs = wrong = 0
    for a in measured:
        for b in measured:
            oa, ob = observed['strength'][a['id']], observed['strength'][b['id']]
            if oa - ob > 1.96 * math.hypot(observed['se'][a['id']], observed['se'][b['id']]):
                pairs += 1
                wrong += a['power'] <= b['power']
    rho = spearman([r['power'] for r in measured], [observed['strength'][r['id']] for r in measured])
    summary = {'rho': rho, 'inside': inside, 'measured': len(measured), 'pairs': pairs, 'wrong': wrong, 'slope': slope}
    if not quiet:
        print(f"{len(read_games())} decided games; going first is worth {observed['first']:+.2f} log-odds.\n")
        print('\n'.join(lines))
        print(f"\nSpearman {rho:+.2f}; {inside} of {len(measured)} decks inside their interval; {pairs - wrong} of {pairs} "
              f"clearly separated pairs in Power's order. One Power point is {slope:+.2f} log-odds "
              f"({1 / (1 + math.exp(-slope)):.0%} against a deck one point lower).\n")
        print('\n'.join(round_robin(rated, slope)))
    return summary


def fit(config: dict, rounds: int, seed: int) -> dict:
    """Random search over the weights: minimise misfit (precision-weighted squared error of Power's line against the
    observed strengths) plus a pull toward the current weights, so parts without data keep their prior share."""
    rng = random.Random(seed)
    cards = Cards()
    analysed = [(d['id'], *(lambda a: (a['parts'], a['penalty']))(analyse(d, cards, config))) for d in load_decks()]
    observed = bradley_terry(read_games())
    prior = dict(config['weights'])

    def loss(weights):
        powers = [{'id': i, 'power': power(p, weights, pen)} for i, p, pen in analysed]
        slope, intercept = slope_fit(powers, observed)
        err = sum(((slope * r['power'] + intercept - observed['strength'][r['id']]) / observed['se'][r['id']]) ** 2
                  for r in powers if r['id'] in observed['strength'])
        pull = sum((weights[p] - prior[p]) ** 2 for p in PARTS) * 40
        return err + pull + (100 if slope <= 0 else 0)

    best, best_loss = dict(prior), loss(prior)
    for i in range(rounds):
        step = 0.08 * (1 - i / rounds) + 0.01
        trial = {p: max(0.02, best[p] + rng.gauss(0, step)) for p in PARTS}
        total = sum(trial.values())
        trial = {p: round(v / total, 3) for p, v in trial.items()}
        trial_loss = loss(trial)
        if trial_loss < best_loss:
            best, best_loss = trial, trial_loss
    return best


def rate(config: dict) -> list[dict]:
    """Each deck's Power from its own games, with the formula as the starting estimate.

    The formula's line (slope_fit) turns its 1-10 into an expected strength; that estimate counts with the formula's
    out-of-sample error (`scale.formulaErrorLogOdds`), each deck's games with their own standard error, and the two are
    combined by precision. A deck without games keeps the formula's estimate and its full error. Power is then
    `scale.referencePower` plus the strength above the reference decks' average, in units of `scale.pointLogOdds`."""
    scale = config['scale']
    rated = rate_all(config)
    observed = bradley_terry(read_games())
    slope, intercept = slope_fit(rated, observed)
    prior = scale['formulaErrorLogOdds'] ** -2
    for r in rated:
        estimate, precision = slope * r['power'] + intercept, prior
        if r['id'] in observed['strength']:
            measured = observed['se'][r['id']] ** -2
            estimate = (estimate * prior + observed['strength'][r['id']] * measured) / (prior + measured)
            precision += measured
        r['strength'], r['strengthSE'], r['games'] = estimate, precision ** -0.5, observed['games'].get(r['id'], 0)
    references = [r['strength'] for r in rated if r['id'] in scale['referenceDecks']]
    anchor = sum(references) / len(references)
    to_power = lambda s: max(1.0, min(10.0, scale['referencePower'] + (s - anchor) / scale['pointLogOdds']))
    for r in rated:
        r['formulaPower'] = r.pop('power')
        r['power'] = round(to_power(r['strength']), 1)
        r['powerRange'] = [round(to_power(r['strength'] + z * 1.96 * r['strengthSE']), 1) for z in (-1, 1)]
    return sorted(rated, key=lambda r: -r['power'])


def ship_power(rated: list[dict], config: dict):
    """The apps' copy: a `power` block in ai-decks.json (bundled on iOS, Android and web), read by AIDeckPool.

    Ranked aims each division at its tier's band (IV low, I high; Mythic the middle of its band) and allows the tier's
    bracket or lower; Quick Match's levels set a Power and an AI skill. Every app picks among the `closest` decks."""
    path = RESOURCES / 'ai-decks.json'
    data = json.loads(path.read_text())
    lad = config['ladder']
    data['power'] = {
        'source': 'scripts/ranked/deck_power.py rate --write (docs/DECK_POWER.md)',
        'closest': lad['closest'],
        'rankedTiers': [t['power'] for t in lad['tiers']],
        'quickMatch': {q['name'].lower(): {'power': sum(q['power']) / 2, 'skill': q['skill']} for q in lad['quickMatch']},
        'decks': {d['id']: d['power'] for d in sorted(rated, key=lambda d: d['id'])},
    }
    path.write_text(json.dumps(data, indent=1, ensure_ascii=False) + '\n')
    print(f'wrote the power block of {path.relative_to(REPO)}')


def ladder(rated: list[dict], config: dict) -> str:
    """Which decks each Ranked division and Quick Match level would bring: the nearest few allowed decks to the target."""
    few = config['ladder']['closest']
    lines = ['| Tier | Division | Target | Max bracket | Nearest allowed decks (Power) | Gap |', '|---|---|---|---|---|---|']
    for tier in config['ladder']['tiers']:
        low, high = tier['power']
        divisions = ('IV', 'III', 'II', 'I') if tier['name'] != 'Mythic' else ('',)
        for step, division in enumerate(divisions):
            target = low + (high - low) * (step + 0.5) / len(divisions)
            allowed = sorted((r for r in rated if r['bracket'] <= tier['maxBracket']), key=lambda r: abs(r['power'] - target))
            near = allowed[:few]
            gap = abs(near[0]['power'] - target)
            lines.append(f"| {tier['name']} | {division} | {target:.2f} | {tier['maxBracket']} | " +
                         ', '.join(f"{r['id'].removeprefix('ai-')} {r['power']:.1f}" for r in near) +
                         f" | {'**' + format(gap, '.1f') + '**' if gap > 0.5 else format(gap, '.1f')} |")
    lines += ['', '| Quick Match | Power band | Decks in the band |', '|---|---|---|']
    for level in config['ladder']['quickMatch']:
        low, high = level['power']
        inside = [r for r in rated if low <= r['power'] <= high]
        lines.append(f"| {level['name']} | {low}–{high} | {len(inside)}: " +
                     ', '.join(r['id'].removeprefix('ai-') for r in inside) + ' |')
    return '\n'.join(lines)


def table(rated: list[dict], observed: dict | None) -> str:
    head = '| Deck | Bracket | Power | ' + ' | '.join(p.capitalize() for p in PARTS) + ' | Observed |'
    lines = [head, '|' + '---|' * (len(PARTS) + 4)]
    for r in sorted(rated, key=lambda r: -r['power']):
        seen = ''
        if observed and r['id'] in observed['strength']:
            seen = f"{observed['strength'][r['id']]:+.2f} ±{1.96 * observed['se'][r['id']]:.2f}"
        lines.append(f"| {r['id']} | {r['bracket']} | **{r['power']:.1f}** | " +
                     ' | '.join(f"{r['parts'][p]:.2f}" for p in PARTS) + f' | {seen} |')
    return '\n'.join(lines)


def refresh_stats(card_data: Path):
    """Power and toughness of every creature in the AI pool, from XMage's card list (name|set|number|rarity|cost|type|P|T|text)."""
    wanted = set()
    cards = Cards()
    for deck in load_decks():
        for name, _ in deck['cards']:
            if 'CREATURE' in cards.card(name)['types']:
                wanted.add(name)
    found = {}
    for line in card_data.read_text(encoding='utf-8').splitlines():
        fields = line.split('|')
        if len(fields) > 7 and fields[6] != '':
            for name in (fields[0],):
                if name in wanted and name not in found:
                    found[name] = (fields[6], fields[7])
    for name in wanted - set(found):
        front = name.split(' // ')[0]
        for line in card_data.read_text(encoding='utf-8').splitlines():
            fields = line.split('|')
            if fields[0] == front and len(fields) > 7 and fields[6] != '':
                found[name] = (fields[6], fields[7])
                break
    missing = sorted(wanted - set(found))
    STATS.write_text('name\tpower\ttoughness\n' + ''.join(f'{n}\t{p}\t{t}\n' for n, (p, t) in sorted(found.items())))
    print(f'wrote {STATS.relative_to(REPO)}: {len(found)} creatures' + (f'; missing {missing}' if missing else ''))


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = parser.add_subparsers(dest='command', required=True)
    t = sub.add_parser('table')
    t.add_argument('--json', action='store_true', help='every deck with counts, parts and Power')
    sub.add_parser('check')
    r = sub.add_parser('rate')
    r.add_argument('--write', action='store_true', help=f'save the ratings to {RATINGS.name}')
    sub.add_parser('ladder')
    f = sub.add_parser('fit')
    f.add_argument('--rounds', type=int, default=4000)
    f.add_argument('--seed', type=int, default=1)
    f.add_argument('--write', action='store_true', help='save the fitted weights to deck-power-weights.json')
    s = sub.add_parser('stats')
    s.add_argument('--card-data', type=Path, required=True, help="XMage's Utils/mtg-cards-data.txt at the pinned commit")
    args = parser.parse_args()
    config = json.loads(WEIGHTS.read_text())
    if args.command == 'stats':
        refresh_stats(args.card_data)
    elif args.command == 'table':
        rated = rate_all(config)
        if args.json:
            print(json.dumps(rated, indent=1, ensure_ascii=False))
        else:
            games = read_games()
            print(table(rated, bradley_terry(games) if games else None))
    elif args.command == 'check':
        check(config)
    elif args.command == 'rate':
        rated = rate(config)
        print('| Deck | Bracket | Power (95% CI) | Formula | Games |\n|---|---|---|---|---|')
        for d in rated:
            print(f"| {d['id']} | {d['bracket']} | **{d['power']:.1f}** ({d['powerRange'][0]:.1f}–{d['powerRange'][1]:.1f}) | "
                  f"{d['formulaPower']:.1f} | {d['games']} |")
        if args.write:
            keep = ('id', 'bracket', 'power', 'powerRange', 'formulaPower', 'games')
            RATINGS.write_text(json.dumps({'schemaVersion': 1, 'scale': config['scale'],
                                           'decks': [{k: d[k] for k in keep} for d in rated]}, indent=1) + '\n')
            print(f'\nwrote {RATINGS.relative_to(REPO)}')
            ship_power(rated, config)
    elif args.command == 'ladder':
        print(ladder(rate(config), config))
    elif args.command == 'fit':
        weights = fit(config, args.rounds, args.seed)
        print(json.dumps(weights, indent=1))
        check({**config, 'weights': weights})
        if args.write:
            config['weights'] = weights
            WEIGHTS.write_text(json.dumps(config, indent=1, ensure_ascii=False) + '\n')


if __name__ == '__main__':
    main()
