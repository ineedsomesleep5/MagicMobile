#!/usr/bin/env python3
"""Inspect upstream objects and prepare an explicitly reviewed, isolated candidate."""
import argparse
import hashlib
import io
import json
import os
from pathlib import Path
import re
import subprocess
import tarfile
import tempfile
import types
import sys

PACKAGE = Path(__file__).resolve().parents[2] / 'packages/ondevice-engine'
REPOSITORY = 'ineedsomesleep5/MagicMobile'
BASELINE = 'apps/ios/MagicMobile/Resources/ondevice-catalogue.json'
NON_SIM = 'magicmobile-issue4-nonsimulator.yml'
REPOSITORY_SOURCES = 'Mage/src/main/java/mage/cards/repository/'
IDENTITIES = (
    'engine/xmage/src/main/java/io/magicmobile/xmage/XmageEngine.java',
    'engine/tools/CommanderSetExporter.java',
    'engine/tools/CardMetadataExporter.java',
    'scripts/export_ios_catalogue.py',
)
GENERATED = {'CATALOGUE_SHA256': 'generated/catalogue.jsonl',
             'REPORT_SHA256': 'generated/registry-report.json',
             'SET_ELIGIBILITY_SHA256': 'generated/commander-set-codes.json',
             'METADATA_SHA256': 'engine/mage/mobile/card-metadata.jsonl.gz'}


def encoded(value):
    return (json.dumps(value, sort_keys=True, indent=2) + '\n').encode()


def digest(data):
    return hashlib.sha256(data).hexdigest()


def git(repo, *args):
    # No credentials, global configuration, hooks, replace refs or external diff.
    env = {k: v for k, v in os.environ.items()
           if k in ('PATH', 'SYSTEMROOT', 'TMPDIR')}
    env.update(GIT_CONFIG_NOSYSTEM='1', GIT_CONFIG_GLOBAL=os.devnull,
               GIT_TERMINAL_PROMPT='0', GIT_NO_REPLACE_OBJECTS='1')
    return subprocess.check_output(
        ['git', '-c', 'core.hooksPath=/dev/null', '-C', str(repo), *args],
        env=env, timeout=180)


def exact(sha):
    if not re.fullmatch('[0-9a-f]{40}', sha):
        raise ValueError('Expected an exact lowercase 40-character commit SHA')
    return sha


def write_new(path, data):
    with Path(path).open('xb') as stream:
        stream.write(data)


def object_info(repo, sha, path):
    entries = git(repo, 'ls-tree', '-z', sha, '--', path).split(b'\0')
    entries = [entry for entry in entries if entry]
    if not entries:
        return None
    metadata, name = entries[0].split(b'\t', 1)
    mode, kind, oid = metadata.decode().split()
    if len(entries) != 1 or name.decode() != path or kind != 'blob':
        raise ValueError('Not a single source blob: ' + path)
    data = git(repo, 'cat-file', 'blob', oid)
    return {'blob': oid, 'mode': mode, 'sha256': digest(data)}


def detect(repo, lock, candidate, repository_lock):
    old = exact(lock['commit']); candidate = exact(candidate)
    if repository_lock['commit'] != old:
        raise ValueError('Repository-source lock and upstream lock disagree')
    for sha in (old, candidate):
        if git(repo, 'cat-file', '-t', sha).strip() != b'commit':
            raise ValueError('Object is not a commit')
    paths = sorted(p.decode() for p in git(
        repo, 'diff', '--no-ext-diff', '--no-renames', '--name-only', '-z', old, candidate).split(b'\0') if p)
    changes = [{'path': p, 'old': object_info(repo, old, p),
                'candidate': object_info(repo, candidate, p)} for p in paths]
    sources = {}
    for path, expected in lock['sourceBlobs'].items():
        before = object_info(repo, old, path)
        after = object_info(repo, candidate, path)
        if not before or before['blob'] != expected or before['mode'] != '100644':
            raise ValueError('Old source does not match lock: ' + path)
        if not after or after['mode'] != '100644':
            raise ValueError('Candidate source missing or not a regular file: ' + path)
        sources[path] = {'old': before, 'candidate': after}
    repository_sources = {}
    for name, expected in repository_lock['blobs'].items():
        if Path(name).name != name:
            raise ValueError('Repository-source key must be a basename')
        path = REPOSITORY_SOURCES + name
        before, after = object_info(repo, old, path), object_info(repo, candidate, path)
        if not before or before['blob'] != expected or before['mode'] != '100644':
            raise ValueError('Old repository source does not match reviewed regular blob: ' + path)
        if not after or after['mode'] != '100644':
            raise ValueError('Candidate repository source missing or not a regular file: ' + path)
        repository_sources[name] = {'path': path, 'old': before, 'candidate': after}
    if set(repository_sources) != {'CardRepository.java', 'ExpansionRepository.java',
                                  'CardCriteria.java', 'DatabaseUtils.java', 'CardInfo.java'}:
        raise ValueError('Expected the five reviewed repository source files')
    dependencies = [p for p in paths if Path(p).name in (
        'pom.xml', 'build.gradle', 'build.gradle.kts', 'gradle.lockfile',
        'settings.gradle', 'settings.gradle.kts') or p.startswith('.mvn/')
        or Path(p).suffix in ('.jar', '.lock')]
    module_dirs = set()
    for sha in (old, candidate):
        for name in git(repo, 'ls-tree', '-r', '--name-only', '-z', sha).split(b'\0'):
            if name and Path(name.decode()).name == 'pom.xml':
                module_dirs.add(Path(name.decode()).parent)
    modules = set()
    for path in paths:
        ancestors = [p for p in Path(path).parents if p in module_dirs]
        modules.add(str(ancestors[0]) if ancestors and ancestors[0] != Path('.') else '(root)')
    key = digest(encoded({'repository': lock['repository'], 'old': old, 'candidate': candidate}))
    return {'schema': 1, 'repository': lock['repository'], 'old': old,
            'candidate': candidate, 'updateAvailable': old != candidate,
            'compareURL': f'https://github.com/magefree/mage/compare/{old}...{candidate}',
            'changedModules': sorted(modules),
            'dedupKey': key, 'changes': changes, 'dependencyPaths': dependencies,
            'sourceBlobs': sources, 'repositorySourceBlobs': repository_sources}


def archive(repo, sha, destination):
    """Extract data only; disallow symlinks, submodules and unsafe paths."""
    if any(entry.startswith(b'160000 ') for entry in git(repo, 'ls-tree', '-r', '-z', sha).split(b'\0')):
        raise ValueError('Submodules require separate review; archive would omit them')
    with tarfile.open(fileobj=io.BytesIO(git(repo, 'archive', sha))) as bundle:
        members = bundle.getmembers()
        for member in members:
            path = Path(member.name)
            if path.is_absolute() or '..' in path.parts or any(p.lower() == '.git' for p in path.parts) or not (member.isdir() or member.isfile()):
                raise ValueError('Unsafe archive entry: ' + member.name)
        bundle.extractall(destination, members=members, filter='data')


def prepare(repo, project, report, approval, destination):
    if digest(encoded(report)) != approval:
        raise ValueError('Detection digest has not been explicitly approved')
    package = project / 'packages/ondevice-engine'
    lock = json.loads((package / 'upstream.lock.json').read_bytes())
    repository_lock = json.loads((package / 'platform/repository-sources.json').read_bytes())
    if detect(repo, lock, report['candidate'], repository_lock) != report or not report['updateAvailable']:
        raise ValueError('Report is stale, modified or has no update')
    if git(project, 'status', '--porcelain', '--untracked-files=all').strip():
        raise ValueError('Project must be a clean, committed source checkout')
    source = git(project, 'rev-parse', 'HEAD').decode().strip()
    destination.mkdir()  # Never reuse or overwrite an occupied tree.
    archive(project, source, destination)
    baseline = (destination / BASELINE).read_bytes()
    if json.loads(baseline)['upstreamCommit'] != report['old']:
        raise ValueError('Trusted shipped catalogue does not match the old lock')
    (destination / 'maintenance-baseline-catalogue.json').write_bytes(baseline)
    target = destination / 'packages/ondevice-engine'
    upstream = target / '.upstream/mage'
    upstream.mkdir(parents=True)
    archive(repo, report['candidate'], upstream)
    # Use the trusted port transformer, never import or execute upstream code.
    patcher = package / 'scripts/prepare_upstream.py'
    module = types.ModuleType('port_transform')
    module.__file__ = str(patcher)
    exec(compile(patcher.read_bytes(), str(patcher), 'exec'), module.__dict__)
    functions = {'CardImpl.java': module.patch_card, 'Sets.java': module.patch_sets,
                 'HumanPlayer.java': module.patch_human}
    outputs = {}
    for path, info in report['sourceBlobs'].items():
        data = (upstream / path).read_bytes()
        if module.git_blob(data) != info['candidate']['blob']:
            raise ValueError('Reviewed source blob mismatch: ' + path)
        outputs[path] = functions[Path(path).name](data.decode()).encode()
    factory = 'Mage/src/main/java/mage/cards/MobileCardFactories.java'
    if (upstream / factory).exists():
        raise ValueError('Upstream now owns the injected factory path; review required')
    outputs[factory] = module.FACTORY.encode()
    for path, data in outputs.items():
        (upstream / path).write_bytes(data)
    (upstream / '.mobile-patch.json').write_bytes(encoded({
        'commit': report['candidate'], 'outputs': {p: digest(b) for p, b in outputs.items()}}))
    lock['commit'] = report['candidate']
    lock['sourceBlobs'] = {p: v['candidate']['blob'] for p, v in report['sourceBlobs'].items()}
    (target / 'upstream.lock.json').write_bytes(encoded(lock))
    repository_lock['commit'] = report['candidate']
    repository_lock['blobs'] = {name: info['candidate']['blob']
                              for name, info in report['repositorySourceBlobs'].items()}
    (target / 'platform/repository-sources.json').write_bytes(encoded(repository_lock))
    status_path = target / 'implementation-status.json'
    status = json.loads(status_path.read_bytes())
    if status['upstreamCommit'] != report['old']:
        raise ValueError('Implementation status upstream identity differs from baseline')
    candidate_status = {key: status[key] for key in ('schema', 'targetRepository', 'acceptanceChecklist',
                                                    'upstreamMaintenance') if key in status}
    candidate_status.update({
        'upstreamCommit': report['candidate'], 'status': 'upstream-candidate-unverified',
        'currentCandidate': {'upstreamCommit': report['candidate'], 'state': 'unverified',
                             'appSourceCommit': None, 'engineSourceCommit': None,
                             'nativeArtifact': None, 'nativeRun': None, 'nativeState': 'not-run',
                             'physicalAcceptance': 'not-run'},
        'verification': {'state': 'not-run', 'sourceCommit': None,
                         'scope': 'New upstream candidate; prior results are historical only'},
        'nativeDeviceValidated': False,
        'previousStatus': {'scope': 'Historical baseline evidence; not validation of this candidate',
                           'record': status},
    })
    status_path.write_bytes(encoded(candidate_status))
    for path in IDENTITIES:
        text = (target / path).read_text()
        if text.count(report['old']) != 1:
            raise ValueError('Expected exactly one upstream identity: ' + path)
        (target / path).write_text(text.replace(report['old'], report['candidate']))
    # Bootstrap requires a real exact-HEAD checkout. Import objects without checkout,
    # so no checkout filters or upstream hooks can run over the transformed files.
    git(upstream, 'init')
    git(upstream, 'fetch', '--no-tags', str(repo.resolve()), report['candidate'])
    git(upstream, 'update-ref', 'HEAD', report['candidate'])
    git(upstream, 'read-tree', report['candidate'])
    state = {'schema': 1, 'projectCommit': source, 'detectionDigest': approval,
             'checkoutIdentity': 'exported candidate; no Git HEAD, not release source identity',
             'repositorySourceLockSHA256': digest((target / 'platform/repository-sources.json').read_bytes()),
             'baselineSHA256': digest(baseline),
             'candidate': report['candidate'], 'status': 'prepared; regeneration and review pending',
             'patcherSHA256': digest((package / 'scripts/prepare_upstream.py').read_bytes()),
             'patchedSources': {p: digest(b) for p, b in outputs.items()}}
    (destination / 'maintenance-candidate.json').write_bytes(encoded(state))
    return state


def inventory(candidate):
    """Compare candidate Commander inventory against the committed shipped baseline."""
    state = json.loads((candidate / 'maintenance-candidate.json').read_bytes())
    baseline = (candidate / 'maintenance-baseline-catalogue.json').read_bytes()
    if digest(baseline) != state['baselineSHA256']:
        raise ValueError('Trusted inventory baseline changed')
    old = json.loads(baseline)
    generated = candidate / 'packages/ondevice-engine/build/generated'
    rows = [json.loads(line) for line in (generated / 'catalogue.jsonl').read_bytes().splitlines() if line.strip()]
    eligible = json.loads((generated / 'commander-set-codes.json').read_bytes())
    # Trusted port normalization, without calling export() or checking OLD hash pins.
    path = PACKAGE / 'scripts/export_ios_catalogue.py'
    module = types.ModuleType('trusted_catalogue'); module.__file__ = str(path)
    exec(compile(path.read_bytes(), str(path), 'exec'), module.__dict__)
    cards, stats = module.normalize(rows, set(eligible['eternalLegalSetCodes']))
    def identities(values):
        return {(v['name'], v['setCode'], v['collectorNumber']) for v in values}
    before, after = identities(old['cards']), identities(cards)
    prior_exclusions = set(old.get('statistics', {}).get('unresolvableNames', []))
    current_exclusions = set(stats['unresolvableNames'])
    return {'scope': 'Commander-exported printing inventory versus trusted shipped catalogue; not full raw registry history',
            'baselineProjectCommit': state['projectCommit'], 'baselineSHA256': state['baselineSHA256'],
            'normalizerSHA256': digest(path.read_bytes()),
            'additions': [list(v) for v in sorted(after - before)],
            'removals': [list(v) for v in sorted(before - after)],
            'newlyExcludedNames': sorted(current_exclusions - prior_exclusions),
            'resolvedExcludedNames': sorted(prior_exclusions - current_exclusions),
            'baselineStatistics': old.get('statistics', {}), 'candidateStatistics': stats}


def generated_review(candidate):
    state = json.loads((candidate / 'maintenance-candidate.json').read_bytes())
    package = candidate / 'packages/ondevice-engine'
    lock = json.loads((package / 'upstream.lock.json').read_bytes())
    if lock['commit'] != state['candidate']:
        raise ValueError('Candidate lock changed')
    if digest((package / 'platform/repository-sources.json').read_bytes()) != state['repositorySourceLockSHA256']:
        raise ValueError('Reviewed repository source lock changed')
    for path, expected in state['patchedSources'].items():
        if digest((package / '.upstream/mage' / path).read_bytes()) != expected:
            raise ValueError('Prepared source changed: ' + path)
    generated = package / 'build/generated'
    hashes = {key: digest((package / 'build' / name).read_bytes()) for key, name in GENERATED.items()}
    registry = json.loads((generated / 'registry-report.json').read_bytes())
    eligibility = json.loads((generated / 'commander-set-codes.json').read_bytes())
    if eligibility['upstreamCommit'] != state['candidate']:
        raise ValueError('Generated eligibility has wrong upstream identity')
    value = registry['registryHash']
    if not re.fullmatch('[0-9a-f]{64}', value):
        raise ValueError('Invalid registry fingerprint')
    hashes['REGISTRY_HASH'] = value
    return {'candidate': state['candidate'], 'detectionDigest': state['detectionDigest'],
            'hashes': hashes, 'inventory': inventory(candidate)}


def accept_generated(candidate, approval):
    review = generated_review(candidate)
    if digest(encoded(review)) != approval:
        raise ValueError('Generated report digest has not been approved')
    exporter = candidate / 'packages/ondevice-engine/scripts/export_ios_catalogue.py'
    text = exporter.read_text()
    for key, value in review['hashes'].items():
        text, count = re.subn(r"^" + key + r" = '[0-9a-f]{64}'$", key + " = '" + value + "'", text, flags=re.M)
        if count != 1:
            raise ValueError('Expected exactly one hash constant: ' + key)
    exporter.write_text(text)
    (candidate / 'maintenance-generated-review.json').write_bytes(encoded(review))
    return review


def regenerate(candidate, execute=False):
    """Explicit build stage; separate from all credential-bearing publication."""
    state = json.loads((candidate / 'maintenance-candidate.json').read_bytes())
    package = candidate / 'packages/ondevice-engine'
    commands = [['bash', 'scripts/build_jvm.sh']]
    if not execute:
        return {'commands': commands, 'executed': False}
    if (package / 'build').exists():
        raise ValueError('Regeneration requires a fresh candidate without build outputs')
    if not (package / 'scripts/test_seeded_soak.py').is_file():
        raise ValueError('Root-owned seeded soak must be integrated before regeneration')
    run_commands(candidate, commands, 'build')
    review = generated_review(candidate)
    write_new(candidate / 'maintenance-inventory.json', encoded(review['inventory']))
    write_new(candidate / 'maintenance-review.json', encoded(review))
    (candidate / 'maintenance-regeneration.json').write_bytes(encoded({
        'candidate': state['candidate'], 'commands': commands,
        'generatedDigest': digest(encoded(review)), 'status': 'generated; human hash review and validation pending'}))
    return review


def run_commands(candidate, commands, stage, extra_env=None):
    # Keep the isolated Maven cache for the subsequent JVM stages: classpaths point
    # into it. This directory is candidate-local and never a credential-bearing HOME.
    home = candidate.resolve() / '.maintenance-build-home'
    home.mkdir(exist_ok=True)
    env = {k: os.environ[k] for k in ('PATH', 'JAVA_HOME', 'DEVELOPER_DIR', 'TMPDIR') if k in os.environ}
    env.update(HOME=str(home), GIT_CONFIG_NOSYSTEM='1', GIT_CONFIG_GLOBAL=os.devnull,
               GIT_TERMINAL_PROMPT='0', GIT_CEILING_DIRECTORIES=str(candidate.resolve()),
               MAVEN_OPTS='-Xmx4g', PYTHONDONTWRITEBYTECODE='1')
    env.update(extra_env or {})
    for index, command in enumerate(commands):
        with (candidate / f'maintenance-{stage}-{index}.log').open('xb') as log:
            subprocess.run(command, cwd=candidate / 'packages/ondevice-engine', env=env, stdout=log,
                           stderr=subprocess.STDOUT, timeout=7200, check=True)


def validate(candidate, execute=False):
    """Post-review gates; never validate new outputs against old expected pins."""
    review = generated_review(candidate)
    if json.loads((candidate / 'maintenance-generated-review.json').read_bytes()) != review:
        raise ValueError('Current generated outputs must have an accepted human review receipt')
    if json.loads((candidate / 'maintenance-regeneration.json').read_bytes())['generatedDigest'] != digest(encoded(review)):
        raise ValueError('Regeneration receipt does not match reviewed outputs')
    decks = candidate.resolve() / 'maintenance-precons'
    commands = [
        [sys.executable, 'scripts/export_ios_catalogue.py', '--self-test'],
        [sys.executable, 'scripts/export_ios_catalogue.py'],
        [sys.executable, 'scripts/export_ios_catalogue.py', '--check'],
        ['bash', 'scripts/test_tooling.sh'], ['bash', 'scripts/test_native_boundary.sh'],
        ['swift', 'test', '--package-path', 'swift', '--jobs', '2'],
        ['swift', 'test', '--package-path', '../../apps/ios', '--jobs', '2'],
        ['bash', 'scripts/test_swift_close.sh'], ['bash', 'scripts/test_runtime_manager.sh'],
        ['bash', 'scripts/test_real_engine.sh'],
        [sys.executable, 'scripts/test_seeded_soak.py'],
        ['bash', 'scripts/test_desktop_dependencies.sh'],
        [sys.executable, 'scripts/test_ios_precons.py', str(decks)],
    ]
    if not execute:
        return {'commands': commands, 'executed': False}
    decks.mkdir()  # Refuse stale exported decks.
    run_commands(candidate, commands, 'validation', {'MAGICMOBILE_PRECON_EXPORT_DIR': str(decks)})
    expected = {'token-triumph', 'first-flight', 'grave-danger', 'chaos-incarnate', 'draconic-destruction'}
    if {p.stem for p in decks.glob('*.json')} != expected:
        raise ValueError('Expected exactly the five freshly Swift-exported bundled decks')
    receipt = {'reviewDigest': digest(encoded(review)), 'commands': commands, 'status': 'passed',
               'deckSHA256': {p.name: digest(p.read_bytes()) for p in sorted(decks.glob('*.json'))}}
    write_new(candidate / 'maintenance-validation.json', encoded(receipt))
    return receipt


def candidate_branch(project, commit):
    exact(commit)
    if git(project, 'rev-parse', 'HEAD').decode().strip() != commit or git(
            project, 'status', '--porcelain', '--untracked-files=all').strip():
        raise ValueError('Publication requires the exact clean reviewed candidate commit')
    upstream = exact(json.loads((project / 'packages/ondevice-engine/upstream.lock.json').read_bytes())['commit'])
    return 'maintenance/xmage-' + upstream


def publish(project, commit, base, execute=False):
    """One upstream candidate branch; subsequent reviewed app commits fast-forward it."""
    branch = candidate_branch(project, commit)
    subprocess.run(['git', 'check-ref-format', '--branch', base], check=True, capture_output=True)
    plan = {'repository': REPOSITORY, 'commit': commit, 'branch': branch, 'base': base, 'draft': True, 'executed': False}
    if not execute:
        return plan
    # This trusted orchestration process needs push/PR permission only here. It does
    # not import candidate scripts, invoke builds or use candidate PR body files.
    def gh(*args):
        return subprocess.check_output(['gh', *args], cwd=project, text=True, timeout=120)
    repository = REPOSITORY
    matches = json.loads(gh('pr', 'list', '--repo', repository, '--head', branch,
                            '--state', 'all', '--json', 'url,headRefOid,baseRefName,isDraft,state'))
    if matches:
        if len(matches) != 1 or matches[0]['baseRefName'] != base:
            raise ValueError('Existing PR conflicts with candidate; manual reconciliation required')
        if matches[0]['headRefOid'] == commit:
            return {**plan, 'executed': True, 'url': matches[0]['url'], 'reused': True}
        if matches[0]['state'] != 'OPEN' or not matches[0]['isDraft']:
            raise ValueError('Only an open draft can advance; preserve closed or ready review decisions')
        # Missing ancestry or a rewritten candidate must be reconciled by the owner.
        git(project, 'merge-base', '--is-ancestor', exact(matches[0]['headRefOid']), commit)
    remote = 'https://github.com/' + repository + '.git'
    subprocess.run(['git', '-c', 'core.hooksPath=/dev/null', '-C', str(project),
                    'push', remote, commit + ':refs/heads/' + branch], check=True, timeout=180)
    if matches:
        return {**plan, 'executed': True, 'url': matches[0]['url'], 'updated': True}
    with tempfile.TemporaryDirectory(prefix='mm-pr-') as directory:
        body = Path(directory) / 'body.md'
        body.write_text('Prepared XMage maintenance candidate for upstream `' + branch.removeprefix('maintenance/xmage-') + '`. '
                        'The current MagicMobile candidate identity is the PR head commit.\n\n'
                        'Draft for source, generated-report and dependency review. '
                        'Native gating must require this exact MagicMobile SHA and a successful '
                        'exact-SHA non-simulator run including real-engine and seeded soak tests. '
                        'No release or device acceptance is asserted.\n')
        url = gh('pr', 'create', '--repo', repository, '--head', branch, '--base', base,
                 '--draft', '--title', 'Review XMage maintenance candidate ' + branch.removeprefix('maintenance/xmage-')[:12],
                 '--body-file', str(body)).strip()
    return {**plan, 'executed': True, 'url': url}


def dispatch(project, commit, execute=False):
    branch = candidate_branch(project, commit)
    plan = {'repository': REPOSITORY, 'workflow': NON_SIM, 'ref': branch,
            'requiredHeadSha': commit, 'executed': False}
    if not execute:
        return plan
    current = json.loads(subprocess.check_output([
        'gh', 'api', f'repos/{REPOSITORY}/git/ref/heads/{branch}'], text=True, timeout=120))
    if current['object']['sha'] != commit:
        raise ValueError('Remote candidate branch no longer matches exact approved commit')
    subprocess.run(['gh', 'workflow', 'run', NON_SIM, '--repo', REPOSITORY,
                    '--ref', branch], check=True, timeout=120)
    return {**plan, 'executed': True,
            'acceptance': 'Dispatch only. Require completed successful run with exact headSha through native gate.'}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest='command', required=True)
    d = sub.add_parser('detect')
    d.add_argument('--upstream', type=Path, help='Local object repository; no fetch when provided')
    d.add_argument('--candidate', help='Exact commit; default resolves remote master once')
    d.add_argument('--lock', type=Path, default=PACKAGE / 'upstream.lock.json')
    d.add_argument('--repository-lock', type=Path, help='Default: platform/repository-sources.json beside --lock')
    d.add_argument('--output', type=Path, help='Optional NEW report file; otherwise stdout only')
    d.add_argument('--records', type=Path, help='Read-only directory of <dedupKey>.json records')
    p = sub.add_parser('prepare')
    p.add_argument('--upstream', type=Path, required=True)
    p.add_argument('--project', type=Path, required=True)
    p.add_argument('--report', type=Path, required=True)
    p.add_argument('--approve-digest', required=True)
    p.add_argument('--destination', type=Path, required=True)
    g = sub.add_parser('generated-review'); g.add_argument('candidate', type=Path)
    a = sub.add_parser('accept-generated'); a.add_argument('candidate', type=Path)
    a.add_argument('--approve-digest', required=True)
    b = sub.add_parser('regenerate'); b.add_argument('candidate', type=Path)
    b.add_argument('--execute', action='store_true', help='Generate real JVM outputs for separate review')
    v = sub.add_parser('validate'); v.add_argument('candidate', type=Path)
    v.add_argument('--execute', action='store_true', help='Run post-review catalogue, portable and real-engine gates')
    dispatch_parser = sub.add_parser('dispatch-non-sim')
    dispatch_parser.add_argument('--project', type=Path, required=True)
    dispatch_parser.add_argument('--candidate-commit', required=True)
    dispatch_parser.add_argument('--execute', action='store_true', help='Explicitly dispatch the exact downstream branch')
    pub = sub.add_parser('publish')
    pub.add_argument('--project', type=Path, required=True)
    pub.add_argument('--candidate-commit', required=True)
    pub.add_argument('--base', required=True)
    pub.add_argument('--execute', action='store_true', help='Push exact commit and create/reuse draft PR')
    args = parser.parse_args()
    if args.command == 'detect':
        lock = json.loads(args.lock.read_bytes())
        repository_lock = json.loads((args.repository_lock or args.lock.parent / 'platform/repository-sources.json').read_bytes())
        with tempfile.TemporaryDirectory(prefix='mm-detection-') as temporary:
            repo = args.upstream or Path(temporary)
            candidate = args.candidate
            if args.upstream and not candidate:
                parser.error('--upstream requires --candidate')
            if not args.upstream:
                if lock['repository'] != 'https://github.com/magefree/mage.git':
                    raise ValueError('Network detection supports only the reviewed public XMage remote')
                git(repo, 'init', '--bare')
                if not candidate:
                    result = git(repo, 'ls-remote', lock['repository'], 'refs/heads/master').decode().split()
                    if len(result) != 2 or result[1] != 'refs/heads/master':
                        raise ValueError('Cannot resolve unique upstream master')
                    candidate = exact(result[0])
                for sha in sorted({exact(lock['commit']), exact(candidate)}):
                    git(repo, 'fetch', '--depth=1', '--no-tags', lock['repository'], sha)
            report = detect(repo, lock, candidate, repository_lock)
        if args.output:
            write_new(args.output, encoded(report))
        record = args.records / (report['dedupKey'] + '.json') if args.records else None
        status = 'new'
        if record and record.exists():
            saved = json.loads(record.read_bytes())
            if saved['dedupKey'] != report['dedupKey'] or saved['detectionDigest'] != digest(encoded(report)):
                raise ValueError('Dedup record conflicts with report')
            status = saved['status']
        print(encoded(report).decode(), end='')
        print('digest=' + digest(encoded(report)) + ' dedup=' + status, file=__import__('sys').stderr)
    elif args.command == 'prepare':
        print(encoded(prepare(args.upstream, args.project, json.loads(args.report.read_bytes()),
                              args.approve_digest, args.destination)).decode())
    elif args.command == 'regenerate':
        print(encoded(regenerate(args.candidate, args.execute)).decode())
    elif args.command == 'publish':
        print(encoded(publish(args.project, args.candidate_commit, args.base, args.execute)).decode())
    elif args.command == 'validate':
        print(encoded(validate(args.candidate, args.execute)).decode())
    elif args.command == 'dispatch-non-sim':
        print(encoded(dispatch(args.project, args.candidate_commit, args.execute)).decode())
    else:
        result = (generated_review(args.candidate) if args.command == 'generated-review'
                  else accept_generated(args.candidate, args.approve_digest))
        print(encoded(result).decode(), end='')
        print('digest=' + digest(encoded(result)), file=__import__('sys').stderr)


if __name__ == '__main__':
    main()
