"""Local synthetic Git fixtures only; never runs Maven or upstream programs."""
import json
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest
from unittest.mock import patch

import upstream as tool


class MaintenanceTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.repo = self.root / 'upstream'; self.repo.mkdir()
        tool.git(self.repo, 'init')
        self.files = {
            'Mage/src/main/java/mage/cards/CardImpl.java':
                'class CardImpl { public static Card createCard(String name, CardSetInfo setInfo) { return null; }\n'
                'public static Card createCard(Class<?> clazz, CardSetInfo setInfo, List<String> errorList) { return null; }}',
            'Mage/src/main/java/mage/cards/Sets.java': 'class Sets { private Sets() { scan(); }}',
            'Mage.Server.Plugins/Mage.Player.Human/src/mage/player/human/HumanPlayer.java':
                'class HumanPlayer { private final transient PlayerResponse response; }',
            'pom.xml': '<project>old</project>',
            'deleted.txt': 'removed',
        }
        for name in ('CardRepository.java', 'ExpansionRepository.java', 'CardCriteria.java',
                     'DatabaseUtils.java', 'CardInfo.java'):
            self.files[tool.REPOSITORY_SOURCES + name] = (
                'class DatabaseUtils { public static String prepareH2Connection(String dbName, boolean improveCaches) { return "old"; }}'
                if name == 'DatabaseUtils.java' else 'class ' + name[:-5] + ' {}')
        for path, text in self.files.items():
            self.put(self.repo / path, text)
        self.old = self.commit(self.repo)
        self.lock = {'repository': 'https://github.com/magefree/mage.git', 'commit': self.old,
                     'magicmobileBase': self.old,
                     'sourceBlobs': {p: tool.object_info(self.repo, self.old, p)['blob']
                                     for p in self.files if p.endswith('.java') and not p.startswith(tool.REPOSITORY_SOURCES)}}
        self.repository_lock = {'commit': self.old, 'blobs': {
            Path(p).name: tool.object_info(self.repo, self.old, p)['blob']
            for p in self.files if p.startswith(tool.REPOSITORY_SOURCES)}}
        self.put(self.repo / 'pom.xml', '<project>new dependency</project>')
        self.put(self.repo / 'new.txt', 'new')
        (self.repo / 'deleted.txt').unlink()
        self.new = self.commit(self.repo)
        self.report = tool.detect(self.repo, self.lock, self.new, self.repository_lock)
        self.project = self.root / 'project'; self.project.mkdir()
        tool.git(self.project, 'init')
        package = self.project / 'packages/ondevice-engine'
        self.put(package / 'upstream.lock.json', json.dumps(self.lock))
        self.put(package / 'platform/repository-sources.json', json.dumps(self.repository_lock))
        self.put(package / 'implementation-status.json', json.dumps({'upstreamCommit': self.old,
                 'status': 'passed', 'currentCandidate': {'nativeState': 'passed', 'nativeArtifact': 123},
                 'verification': {'ciState': 'passed', 'sourceCommit': self.old},
                 'historicalEvidence': {'upstream': self.old, 'passed': True}}))
        self.put(self.project / tool.BASELINE, json.dumps({'upstreamCommit': self.old,
                 'cards': [{'name': 'Old', 'setCode': 'A', 'collectorNumber': '1'}],
                 'statistics': {'unresolvableNames': ['Now available']}}))
        for path in tool.IDENTITIES:
            self.put(package / path, "UPSTREAM = '" + self.old + "'\n" + ''.join(
                key + " = '" + 'a' * 64 + "'\n" for key in (*tool.GENERATED, 'REGISTRY_HASH')))
        (package / 'scripts').mkdir(exist_ok=True)
        shutil.copyfile(tool.PACKAGE / 'scripts/prepare_upstream.py', package / 'scripts/prepare_upstream.py')
        shutil.copyfile(tool.PACKAGE / 'scripts/prepare_mobile_repository.py', package / 'scripts/prepare_mobile_repository.py')
        self.commit(self.project)
        self.dest = self.root / 'candidate'

    def put(self, path, text):
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text)

    def commit(self, repo):
        tool.git(repo, 'add', '.')
        tool.git(repo, '-c', 'user.name=Fixture', '-c', 'user.email=fixture@example.invalid',
                 'commit', '-m', 'fixture')
        return tool.git(repo, 'rev-parse', 'HEAD').decode().strip()

    def prepare(self):
        return tool.prepare(self.repo, self.project, self.report,
                            tool.digest(tool.encoded(self.report)), self.dest)

    def test_detect_exact_changes_and_dependencies(self):
        self.assertEqual(self.report['dependencyPaths'], ['pom.xml'])
        self.assertEqual(self.report['changedModules'], ['(root)'])
        self.assertEqual(self.report['compareURL'], f'https://github.com/magefree/mage/compare/{self.old}...{self.new}')
        changes = {v['path']: v for v in self.report['changes']}
        self.assertIsNone(changes['deleted.txt']['candidate'])
        self.assertIsNone(changes['new.txt']['old'])
        self.assertNotEqual(changes['pom.xml']['old']['blob'], changes['pom.xml']['candidate']['blob'])
        self.assertEqual(self.report, tool.detect(self.repo, self.lock, self.new, self.repository_lock))
        self.assertFalse(tool.detect(self.repo, self.lock, self.old, self.repository_lock)['updateAvailable'])

    def test_invalid_sha_and_wrong_old_blob(self):
        with self.assertRaises(ValueError): tool.detect(self.repo, self.lock, 'master', self.repository_lock)
        self.lock['sourceBlobs'][next(iter(self.lock['sourceBlobs']))] = '0' * 40
        with self.assertRaises(ValueError): tool.detect(self.repo, self.lock, self.new, self.repository_lock)

    def test_missing_object(self):
        with self.assertRaises(subprocess.CalledProcessError): tool.detect(self.repo, self.lock, '0' * 40, self.repository_lock)

    def test_approval_and_stale_report(self):
        with self.assertRaises(ValueError):
            tool.prepare(self.repo, self.project, self.report, 'unapproved', self.dest)
        self.report['changes'] = []
        with self.assertRaises(ValueError): self.prepare()
        self.assertFalse(self.dest.exists())

    def test_dirty_project(self):
        self.put(self.project / 'untracked', 'dirty')
        with self.assertRaises(ValueError): self.prepare()

    def test_candidate_and_reuse(self):
        self.prepare()
        target = self.dest / 'packages/ondevice-engine'
        self.assertEqual(json.loads((target / 'upstream.lock.json').read_bytes())['commit'], self.new)
        for path in tool.IDENTITIES:
            self.assertIn(self.new, (target / path).read_text())
        self.assertEqual(tool.git(target / '.upstream/mage', 'rev-parse', 'HEAD').decode().strip(), self.new)
        self.assertIn('MOBILE_STATIC_SETS', (target / '.upstream/mage/Mage/src/main/java/mage/cards/Sets.java').read_text())
        self.assertEqual(json.loads((self.project / 'packages/ondevice-engine/upstream.lock.json').read_bytes())['commit'], self.old)
        with self.assertRaises(FileExistsError): self.prepare()

    def test_changed_signature_fails_without_success_record(self):
        path = 'Mage/src/main/java/mage/cards/Sets.java'
        self.put(self.repo / path, 'class Sets { private Sets(int changed) {} }')
        sha = self.commit(self.repo)
        self.report = tool.detect(self.repo, self.lock, sha, self.repository_lock)
        with self.assertRaises(ValueError): self.prepare()
        self.assertFalse((self.dest / 'maintenance-candidate.json').exists())

    def test_symlink_source_rejected(self):
        path = self.repo / next(iter(self.lock['sourceBlobs']))
        path.unlink(); path.symlink_to('/etc/passwd')
        with self.assertRaises(ValueError): tool.detect(self.repo, self.lock, self.commit(self.repo), self.repository_lock)

    def test_archive_symlink_rejected(self):
        (self.repo / 'link').symlink_to('/etc/passwd')
        sha = self.commit(self.repo)
        with self.assertRaises(ValueError): tool.archive(self.repo, sha, self.root / 'extract')

    def test_generated_review_requires_outputs_and_new_approval(self):
        self.prepare()
        with self.assertRaises(FileNotFoundError): tool.generated_review(self.dest)
        generated = self.dest / 'packages/ondevice-engine/build/generated'
        self.put(generated / 'catalogue.jsonl', '{"name":"fixture","setCode":"A","collectorNumber":"2"}\n')
        self.put(generated / 'registry-report.json', json.dumps({'registryHash': 'b' * 64}))
        self.put(generated / 'commander-set-codes.json', json.dumps({'upstreamCommit': self.new, 'eternalLegalSetCodes': ['A']}))
        metadata = generated.parent / 'engine/mage/mobile/card-metadata.jsonl.gz'
        self.put(metadata, 'fixture metadata bytes')
        review = tool.generated_review(self.dest)
        self.assertEqual(review['hashes']['METADATA_SHA256'], tool.digest(metadata.read_bytes()))
        approval = tool.digest(tool.encoded(review))
        with self.assertRaises(ValueError): tool.accept_generated(self.dest, 'no')
        self.put(metadata, 'changed metadata bytes')
        with self.assertRaises(ValueError): tool.accept_generated(self.dest, approval)
        self.put(metadata, 'fixture metadata bytes')
        self.put(generated / 'catalogue.jsonl', '{"name":"changed","setCode":"A","collectorNumber":"2"}\n')
        with self.assertRaises(ValueError): tool.accept_generated(self.dest, approval)
        review = tool.generated_review(self.dest)
        tool.accept_generated(self.dest, tool.digest(tool.encoded(review)))
        self.put(generated / 'commander-set-codes.json', json.dumps({'upstreamCommit': self.old}))
        with self.assertRaises(ValueError): tool.generated_review(self.dest)

    def test_cli_dry_run_and_dedup(self):
        lock = self.project / 'packages/ondevice-engine/upstream.lock.json'
        command = ['python3', str(Path(tool.__file__)), 'detect', '--upstream', str(self.repo),
                   '--candidate', self.new, '--lock', str(lock)]
        result = subprocess.run(command, capture_output=True, text=True, check=True)
        self.assertEqual(json.loads(result.stdout), self.report)
        records = self.root / 'records'; records.mkdir()
        record = records / (self.report['dedupKey'] + '.json')
        self.put(record, json.dumps({'dedupKey': self.report['dedupKey'],
                 'detectionDigest': tool.digest(tool.encoded(self.report)), 'status': 'reviewed'}))
        result = subprocess.run(command + ['--records', str(records)], capture_output=True, text=True, check=True)
        self.assertIn('dedup=reviewed', result.stderr)
        self.put(record, '{}')
        self.assertNotEqual(subprocess.run(command + ['--records', str(records)], capture_output=True).returncode, 0)

    def test_regeneration_dry_run_and_missing_soak(self):
        self.prepare()
        self.assertFalse(tool.regenerate(self.dest)['executed'])
        with self.assertRaisesRegex(ValueError, 'seeded soak'):
            tool.regenerate(self.dest, True)

    def test_regeneration_failure_stops_pipeline(self):
        self.prepare()
        self.put(self.dest / 'packages/ondevice-engine/scripts/test_seeded_soak.py', '# fixture')
        with patch.object(tool.subprocess, 'run', side_effect=subprocess.CalledProcessError(1, 'fixture')) as run:
            with self.assertRaises(subprocess.CalledProcessError): tool.regenerate(self.dest, True)
        self.assertEqual(run.call_count, 1)
        env = run.call_args.kwargs['env']
        self.assertNotIn('GITHUB_TOKEN', env)
        self.assertNotEqual(env['HOME'], str(Path.home()))
        self.assertFalse((self.dest / 'maintenance-regeneration.json').exists())

    def test_publish_dry_run_and_wrong_commit(self):
        head = tool.git(self.project, 'rev-parse', 'HEAD').decode().strip()
        self.assertFalse(tool.publish(self.project, head, 'main')['executed'])
        with self.assertRaises(ValueError): tool.publish(self.project, self.old, 'main')

    def test_publish_reuses_exact_pr_without_push(self):
        head = tool.git(self.project, 'rev-parse', 'HEAD').decode().strip()
        original = tool.subprocess.check_output
        def mocked(command, **kwargs):
            if command[0] != 'gh': return original(command, **kwargs)
            if command[1:3] == ['repo', 'view']:
                return json.dumps({'nameWithOwner': 'fixture/project'})
            return json.dumps([{'url': 'https://example.invalid/pr/1', 'headRefOid': head, 'baseRefName': 'main'}])
        with patch.object(tool.subprocess, 'check_output', side_effect=mocked):
            self.assertTrue(tool.publish(self.project, head, 'main', True)['reused'])

    def test_regeneration_success_receipt_with_mocked_builder(self):
        self.prepare()
        self.put(self.dest / 'packages/ondevice-engine/scripts/test_seeded_soak.py', '# fixture')
        generated = self.dest / 'packages/ondevice-engine/build/generated'
        commands = []
        def build(command, **kwargs):
            commands.append(command)
            if len(commands) == 1:
                self.put(generated / 'catalogue.jsonl', '{"name":"fixture","setCode":"A","collectorNumber":"2"}\n')
                self.put(generated.parent / 'engine/mage/mobile/card-metadata.jsonl.gz', 'fixture metadata bytes')
                self.put(generated / 'registry-report.json', json.dumps({'registryHash': 'b' * 64}))
                self.put(generated / 'commander-set-codes.json', json.dumps({'upstreamCommit': self.new, 'eternalLegalSetCodes': ['A']}))
        with patch.object(tool.subprocess, 'run', side_effect=build):
            review = tool.regenerate(self.dest, True)
        self.assertEqual([c[1] for c in commands], [
            'scripts/build_jvm.sh'])
        receipt = json.loads((self.dest / 'maintenance-regeneration.json').read_bytes())
        self.assertEqual(receipt['generatedDigest'], tool.digest(tool.encoded(review)))
        with self.assertRaisesRegex(ValueError, 'fresh candidate'): tool.regenerate(self.dest, True)

    def test_publish_creation_with_mocked_external_commands(self):
        head = tool.git(self.project, 'rev-parse', 'HEAD').decode().strip()
        original_output = tool.subprocess.check_output
        original_run = tool.subprocess.run
        pushes = []
        def output(command, **kwargs):
            if command[0] != 'gh': return original_output(command, **kwargs)
            if command[1:3] == ['repo', 'view']: return '{"nameWithOwner":"fixture/project"}'
            if command[1:3] == ['pr', 'list']: return '[]'
            self.assertIn('--draft', command)
            return 'https://example.invalid/pr/2\n'
        def run(command, **kwargs):
            if 'push' in command:
                pushes.append(command)
                return subprocess.CompletedProcess(command, 0)
            return original_run(command, **kwargs)
        with patch.object(tool.subprocess, 'check_output', side_effect=output), patch.object(tool.subprocess, 'run', side_effect=run):
            result = tool.publish(self.project, head, 'main', True)
        self.assertEqual(result['url'], 'https://example.invalid/pr/2')
        self.assertEqual(len(pushes), 1)
        self.assertNotIn('--force', pushes[0])
        self.assertIn('https://github.com/ineedsomesleep5/MagicMobile.git', pushes[0])
        self.assertEqual(pushes[0][-1], head + ':refs/heads/maintenance/xmage-' + self.old)

    def reviewed_fixture(self):
        self.prepare()
        generated = self.dest / 'packages/ondevice-engine/build/generated'
        rows = [{'name': name, 'setCode': code, 'collectorNumber': number} for name, code, number in
                [('Now available', 'A', '2'), ('Excluded', 'B', '3')]]
        self.put(generated / 'catalogue.jsonl', '\n'.join(json.dumps(v) for v in rows))
        self.put(generated.parent / 'engine/mage/mobile/card-metadata.jsonl.gz', 'fixture metadata bytes')
        self.put(generated / 'registry-report.json', json.dumps({'registryHash': 'b' * 64}))
        self.put(generated / 'commander-set-codes.json', json.dumps({'upstreamCommit': self.new, 'eternalLegalSetCodes': ['A']}))
        review = tool.generated_review(self.dest)
        approval = tool.digest(tool.encoded(review))
        self.put(self.dest / 'maintenance-regeneration.json', json.dumps({'generatedDigest': approval}))
        tool.accept_generated(self.dest, approval)
        return review

    def test_inventory_add_remove_exclusions_and_tampered_baseline(self):
        changes = self.reviewed_fixture()['inventory']
        self.assertEqual(changes['additions'], [['Now available', 'A', '2']])
        self.assertEqual(changes['removals'], [['Old', 'A', '1']])
        self.assertEqual(changes['newlyExcludedNames'], ['Excluded'])
        self.assertEqual(changes['resolvedExcludedNames'], ['Now available'])
        self.put(self.dest / 'maintenance-baseline-catalogue.json', '{}')
        with self.assertRaisesRegex(ValueError, 'baseline changed'): tool.inventory(self.dest)

    def test_post_review_order_receipt_and_five_deck_hashes(self):
        self.reviewed_fixture()
        plan = tool.validate(self.dest)
        self.assertEqual(plan['commands'][2][2], '--check')
        self.assertEqual(plan['commands'][3][1], 'scripts/test_tooling.sh')
        self.assertIn('swift', plan['commands'][5])
        def run(command, **kwargs):
            if command[0] == 'swift' and '../../apps/ios' in command:
                for name in ('token-triumph', 'first-flight', 'grave-danger', 'chaos-incarnate', 'draconic-destruction'):
                    self.put(Path(kwargs['env']['MAGICMOBILE_PRECON_EXPORT_DIR']) / (name + '.json'), '{}')
        with patch.object(tool.subprocess, 'run', side_effect=run):
            receipt = tool.validate(self.dest, True)
        self.assertEqual(len(receipt['deckSHA256']), 5)

    def test_post_review_requires_approval_and_stops_on_failure(self):
        self.reviewed_fixture()
        with patch.object(tool.subprocess, 'run', side_effect=subprocess.CalledProcessError(1, 'fixture')) as run:
            with self.assertRaises(subprocess.CalledProcessError): tool.validate(self.dest, True)
        self.assertEqual(run.call_count, 1)
        self.assertFalse((self.dest / 'maintenance-validation.json').exists())
        self.put(self.dest / 'maintenance-generated-review.json', '{}')
        with self.assertRaises(ValueError): tool.validate(self.dest)

    def test_dispatch_dry_run_remote_mismatch_and_explicit_dispatch(self):
        head = tool.git(self.project, 'rev-parse', 'HEAD').decode().strip()
        self.assertFalse(tool.dispatch(self.project, head)['executed'])
        original = tool.subprocess.check_output
        remote_head = self.old
        def output(command, **kwargs):
            if command[0] == 'gh': return json.dumps({'object': {'sha': remote_head}})
            return original(command, **kwargs)
        with patch.object(tool.subprocess, 'check_output', side_effect=output):
            with self.assertRaisesRegex(ValueError, 'Remote candidate'): tool.dispatch(self.project, head, True)
            remote_head = head
            original_run = tool.subprocess.run
            calls = []
            def run(command, **kwargs):
                if command[0] == 'gh': calls.append(command); return subprocess.CompletedProcess(command, 0)
                return original_run(command, **kwargs)
            with patch.object(tool.subprocess, 'run', side_effect=run):
                self.assertTrue(tool.dispatch(self.project, head, True)['executed'])
            self.assertEqual(calls[0][3], tool.NON_SIM)

    def test_existing_draft_fast_forward_and_closed_refusal(self):
        before = tool.git(self.project, 'rev-parse', 'HEAD').decode().strip()
        self.put(self.project / 'reviewed-change', 'new revision')
        after = self.commit(self.project)
        original_output, original_run = tool.subprocess.check_output, tool.subprocess.run
        state = 'OPEN'; pushes = []
        def output(command, **kwargs):
            if command[0] == 'gh': return json.dumps([{'url': 'fixture', 'headRefOid': before,
                'baseRefName': 'main', 'isDraft': True, 'state': state}])
            return original_output(command, **kwargs)
        def run(command, **kwargs):
            if 'push' in command: pushes.append(command); return subprocess.CompletedProcess(command, 0)
            return original_run(command, **kwargs)
        with patch.object(tool.subprocess, 'check_output', side_effect=output), patch.object(tool.subprocess, 'run', side_effect=run):
            self.assertTrue(tool.publish(self.project, after, 'main', True)['updated'])
            self.assertEqual(len(pushes), 1)
            state = 'CLOSED'
            with self.assertRaisesRegex(ValueError, 'open draft'): tool.publish(self.project, after, 'main', True)

    def test_export_cannot_discover_enclosing_repository(self):
        self.dest = self.project / 'exported-candidate'
        self.prepare()
        code = ('import subprocess; '
                'r=subprocess.run(["git","rev-parse","--show-toplevel"],capture_output=True); '
                'assert r.returncode != 0, r.stdout; '
                'r=subprocess.run(["git","-C",".upstream/mage","rev-parse","HEAD"],capture_output=True,text=True); '
                f'assert r.returncode == 0 and r.stdout.strip() == "{self.new}", r.stderr')
        tool.run_commands(self.dest, [[tool.sys.executable, '-c', code]], 'git-boundary')

    def test_changed_modules_resolve_nearest_pom(self):
        self.put(self.repo / 'Plugins/Human/pom.xml', '<project/>')
        self.put(self.repo / 'Plugins/Human/src/New.java', 'class New {}')
        report = tool.detect(self.repo, self.lock, self.commit(self.repo), self.repository_lock)
        self.assertIn('Plugins/Human', report['changedModules'])

    def test_publisher_rejects_non_ancestor_without_push(self):
        head = tool.git(self.project, 'rev-parse', 'HEAD').decode().strip()
        original = tool.subprocess.check_output
        def output(command, **kwargs):
            if command[0] == 'gh': return json.dumps([{'url': 'fixture', 'headRefOid': self.old,
                'baseRefName': 'main', 'isDraft': True, 'state': 'OPEN'}])
            return original(command, **kwargs)
        with patch.object(tool.subprocess, 'check_output', side_effect=output):
            with self.assertRaises(subprocess.CalledProcessError): tool.publish(self.project, head, 'main', True)

    def test_repository_lock_update_passes_actual_guard_and_rejects_tamper(self):
        path = tool.REPOSITORY_SOURCES + 'CardInfo.java'
        self.put(self.repo / path, 'class CardInfo { int reviewedChange; }')
        new = self.commit(self.repo)
        self.report = tool.detect(self.repo, self.lock, new, self.repository_lock)
        self.prepare()
        package = self.dest / 'packages/ondevice-engine'
        lock = json.loads((package / 'platform/repository-sources.json').read_bytes())
        self.assertEqual(lock['commit'], new)
        self.assertNotEqual(lock['blobs']['CardInfo.java'], self.repository_lock['blobs']['CardInfo.java'])
        status = json.loads((package / 'implementation-status.json').read_bytes())
        self.assertEqual(status['upstreamCommit'], new)
        self.assertEqual(status['status'], 'upstream-candidate-unverified')
        self.assertIsNone(status['currentCandidate']['nativeArtifact'])
        self.assertIsNone(status['currentCandidate']['appSourceCommit'])
        self.assertEqual(status['verification']['state'], 'not-run')
        self.assertEqual(status['previousStatus']['record']['historicalEvidence'], {'upstream': self.old, 'passed': True})
        self.assertEqual(status['previousStatus']['record']['currentCandidate']['nativeArtifact'], 123)
        self.assertEqual(status['previousStatus']['record']['verification']['ciState'], 'passed')
        output = self.root / 'actual-repository-output'
        command = [tool.sys.executable, '-B', str(package / 'scripts/prepare_mobile_repository.py'),
                   '--checkout', str(package / '.upstream/mage'), '--mode', 'export', '--output', str(output)]
        result = subprocess.run(command, text=True, capture_output=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        manifest = json.loads((output / 'repository-patch-manifest.json').read_bytes())
        self.assertEqual(manifest['upstream'], new)
        self.assertEqual(manifest['sourceBlobs'], lock['blobs'])
        self.assertIn('jdbc:h2:mem:mobile_catalogue_export', (output / 'mage/cards/repository/DatabaseUtils.java').read_text())
        self.put(package / '.upstream/mage' / path, 'class CardInfo { int unreviewed; }')
        result = subprocess.run(command, text=True, capture_output=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('Unreviewed repository source', result.stderr)
        # Restoring the OLD pin reproduces the original blocker in the actual guard.
        self.put(package / 'platform/repository-sources.json', json.dumps(self.repository_lock))
        result = subprocess.run(command, text=True, capture_output=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('Unreviewed upstream revision', result.stderr)

    def test_repository_lock_old_blob_commit_and_candidate_mode_rejections(self):
        broken = json.loads(json.dumps(self.repository_lock))
        broken['commit'] = self.new
        with self.assertRaisesRegex(ValueError, 'locks? disagree|lock disagree'):
            tool.detect(self.repo, self.lock, self.new, broken)
        broken['commit'] = self.old
        broken['blobs']['CardInfo.java'] = '0' * 40
        with self.assertRaisesRegex(ValueError, 'Old repository source'):
            tool.detect(self.repo, self.lock, self.new, broken)
        path = self.repo / tool.REPOSITORY_SOURCES / 'CardInfo.java'
        path.unlink(); path.symlink_to('/etc/passwd')
        with self.assertRaisesRegex(ValueError, 'not a regular file'):
            tool.detect(self.repo, self.lock, self.commit(self.repo), self.repository_lock)


if __name__ == '__main__':
    unittest.main()
