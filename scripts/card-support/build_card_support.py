#!/usr/bin/env python3
"""Compare the cards XMage (magefree/mage master) implements with the cards MagicMobile ships.

Read-only on magefree/mage: it keeps two sparse, blob-less clones (latest master and the commit
MagicMobile is pinned to) under --workdir and reads only set files, SetType.java and the card
classes of newly added cards. Writes data.json for the Card Support page.

    python3 scripts/card-support/build_card_support.py --repo . --workdir /tmp/xmage-cards --out out

make_sprites.py then adds card pictures. The weekly workflow is magicmobile-card-support.yml.
"""
import argparse
import datetime as dt
import json
import re
import subprocess
from collections import Counter, defaultdict
from pathlib import Path

UPSTREAM = 'https://github.com/magefree/mage.git'
SETS_DIR = 'Mage.Sets/src/mage/sets'
SET_TYPE = 'Mage/src/main/java/mage/constants/SetType.java'
NOT_ETERNAL = {'CUSTOM_SET', 'JOKE_SET', 'REMIX', 'MAGIC_ARENA'}  # SetType.isEternalLegal()

SET_RE = re.compile(r'super\(\s*"((?:[^"\\]|\\.)*)"\s*,\s*"([^"]+)"\s*,\s*ExpansionSet\.buildDate\((\d+),\s*(\d+),\s*(\d+)\)\s*,\s*SetType\.(\w+)')
CARD_RE = re.compile(r'new\s+SetCardInfo\(\s*"((?:[^"\\]|\\.)*)"\s*,\s*("(?:[^"\\]|\\.)*"|[^,]+?)\s*,\s*Rarity\.(\w+)\s*,\s*([\w.]+?)\.class')


def git(repo, *args, timeout=900):
    return subprocess.check_output(['git', '-C', str(repo), *args], text=True, timeout=timeout).strip()


def sparse_clone(path, ref, depth_one):
    """Blob-less clone holding only the set files; ref is 'master' or an exact SHA."""
    path = Path(path)
    if not (path / '.git').exists():
        path.parent.mkdir(parents=True, exist_ok=True)
        subprocess.check_call(['git', 'clone', '-q', '--filter=blob:none', '--no-checkout',
                               *(['--depth', '1'] if depth_one else []), UPSTREAM, str(path)], timeout=1800)
        git(path, 'sparse-checkout', 'set', '--no-cone', f'/{SETS_DIR}/*', f'/{SET_TYPE}')
    git(path, 'fetch', '-q', '--depth', '1', 'origin', ref)
    git(path, 'checkout', '-q', '--force', 'FETCH_HEAD')
    return git(path, 'rev-parse', 'HEAD'), git(path, 'log', '-1', '--format=%cI')


def unq(value):
    return value.replace('\\"', '"').replace('\\\\', '\\')


def strip_comments(text):
    """Drop commented-out lines (XMage comments out unimplemented printings) and block comments."""
    kept, block = [], False
    for line in text.splitlines():
        t = line.strip()
        if block:
            if '*/' in t:
                block = False
            continue
        if t.startswith('/*'):
            block = '*/' not in t
            continue
        if t.startswith('//') or t.startswith('*'):
            continue
        kept.append(line)
    return '\n'.join(kept)


def read_sets(clone):
    sets, printings = {}, []
    for f in sorted((Path(clone) / SETS_DIR).glob('*.java')):
        text = strip_comments(f.read_text(encoding='utf-8', errors='replace'))
        m = SET_RE.search(text)
        if not m:
            continue
        name, code, y, mo, d, kind = m.groups()
        sets[code] = {'name': unq(name), 'code': code, 'date': f'{int(y):04d}-{int(mo):02d}-{int(d):02d}', 'type': kind}
        for cm in CARD_RE.finditer(text):
            card, num, rarity, cls = cm.groups()
            num = unq(num[1:-1]) if num.startswith('"') else num.strip()
            printings.append({'name': unq(card), 'set': code, 'num': num, 'rarity': rarity, 'cls': cls})
    return sets, printings


def addressable(sets, printings):
    """Mirror export_ios_catalogue.normalize: eternal-legal sets, unique (set, number), lowest printing per name."""
    freq = Counter((p['set'], p['num']) for p in printings)
    chosen = {}
    for p in printings:
        if sets[p['set']]['type'] in NOT_ETERNAL or freq[(p['set'], p['num'])] != 1:
            continue
        prev = chosen.get(p['name'])
        if prev is None or (p['set'], p['num']) < (prev['set'], prev['num']):
            chosen[p['name']] = p
    return chosen


def parse_card_class(path):
    """Best-effort card facts from an XMage card class (types, cost, P/T, rules comments)."""
    try:
        text = Path(path).read_text(encoding='utf-8', errors='replace')
    except FileNotFoundError:
        return {}
    ctor = re.search(r'super\(\s*ownerId\s*,\s*setInfo(.*?)\);', text, re.S)
    head = ctor.group(1) if ctor else ''
    types_block = re.search(r'CardType\[\]\s*\{([^}]*)\}', head)
    types = re.findall(r'CardType\.(\w+)', types_block.group(1)) if types_block else []
    cost = re.search(r'"((?:\{[^}]+\})+)"', head)
    supers = set(re.findall(r'SuperType\.(\w+)', head)) | set(re.findall(r'this\.supertype\.add\(SuperType\.(\w+)', text))
    subs = re.findall(r'this\.subtype\.add\(SubType\.(\w+)', text) or re.findall(r'SubType\.(\w+)', head)
    pw = re.search(r'this\.power\s*=\s*new MageInt\((\d+)', text)
    tg = re.search(r'this\.toughness\s*=\s*new MageInt\((\d+)', text)
    body = text[ctor.end():] if ctor else text
    body = body.split('\n    private ')[0].split('\n    public ')[0]
    rules = [ln.strip()[2:].strip() for ln in body.splitlines() if ln.strip().startswith('//')]
    rules = [r for r in rules if r and not r.upper().startswith(('TODO', 'NOTE'))]
    pretty = lambda w: w.replace('_', ' ').title()
    type_line = ' '.join([pretty(s) for s in sorted(supers) if s != 'NONE'] + [pretty(t) for t in types])
    if subs:
        type_line += ' — ' + ' '.join(pretty(s) for s in subs)
    out = {'typeLine': type_line.strip(), 'manaCost': cost.group(1) if cost else '', 'rules': rules[:8]}
    if pw and tg:
        out['pt'] = f'{pw.group(1)}/{tg.group(1)}'
    out['commander'] = ('LEGENDARY' in supers and 'CREATURE' in types) or any('can be your commander' in r.lower() for r in rules)
    return out


def class_path(cls):
    parts = cls.split('.')  # mage.cards.a.AcererakTheArchlich
    return 'Mage.Sets/src/' + '/'.join(parts) + '.java'


def is_commander(meta):
    line = meta.get('typeLine', '')
    return ('Legendary' in line and 'Creature' in line) or 'can be your commander' in (meta.get('oracleText') or '').lower()


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--repo', required=True, help='MagicMobile checkout (main)')
    ap.add_argument('--workdir', required=True, help='where the two XMage clones live')
    ap.add_argument('--out', required=True)
    args = ap.parse_args()
    repo, work, out = Path(args.repo), Path(args.workdir), Path(args.out)
    out.mkdir(parents=True, exist_ok=True)

    lock = json.loads((repo / 'packages/ondevice-engine/upstream.lock.json').read_text())
    catalogue = json.loads((repo / 'apps/ios/MagicMobile/Resources/ondevice-catalogue.json').read_text())
    mm_meta = catalogue['cardMetadata']
    mm_cards = {c['name']: c for c in catalogue['cards']}
    mm_head = git(repo, 'rev-parse', 'HEAD')

    master_sha, master_date = sparse_clone(work / 'mage-master', 'master', True)
    pin_sha, pin_date = sparse_clone(work / 'mage-pin', lock['commit'], True)
    behind = None
    try:  # Commits on master after the pinned commit's date (blob-less, so cheap).
        git(work / 'mage-master', 'fetch', '-q', f'--shallow-since={pin_date}', 'origin', 'master')
        behind = int(git(work / 'mage-master', 'rev-list', '--count', f'--since={pin_date}', 'FETCH_HEAD')) - 1
    except Exception:
        pass
    m_sets, m_print = read_sets(work / 'mage-master')
    p_sets, p_print = read_sets(work / 'mage-pin')
    m_ok, p_ok = addressable(m_sets, m_print), addressable(p_sets, p_print)
    m_names = {p['name'] for p in m_print}
    p_names = {p['name'] for p in p_print}

    shipped = set(mm_cards)
    both = shipped & set(m_ok)
    new_names = sorted(set(m_ok) - shipped)
    dropped = sorted(shipped - set(m_ok))
    not_commander_legal = m_names - set(m_ok)
    squash = lambda n: re.sub(r'[^a-z0-9]', '', n.lower())
    new_by_squash = {squash(n): n for n in new_names}
    renamed = {d: new_by_squash[squash(d)] for d in dropped if squash(d) in new_by_squash}
    by_name = defaultdict(list)
    for p in m_print:
        by_name[p['name']].append(p)

    # Card classes for the new cards only.
    wanted = sorted({class_path(by_name[n][0]['cls']) for n in new_names})
    if wanted:
        git(work / 'mage-master', 'sparse-checkout', 'add', *[f'/{w}' for w in wanted])
    new_cards = []
    for n in new_names:
        pick = m_ok[n]
        facts = parse_card_class(work / 'mage-master' / class_path(pick['cls']))
        new_cards.append({
            'name': n, 'set': pick['set'], 'num': pick['num'], 'rarity': pick['rarity'].title(),
            'setName': m_sets[pick['set']]['name'],
            'kind': ('renamed' if n in renamed.values() else 'new card' if n not in p_names else 'not shipped yet'),
            'oldName': next((d for d, r in renamed.items() if r == n), None),
            **facts})

    commanders = []
    for n in sorted(shipped):
        meta = mm_meta.get(n, {})
        if not is_commander(meta):
            continue
        c = mm_cards[n]
        commanders.append({'name': n, 'set': c['setCode'], 'num': c['collectorNumber'],
                           'ci': ''.join(meta.get('colorIdentity', [])), 'manaCost': meta.get('manaCost', ''),
                           'mv': meta.get('manaValue', 0), 'typeLine': meta.get('typeLine', ''),
                           'text': meta.get('oracleText', ''), 'stillInXmage': n in m_ok})

    new_sets = sorted((s for c, s in m_sets.items() if c not in p_sets), key=lambda s: s['date'], reverse=True)
    data = {
        'generatedAt': dt.datetime.now(dt.timezone.utc).replace(microsecond=0).isoformat(),
        'xmage': {'commit': master_sha, 'date': master_date},
        'pin': {'commit': pin_sha, 'date': pin_date, 'commitsBehind': behind},
        'magicmobile': {'commit': mm_head, 'catalogueUpstreamCommit': catalogue.get('upstreamCommit')},
        'counts': {
            'xmageCardNames': len(m_names),
            'xmageCommanderPlayable': len(m_ok),
            'magicmobileCards': len(shipped),
            'supportedBoth': len(both),
            'newInXmage': len(new_names),
            'notShippedAtPin': sum(1 for c in new_cards if c['kind'] == 'not shipped yet'),
            'newCardImplementations': sum(1 for c in new_cards if c['kind'] == 'new card'),
            'newCommanders': sum(1 for c in new_cards if c.get('commander')),
            'droppedFromXmage': len(dropped) - len(renamed),
            'renamedInXmage': len(renamed),
            'xmageNotCommanderLegal': len(not_commander_legal),
            'magicmobileCommanders': len(commanders),
            'xmageSets': len(m_sets), 'newSets': len(new_sets),
            # Rebuilding the shipped list from the pinned commit's set files should give MagicMobile's list.
            'pinRebuildExtra': len(set(p_ok) - shipped), 'pinRebuildMissing': len(shipped - set(p_ok)),
        },
        'newSets': new_sets,
        'newCards': new_cards,
        'dropped': [{'name': n, 'set': mm_cards[n]['setCode'], 'num': mm_cards[n]['collectorNumber'],
                     'typeLine': mm_meta.get(n, {}).get('typeLine', ''), 'renamedTo': renamed.get(n)} for n in dropped],
        'commanders': commanders,
        'supported': sorted(both),
    }
    (out / 'data.json').write_text(json.dumps(data, ensure_ascii=False, separators=(',', ':')))
    print(json.dumps(data['counts'], indent=1))


if __name__ == '__main__':
    main()
