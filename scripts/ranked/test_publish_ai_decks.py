import copy
import unittest

from publish_ai_decks import problems


def deck(name='ai-a', extra=None):
    return {'id': name, 'entries': [{'name': 'Lord', 'quantity': 1, 'section': 'commander'}, {'name': extra or 'Swamp', 'quantity': 99, 'section': 'deck'}]}


FILE = {'catalogueHash': 'c', 'decks': [deck()], 'power': {'rankedTiers': [[1, 2]] * 6, 'quickMatch': {'easy': {}, 'medium': {}, 'hard': {}}}}
CARDS = {'Lord', 'Swamp'}


class ProblemsTest(unittest.TestCase):
    def test_a_good_file_passes(self):
        self.assertEqual(problems(FILE, FILE, CARDS, 'c'), [])

    def test_each_break_is_named(self):
        self.assertTrue(problems(FILE, FILE, CARDS, 'other'))
        self.assertTrue(problems({**FILE, 'decks': []}, FILE, CARDS, 'c'), 'a shipped deck is gone')
        self.assertTrue(problems({**FILE, 'decks': [deck(), deck()]}, FILE, CARDS, 'c'), 'repeated ID')
        self.assertTrue(problems({**FILE, 'decks': [deck(extra='Unknown')]}, FILE, CARDS, 'c'), 'unknown card')
        short = copy.deepcopy(FILE)
        short['decks'][0]['entries'][1]['quantity'] = 98
        self.assertTrue(problems(short, FILE, CARDS, 'c'), '99 cards')
        self.assertTrue(problems({**FILE, 'power': {}}, FILE, CARDS, 'c'), 'no power')


if __name__ == '__main__':
    unittest.main()
