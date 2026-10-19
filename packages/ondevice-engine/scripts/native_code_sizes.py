#!/usr/bin/env python3
"""Break down the AOT code of an unstripped native engine library by Java package and class.

GraalVM 22.1 cross-compiles stop before native-image prints its "Top 10 packages in code area"
table (Substrate adds -H:+ExitAfterRelocatableImageWrite), so this reads the function symbols of
the unstripped library instead (the android-native-symbols-<sha> CI artifact). No dependencies:
it parses the ELF64 symbol table directly.

GraalVM names a method symbol <SimpleClassName>_<method>_<digest>, without the package (22.1: a 40-digit SHA-1;
24.1: a 22-character base-62 digest, constructors <SimpleClassName>_<digest>, class names over 40 characters cut
to their last 40), so package names come from class inventories given on the command line:
  --sources DIR    Java sources: every class, interface, enum or record declared in each file
  --classes FILE   one fully qualified class name per line (jimage list, unzip -Z1 of a jar)

  native_code_sizes.py libmmengine.so --sources .upstream/mage --classes jdk.txt [--csv out.csv]

Prints Markdown: the code total, then code by package group, by package, card classes, the largest
classes and the largest names no inventory knows. Measurement only; it changes nothing.
"""
from __future__ import annotations
import argparse, collections, csv, os, re, struct, sys


def function_symbols(path: str):
    """(name, size) for every sized FUNC symbol in .symtab (ELF64 little-endian)."""
    with open(path, 'rb') as f:
        data = f.read()
    if data[:4] != b'\x7fELF' or data[4] != 2 or data[5] != 1:
        raise SystemExit(f'{path}: not a little-endian ELF64 file')
    shoff, = struct.unpack_from('<Q', data, 0x28)
    shentsize, shnum = struct.unpack_from('<HH', data, 0x3A)
    sections = [struct.unpack_from('<IIQQQQIIQQ', data, shoff + i * shentsize) for i in range(shnum)]
    symtabs = [s for s in sections if s[1] == 2]  # SHT_SYMTAB
    if not symtabs:
        raise SystemExit(f'{path}: no .symtab (stripped library?)')
    for _, _, _, _, offset, size, link, _, _, entsize in symtabs:
        str_off = sections[link][4]
        for i in range(size // entsize):
            name_off, info, _, _, _, sym_size = struct.unpack_from('<IBBHQQ', data, offset + i * entsize)
            if info & 0xF != 2 or sym_size == 0:  # STT_FUNC with a size
                continue
            end = data.index(b'\0', str_off + name_off)
            yield data[str_off + name_off:end].decode('utf-8', 'replace'), sym_size


HASH = re.compile(r'(?:_[0-9a-f]{40})+$|_[0-9A-Za-z]{22}$')
DECLARATION = re.compile(r'^\s*(?:(?:public|protected|private|abstract|final|static|sealed|non-sealed|strictfp)\s+)*'
                         r'(?:class|interface|enum|record|@interface)\s+([A-Za-z_$][\w$]*)', re.M)
PACKAGE = re.compile(r'^\s*package\s+([\w.]+)\s*;', re.M)


# Classes no source declares: GraalVM's generated stubs and MagicMobile's generated registry.
GENERATED = {'ReflectionAccessorHolder': '(GraalVM reflection and serialization accessors)',
             'FactoryMethodHolder': '(GraalVM factory methods for allocation)',
             'JNIJavaCallWrappers': '(GraalVM JNI call wrappers)'}
GENERATED_PREFIXES = (('GeneratedCardBucket', 'io.magicmobile.generated (card factory)'),
                      ('GeneratedSetBucket', 'io.magicmobile.generated (set registry)'),
                      ('GeneratedCardFactory', 'io.magicmobile.generated (card factory)'),
                      ('GeneratedSetRegistry', 'io.magicmobile.generated (set registry)'))


def split_symbol(name: str) -> tuple[str, str] | None:
    """(simple class, method) for a GraalVM Java method symbol, None for C and runtime stubs."""
    if not HASH.search(name):
        return None
    head = HASH.sub('', name)
    cls, _, method = head.partition('_')
    return (cls, method or 'constructor') if cls else None  # 22.1 named constructors 'constructor'


class Inventory:
    """Simple class name to the packages that declare it."""
    def __init__(self):
        self.packages: dict[str, set[str]] = collections.defaultdict(set)
        self.tails: dict[str, set[str]] | None = None

    def add(self, fqcn: str):
        fqcn = fqcn.strip().replace('/', '.')
        if fqcn.endswith('.class'):
            fqcn = fqcn[:-6]
        if not fqcn or fqcn.startswith(('META-INF', 'module-info')) or '.' not in fqcn:
            return
        package, _, simple = fqcn.rpartition('.')
        self.packages[simple].add(package)
        # Nested classes: GraalVM keeps the binary name (Outer$Inner), also index the outer class.
        if '$' in simple:
            self.packages[simple.split('$')[0]].add(package)

    def scan_sources(self, root: str):
        for directory, _, files in os.walk(root):
            for file in files:
                if not file.endswith('.java'):
                    continue
                with open(os.path.join(directory, file), encoding='utf-8', errors='replace') as f:
                    text = f.read()
                m = PACKAGE.search(text)
                if not m:
                    continue
                for declared in DECLARATION.findall(text):
                    self.packages[declared].add(m.group(1))

    def package(self, simple: str) -> str:
        found = self.packages.get(simple) or self.packages.get(simple.split('$')[0])
        if not found and len(simple) == 40:  # GraalVM 24.1 keeps a long class name's last 40 characters
            if self.tails is None:
                self.tails = collections.defaultdict(set)
                for name, packages in self.packages.items():
                    if len(name) > 40:
                        self.tails[name[-40:]] |= packages
            found = self.tails.get(simple)
        if not found:
            return '(unknown)'
        if len(found) == 1:
            return next(iter(found))
        # Same simple name in several packages: prefer XMage, then the shared prefix.
        mage = sorted(p for p in found if p.startswith('mage.'))
        pick = mage or sorted(found)
        prefix = os.path.commonprefix([p.split('.') for p in pick])
        return '.'.join(prefix) + '.*' if prefix else '(ambiguous)'


def group(package: str) -> str:
    """A coarse owner for one package: card classes, XMage areas, the adapter, the JDK or a library."""
    if package.startswith('io.magicmobile.generated'):
        return 'MagicMobile generated registry'
    if package.startswith('mage.cards.') and re.match(r'mage\.cards\.[a-z]$', package):
        return 'XMage card classes (mage.cards.<letter>)'
    for prefix, label in (('mage.abilities', 'XMage abilities and effects'), ('mage.game', 'XMage game'),
                          ('mage.filter', 'XMage filters'), ('mage.target', 'XMage targets'),
                          ('mage.watchers', 'XMage watchers'), ('mage.player', 'XMage AI and players'),
                          ('mage.players', 'XMage AI and players'), ('mage.view', 'XMage views'),
                          ('mage.sets', 'XMage set classes'), ('mage.', 'XMage other'),
                          ('io.magicmobile', 'MagicMobile adapter'), ('java.', 'JDK'), ('javax.', 'JDK'),
                          ('jdk.', 'JDK'), ('sun.', 'JDK'), ('com.sun.', 'JDK'), ('com.oracle.svm', 'GraalVM runtime'),
                          ('org.graalvm', 'GraalVM runtime'), ('com.google.common', 'Guava'),
                          ('com.google.protobuf', 'protobuf'), ('com.google.gson', 'Gson'), ('org.h2', 'H2'),
                          ('com.j256.ormlite', 'ORMLite'), ('org.jsoup', 'jsoup'), ('org.jboss', 'JBoss remoting'),
                          ('org.apache.log4j', 'reload4j'), ('org.slf4j', 'SLF4J'), ('org.apache.commons', 'commons-lang3')):
        if package.startswith(prefix):
            return label
    return package if package.startswith('(') else 'other library'


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('library')
    parser.add_argument('--sources', action='append', default=[], help='Java source root to scan (repeatable)')
    parser.add_argument('--classes', action='append', default=[], help='file of class names (repeatable)')
    parser.add_argument('--csv', help='write package,class,methods,bytes rows')
    parser.add_argument('--top', type=int, default=40)
    args = parser.parse_args()
    inventory = Inventory()
    for root in args.sources:
        inventory.scan_sources(root)
    for path in args.classes:
        with open(path, encoding='utf-8', errors='replace') as f:
            for line in f:
                inventory.add(line)
    by_class, methods, owners = collections.Counter(), collections.Counter(), {}
    special = collections.Counter()
    total = count = 0
    for name, size in function_symbols(args.library):
        total += size
        count += 1
        parsed = split_symbol(name)
        if parsed is None:
            special['C, runtime stubs and other unhashed symbols'] += size
            continue
        cls, method = parsed
        by_class[cls] += size
        methods[cls] += 1
        if cls not in owners:
            # GraalVM's generated accessors for reflective and serialization access, one per registered member.
            owners[cls] = GENERATED.get(cls) or next((label for prefix, label in GENERATED_PREFIXES if cls.startswith(prefix)),
                                                     None) or inventory.package(cls)
    mb = lambda b: f'{b / 1e6:.1f}'
    pct = lambda b: f'{100 * b / total:.1f}%'
    out = [f'# Native code by Java owner: {os.path.basename(args.library)}', '',
           f'{count:,} sized function symbols, {total:,} bytes ({mb(total)} MB). Inventory: '
           f'{len(inventory.packages):,} simple class names.', '']
    groups, packages = collections.Counter(), collections.Counter()
    for cls, size in by_class.items():
        groups[group(owners[cls])] += size
        packages[owners[cls]] += size
    for label, size in special.items():
        groups['(' + label + ')'] += size
    out += ['## By owner', '', '| Owner | MB | Share |', '|---|---|---|']
    out += [f'| {g} | {mb(s)} | {pct(s)} |' for g, s in groups.most_common()] + ['']
    out += ['## By package', '', '| Package | MB | Share |', '|---|---|---|']
    out += [f'| {p} | {mb(s)} | {pct(s)} |' for p, s in packages.most_common(args.top)] + ['']
    card = [c for c in by_class if group(owners[c]).startswith('XMage card')]
    card_bytes = sum(by_class[c] for c in card)
    out += ['## Card classes', '',
            f'{len(card):,} classes in mage.cards.<letter> (cards and their effect classes), {mb(card_bytes)} MB, '
            f'{pct(card_bytes)}, {card_bytes / max(1, len(card)):,.0f} bytes and '
            f'{sum(methods[c] for c in card) / max(1, len(card)):.1f} methods per class on average.', '']
    card_methods = collections.Counter()
    for name, size in function_symbols(args.library) if card else ():
        parsed = split_symbol(name)
        if parsed and parsed[0] in owners and group(owners[parsed[0]]).startswith('XMage card'):
            card_methods[parsed[1]] += size
    if card_methods:
        out += ['Card-class code by method name:', '', '| Method | MB |', '|---|---|']
        out += [f'| {m} | {mb(s)} |' for m, s in card_methods.most_common(12)] + ['']
    out += ['## Largest classes', '', '| Class | Package | Methods | KB |', '|---|---|---|---|']
    out += [f'| {c} | {owners[c]} | {methods[c]} | {s / 1e3:.0f} |' for c, s in by_class.most_common(args.top)] + ['']
    unknown = [(c, s) for c, s in by_class.most_common() if owners[c] == '(unknown)'][:args.top]
    out += ['## Largest classes no inventory names', '', '| Class | Methods | KB |', '|---|---|---|']
    out += [f'| {c} | {methods[c]} | {s / 1e3:.0f} |' for c, s in unknown] + ['']
    print('\n'.join(out))
    if args.csv:
        with open(args.csv, 'w', newline='') as f:
            w = csv.writer(f)
            w.writerow(['package', 'class', 'methods', 'bytes'])
            for c, s in by_class.most_common():
                w.writerow([owners[c], c, methods[c], s])


if __name__ == '__main__':
    sys.exit(main())
