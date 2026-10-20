#!/usr/bin/env python3
"""Builds the web client's card data from the committed iOS resources, with no remote lookups.

Writes public/generated/ (git-ignored):
- printings.tsv: the compact name -> printing index Android also ships (scripts/android/prepare_assets.py),
  headed by the catalogue hash and upstream commit, which are the relay identity a guest presents;
- precons.json: the five included Commander precons, unchanged from PreconCatalog.swift.
"""
import json, re
from pathlib import Path

web = Path(__file__).resolve().parent.parent
repo = web.parent.parent
out = web / 'public' / 'generated'
source = repo / 'apps/ios/MagicMobile/Resources/ondevice-catalogue.json'
data = json.loads(source.read_bytes())
assert data['schemaVersion'] == 1 and isinstance(data['cards'], list), 'Unexpected catalogue schema'
assert re.fullmatch(r'[0-9a-f]{64}', data['catalogueHash']) and re.fullmatch(r'[0-9a-f]{40}', data['upstreamCommit'])
assert len({row['name'] for row in data['cards']}) == len(data['cards']), 'Ambiguous printing names'

swift = (repo / 'apps/ios/MagicMobile/PreconCatalog.swift').read_text()
pattern = re.compile(r'PreconDeck\(\s*id:\s*"([^"\n]+)",\s*name:\s*"([^"\n]+)",\s*subtitle:\s*"([^"\n]*)",\s*colors:\s*"([^"\n]*)",'
                     r'\s*commander:\s*"([^"\n]+)",.*?rawList:\s*"""(.*?)"""', re.S)
decks = []
for ident, name, subtitle, colors, commander, text in pattern.findall(swift):
    entries = [dict(name=commander, quantity=1, section='commanders')]
    for line in text.strip().splitlines():
        count, card = line.strip().split(' ', 1)
        assert count.isdigit() and 0 < int(count) <= 100
        if card != commander:
            entries.append(dict(name=card, quantity=int(count), section='deck'))
    assert sum(x['quantity'] for x in entries) == 100
    decks.append(dict(id=ident, name=name, subtitle=subtitle, colors=colors, entries=entries))
assert len(decks) == 5, 'Expected five exact committed precons; source format changed'

out.mkdir(parents=True, exist_ok=True)
with (out / 'printings.tsv').open('w') as f:
    f.write('\t'.join(['#', data['catalogueHash'], data['upstreamCommit']]) + '\n')
    for row in data['cards']:
        assert not any(c in row[k] for k in ('name', 'setCode', 'collectorNumber') for c in '\t\n\r'), 'Tab or newline in a printing'
        f.write('\t'.join([row['name'], row['setCode'], row['collectorNumber']]) + '\n')
    for alias, target in sorted((data.get('nameAliases') or {}).items()):
        f.write('\t'.join(['=', alias, target]) + '\n')
# Recorded engine polls for the `?preview=<fixture>` scripted host (development only).
fixtures = repo / 'apps/ios/MagicMobileTests/Fixtures/OnDevice'
(out / 'preview').mkdir(exist_ok=True)
for name in ('2p-priority', '2p-battlefield', '2p-combat', '2p-stack', '2p-mana', '2p-attackers'):
    (out / 'preview' / f'{name}.json').write_bytes((fixtures / f'{name}.json').read_bytes())
(out / 'precons.json').write_text(json.dumps({'decks': decks}, ensure_ascii=False))
print('Prepared', len(data['cards']), 'printings and', len(decks), 'precons for catalogue', data['catalogueHash'][:12])
