"""Tests the deck resolver with in-memory fixtures."""
import importlib.util, unittest
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
spec=importlib.util.spec_from_file_location('resolver',ROOT/'scripts/resolve_deck.py')
resolver=importlib.util.module_from_spec(spec);spec.loader.exec_module(resolver)

class ResolverTests(unittest.TestCase):
    def setUp(self):
        self.catalogue=[{'name':name,'setCode':code,'collectorNumber':number,'className':'fixture.'+str(i),'rarity':'COMMON'}
          for i,(name,code,number) in enumerate([('Fixture Leader','AAA','1'),('Fixture Land','AAA','2'),('Fixture Land','BBB','3')])]
    def test_names_resolve_to_trusted_printings(self):
        deck=resolver.resolve('1 Fixture Leader\n99 Fixture Land',self.catalogue,['Fixture Leader'],[])
        self.assertEqual(deck['commanders'][0]['name'],'Fixture Leader')
        self.assertEqual(deck['main'][0]['setCode'],'AAA');self.assertNotIn('className',deck['main'][0])
    def test_explicit_printing_is_respected(self):
        deck=resolver.resolve('1 Fixture Leader\n99 Fixture Land (BBB) 3',self.catalogue,['Fixture Leader'],[])
        self.assertEqual(deck['main'][0]['setCode'],'BBB')
    def test_missing_printing_fails(self):
        with self.assertRaises(ValueError):resolver.resolve('1 Fixture Leader\n99 Missing',self.catalogue,['Fixture Leader'],[])
    def test_missing_commander_fails(self):
        with self.assertRaises(ValueError):resolver.resolve('100 Fixture Land',self.catalogue,['Fixture Leader'],[])
    def test_unrecognized_line_fails_not_silently_skips(self):
        with self.assertRaises(ValueError):resolver.resolve('1 Fixture Leader\nSIDEBOARD JUNK',self.catalogue,['Fixture Leader'],[])

if __name__=='__main__':unittest.main(verbosity=2)