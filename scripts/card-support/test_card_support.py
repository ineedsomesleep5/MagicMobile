"""Fixture tests for the card support parser (no network)."""
import tempfile
import unittest
from pathlib import Path

import build_card_support as b

SET = '''package mage.sets;
public final class Fixture extends ExpansionSet {
    private Fixture() {
        super("Fixture Set", "FIX", ExpansionSet.buildDate(2026, 10, 2), SetType.EXPANSION);
        cards.add(new SetCardInfo("Fire // Ice", 1, Rarity.UNCOMMON, mage.cards.f.FireIce.class));
        cards.add(new SetCardInfo("\\"Name Sticker\\" Goblin", "107m", Rarity.COMMON, mage.cards.n.NameStickerGoblin.class));
        //cards.add(new SetCardInfo("Unimplemented Card", 3, Rarity.RARE, mage.cards.u.UnimplementedCard.class));
        /* cards.add(new SetCardInfo("Blocked Out", 4, Rarity.RARE, mage.cards.b.BlockedOut.class)); */
        cards.add(new SetCardInfo("Twin", 5, Rarity.RARE, mage.cards.t.Twin.class));
        cards.add(new SetCardInfo("Twin", 5, Rarity.RARE, mage.cards.t.Twin.class));
    }
}
'''
JOKE = SET.replace('"Fixture Set", "FIX"', '"Joke Set", "JOK"').replace('SetType.EXPANSION', 'SetType.JOKE_SET')

CARD = '''public final class AcererakTheArchlich extends CardImpl {
    public AcererakTheArchlich(UUID ownerId, CardSetInfo setInfo) {
        super(ownerId, setInfo, new CardType[]{CardType.CREATURE}, "{2}{B}");
        this.supertype.add(SuperType.LEGENDARY);
        this.subtype.add(SubType.ZOMBIE);
        this.power = new MageInt(5);
        this.toughness = new MageInt(5);
        // Whenever Acererak attacks, create a 2/2 black Zombie creature token.
        this.addAbility(new AttacksTriggeredAbility(null));
    }
'''


class ParserTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        root = Path(self.tmp.name) / b.SETS_DIR
        root.mkdir(parents=True)
        (root / 'Fixture.java').write_text(SET)
        (root / 'Joke.java').write_text(JOKE)
        self.sets, self.printings = b.read_sets(self.tmp.name)

    def tearDown(self):
        self.tmp.cleanup()

    def test_commented_printings_are_skipped(self):
        names = {p['name'] for p in self.printings}
        self.assertIn('Fire // Ice', names)
        self.assertIn('"Name Sticker" Goblin', names)
        self.assertNotIn('Unimplemented Card', names)
        self.assertNotIn('Blocked Out', names)

    def test_addressable_matches_catalogue_rules(self):
        ok = b.addressable(self.sets, self.printings)
        self.assertEqual(ok['Fire // Ice']['set'], 'FIX')       # joke-set printing ignored
        self.assertEqual(ok['"Name Sticker" Goblin']['num'], '107m')
        self.assertNotIn('Twin', ok)                             # repeated collector number

    def test_card_class_facts(self):
        path = Path(self.tmp.name) / 'Card.java'
        path.write_text(CARD)
        facts = b.parse_card_class(path)
        self.assertEqual(facts['typeLine'], 'Legendary Creature — Zombie')
        self.assertEqual(facts['manaCost'], '{2}{B}')
        self.assertEqual(facts['pt'], '5/5')
        self.assertTrue(facts['commander'])
        self.assertEqual(facts['rules'], ['Whenever Acererak attacks, create a 2/2 black Zombie creature token.'])


if __name__ == '__main__':
    unittest.main()
