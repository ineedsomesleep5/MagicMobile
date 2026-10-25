"""Unit tests for deck_power.py (the formula's pieces and the strength fit; real catalogue, no engine)."""
import json
import random
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import deck_power as dp  # noqa: E402

CONFIG = json.loads(dp.WEIGHTS.read_text())


class FormulaTests(unittest.TestCase):
    def test_lin_clamps_both_directions(self):
        self.assertEqual(dp.lin(5, 0, 10), 0.5)
        self.assertEqual(dp.lin(-1, 0, 10), 0.0)
        self.assertEqual(dp.lin(2, 4.6, 2.6), 1.0)  # lower is better for mana value

    def test_weights_cover_every_part(self):
        self.assertEqual(set(CONFIG['weights']), set(dp.PARTS))
        self.assertAlmostEqual(sum(CONFIG['weights'].values()), 1.0, places=6)

    def test_every_ai_deck_rates_between_1_and_10(self):
        rated = dp.rate_all(CONFIG)
        self.assertEqual(len(rated), 33)
        for deck in rated:
            self.assertTrue(1 <= deck['power'] <= 10, deck['id'])
            self.assertTrue(all(0 <= v <= 1 for v in deck['parts'].values()), deck['id'])

    def test_cheat_outs_lower_the_effective_curve(self):
        cards = dp.Cards()
        big = [('Craterhoof Behemoth', 1), ('Old Gnawbone', 1), ('Forest', 36)]
        plain = {'id': 'x', 'commander': 'Krenko, Mob Boss', 'cards': big}
        cheated = {'id': 'y', 'commander': 'Krenko, Mob Boss', 'cards': big + [('Sneak Attack', 1), ('Natural Order', 1)]}
        p = dp.analyse(plain, cards, CONFIG)['counts']
        c = dp.analyse(cheated, cards, CONFIG)['counts']
        self.assertEqual(p['effectiveManaValue'], p['manaValue'])
        self.assertGreaterEqual(c['cheat'], 2)
        self.assertLess(c['effectiveManaValue'], c['manaValue'])


class RatingTests(unittest.TestCase):
    def test_ratings_cover_every_deck_and_anchor_the_references(self):
        rated = dp.rate(CONFIG)
        self.assertEqual(len(rated), 33)
        refs = [r['power'] for r in rated if r['id'] in CONFIG['scale']['referenceDecks']]
        self.assertAlmostEqual(sum(refs) / len(refs), CONFIG['scale']['referencePower'], delta=0.1)
        for r in rated:
            low, high = r['powerRange']
            self.assertTrue(1 <= low <= r['power'] <= high <= 10, r['id'])

    def test_games_narrow_the_range(self):
        rated = {r['id']: r for r in dp.rate(CONFIG)}
        many, few = rated['grave-danger'], rated['ai-tormod-the-desecrator-core']
        self.assertGreater(many['games'], 10 * few['games'])
        self.assertLess(many['powerRange'][1] - many['powerRange'][0], few['powerRange'][1] - few['powerRange'][0])


class StrengthTests(unittest.TestCase):
    def test_bradley_terry_recovers_order_and_first_player(self):
        rng = random.Random(3)
        truth = {'a': 0.6, 'b': 0.0, 'c': -0.6}
        games = []
        for i in range(3000):
            x, y = rng.sample(sorted(truth), 2)
            first = 'A' if i % 2 else 'B'
            logit = truth[x] - truth[y] + (0.5 if first == 'A' else -0.5)
            winner = 'A' if rng.random() < 1 / (1 + 2.718281828 ** -logit) else 'B'
            games.append({'deck_a': x, 'deck_b': y, 'first': first, 'winner': winner, 'file': 'f.csv'})
        fit = dp.bradley_terry(games)
        s = fit['strength']
        self.assertGreater(s['a'], s['b'])
        self.assertGreater(s['b'], s['c'])
        self.assertAlmostEqual(s['a'] - s['c'], 1.2, delta=0.25)
        self.assertAlmostEqual(fit['first'], 0.5, delta=0.15)


if __name__ == '__main__':
    unittest.main()
