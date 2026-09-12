#!/usr/bin/env python3
"""Download one explicitly selected successful native CI artifact with gh.

Requires a read-only GH_TOKEN when the GitHub CLI requires authentication.
Never guesses latest, changes a repository, signs, installs, or executes code.
"""
from __future__ import annotations
import argparse
import hashlib
import json
from pathlib import Path, PurePosixPath
import re
import shutil
import stat
import subprocess
import sys
import tempfile
import zipfile

REPO = 'ineedsomesleep5/MagicMobile'
WORKFLOW = '.github/workflows/magicmobile-far-calls.yml'


def api(path):
    return json.loads(subprocess.check_output(['gh', 'api', path], text=True))


def select(request, run, artifacts):
    if set(request) != {'runId', 'sourceCommit', 'artifactId', 'archiveSHA256'}:
        raise ValueError('Explicit runId, sourceCommit, artifactId and archiveSHA256 are required')
    if any(type(request[key]) is not int or request[key] < 1 for key in ('runId', 'artifactId')):
        raise ValueError('Invalid run or artifact ID')
    if not re.fullmatch(r'[0-9a-f]{40}', request['sourceCommit']) or not re.fullmatch(r'[0-9a-f]{64}', request['archiveSHA256']):
        raise ValueError('Full source and archive hashes are required')
    if run.get('id') != request['runId'] or run.get('head_sha') != request['sourceCommit']:
        raise ValueError('Producer run/source mismatch')
    if run.get('status') != 'completed' or run.get('conclusion') != 'success':
        raise ValueError('Producer has not completed successfully; do not substitute a probe or older library')
    if run.get('path') != WORKFLOW or run.get('repository', {}).get('full_name') != REPO:
        raise ValueError('Wrong producer workflow or repository')
    matches = [a for a in artifacts if a.get('id') == request['artifactId']]
    if len(matches) != 1: raise ValueError('Exact producer artifact not found')
    artifact = matches[0]
    if artifact.get('expired') or artifact.get('name') != 'issue4-full-native-candidate-' + request['sourceCommit']:
        raise ValueError('Expired or incorrectly named full-engine artifact')
    if artifact.get('digest') != 'sha256:' + request['archiveSHA256']:
        raise ValueError('Artifact digest does not match explicit selection')
    owner = artifact.get('workflow_run', {})
    if owner.get('id') != request['runId'] or owner.get('head_sha') != request['sourceCommit']:
        raise ValueError('Artifact producer provenance mismatch')
    return artifact


def extract(archive, destination):
    """Extract into a new owned directory, rejecting path traversal/links/bombs."""
    if destination.exists() or destination.is_symlink(): raise ValueError('Extraction destination already exists')
    with zipfile.ZipFile(archive) as source:
        infos = source.infolist()
        if not infos or len(infos) > 5000 or sum(i.file_size for i in infos) > 8 * 1024**3:
            raise ValueError('Invalid or excessive artifact contents')
        names = set()
        for item in infos:
            name = item.filename.rstrip('/')
            path = PurePosixPath(name)
            mode = item.external_attr >> 16
            if (not name or path.is_absolute() or '..' in path.parts or str(path) != name
                    or '\\' in name or name in names or stat.S_ISLNK(mode)
                    or (mode & 0o170000) not in (0, stat.S_IFREG, stat.S_IFDIR)):
                raise ValueError('Unsafe artifact member')
            names.add(name)
        destination.mkdir(parents=True)
        try:
            source.extractall(destination)
        except BaseException:
            shutil.rmtree(destination)
            raise


def fetch(request, destination, report):
    run = api(f'repos/{REPO}/actions/runs/{request["runId"]}')
    artifacts = []
    for page in range(1, 101):
        values = api(f'repos/{REPO}/actions/runs/{request["runId"]}/artifacts?per_page=100&page={page}')['artifacts']
        artifacts.extend(values)
        if len(values) < 100: break
    else: raise ValueError('Artifact pagination exceeded safe limit')
    artifact = select(request, run, artifacts)
    if report.exists() or report.is_symlink(): raise ValueError('Evidence report already exists')
    with tempfile.TemporaryDirectory(prefix='magicmobile-native-download-') as temp:
        archive = Path(temp) / 'candidate.zip'
        with archive.open('xb') as output:
            subprocess.run(['gh', 'api', f'repos/{REPO}/actions/artifacts/{artifact["id"]}/zip'], stdout=output, check=True)
        digest = hashlib.sha256()
        with archive.open('rb') as stream:
            for block in iter(lambda: stream.read(1024 * 1024), b''): digest.update(block)
        if digest.hexdigest() != request['archiveSHA256']: raise ValueError('Downloaded artifact checksum mismatch')
        extract(archive, destination)
    report.parent.mkdir(parents=True, exist_ok=True)
    with report.open('x') as output:
        json.dump({'schema': 1, 'selection': request, 'producerRun': run['html_url'],
                   'producerConclusion': run['conclusion'], 'artifact': artifact,
                   'scope': 'verified source artifact provenance; no execution'}, output, indent=2)
        output.write('\n')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('request', type=Path)
    parser.add_argument('--destination', type=Path, required=True)
    parser.add_argument('--report', type=Path, required=True)
    args = parser.parse_args()
    try:
        request = json.loads(args.request.read_text())
        # Validate types/hashes before interpolation into any endpoint.
        if set(request) != {'runId', 'sourceCommit', 'artifactId', 'archiveSHA256'} or any(type(request[k]) is not int or request[k] < 1 for k in ('runId', 'artifactId')):
            raise ValueError('Malformed artifact request')
        fetch(request, args.destination, args.report)
        print('Verified and extracted exact native artifact. No app execution or signing.')
    except (ValueError, OSError, KeyError, TypeError, subprocess.SubprocessError, zipfile.BadZipFile) as error:
        parser.exit(1, f'Native artifact rejected: {error}\n')


if __name__ == '__main__': main()
