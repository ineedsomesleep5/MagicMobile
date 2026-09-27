"""The native resource guard: the production config embeds only what the engine reads, never class files."""
import contextlib
import importlib.util
import io
import json
import os
from pathlib import Path
import re
import shutil
import tempfile
import unittest
import zipfile

ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location('check_native_resources', ROOT / 'scripts/check_native_resources.py')
guard = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(guard)


class NativeResourceGuardTests(unittest.TestCase):
    def setUp(self):
        self.dir = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, self.dir, ignore_errors=True)
        # A directory entry like build/engine plus Mage classes, and a jar with a service file.
        classes = self.dir / 'classes'
        for name, data in {'mage/mobile/card-names.json.gz': b'n', 'mage/mobile/card-metadata.jsonl.gz': b'm',
                           'mage/mobile/card-metadata-report.json': b'{}', 'mage/cards/a/Abc.class': b'\xca\xfe\xba\xbe',
                           'mage/mobile/Loader.class': b'\xca\xfe\xba\xbe', 'tokens-database.txt': b't',
                           'pennydreadful.properties': b'p', 'log4j-unused.properties': b'x',
                           'ratings/dom.csv': b'r'}.items():
            path = classes / name; path.parent.mkdir(parents=True, exist_ok=True); path.write_bytes(data)
        self.jar = self.dir / 'lib.jar'
        with zipfile.ZipFile(self.jar, 'w') as jar:
            jar.writestr('META-INF/services/org.slf4j.spi.SLF4JServiceProvider', 'x\n')
            jar.writestr('META-INF/maven/x/y/pom.properties', 'v=1\n')
            jar.writestr('org/x/Y.class', b'\xca\xfe\xba\xbe')
            jar.writestr('org/x/', b'')
        self.classpath = os.pathsep.join([str(classes), str(self.jar)])

    def run_guard(self, config):
        path = self.dir / 'resource-config.json'
        path.write_text(json.dumps(config))
        report = self.dir / 'report.json'
        with contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(io.StringIO()):
            code = guard.main(['--classpath', self.classpath, '--config', str(path), '--report', str(report)])
        return code, json.loads(report.read_text())

    def test_production_config_embeds_only_read_resources(self):
        code, report = self.run_guard(json.loads((ROOT / 'native/resource-config.json').read_text()))
        self.assertEqual(code, 0)
        self.assertEqual(sorted(r['name'] for r in report['embedded']), [
            'META-INF/services/org.slf4j.spi.SLF4JServiceProvider', 'mage/mobile/card-metadata.jsonl.gz',
            'mage/mobile/card-names.json.gz', 'pennydreadful.properties', 'tokens-database.txt'])
        self.assertEqual(report['classFiles'], 0)

    def test_broad_mage_pattern_is_refused(self):
        code, report = self.run_guard({'resources': {'includes': [
            {'pattern': 'mage/.*'}, {'pattern': 'META-INF/services/.*'}, {'pattern': r'.*\.properties$'},
            {'pattern': r'tokens-database\.txt'}]}})
        self.assertEqual(code, 1)
        self.assertEqual(report['classFiles'], 2)

    def test_missing_required_resource_is_refused(self):
        code, report = self.run_guard({'resources': {'includes': [{'pattern': r'mage/mobile/.*\.gz'}]}})
        self.assertEqual(code, 1)
        self.assertEqual(report['missingRequired'], ['tokens-database.txt', 'pennydreadful.properties'])

    def test_excludes_apply(self):
        config = json.loads((ROOT / 'native/resource-config.json').read_text())
        config['resources']['excludes'] = [{'pattern': 'META-INF/services/.*'}]
        code, report = self.run_guard(config)
        self.assertEqual(code, 0)
        self.assertNotIn('META-INF/services/org.slf4j.spi.SLF4JServiceProvider', [r['name'] for r in report['embedded']])

    def test_no_production_pattern_can_match_a_class_file(self):
        includes = json.loads((ROOT / 'native/resource-config.json').read_text())['resources']['includes']
        for name in ('mage/cards/a/Abc.class', 'mage/mobile/Loader.class', 'Main.class', 'x.properties.class',
                     'META-INF/versions/9/module-info.class'):
            self.assertFalse(any(re.fullmatch(e['pattern'], name) for e in includes), name)


if __name__ == '__main__':
    unittest.main()
