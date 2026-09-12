"""Packaging/inspection fixtures only; no native executable is run by these tests."""
import hashlib
import importlib.util
import json
from pathlib import Path
import plistlib
import tempfile
import unittest
from unittest.mock import patch

SCRIPTS = Path(__file__).resolve().parents[1] / 'scripts'
def load(name):
    spec = importlib.util.spec_from_file_location(name, SCRIPTS / (name + '.py'))
    module = importlib.util.module_from_spec(spec); spec.loader.exec_module(module)
    return module
candidate = load('native_candidate')
product = load('verify_ios_product')

def write_json(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, sort_keys=True) + '\n')

class CandidateFixtures(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(); self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name); self.repo = self.root / 'repo'
        self.directory = self.root / 'candidate'; self.directory.mkdir()
        self.source = 'a' * 40
        engine = self.repo / 'packages/ondevice-engine'
        patch_root = engine / 'native/gluon/compiler-patches'
        for path in ('far-calls.patch', 'upstream-sources.json', 'src/com/oracle/svm/hosted/image/FarCallPlanner.java'):
            file = patch_root / path; file.parent.mkdir(parents=True, exist_ok=True); file.write_text('fixture ' + path)
        write_json(engine / 'upstream.lock.json', {'commit': 'b' * 40})
        registry = {'registryHash': 'c' * 64, 'cardClasses': 12, 'setClasses': 2}
        write_json(self.directory / 'registry-report.json', registry)
        write_json(self.repo / 'apps/ios/MagicMobile/Resources/ondevice-catalogue.json', {
            'upstreamCommit': 'b' * 40, 'catalogueHash': 'c' * 64,
            'sourceRegistrySHA256': candidate.sha(self.directory / 'registry-report.json')})
        write_json(self.directory / 'compiler-patch-manifest.json', {
            'officialArchiveSha256': candidate.__dict__.get('ARCHIVE_SHA256', '61084c8e12a500e5019657d3160fa3394cd8230a0e780718a051d59028fbfb99'),
            'patchSha256': candidate.sha(patch_root / 'far-calls.patch'),
            'sourceManifestSha256': candidate.sha(patch_root / 'upstream-sources.json'),
            'plannerSha256': candidate.sha(patch_root / 'src/com/oracle/svm/hosted/image/FarCallPlanner.java'),
            'patchedSvmJarSha256': 'd' * 64, 'replacementClasses': {'fixture': 'e' * 64}})
        for name in ('libmmengine.a', 'include/libmmengine.h', 'include/graal_isolate.h', 'reflect-config.json'):
            file = self.directory / name; file.parent.mkdir(exist_ok=True); file.write_text('NOT NATIVE: fixture ' + name)
        (self.directory / 'commit.txt').write_text(self.source + '\n')
        (self.directory / 'class-snapshot.sha256').write_text('f' * 64 + '  core/fixture.class\n')
        self.checksums()

    def checksums(self):
        files = sorted(p for p in self.directory.rglob('*') if p.is_file() and p.name not in ('SHA256SUMS', 'SCOPE.txt'))
        (self.directory / 'SHA256SUMS').write_text(''.join(candidate.sha(p) + '  ./' + p.relative_to(self.directory).as_posix() + '\n' for p in files))

    def verify(self): return candidate.verify(self.directory, self.source, repo=self.repo)

    def test_paired_identity_has_explicit_nonexecution_scope(self):
        report = self.verify()
        self.assertFalse(report['nativeExecutionVerified'])
        self.assertEqual(report['sourceCommit'], self.source)
        self.assertEqual(report['cardFactories'], 12)
        self.assertNotIn('deviceReady', report)

    def test_source_mismatch_even_with_consistent_hashes(self):
        (self.directory / 'commit.txt').write_text('1' * 40); self.checksums()
        with self.assertRaisesRegex(ValueError, 'source commit'): self.verify()

    def test_no_abbreviated_or_invalid_expected_commit(self):
        for sha in ('e9d3d68', '', '../bad', 'g' * 40):
            with self.assertRaisesRegex(ValueError, 'full source'):
                candidate.verify(self.directory, sha, repo=self.repo)

    def test_replaced_archive_and_untracked_file_rejected(self):
        (self.directory / 'libmmengine.a').write_bytes(b'changed')
        with self.assertRaisesRegex(ValueError, 'checksum mismatch'): self.verify()
        self.checksums(); (self.directory / 'extra.a').write_bytes(b'untracked')
        with self.assertRaisesRegex(ValueError, 'completely covered'): self.verify()

    def test_symlinks_rejected(self):
        (self.directory / 'link').symlink_to(self.directory / 'libmmengine.a')
        with self.assertRaisesRegex(ValueError, 'Symlink'): self.verify()

    def test_parent_path_and_duplicates_rejected(self):
        manifest = self.directory / 'SHA256SUMS'; original = manifest.read_text()
        manifest.write_text('a' * 64 + '  ../outside\n')
        with self.assertRaisesRegex(ValueError, 'Unsafe'): self.verify()
        manifest.write_text(original + original.splitlines()[0] + '\n')
        with self.assertRaisesRegex(ValueError, 'duplicate'): self.verify()

    def test_metadata_and_reviewed_patch_must_match(self):
        registry = self.directory / 'registry-report.json'
        obj = json.loads(registry.read_text()); obj['registryHash'] = '0' * 64
        write_json(registry, obj); self.checksums()
        with self.assertRaisesRegex(ValueError, 'catalogue'): self.verify()

    def test_different_compiler_patch_rejected(self):
        path = self.repo / 'packages/ondevice-engine/native/gluon/compiler-patches/far-calls.patch'
        path.write_text('different')
        with self.assertRaisesRegex(ValueError, 'backport mismatch'): self.verify()

    def test_required_header_and_bad_frozen_manifest_rejected(self):
        header = self.directory / 'include/libmmengine.h'; old = header.read_bytes(); header.unlink(); self.checksums()
        with self.assertRaisesRegex(ValueError, 'Missing checksummed'): self.verify()
        header.write_bytes(old); (self.directory / 'class-snapshot.sha256').write_text('fabricated')
        self.checksums()
        with self.assertRaisesRegex(ValueError, 'frozen JVM'): self.verify()

    def test_scope_text_cannot_assert_runtime_acceptance(self):
        (self.directory / 'SCOPE.txt').write_text('This untrusted note claims everything passed')
        self.assertFalse(self.verify()['nativeExecutionVerified'])

class ProductFixtures(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(); self.addCleanup(self.temp.cleanup)
        self.app = Path(self.temp.name) / 'MagicMobile.app'; self.app.mkdir()
        (self.app / 'MagicMobile').write_bytes(b'NOT A MACH-O: fixture only')
        self.info = {'CFBundleIdentifier': product.BUNDLE_ID, 'MagicMobileEngineMode': 'embedded-xmage',
                     'CFBundleExecutable': 'MagicMobile', 'CFBundleVersion': '1', 'CFBundleShortVersionString': '0.1',
                     'UISupportedInterfaceOrientations': ['UIInterfaceOrientationPortrait', 'UIInterfaceOrientationLandscapeLeft', 'UIInterfaceOrientationLandscapeRight']}
        self.save()
        self.outputs = {'lipo': 'arm64', 'vtool': 'platform IOS\nminos 17.0\n',
                        'nm': '\n'.join('0000 T _' + s for s in product.REQUIRED),
                        'otool': 'MagicMobile:\n  /usr/lib/libSystem.B.dylib (compatibility version 1.0)\n'}
        mock = patch.object(product, 'xcrun', side_effect=lambda *args: self.outputs[args[0]])
        mock.start(); self.addCleanup(mock.stop)

    def save(self):
        with (self.app / 'Info.plist').open('wb') as output: plistlib.dump(self.info, output)

    def test_verified_link_report_never_claims_execution(self):
        report = product.verify(self.app)
        self.assertFalse(report['nativeExecutionVerified'])
        self.assertFalse(report['signingPerformedByThisCheck'])
        self.assertFalse(report['uploadPerformedByThisCheck'])
        self.assertEqual(report['executableSHA256'], hashlib.sha256((self.app / 'MagicMobile').read_bytes()).hexdigest())

    def test_wrong_architecture_platform_or_minos_rejected(self):
        for tool, bad in [('lipo', 'arm64 x86_64'), ('vtool', 'platform IOSSIMULATOR\nminos 17.0\n'), ('vtool', 'platform IOS\nminos 16.9\n')]:
            old = self.outputs[tool]; self.outputs[tool] = bad
            with self.assertRaises(ValueError): product.verify(self.app)
            self.outputs[tool] = old
        self.outputs['vtool'] = 'platform IOS\nminos 17\n'
        self.assertFalse(product.verify(self.app)['nativeExecutionVerified'])

    def test_undefined_engine_symbol_is_not_a_linked_export(self):
        self.outputs['nm'] = self.outputs['nm'].replace('T _mm_engine_request', 'U _mm_engine_request')
        with self.assertRaisesRegex(ValueError, 'Missing linked'): product.verify(self.app)

    def test_probe_and_foreign_app_delegate_rejected(self):
        original = self.outputs['nm']
        for symbol in ('mm_toolchain_probe', 'runtime_swift_close', '_OBJC_CLASS_$_AppDelegate'):
            self.outputs['nm'] = original + '\n000 T _' + symbol
            with self.assertRaisesRegex(ValueError, 'Probe, fixture'): product.verify(self.app)

    def test_build_machine_dynamic_libraries_rejected(self):
        self.outputs['otool'] += '  /Users/runner/build/libjvm.dylib\n'
        with self.assertRaisesRegex(ValueError, 'desktop/build-machine'): product.verify(self.app)

    def test_bundle_version_and_engine_mode_are_required(self):
        for key, bad in [('CFBundleIdentifier', 'another.app'), ('CFBundleVersion', '$(CURRENT_PROJECT_VERSION)'),
                         ('MagicMobileEngineMode', 'unlinked-reference'), ('CFBundleExecutable', '../elsewhere')]:
            original = self.info[key]; self.info[key] = bad; self.save()
            with self.assertRaises(ValueError): product.verify(self.app)
            self.info[key] = original
        self.save()

    def test_portrait_landscape_preserved(self):
        self.info['UISupportedInterfaceOrientations'].pop(); self.save()
        with self.assertRaisesRegex(ValueError, 'portrait/landscape'): product.verify(self.app)

    def test_executable_symlink_rejected(self):
        binary = self.app / 'MagicMobile'; binary.rename(self.app.parent / 'outside')
        binary.symlink_to(self.app.parent / 'outside')
        with self.assertRaisesRegex(ValueError, 'Missing linked'): product.verify(self.app)

if __name__ == '__main__': unittest.main()
