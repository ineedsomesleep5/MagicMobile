"""Offline tooling tests. Java fixtures are NOT XMage and never enter the app build."""
from __future__ import annotations
import importlib.util, json, os, subprocess, tempfile, unittest
from pathlib import Path

ROOT=Path(__file__).resolve().parents[1]
spec=importlib.util.spec_from_file_location('prepare_upstream',ROOT/'scripts/prepare_upstream.py')
patch=importlib.util.module_from_spec(spec);spec.loader.exec_module(patch)

def run(*args, **kwargs):
    return subprocess.run(args,check=True,text=True,capture_output=True,**kwargs)

class PatchTests(unittest.TestCase):
    def test_braces_in_comments_and_literals(self):
        s='class X { private Sets() { String x="}"; /* { */ if(true){go();} } void keep() {} }'
        out=patch.patch_sets(s)
        self.assertIn('void keep() {}',out);self.assertNotIn('go();',out)
    def test_duplicate_signature_fails(self):
        with self.assertRaises(ValueError):patch.patch_sets('private Sets() {} private Sets() {}')
    def test_missing_signature_fails(self):
        with self.assertRaises(ValueError):patch.patch_sets('private NewSets() {}')
    def test_unbalanced_method_fails(self):
        with self.assertRaises(ValueError):patch.patch_sets('private Sets() {')
    def test_unclosed_comment_fails(self):
        with self.assertRaises(ValueError):patch.java_mask('/* abc')
    def test_human_hook_is_exact(self):
        self.assertIn('protected final transient',patch.patch_human('private final transient PlayerResponse response;'))
        with self.assertRaises(ValueError):patch.patch_human('private transient PlayerResponse response;')
    def test_card_hooks_remove_reflective_bodies(self):
        s='''class CardImpl {
 public static Card createCard(String name, CardSetInfo setInfo) { return dangerousReflection(); }
 public static Card createCard(Class<?> clazz, CardSetInfo setInfo, List<String> errorList) { return dangerousReflection(); }
 public void keepMe() { log("{ wow }"); }
}'''
        out=patch.patch_card(s)
        self.assertEqual(out.count('MobileCardFactories.create('),2)
        self.assertNotIn('dangerousReflection',out);self.assertIn('keepMe()',out)
    def test_git_blob_hash(self):
        expected=run('git','hash-object','--stdin',input='abc\n').stdout.strip()
        self.assertEqual(patch.git_blob(b'abc\n'),expected)

class RegistryTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.tmp=tempfile.TemporaryDirectory();cls.root=Path(cls.tmp.name)
        src=cls.root/'src';cls.classes=cls.root/'classes';cls.classes.mkdir()
        files={
          'mage/cards/Card.java':'package mage.cards; public interface Card {}',
          'mage/cards/CardSetInfo.java':'package mage.cards; public class CardSetInfo {}',
          'mage/cards/Sets.java':'''package mage.cards; public final class Sets extends java.util.HashMap<String,ExpansionSet> {
 private static final Sets I=new Sets(); public static Sets getInstance(){return I;}
 public void addSet(ExpansionSet s){if(putIfAbsent(s.getCode(),s)!=null)throw new IllegalStateException();}}''',
          'mage/cards/ExpansionSet.java':'''package mage.cards; public abstract class ExpansionSet {
 public enum Rarity { COMMON }
 public static class SetCardInfo {
 public String getName(){return "Fixture One";} public String getCardNumber(){return "1";}
 public Rarity getRarity(){return Rarity.COMMON;} public Class<?> getCardClass(){return mage.cards.fixture.FixtureOne.class;}}
 public String getCode(){return "FIX";} public java.util.List<SetCardInfo> getSetCardInfo(){return java.util.List.of(new SetCardInfo());}}''',
          'mage/cards/fixture/FixtureOne.java':'''package mage.cards.fixture; public final class FixtureOne implements mage.cards.Card {
 public FixtureOne(java.util.UUID id,mage.cards.CardSetInfo info){} }''',
          'mage/cards/fixture/FixtureTwo.java':'''package mage.cards.fixture; public final class FixtureTwo implements mage.cards.Card {
 public FixtureTwo(java.util.UUID id){} }''',
          'mage/cards/fixture/DirectOnly.java':'''package mage.cards.fixture; public final class DirectOnly implements mage.cards.Card {
 public DirectOnly(String value){} }''',
          'mage/sets/FixtureSet.java':'''package mage.sets; public final class FixtureSet extends mage.cards.ExpansionSet {
 private static final FixtureSet I=new FixtureSet();public static FixtureSet getInstance(){return I;} }'''
        }
        for name,text in files.items():
            p=src/name;p.parent.mkdir(parents=True,exist_ok=True);p.write_text(text)
        run('javac','--release','17','-d',str(cls.classes),*[str(p) for p in src.rglob('*.java')])
        tools=cls.root/'tools';tools.mkdir()
        run('javac','--release','17','-cp',str(ROOT/'build/core'),'-d',str(tools),str(ROOT/'engine/tools/RegistryExporter.java'))
        cls.cp=os.pathsep.join(map(str,[ROOT/'build/core',tools,cls.classes]));cls.output=cls.root/'generated'
        cls.export()
    @classmethod
    def tearDownClass(cls):cls.tmp.cleanup()
    @classmethod
    def export(cls):return run('java','-cp',cls.cp,'RegistryExporter',str(cls.output),str(cls.classes))
    def test_inventory_and_explicit_exclusions(self):
        report=json.loads((self.output/'registry-report.json').read_text())
        self.assertEqual(report['cardClasses'],2);self.assertEqual(report['setClasses'],1)
        self.assertEqual(len(report['excluded']),1)
    def test_repeat_export_is_deterministic(self):
        before={p.relative_to(self.output):p.read_bytes() for p in self.output.rglob('*') if p.is_file()}
        self.export()
        after={p.relative_to(self.output):p.read_bytes() for p in self.output.rglob('*') if p.is_file()}
        self.assertEqual(before,after)
    def test_generated_source_has_no_reflection(self):
        for file in (self.output/'java').rglob('*.java'):
            s=file.read_text();self.assertNotIn('Class.forName',s);self.assertNotIn('getConstructor(',s)
    def test_catalogue_uses_set_metadata(self):
        rows=[json.loads(l) for l in (self.output/'catalogue.jsonl').read_text().splitlines()]
        self.assertEqual(rows,[{'name':'Fixture One','setCode':'FIX','collectorNumber':'1','rarity':'COMMON','className':'mage.cards.fixture.FixtureOne'}])
    def test_generated_java_compiles_and_instantiates(self):
        out=self.root/'compiled';out.mkdir(exist_ok=True)
        run('javac','--release','17','-cp',str(self.classes),'-d',str(out),*[str(p) for p in (self.output/'java').rglob('*.java')])
        main=self.root/'Probe.java';main.write_text('''import io.magicmobile.generated.*; public class Probe {
 public static void main(String[] args){
 GeneratedSetRegistry.install();GeneratedSetRegistry.install();
 if(mage.cards.Sets.getInstance().size()!=1)throw new AssertionError();
 if(!(GeneratedCardFactory.create("mage.cards.fixture.FixtureOne",new mage.cards.CardSetInfo()) instanceof mage.cards.fixture.FixtureOne))throw new AssertionError();
 if(!(GeneratedCardFactory.create("mage.cards.fixture.FixtureTwo",null) instanceof mage.cards.fixture.FixtureTwo))throw new AssertionError();
 try {GeneratedCardFactory.create("mage.cards.fixture.Missing",null);throw new AssertionError();}catch(IllegalArgumentException expected){}
 System.out.println("PASS: fixture factories, NOT XMage");}}
''')
        cp=os.pathsep.join(map(str,[self.classes,out]));run('javac','-cp',cp,'-d',str(out),str(main))
        self.assertIn('PASS: fixture factories',run('java','-cp',cp,'Probe').stdout)
    def test_reflection_metadata_is_parseable(self):
        data=json.loads((self.output/'reflect-config.json').read_text());self.assertGreater(len(data),1)
    def test_empty_input_is_rejected(self):
        empty=self.root/'empty';empty.mkdir(exist_ok=True)
        result=subprocess.run(['java','-cp',self.cp,'RegistryExporter',str(self.root/'bad'),str(empty)],capture_output=True)
        self.assertNotEqual(result.returncode,0)

if __name__=='__main__':unittest.main(verbosity=2)
