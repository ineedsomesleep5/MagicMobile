"""The Android engine staging must pick the static C ABI header, not the dynamic variant."""
import importlib.util
import pathlib
import shutil
import sys
import tempfile
import unittest

SPEC = importlib.util.spec_from_file_location(
    'stage_native', pathlib.Path(__file__).resolve().parents[1] / 'stage_native.py')
stage_native = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(stage_native)

# Shapes taken from a real Gluon aarch64-android build: both headers name the entry points.
STATIC = '''#ifndef __IO_MAGICMOBILE_NATIVEBRIDGE_IOSLIBRARYMAIN_H
#include <graal_isolate.h>
char* mm_engine_request(graal_isolatethread_t*, char*, int);
void mm_engine_free(graal_isolatethread_t*, char*);
int mm_engine_shutdown_v2(graal_isolatethread_t*);
#endif
'''
DYNAMIC = '''#ifndef __IO_MAGICMOBILE_NATIVEBRIDGE_IOSLIBRARYMAIN_DYNAMIC_H
#include <graal_isolate_dynamic.h>
typedef char* (*mm_engine_request_fn_t)(graal_isolatethread_t*, char*, int);
typedef void (*mm_engine_free_fn_t)(graal_isolatethread_t*, char*);
typedef int (*mm_engine_shutdown_v2_fn_t)(graal_isolatethread_t*);
#endif
'''


class HeaderSelectionTests(unittest.TestCase):
    def setUp(self):
        self.dir = pathlib.Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, self.dir, ignore_errors=True)

    def write(self, name, text):
        path = self.dir / name
        path.write_text(text)
        return path

    def select(self):
        """Mirror the staging selection over a populated include directory."""
        entries = ('mm_engine_request', 'mm_engine_free', 'mm_engine_shutdown_v2')
        declares = lambda p: all(e in p.read_text() for e in entries)
        return [p for p in sorted(self.dir.glob('*.h'))
                if not p.stem.endswith('_dynamic') and declares(p)]

    def test_dynamic_variant_does_not_create_ambiguity(self):
        self.write('io.magicmobile.nativebridge.ioslibrarymain.h', STATIC)
        self.write('io.magicmobile.nativebridge.ioslibrarymain_dynamic.h', DYNAMIC)
        self.write('graal_isolate.h', '/* isolate */')
        self.write('grandroid.h', '/* android shim */')
        chosen = self.select()
        self.assertEqual([p.name for p in chosen], ['io.magicmobile.nativebridge.ioslibrarymain.h'])

    def test_partial_abi_header_is_not_accepted(self):
        self.write('partial.h', 'char* mm_engine_request(void*, char*, int);')
        self.assertEqual(self.select(), [])

    def test_declares_abi_requires_every_entry_point(self):
        full = self.write('full.h', STATIC)
        partial = self.write('partial.h', 'char* mm_engine_request(void*, char*, int);')
        entries = ('mm_engine_request', 'mm_engine_free', 'mm_engine_shutdown_v2')
        self.assertTrue(all(e in full.read_text() for e in entries))
        self.assertFalse(all(e in partial.read_text() for e in entries))


if __name__ == '__main__':
    unittest.main()
