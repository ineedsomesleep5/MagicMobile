#!/usr/bin/env python3
"""Download and hash-check one native artifact, without forwarding GitHub credentials."""
import argparse
import hashlib
import os
from pathlib import Path, PurePosixPath
import re
import shutil
import stat
import tempfile
import urllib.request
import urllib.parse
import zipfile

MAX_BYTES = 4 * 1024 ** 3


class PrivateRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, request, fp, code, message, headers, new_url):
        if urllib.parse.urlparse(new_url).scheme != 'https':
            raise ValueError('Artifact redirect must use HTTPS')
        redirected = super().redirect_request(request, fp, code, message, headers, new_url)
        if redirected is not None:
            redirected.remove_header('Authorization')
        return redirected


def extract(archive: Path, destination: Path):
    if destination.exists() or destination.is_symlink():
        raise ValueError('Artifact destination must be new')
    with zipfile.ZipFile(archive) as source:
        entries = source.infolist()
        if not entries or sum(entry.file_size for entry in entries) > MAX_BYTES:
            raise ValueError('Invalid/oversized native artifact')
        names = set()
        for entry in entries:
            name = entry.filename.rstrip('/')
            path = PurePosixPath(name)
            mode = entry.external_attr >> 16
            if (not name or path.is_absolute() or '..' in path.parts or '\\' in name
                    or str(path) != name or name in names or stat.S_ISLNK(mode)):
                raise ValueError('Unsafe or duplicate artifact path')
            names.add(name)
        destination.mkdir(parents=True)
        for entry in entries:
            target = destination / entry.filename
            if entry.is_dir():
                target.mkdir(parents=True, exist_ok=True)
                continue
            target.parent.mkdir(parents=True, exist_ok=True)
            with source.open(entry) as incoming, target.open('xb') as outgoing:
                shutil.copyfileobj(incoming, outgoing, length=1024 * 1024)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--artifact-id', type=int, required=True)
    parser.add_argument('--digest', required=True)
    parser.add_argument('--destination', type=Path, required=True)
    args = parser.parse_args()
    if args.artifact_id <= 0 or not re.fullmatch('sha256:[a-f0-9]{64}', args.digest):
        parser.error('Exact artifact identity/digest required')
    request = urllib.request.Request(
        f'https://api.github.com/repos/ineedsomesleep5/MagicMobile/actions/artifacts/{args.artifact_id}/zip',
        headers={'Authorization': 'Bearer ' + os.environ['GH_TOKEN'],
                 'Accept': 'application/vnd.github+json', 'X-GitHub-Api-Version': '2022-11-28'})
    with tempfile.TemporaryDirectory(prefix='mm-native-download-') as temporary:
        archive = Path(temporary) / 'native.zip'
        digest = hashlib.sha256()
        size = 0
        with urllib.request.build_opener(PrivateRedirect()).open(request, timeout=120) as response, archive.open('xb') as output:
            for block in iter(lambda: response.read(1024 * 1024), b''):
                size += len(block)
                if size > MAX_BYTES:
                    raise ValueError('Oversized artifact download')
                digest.update(block)
                output.write(block)
        if 'sha256:' + digest.hexdigest() != args.digest:
            raise ValueError('GitHub artifact ZIP digest mismatch')
        extract(archive, args.destination)
    print('PASS exact GitHub archive digest and safe extraction; no native runtime execution')


if __name__ == '__main__':
    main()
