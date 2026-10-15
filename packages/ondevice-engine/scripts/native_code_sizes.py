#!/usr/bin/env python3
"""Break down the AOT code of an unstripped native engine library by Java package and class.

GraalVM 22.1 cross-compiles stop before native-image prints its "Top 10 packages in code area"
table (Substrate adds -H:+ExitAfterRelocatableImageWrite), so this reads the function symbols of
the unstripped library instead (the android-native-symbols-<sha> CI artifact). No dependencies:
it parses the ELF64 symbol table directly.

  native_code_sizes.py libmmengine.so [--csv out.csv] [--top 40] [--samples 20]

Prints Markdown: the code total, then the largest packages (two and three levels), card classes
grouped as mage.cards.*, and the largest classes. Measurement only; it changes nothing.
"""
from __future__ import annotations
import argparse, collections, csv, re, struct, sys


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
        strtab = sections[link]
        str_off = strtab[4]
        for i in range(size // entsize):
            name_off, info, _, _, _, sym_size = struct.unpack_from('<IBBHQQ', data, offset + i * entsize)
            if info & 0xF != 2 or sym_size == 0:  # STT_FUNC with a size
                continue
            end = data.index(b'\0', str_off + name_off)
            yield data[str_off + name_off:end].decode('utf-8', 'replace'), sym_size


QUALIFIED = re.compile(r'([A-Za-z_$][\w$]*(?:[./][A-Za-z_$][\w$]*)+)')


def owner(name: str) -> str:
    """The Java class a method symbol belongs to, or '(native)' for C and runtime stubs."""
    if name.startswith('_Z'):  # C++ (JDK static libraries)
        return '(native)'
    head = name.split('(', 1)[0]
    head = head.replace('::', '.')
    m = QUALIFIED.search(head)
    if not m:
        return '(native)'
    parts = m.group(1).replace('/', '.').split('.')
    # The last part is the method; a class name starts upper case (or is an inner class with $).
    return '.'.join(parts[:-1]) if len(parts) > 1 else parts[0]


def package(cls: str, depth: int) -> str:
    parts = cls.split('.')
    pkg = [p for p in parts[:-1]]
    return '.'.join(pkg[:depth]) if pkg else cls


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('library')
    parser.add_argument('--csv', help='write class,methods,bytes rows')
    parser.add_argument('--top', type=int, default=40)
    parser.add_argument('--samples', type=int, default=20, help='raw symbol names to print, to check the parsing')
    args = parser.parse_args()
    by_class = collections.Counter()
    methods = collections.Counter()
    total = count = 0
    samples = []
    for name, size in function_symbols(args.library):
        cls = owner(name)
        by_class[cls] += size
        methods[cls] += 1
        total += size
        count += 1
        if len(samples) < args.samples and count % 9973 == 1:
            samples.append(f'{size:>8}  {name[:160]}')
    mb = lambda b: f'{b / 1e6:.1f}'
    pct = lambda b: f'{100 * b / total:.1f}%'
    out = [f'# Native code by Java owner: {args.library}', '',
           f'{count:,} sized function symbols, {total:,} bytes ({mb(total)} MB).', '']
    for depth in (2, 3):
        pk = collections.Counter()
        for cls, size in by_class.items():
            pk[package(cls, depth)] += size
        out += [f'## Packages, {depth} levels', '', '| Package | MB | Share |', '|---|---|---|']
        out += [f'| {p} | {mb(s)} | {pct(s)} |' for p, s in pk.most_common(args.top)] + ['']
    cards = sum(s for c, s in by_class.items() if c.startswith('mage.cards.') and c.count('.') >= 3)
    card_classes = {c.split('$')[0] for c in by_class if c.startswith('mage.cards.') and c.count('.') >= 3}
    out += ['## Card classes', '',
            f'mage.cards.<letter>.* (card classes and their inner effect classes): {mb(cards)} MB, {pct(cards)},'
            f' {len(card_classes):,} top-level classes, {cards / max(1, len(card_classes)):,.0f} bytes each on average.', '']
    out += ['## Largest classes', '', '| Class | Methods | KB |', '|---|---|---|']
    out += [f'| {c} | {methods[c]} | {s / 1e3:.0f} |' for c, s in by_class.most_common(args.top)] + ['']
    out += ['## Sample symbols (to check the name parsing)', '', '```'] + samples + ['```']
    print('\n'.join(out))
    if args.csv:
        with open(args.csv, 'w', newline='') as f:
            w = csv.writer(f)
            w.writerow(['class', 'methods', 'bytes'])
            for c, s in by_class.most_common():
                w.writerow([c, methods[c], s])


if __name__ == '__main__':
    sys.exit(main())
