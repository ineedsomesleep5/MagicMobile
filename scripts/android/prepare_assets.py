#!/usr/bin/env python3
"""Translate the committed iOS catalogue/precons without remote lookups or card substitution."""
import hashlib, json, re, sys
from pathlib import Path
repo, out = map(Path, sys.argv[1:])
source = repo/'apps/ios/MagicMobile/Resources/ondevice-catalogue.json'
raw = source.read_bytes(); data = json.loads(raw)
assert data['schema'] == 1 and isinstance(data['cards'],list)
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
header={k:v for k,v in data.items() if k!='cards'}
with (out/'catalogue.jsonl').open('w') as f:
    for row in [header,*data['cards']]: f.write(json.dumps(row,ensure_ascii=False,separators=(',',':'))+'\n')
(out/'precons.json').write_text(json.dumps({'decks':decks},ensure_ascii=False))
(out/'asset-provenance.json').write_text(json.dumps({'catalogueSourceSHA256':hashlib.sha256(raw).hexdigest(),'preconSourceSHA256':hashlib.sha256(precon_source.read_bytes()).hexdigest(),'cards':len(data['cards']),'precons':len(decks),'catalogueHash':data['catalogueHash']},indent=2))
print('Prepared',len(data['cards']),'compiled catalogue cards and',len(decks),'unchanged precons')
