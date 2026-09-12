"""Artifact provenance/archive fixtures only. No network or native code execution."""
import importlib.util
import io
from pathlib import Path
import stat
import tempfile
import unittest
import zipfile

path = Path(__file__).resolve().parents[1] / 'scripts/fetch_native_candidate.py'
spec = importlib.util.spec_from_file_location('native_download', path)
download = importlib.util.module_from_spec(spec); spec.loader.exec_module(download)

class NativeDownloadTests(unittest.TestCase):
    def setUp(self):
        self.request = {'runId': 123, 'sourceCommit': 'a'*40, 'artifactId': 456, 'archiveSHA256': 'b'*64}
        self.run = {'id':123, 'head_sha':'a'*40, 'status':'completed', 'conclusion':'success',
                    'path': download.WORKFLOW, 'repository': {'full_name': download.REPO}}
        self.artifact = {'id':456, 'expired':False, 'name':'issue4-full-native-candidate-'+'a'*40,
                         'digest':'sha256:'+'b'*64, 'workflow_run':{'id':123,'head_sha':'a'*40}}

    def test_accept_exact_successful_producer(self):
        self.assertEqual(download.select(self.request,self.run,[self.artifact]),self.artifact)

    def test_running_or_failed_producer_never_accepted(self):
        for status, conclusion in [('in_progress',None), ('completed','failure'),('completed','cancelled')]:
            self.run.update(status=status,conclusion=conclusion)
            with self.assertRaisesRegex(ValueError, 'not completed successfully'):
                download.select(self.request,self.run,[self.artifact])

    def test_wrong_source_repository_workflow_or_artifact_rejected(self):
        for key,bad in [('head_sha','c'*40), ('path','another-workflow.yml'),('repository',{'full_name':'another/repo'})]:
            run = dict(self.run); run[key]=bad
            with self.assertRaises(ValueError): download.select(self.request,run,[self.artifact])
        for key,bad in [('expired',True),('name','probe'),('digest','sha256:'+'d'*64),('workflow_run',{'id':999,'head_sha':'a'*40})]:
            artifact = dict(self.artifact); artifact[key]=bad
            with self.assertRaises(ValueError): download.select(self.request,self.run,[artifact])

    def test_missing_duplicate_or_invalid_selection_rejected(self):
        for artifacts in [[], [self.artifact,self.artifact]]:
            with self.assertRaises(ValueError): download.select(self.request,self.run,artifacts)
        for key,bad in [('runId',True), ('artifactId',-1),('sourceCommit','short'),('archiveSHA256','invalid')]:
            request = dict(self.request); request[key]=bad
            with self.assertRaises(ValueError): download.select(request,self.run,[self.artifact])

    def test_safe_extraction_and_existing_destination_preserved(self):
        with tempfile.TemporaryDirectory() as raw:
            root=Path(raw); archive=root/'test.zip'; destination=root/'out'
            with zipfile.ZipFile(archive,'w') as out: out.writestr('include/header.h','fixture')
            download.extract(archive,destination)
            self.assertEqual((destination/'include/header.h').read_text(),'fixture')
            with self.assertRaisesRegex(ValueError,'already exists'): download.extract(archive,destination)
            self.assertEqual((destination/'include/header.h').read_text(),'fixture')

    def test_traversal_absolute_backslash_and_symlink_rejected_before_extract(self):
        for name, mode in [('../outside',0),('/outside',0),('dir\\outside',0),('link',stat.S_IFLNK|0o777)]:
            with self.subTest(name=name), tempfile.TemporaryDirectory() as raw:
                root=Path(raw); archive=root/'test.zip'; destination=root/'out'
                info=zipfile.ZipInfo(name); info.external_attr=mode<<16
                with zipfile.ZipFile(archive,'w') as out: out.writestr(info,'fixture')
                with self.assertRaisesRegex(ValueError,'Unsafe'): download.extract(archive,destination)
                self.assertFalse(destination.exists())

if __name__ == '__main__': unittest.main()
