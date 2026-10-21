#!/usr/bin/env python3
"""Refuses -Dmagicmobile.webimage.dispatchSkipPackages for packages that make Unsafe-style accesses themselves.

The builder patch (build_patch.sh) leaves fields declared in those packages out of Web Image's unsafe access
dispatch arrays unless the analysis registered them as unsafe-accessed. That is only safe while no class in the
packages uses a VarHandle, sun.misc/jdk.internal.misc.Unsafe or an atomic field updater: the JDK's own VarHandle
fields reach the dispatch arrays without being registered (AtomicReference.value). This scans every class of the
packages on the image class path, in directories and jars, for references to those APIs.

    check_skip_packages.py <class path> <package prefix>...      e.g. ... "$CP" mage. io.magicmobile.
"""
import sys
import zipfile
from pathlib import Path

FORBIDDEN = (b'java/lang/invoke/VarHandle', b'sun/misc/Unsafe', b'jdk/internal/misc/Unsafe', b'FieldUpdater',
             b'objectFieldOffset', b'staticFieldOffset')


def main() -> int:
    classpath, prefixes = sys.argv[1], [p.replace('.', '/') for p in sys.argv[2:]]
    if not prefixes:
        print('check_skip_packages.py: no package prefixes given', file=sys.stderr)
        return 2
    scanned, hits = 0, []

    def check(name: str, data: bytes) -> None:
        nonlocal scanned
        if name.endswith('.class') and any(name.startswith(p) for p in prefixes):
            scanned += 1
            found = [f.decode() for f in FORBIDDEN if f in data]
            if found:
                hits.append(f'{name}: {", ".join(found)}')

    for entry in filter(None, classpath.split(':')):
        path = Path(entry)
        if path.is_dir():
            for f in path.rglob('*.class'):
                check(f.relative_to(path).as_posix(), f.read_bytes())
        elif path.suffix == '.jar' and path.is_file():
            with zipfile.ZipFile(path) as jar:
                for name in jar.namelist():
                    if name.endswith('.class') and any(name.startswith(p) for p in prefixes):
                        check(name, jar.read(name))
    if hits:
        print('These classes make Unsafe-style accesses, so their packages must keep upstream dispatch arrays '
              '(drop them from dispatchSkipPackages in build_web.sh):\n  ' + '\n  '.join(hits[:50]), file=sys.stderr)
        return 1
    if scanned == 0:
        print(f'check_skip_packages.py: no classes under {sys.argv[2:]} on the class path', file=sys.stderr)
        return 1
    print(f'dispatchSkipPackages {" ".join(sys.argv[2:])}: {scanned} classes, no Unsafe, VarHandle or field updater use')
    return 0


if __name__ == '__main__':
    sys.exit(main())
