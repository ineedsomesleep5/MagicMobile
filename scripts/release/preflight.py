#!/usr/bin/env python3
"""Early local checks, not release approval. Plan is read-only; run saves fresh logs.

No network lookup, native rebuild, simulator boot, signing or upload is performed.
No results are reused to bypass CI or release gates.
"""
import argparse
import fcntl
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import time

ROOT = Path(__file__).resolve().parents[2]
DEVELOPER_DIR = '/Applications/Xcode.app/Contents/Developer'


def load(path, name):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def git(repo, *args):
    return subprocess.check_output(['git', '-C', str(repo), *args])


def source_snapshot(repo):
    """Include dirty and untracked nonignored inputs; never print file contents."""
    head = git(repo, 'rev-parse', 'HEAD').decode().strip()
    names = set(git(repo, 'ls-files', '-z', '--cached', '--others', '--exclude-standard').split(b'\0')) - {b''}
    digest = hashlib.sha256(head.encode())
    for name in sorted(names):
        path = repo / os.fsdecode(name)
        digest.update(name + b'\0')
        if path.is_symlink():
            digest.update(b'link:' + os.fsencode(os.readlink(path)))
        elif path.is_file():
            digest.update(str(path.stat().st_mode).encode() + b'\0')
            with path.open('rb') as stream:
                for block in iter(lambda: stream.read(1024 * 1024), b''):
                    digest.update(block)
        elif path.is_dir():
            # Submodules need their own verification; don't silently fingerprint them as files.
            raise ValueError('Directory/submodule input requires separate verification: ' + os.fsdecode(name))
        else:
            digest.update(b'missing')
        digest.update(b'\0')
    return {'commit': head, 'workingTreeSHA256': digest.hexdigest()}


def commands(profile):
    checks = [
        ('diff-check', ['git', 'diff', '--check', 'HEAD']),
        ('ci-tools', [sys.executable, '-m', 'unittest', 'discover', '-s', 'scripts/ci', '-p', 'test_*.py']),
        ('release-tools', [sys.executable, '-m', 'unittest', 'discover', '-s', 'scripts/release', '-p', 'test_*.py']),
        ('ui-runner', [sys.executable, '-m', 'unittest', 'discover', '-s', 'scripts/deck-studio', '-p', 'test_ios_ui_tests.py']),
        ('timing-tools', [sys.executable, '-m', 'unittest', 'discover', '-s', 'scripts', '-p', 'test_workflow_metrics.py']),
        ('upload-syntax', ['bash', '-n', 'scripts/ios/deploy-testflight.sh']),
        ('distribution-syntax', ['bash', '-n', 'scripts/ios/distribute-testflight-groups.sh']),
    ]
    if profile == 'ios-fast':
        checks += [
            ('generated-project', [sys.executable, '-c', "import runpy; runpy.run_path('scripts/deck-studio/ios-ui-tests.py')['project_is_native'](verify_generated=True)"]),
            ('standalone-deck-contracts', ['bash', 'scripts/deck-studio/test-core.sh']),
            ('engine-swift-contracts', ['swift', 'test', '--package-path', 'packages/ondevice-engine/swift', '--jobs', '2']),
            ('presentation-contracts', ['swift', 'test', '--package-path', 'apps/ios', '--jobs', '2']),
        ]
    elif profile != 'tooling':
        raise ValueError('Unknown profile')
    return checks


def native_decision(repo, engine_commit=None):
    """Use the existing conservative verifier; never substitute a new reuse policy."""
    scope = 'Source equivalence only; artifact bytes, provenance, linkage and runtime gates still required.'
    try:
        if engine_commit is None:
            path = repo / 'packages/ondevice-engine/build/native-candidate-provenance.json'
            if not path.is_file() or path.is_symlink():
                return {'state': 'unknown', 'reason': 'No local native provenance receipt. Run the existing native resolver.', 'scope': scope}
            engine_commit = json.loads(path.read_text())['engineSourceCommit']
        verifier = load(repo / 'packages/ondevice-engine/scripts/verify_native_candidate.py', 'preflight_native')
        identity = verifier.source_identity(repo, engine_commit)
        untracked = git(repo, 'ls-files', '--others', '--exclude-standard').decode().strip()
        if untracked:
            return {'state': 'unknown', 'reason': 'Untracked source exists; review and commit before deciding native reuse.', 'scope': scope}
        return {'state': 'equivalent-source', 'engineCommit': engine_commit,
                'inputSHA256': identity['equivalentInputTreeSHA256'], 'scope': scope,
                'next': 'Verify retained artifact/staging; do not dispatch a new engine build solely for UI changes.'}
    except ValueError as error:
        changed = str(error).startswith('App and native artifact have different engine inputs:')
        return {'state': 'different-source' if changed else 'unknown', 'reason': str(error), 'scope': scope,
                'next': 'Look for another exact-input artifact before authorizing a new native build.'}
    except (OSError, KeyError, TypeError, subprocess.CalledProcessError):
        return {'state': 'unknown', 'reason': 'Source is uncommitted, receipt is invalid, or comparison is unavailable. No reuse or rebuild decision made.', 'scope': scope}


def plan(repo, profile, engine_commit=None):
    actual = Path(os.fsdecode(git(repo, 'rev-parse', '--show-toplevel')).strip()).resolve()
    if actual != repo.resolve():
        raise ValueError('Run against the repository root, not another checkout')
    return {'checkout': str(repo), 'profile': profile, 'source': source_snapshot(repo),
            'checks': [{'name': name, 'command': command} for name, command in commands(profile)],
            'nativeDecision': native_decision(repo, engine_commit),
            'scope': 'Early development checks only. Not CI, UI execution, native runtime or release acceptance.'}


def output_root(repo):
    root = repo / 'build_output/preflight'
    if any(path.is_symlink() for path in (root, *root.parents)):
        raise ValueError('Refusing symlinked preflight output')
    root.mkdir(parents=True, exist_ok=True)
    return root


def execute(command, log, repo):
    # Clear opt-in live fixture variables: this early check does not request network/audits.
    env = {key: value for key, value in os.environ.items()
           if not key.startswith('MM_LIVE_')
           and key not in ('MAGICMOBILE_BULK_FIXTURE', 'MAGICMOBILE_ARTWORK_AUDIT_DIR',
                           'MAGICMOBILE_PRECON_EXPORT_DIR')}
    env['DEVELOPER_DIR'] = DEVELOPER_DIR
    with log.open('xb') as stream:
        result = subprocess.run(command, cwd=repo, env=env, stdout=stream,
                                stderr=subprocess.STDOUT, timeout=900)
    return result.returncode


def run(repo, profile, engine_commit=None, runner=execute):
    root = output_root(repo)
    lock_path = root / '.lock'
    if lock_path.is_symlink():
        raise ValueError('Refusing symlinked preflight lock')
    with lock_path.open('a+b') as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError as error:
            raise ValueError('Another preflight is already running in this checkout') from error
        report = plan(repo, profile, engine_commit)
        directory = Path(tempfile.mkdtemp(prefix=profile + '-', dir=root))
        report.update({'state': 'running', 'results': [], 'evidenceDirectory': str(directory)})
        def save():
            (directory / 'report.json').write_text(json.dumps(report, indent=2) + '\n')
        save()
        start = time.monotonic()
        try:
            for number, check in enumerate(report['checks'], 1):
                log = directory / f'{number:02d}-{check["name"]}.log'
                before = time.monotonic()
                print(f'Checking {check["name"]} (log: {log})', flush=True)
                code = runner(check['command'], log, repo)
                report['results'].append({'name': check['name'], 'exitCode': code,
                    'seconds': round(time.monotonic() - before, 3), 'log': str(log)})
                save()
                if code:
                    report['state'] = 'failed'
                    break
            else:
                report['state'] = 'passed'
            report['sourceAfter'] = source_snapshot(repo)
            if report['sourceAfter'] != report['source']:
                report['state'] = 'source-changed'
        except BaseException as error:
            report.update({'state': 'interrupted', 'errorType': type(error).__name__})
            raise
        finally:
            report['elapsedSeconds'] = round(time.monotonic() - start, 3)
            save()
        return report


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('mode', choices=('plan', 'run'))
    parser.add_argument('--profile', choices=('tooling', 'ios-fast'), default='tooling')
    parser.add_argument('--engine-commit', help='Exact native source commit, not a branch name')
    args = parser.parse_args()
    try:
        report = (plan if args.mode == 'plan' else run)(ROOT, args.profile, args.engine_commit)
        print(json.dumps(report, indent=2))
        return 0 if args.mode == 'plan' or report['state'] == 'passed' else 1
    except (ValueError, OSError, subprocess.SubprocessError) as error:
        print('preflight: ' + str(error), file=sys.stderr)
        return 2


if __name__ == '__main__':
    raise SystemExit(main())
