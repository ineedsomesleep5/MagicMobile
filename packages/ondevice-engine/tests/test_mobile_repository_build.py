"""Checked platform-source generation and packaging contracts, not native acceptance."""
import json
from pathlib import Path
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'scripts'))
import prepare_mobile_repository as repository


class MobileRepositoryBuildTests(unittest.TestCase):
    def test_runtime_patch_preserves_original_files_and_rejects_desktop_writes(self):
        upstream = ROOT / '.upstream/mage'
        if not upstream.exists():
            self.skipTest('Pinned upstream checkout not bootstrapped')
        lock = json.loads((ROOT / 'platform/repository-sources.json').read_text())
        before = {name: (upstream / repository.PACKAGE / name).read_bytes() for name in lock['blobs']}
        with tempfile.TemporaryDirectory() as scratch:
            output = Path(scratch)
            repository.prepare(upstream, output, 'runtime')
            manifest = json.loads((output / 'repository-patch-manifest.json').read_text())
            self.assertEqual(manifest['upstream'], lock['commit'])
            self.assertEqual(set(manifest['outputs']), {'CardRepository.java', 'ExpansionRepository.java', 'CardCriteria.java'})
            card = (output / 'mage/cards/repository/CardRepository.java').read_text()
            self.assertIn('return MobileCardCatalogue.names("getNames");', card)
            self.assertIn('throw new UnsupportedOperationException', card)
            self.assertNotIn('connectionSource = new JdbcConnectionSource', card)
            criteria = (output / 'mage/cards/repository/CardCriteria.java').read_text()
            self.assertIn('public Boolean getNightCard()', criteria)
        self.assertEqual(before, {name: (upstream / repository.PACKAGE / name).read_bytes() for name in lock['blobs']})

    def test_export_retains_original_queries_but_uses_memory_database(self):
        upstream = ROOT / '.upstream/mage'
        if not upstream.exists():
            self.skipTest('Pinned upstream checkout not bootstrapped')
        with tempfile.TemporaryDirectory() as scratch:
            output = Path(scratch)
            repository.prepare(upstream, output, 'export')
            for name in ('CardRepository.java', 'ExpansionRepository.java', 'CardCriteria.java'):
                self.assertEqual((output / 'mage/cards/repository' / name).read_bytes(),
                                 (upstream / repository.PACKAGE / name).read_bytes())
            database = (output / 'mage/cards/repository/DatabaseUtils.java').read_text()
            self.assertIn('jdbc:h2:mem:mobile_catalogue_export;DB_CLOSE_DELAY=-1;IGNORECASE=TRUE', database)

    def test_catalogue_resources_are_frozen_and_packaged(self):
        build = (ROOT / 'scripts/build_native_ios.sh').read_text()
        self.assertIn('find core engine -type f -print', build)
        workflow = (ROOT.parents[1] / '.github/workflows/magicmobile-far-calls.yml').read_text()
        self.assertIn('"$OUT/engine/mage/mobile" build/native-candidate/catalogue', workflow)
        self.assertIn('repository-patch-manifest.json', workflow)


if __name__ == '__main__':
    unittest.main()
