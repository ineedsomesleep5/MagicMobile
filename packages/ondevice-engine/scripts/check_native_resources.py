#!/usr/bin/env python3
"""Lists what native/resource-config.json embeds from a classpath and refuses class files.

GraalVM embeds every classpath file (directory entry or jar member) whose path fully matches an
include pattern. A broad pattern such as mage/.* once embedded every XMage .class file (about
272 MB of image heap) that the engine never reads as a resource. This runs before native-image,
from the same classpath and configuration, so a build that would embed any .class resource, or
miss a resource the engine reads at runtime, stops before the long native build starts.
"""
import argparse
import json
import os
import re
import sys
import zipfile
from pathlib import Path

# Read at runtime by the mobile engine (see docs/NATIVE_METADATA.md, "Resources").
REQUIRED = ('mage/mobile/card-names.json.gz', 'mage/mobile/card-metadata.jsonl.gz',
            'tokens-database.txt', 'pennydreadful.properties')


def resources(entry):
    """(name, bytes) for every file in one classpath entry, named as GraalVM names resources."""
    path = Path(entry)
    if path.is_dir():
        for file in sorted(p for p in path.rglob('*') if p.is_file()):
            yield file.relative_to(path).as_posix(), file.stat().st_size
    elif path.is_file() and zipfile.is_zipfile(path):
        with zipfile.ZipFile(path) as jar:
            for info in jar.infolist():
                if not info.is_dir():
                    yield info.filename, info.file_size


def scan(classpath, config):
    rules = json.loads(Path(config).read_text())['resources']
    includes = [re.compile(rule['pattern']) for rule in rules.get('includes', [])]
    excludes = [re.compile(rule['pattern']) for rule in rules.get('excludes', [])]
    embedded = []
    for entry in [e for e in classpath.split(os.pathsep) if e]:
        for name, size in resources(entry):
            if any(p.fullmatch(name) for p in includes) and not any(p.fullmatch(name) for p in excludes):
                embedded.append({'name': name, 'bytes': size, 'entry': entry})
    return embedded


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument('--classpath', required=True, help='the native-image classpath')
    parser.add_argument('--config', required=True, help='resource-config.json')
    parser.add_argument('--report', help='write the embedded resource list here (JSON)')
    args = parser.parse_args(argv)
    embedded = scan(args.classpath, args.config)
    classes = [r for r in embedded if r['name'].endswith('.class')]
    names = {r['name'] for r in embedded}
    missing = [name for name in REQUIRED if name not in names]
    total = sum(r['bytes'] for r in embedded)
    report = {'resources': len(embedded), 'bytes': total, 'classFiles': len(classes),
              'classFileBytes': sum(r['bytes'] for r in classes), 'missingRequired': missing,
              'embedded': sorted(embedded, key=lambda r: (r['name'], r['entry']))}
    if args.report: Path(args.report).write_text(json.dumps(report, indent=2) + '\n')
    print(f'NATIVE-RESOURCES embedded={len(embedded)} bytes={total} classFiles={len(classes)}'
          f' classFileBytes={report["classFileBytes"]} missingRequired={missing}')
    for r in report['embedded'][:40]: print(f'  {r["bytes"]:>10} {r["name"]}')
    if len(embedded) > 40: print(f'  ... {len(embedded) - 40} more (see the report)')
    if classes:
        print(f'FAIL resource-config.json would embed {len(classes)} .class files as resources, e.g. '
              + ', '.join(r['name'] for r in classes[:5]), file=sys.stderr)
        return 1
    if missing:
        print('FAIL resource-config.json would leave out resources the engine reads: ' + ', '.join(missing), file=sys.stderr)
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main())
