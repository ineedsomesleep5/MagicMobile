"""Extract the checksum-pinned Gluon archive without trusting its build-host links."""
import json
from pathlib import Path, PurePosixPath
import tarfile

TOOLCHAIN = 'graalvm-svm-java17-linux-gluon-22.1.0.1-Final'
# The official archive contains a dangling, absolute link to the producer's
# desktop Linux ARM64 freetype. It is not an Android or host compiler input.
# Omit just that nonportable link, never change the generic safe tar policy.
IGNORED_ABSOLUTE_LINK = TOOLCHAIN + '/lib/svm/clibraries/linux-aarch64/libfreetype.a'


def extract_toolchain(archive: Path, destination: Path) -> list[dict[str, str]]:
    destination = destination.resolve()
    if any(destination.iterdir()):
        raise ValueError('Toolchain destination must be empty')
    omitted = []
    seen = set()
    with tarfile.open(archive) as source:
        members = source.getmembers()
        if len(members) > 100_000 or sum(m.size for m in members) > 4 * 1024**3:
            raise ValueError('Toolchain archive exceeds the reviewed size limits')
        accepted = []
        for member in members:
            path = PurePosixPath(member.name)
            if path.is_absolute() or '..' in path.parts or not path.parts or path.parts[0] != TOOLCHAIN:
                raise ValueError('Unexpected toolchain archive path: ' + member.name)
            if member.name in seen:
                raise ValueError('Duplicate toolchain archive member: ' + member.name)
            seen.add(member.name)
            if member.name == IGNORED_ABSOLUTE_LINK and member.issym() and PurePosixPath(member.linkname).is_absolute():
                omitted.append({'path': member.name, 'target': member.linkname,
                                'reason': 'Unused desktop Linux ARM64 producer-path symlink'})
                continue
            # Preflight obvious unsafe paths/types. Extraction below rechecks
            # every entry, including link chains created by preceding entries.
            tarfile.data_filter(member, str(destination))
            accepted.append(member)
        source.extractall(destination, members=accepted, filter='data')
    (destination / 'archive-omissions.json').write_text(json.dumps(omitted, indent=2) + '\n')
    return omitted
