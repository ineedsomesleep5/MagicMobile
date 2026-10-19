"""Extract the checksum-pinned Gluon archive without trusting its build-host links."""
import json
from pathlib import Path, PurePosixPath
import tarfile

ROOT = Path(__file__).resolve().parents[2]
_PINS = json.loads((ROOT / 'packages/ondevice-engine/native/gluon/toolchain.json').read_text())
TOOLCHAIN = _PINS['graalvm']['archives']['linux-amd64']['name'].removesuffix('.tar.gz')


def extract_toolchain(archive: Path, destination: Path) -> None:
    """Every member must sit under TOOLCHAIN; links may not leave the destination (data filter)."""
    destination = destination.resolve()
    if any(destination.iterdir()):
        raise ValueError('Toolchain destination must be empty')
    seen = set()
    with tarfile.open(archive) as source:
        members = source.getmembers()
        if len(members) > 100_000 or sum(m.size for m in members) > 4 * 1024**3:
            raise ValueError('Toolchain archive exceeds the reviewed size limits')
        for member in members:
            path = PurePosixPath(member.name)
            if path.is_absolute() or '..' in path.parts or not path.parts or path.parts[0] != TOOLCHAIN:
                raise ValueError('Unexpected toolchain archive path: ' + member.name)
            if member.name in seen:
                raise ValueError('Duplicate toolchain archive member: ' + member.name)
            seen.add(member.name)
            # Preflight obvious unsafe paths/types. Extraction below rechecks
            # every entry, including link chains created by preceding entries.
            tarfile.data_filter(member, str(destination))
        source.extractall(destination, members=members, filter='data')
