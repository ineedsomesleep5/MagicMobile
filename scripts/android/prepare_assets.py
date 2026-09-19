#!/usr/bin/env python3
"""Translate the committed iOS catalogue/precons without remote lookups or card substitution.

The iOS catalogue keeps printings in `cards` and everything the player reads in a separate
`cardMetadata` map. Android's Catalogue reader consumes one JSONL row per card, so the two
are joined here rather than shipping the whole metadata map as an unusable header row.
"""
import hashlib, json, re, sys
from pathlib import Path

# Fields Decks.kt CardInfo reads off each row. Absent metadata stays absent; it is never
# invented, and a missing field must surface in the app as unknown rather than as a guess.
CARD_FIELDS = ('typeLine', 'oracleText', 'manaCost', 'colorIdentity')
# Only what Catalogue's header parser needs. cardMetadata is joined onto rows instead.
HEADER_FIELDS = ('schemaVersion', 'catalogueHash', 'nameAliases', 'upstreamCommit',
                 'sourceMetadataSHA256', 'sourceCatalogueSHA256')

repo, out = map(Path, sys.argv[1:])
source = repo/'apps/ios/MagicMobile/Resources/ondevice-catalogue.json'
raw = source.read_bytes(); data = json.loads(raw)
assert data['schemaVersion'] == 1 and isinstance(data['cards'], list), 'Unexpected catalogue schema'
metadata = data.get('cardMetadata') or {}
assert isinstance(metadata, dict) and metadata, 'Catalogue is missing card metadata'

precon_source = repo/'apps/ios/MagicMobile/PreconCatalog.swift'
swift = precon_source.read_text()
pattern = re.compile(r'PreconDeck\(\s*id:\s*"([^"\n]+)",\s*name:\s*"([^"\n]+)",.*?commander:\s*"([^"\n]+)",.*?rawList:\s*"""(.*?)"""',re.S)
decks=[]
for ident,name,commander,text in pattern.findall(swift):
    entries=[dict(name=commander,quantity=1,section='commanders')]
    for line in text.strip().splitlines():
        count, card=line.strip().split(' ',1)
        assert count.isdigit() and 0<int(count)<=100
        if card != commander: entries.append(dict(name=card,quantity=int(count),section='deck'))
    assert sum(x['quantity'] for x in entries)==100
    decks.append(dict(id=ident,name=name,entries=entries))
assert len(decks)==5, 'Expected five exact committed precons; source format changed'
assert len({x['name'] for x in data['cards']})==len(data['cards'])

out.mkdir(parents=True,exist_ok=True)
header={k:data[k] for k in HEADER_FIELDS if k in data}
assert 'catalogueHash' in header, 'Catalogue hash is required to pair assets with the engine'
joined=0
with (out/'catalogue.jsonl').open('w') as f:
    f.write(json.dumps(header,ensure_ascii=False,separators=(',',':'))+'\n')
    for row in data['cards']:
        entry=dict(row)
        card=metadata.get(row['name'])
        if card:
            joined+=1
            for field in CARD_FIELDS:
                value=card.get(field)
                if value is not None: entry[field]=value
        f.write(json.dumps(entry,ensure_ascii=False,separators=(',',':'))+'\n')
# Every alias target must resolve; Catalogue rejects the asset otherwise.
names={row['name'] for row in data['cards']}
assert all(v in names for v in header.get('nameAliases',{}).values()), 'Alias target missing from cards'

(out/'precons.json').write_text(json.dumps({'decks':decks},ensure_ascii=False))
(out/'asset-provenance.json').write_text(json.dumps({'catalogueSourceSHA256':hashlib.sha256(raw).hexdigest(),'preconSourceSHA256':hashlib.sha256(precon_source.read_bytes()).hexdigest(),'cards':len(data['cards']),'cardsWithMetadata':joined,'precons':len(decks),'catalogueHash':data['catalogueHash']},indent=2))
print('Prepared',len(data['cards']),'compiled catalogue cards (',joined,'with metadata ) and',len(decks),'unchanged precons')
