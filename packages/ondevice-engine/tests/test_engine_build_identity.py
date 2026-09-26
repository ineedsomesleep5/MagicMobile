"""Save/resume checkpoint identity: offline tooling test, not engine execution."""
from __future__ import annotations
import importlib.util, shutil, subprocess, sys, tempfile, unittest
from pathlib import Path

ROOT=Path(__file__).resolve().parents[1]
spec=importlib.util.spec_from_file_location('engine_build_identity',ROOT/'scripts/engine_build_identity.py')
identity=importlib.util.module_from_spec(spec);spec.loader.exec_module(identity)

class EngineBuildIdentityTests(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory();self.addCleanup(self.temp.cleanup)
        self.root=Path(self.temp.name)
        for tree in identity.TREES:
            (self.root/tree/'io').mkdir(parents=True)
            (self.root/tree/'io'/'A.java').write_text('class A {}\n')
        for name in identity.FILES:
            (self.root/name).parent.mkdir(parents=True,exist_ok=True);(self.root/name).write_text(name)

    def test_stable_and_sensitive_to_every_input(self):
        first=identity.identity(self.root)
        self.assertRegex(first,r'^sha256:[0-9a-f]{64}$')
        self.assertEqual(first,identity.identity(self.root))
        seen={first}
        for path in [self.root/tree/'io'/'A.java' for tree in identity.TREES]+[self.root/n for n in identity.FILES]:
            path.write_text(path.read_text()+' ')
            value=identity.identity(self.root)
            self.assertNotIn(value,seen,'identity must change with '+str(path.relative_to(self.root)))
            seen.add(value)
        (self.root/identity.TREES[0]/'io'/'B.java').write_text('class B {}\n')
        self.assertNotIn(identity.identity(self.root),seen,'a new adapter source changes the identity')

    def test_generated_source_compiles(self):
        out=self.root/'generated'
        subprocess.run([sys.executable,str(ROOT/'scripts/engine_build_identity.py'),'--output',str(out)],check=True,capture_output=True)
        source=out/'io/magicmobile/generated/EngineBuildIdentity.java'
        self.assertIn('public static final String VALUE="sha256:',source.read_text())
        if shutil.which('javac'):
            subprocess.run(['javac','-d',str(self.root/'classes'),str(source)],check=True,capture_output=True)

if __name__=='__main__':unittest.main(verbosity=2)
