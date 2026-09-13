"""Static resource contract; real native execution belongs to test_token_native.sh."""
import json
from pathlib import Path
import re
import subprocess
import unittest

ROOT = Path(__file__).resolve().parents[1]


class NativeTokenResourceTests(unittest.TestCase):
    def setUp(self):
        self.includes = json.loads((ROOT / 'native/resource-config.json').read_text())['resources']['includes']

    def test_root_token_database_is_included(self):
        self.assertTrue(any(re.fullmatch(e['pattern'], 'tokens-database.txt') for e in self.includes))

    def test_fix_is_exact_and_preserves_existing_resource_rules(self):
        token = {'pattern': r'tokens-database\.txt'}
        self.assertEqual(self.includes.count(token), 1)
        baseline = [e for e in self.includes if e != token]
        self.assertEqual(baseline, [{'pattern': 'mage/.*'}, {'pattern': 'META-INF/services/.*'},
                                    {'pattern': r'.*\.properties$'}])
        self.assertFalse(any(re.fullmatch(e['pattern'], 'tokens-database.txt') for e in baseline))
        self.assertFalse(any(re.fullmatch(e['pattern'], 'unrelated-private.txt') for e in self.includes))

    def test_script_shell_syntax(self):
        subprocess.run(['bash', '-n', str(ROOT / 'scripts/test_token_native.sh')], check=True)


if __name__ == '__main__':
    unittest.main()
