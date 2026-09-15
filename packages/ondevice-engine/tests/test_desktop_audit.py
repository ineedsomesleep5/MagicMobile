"""Actual shell audit against fake jdeps and disposable local Git fixtures only."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

SCRIPT = Path(__file__).resolve().parents[1] / 'scripts/test_desktop_dependencies.sh'
INPUTS = (
    'build/engine',
    '.upstream/mage/Mage/target/classes',
    '.upstream/mage/Mage.Common/target/classes',
    '.upstream/mage/Mage.Sets/target/classes',
    '.upstream/mage/Mage.Server.Plugins/Mage.Player.Human/target/classes',
    '.upstream/mage/Mage.Server.Plugins/Mage.Player.AI/target/classes',
    '.upstream/mage/Mage.Server.Plugins/Mage.Player.AI.MAD/target/classes',
    '.upstream/mage/Mage.Server.Plugins/Mage.Deck.Constructed/target/classes',
    '.upstream/mage/Mage.Server.Plugins/Mage.Game.CommanderFreeForAll/target/classes',
)


class DesktopAuditTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.temp = Path(temporary.name).resolve()
        self.project = self.temp / 'candidate export'
        self.package = self.project / 'packages/ondevice-engine'
        scripts = self.package / 'scripts'
        scripts.mkdir(parents=True)
        shutil.copyfile(SCRIPT, scripts / SCRIPT.name)
        for directory in INPUTS:
            (self.package / directory).mkdir(parents=True)
        (self.package / 'build/runtime-classpath.txt').write_text('fixture-classpath\n')
        self.bin = self.temp / 'bin'
        self.bin.mkdir()
        fake = self.bin / 'jdeps'
        fake.write_text('#!' + sys.executable + '\n' +
                        'import json, os, sys\n' +
                        'with open(os.environ["JDEPS_LOG"], "a") as out: out.write(json.dumps(sys.argv[1:])+"\\n")\n' +
                        'print("fixture static output")\n' +
                        'sys.exit(int(os.environ.get("JDEPS_FAIL", "0")) if "--version" not in sys.argv else 0)\n')
        fake.chmod(0o755)
        # Git operations and commits below are confined to disposable fixtures;
        # they never touch the user's checkout, index, config, or remotes.
        self.env = {key: value for key, value in os.environ.items() if not key.startswith('GIT_')}
        self.env.update(PATH=str(self.bin) + os.pathsep + os.environ['PATH'],
                        JDEPS_LOG=str(self.temp / 'jdeps.jsonl'), GIT_CONFIG_NOSYSTEM='1',
                        GIT_CONFIG_GLOBAL=os.devnull, GIT_TERMINAL_PROMPT='0')
        self.upstream = self.package / '.upstream/mage'
        self.upstream_sha = self.init_repo(self.upstream)

    def git(self, root, *args):
        return subprocess.check_output(['git', '-C', str(root), *args], env=self.env,
                                       text=True, stderr=subprocess.PIPE).strip()

    def init_repo(self, root):
        self.git(root, 'init', '-q')
        (root / 'tracked-fixture').write_text('fixture\n')
        self.git(root, 'add', 'tracked-fixture')
        self.git(root, '-c', 'user.name=Fixture', '-c', 'user.email=fixture@example.invalid',
                 '-c', 'commit.gpgSign=false', '-c', 'core.hooksPath=/dev/null', 'commit', '-qm', 'fixture only')
        return self.git(root, 'rev-parse', 'HEAD')

    def run_audit(self, expected=0):
        result = subprocess.run(['bash', str(self.package / 'scripts' / SCRIPT.name)],
                                cwd=self.temp, env=self.env, capture_output=True, text=True, timeout=10)
        self.assertEqual(result.returncode, expected, result.stderr)
        if expected:
            return
        evidence = self.package / 'evidence/desktop-api'
        environment = (evidence / 'environment.txt').read_text()
        self.assertIn('XMage source: ' + self.upstream_sha, environment)
        self.assertIn('not proof of compiled class source provenance', environment)
        calls = [json.loads(line) for line in (self.temp / 'jdeps.jsonl').read_text().splitlines()]
        self.assertEqual(calls[0], ['--version'])
        prefix = ['-J-Xmx1g', '--multi-release', '17', '--class-path', 'fixture-classpath']
        self.assertEqual(calls[1], prefix + ['-verbose:class', '--regex',
                                          r'java\.awt\..*|javax\.swing\..*|javax\.imageio\..*', *INPUTS])
        self.assertEqual(calls[2], prefix + ['--missing-deps', *INPUTS])
        for file in ('class-references.txt', 'missing-references.txt', 'SCOPE.txt'):
            self.assertTrue((evidence / file).is_file())
        return environment

    def test_export_without_git_runs_full_audit(self):
        environment = self.run_audit()
        self.assertIn('unverified-exported-source', environment)
        self.assertNotIn('observed checkout HEAD:', environment)
        self.assertFalse((self.project / '.git').exists())

    def test_export_never_borrows_enclosing_repository_head(self):
        enclosing_sha = self.init_repo(self.temp)
        environment = self.run_audit()
        self.assertIn('unverified-exported-source', environment)
        self.assertNotIn('observed checkout HEAD: ' + enclosing_sha, environment)
        self.assertFalse((self.project / '.git').exists())

    def test_exact_checkout_reports_observed_head_and_clean_tracked_state(self):
        head = self.init_repo(self.project)
        environment = self.run_audit()
        self.assertIn('observed checkout HEAD: ' + head, environment)
        self.assertIn('tracked worktree: clean', environment)

    def test_unstaged_tracked_changes_are_reported(self):
        self.init_repo(self.project)
        (self.project / 'tracked-fixture').write_text('changed\n')
        self.assertIn('tracked worktree: dirty', self.run_audit())

    def test_staged_tracked_changes_are_reported(self):
        self.init_repo(self.project)
        (self.project / 'tracked-fixture').write_text('changed\n')
        self.git(self.project, 'add', 'tracked-fixture')
        self.assertIn('tracked worktree: dirty', self.run_audit())

    def test_jdeps_failure_still_fails_audit(self):
        self.env['JDEPS_FAIL'] = '7'
        self.run_audit(expected=7)


if __name__ == '__main__':
    unittest.main()
