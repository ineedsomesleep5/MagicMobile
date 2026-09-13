"""Tests the resolver and local installer. All repository writes are temporary local fixtures."""
import importlib.util, json, shutil, subprocess, sys, tempfile, unittest
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

class InstallerTests(unittest.TestCase):
    def setUp(self):
        self.tmp=tempfile.TemporaryDirectory();self.repo=Path(self.tmp.name)/'MagicMobile';self.repo.mkdir()
        self.addCleanup(self.tmp.cleanup)
        self.delivery=Path(self.tmp.name)/'delivery'
        ignore=shutil.ignore_patterns('.git','.build','build','.upstream','__pycache__','*.pyc','.DS_Store')
        shutil.copytree(ROOT,self.delivery,ignore=ignore)
        if not (ROOT/'ios-app').is_dir():
            installed_repo=ROOT.parents[1]
            shutil.copytree(installed_repo/'apps/ios-ondevice',self.delivery/'ios-app',ignore=ignore)
            (self.delivery/'integration').mkdir()
            shutil.copy2(installed_repo/'.github/workflows/magicmobile-ondevice.yml',self.delivery/'integration/magicmobile-ondevice.yml')
            for name in ['project.yml','project.native.yml']:
                path=self.delivery/'ios-app'/name;text=path.read_text()
                for original,installed in [('../swift','../../packages/ondevice-engine/swift'),('../native','../../packages/ondevice-engine/native'),('../build/ios','../../packages/ondevice-engine/build/ios')]:
                    text=text.replace(installed,original)
                path.write_text(text)
        (self.delivery/'build').mkdir();(self.delivery/'build/fixture.txt').write_text('Not part of the installed package\n')
        self.git('init','-b','main');self.git('config','user.name','Local Fixture');self.git('config','user.email','fixture@example.invalid')
        # Some Git versions may launch automatic repository maintenance after a
        # commit. These fixtures are intentionally tiny, and an asynchronous gc
        # can race TemporaryDirectory cleanup and create .git files while rmtree
        # is removing the fixture. Disable maintenance so teardown is deterministic.
        self.git('config','gc.auto','0');self.git('config','maintenance.auto','false')
        (self.repo/'README.md').write_text('Original project\n');self.git('add','README.md');self.git('commit','-m','fixture')
    def git(self,*args):return subprocess.run(['git','-C',str(self.repo),*args],check=True,text=True,capture_output=True).stdout.strip()
    def install(self,*args):return subprocess.run([sys.executable,str(self.delivery/'scripts/install_into_magicmobile.py'),str(self.repo),*args],text=True,capture_output=True)
    def test_dry_run_makes_no_changes(self):
        result=self.install();self.assertEqual(result.returncode,0,result.stderr)
        self.assertEqual(self.git('status','--porcelain'),'');self.assertEqual(self.git('branch','--show-current'),'main')
        self.assertFalse((self.repo/'packages/ondevice-engine').exists())
    def test_apply_creates_local_branch_and_keeps_original(self):
        original=self.git('rev-parse','HEAD');result=self.install('--apply');self.assertEqual(result.returncode,0,result.stderr)
        self.assertEqual(self.git('branch','--show-current'),'codex/ondevice-xmage')
        self.assertEqual(self.git('rev-parse','HEAD'),original);self.assertEqual(self.git('rev-parse','main'),original)
        self.assertTrue((self.repo/'packages/ondevice-engine/engine/xmage/src/main/java/io/magicmobile/xmage/XmageEngine.java').exists())
        self.assertTrue((self.repo/'apps/ios-ondevice/Sources/MagicMobileApp.swift').exists())
        text=(self.repo/'apps/ios-ondevice/project.native.yml').read_text();self.assertIn('../../packages/ondevice-engine/native',text)
        self.assertNotIn('path: ../native',text)
        for name in ['project.yml','project.native.yml']:
            expected=(self.delivery/'ios-app'/name).read_text()
            for original,installed in [('../swift','../../packages/ondevice-engine/swift'),('../native','../../packages/ondevice-engine/native'),('../build/ios','../../packages/ondevice-engine/build/ios')]:
                expected=expected.replace(original,installed)
            self.assertEqual((self.repo/'apps/ios-ondevice'/name).read_text(),expected)
        self.assertFalse((self.repo/'packages/ondevice-engine/build').exists())
        self.assertTrue((self.repo/'README.md').read_text().startswith('Original project'))
        self.assertTrue((self.repo/'.github/workflows/magicmobile-ondevice.yml').exists())
        self.assertEqual((self.repo/'.github/workflows/magicmobile-ondevice.yml').read_bytes(),(self.delivery/'integration/magicmobile-ondevice.yml').read_bytes())
    def test_dirty_repo_is_not_modified(self):
        (self.repo/'README.md').write_text('User changes\n');result=self.install('--apply')
        self.assertNotEqual(result.returncode,0);self.assertEqual(self.git('branch','--show-current'),'main')
        self.assertIn('Working tree is not clean',result.stderr)
        self.assertEqual((self.repo/'README.md').read_text(),'User changes\n')
    def test_installed_module_refuses_self_install(self):
        result=self.install('--apply');self.assertEqual(result.returncode,0,result.stderr)
        self.git('add','.');self.git('commit','-m','installed fixture')
        installed=self.repo/'packages/ondevice-engine'
        self.assertFalse((installed/'ios-app').exists());self.assertFalse((installed/'integration').exists())
        original=self.git('rev-parse','HEAD')
        for args in [(),('--apply',)]:
            with self.subTest(args=args):
                result=subprocess.run([sys.executable,str(installed/'scripts/install_into_magicmobile.py'),str(self.repo),*args],text=True,capture_output=True)
                self.assertNotEqual(result.returncode,0)
                self.assertIn('Run this installer from the original extracted delivery, not from an already-installed module.',result.stderr)
                self.assertEqual(self.git('status','--porcelain'),'')
                self.assertEqual(self.git('branch','--show-current'),'codex/ondevice-xmage')
                self.assertEqual(self.git('rev-parse','HEAD'),original)

if __name__=='__main__':unittest.main(verbosity=2)