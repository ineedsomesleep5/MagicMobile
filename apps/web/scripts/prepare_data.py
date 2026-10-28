#!/usr/bin/env python3
"""Builds the web client's card data from the committed iOS resources, with no remote lookups.

Writes public/generated/ (git-ignored):
- printings.tsv: the compact name -> printing index Android also ships (scripts/android/prepare_assets.py),
  headed by the catalogue hash and upstream commit, which are the relay identity a guest presents;
- precons.json: the five included Commander precons, unchanged from PreconCatalog.swift;
- ai-decks.json: the bracket AI decks (AIDeckPool.swift), copied unchanged from the iOS resources;
- catalogue.json: Deck Studio's compact card metadata (search, preview, analysis), with the catalogue hash and aliases;
- commander-brackets.json: the bracket rules (commander-brackets.json), minified.
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
ai_source = repo / 'apps/ios/MagicMobile/Resources/ai-decks.json'
ai = json.loads(ai_source.read_bytes())
assert ai['schemaVersion'] == 1 and isinstance(ai['decks'], list) and ai['decks'], 'Unexpected ai-decks schema'
assert len({deck['id'] for deck in ai['decks']} | {deck['id'] for deck in decks}) == len(ai['decks']) + len(decks), 'Duplicate AI deck IDs'
for deck in ai['decks']:
    assert deck['id'].startswith('ai-') and sum(1 for x in deck['entries'] if x['section'] == 'commander') == 1, deck['id']
(out / 'ai-decks.json').write_bytes(ai_source.read_bytes())
# The lessons (scripts/lessons/record.py), recorded once and read by every platform.
(out / 'lessons').mkdir(parents=True, exist_ok=True)
for lesson in sorted((repo / 'apps/ios/MagicMobile/Resources/Lessons').glob('*.json')):
    (out / 'lessons' / lesson.name).write_bytes(lesson.read_bytes())
print('Prepared', len(data['cards']), 'printings,', len(decks), 'precons and', len(ai['decks']), 'AI decks for catalogue', data['catalogueHash'][:12])

# Deck Studio's card catalogue (NativeDeckMetadataCatalogue.swift; src/core/deckStudio/catalogue.ts reads it): one row per
# printing name, [name, typeLine, types, oracleText, manaValue, manaCost, colors, colorIdentity, setCodes, roles?], with
# types, set codes and roles space-joined and colours as letters ("" is known colorless, null unknown). A name with no
# metadata is a one-item row. The oracle text is the engine's raw text; the app cleans it with EngineDisplayText.
def joined(values, letters=False):
    if values is None:
        return None
    assert all(' ' not in v for v in values), 'Space inside a joined value'
    if letters:
        assert all(v in 'WUBRG' and len(v) == 1 for v in values), 'Unexpected colour symbol'
        return ''.join(values)
    return ' '.join(values)

metadata = data.get('cardMetadata') or {}
rows = []
for printing in data['cards']:
    meta = metadata.get(printing['name'])
    if meta is None:
        rows.append([printing['name']])
        continue
    row = [printing['name'], meta.get('typeLine'), joined(meta.get('types')), meta.get('oracleText'), meta.get('manaValue'),
           meta.get('manaCost'), joined(meta.get('colors'), True), joined(meta.get('colorIdentity'), True),
           ' '.join(meta.get('setCodes') or [])]
    if meta.get('roles'):
        row.append(joined(meta['roles']))
    rows.append(row)
catalogue = {'schema': 1, 'catalogueHash': data['catalogueHash'], 'aliases': data.get('nameAliases') or {}, 'cards': rows}
(out / 'catalogue.json').write_text(json.dumps(catalogue, ensure_ascii=False, separators=(',', ':')))
# Bracket rules for rating a player's own deck (src/core/brackets.ts BracketRules), minified.
brackets = json.loads((repo / 'apps/ios/MagicMobile/Resources/commander-brackets.json').read_bytes())
(out / 'commander-brackets.json').write_text(json.dumps(brackets, ensure_ascii=False, separators=(',', ':')))

# The game's sounds (apps/ios/MagicMobile/Resources/Audio, GameAudio.swift): browsers can't decode the short cues'
# .caf, so they become AAC .m4a with macOS afconvert; the .m4a files are copied. Skipped where afconvert is missing
# (Linux CI runs no audio); the board plays silently without them.
import shutil, subprocess
audio_in = repo / 'apps/ios/MagicMobile/Resources/Audio'
audio_out = out / 'audio'
audio_out.mkdir(parents=True, exist_ok=True)
converter = shutil.which('afconvert')
converted = copied = 0
for source_file in sorted(audio_in.iterdir()):
    if source_file.suffix not in ('.caf', '.m4a'):
        continue
    target = audio_out / (source_file.stem + '.m4a')
    if target.exists() and target.stat().st_mtime >= source_file.stat().st_mtime:
        continue
    if source_file.suffix == '.m4a':
        shutil.copyfile(source_file, target)
        copied += 1
    elif converter:
        subprocess.run([converter, '-f', 'm4af', '-d', 'aac', str(source_file), str(target)], check=True, capture_output=True)
        converted += 1
if converted or copied:
    print(f'Prepared {converted} converted and {copied} copied sounds')

# The card moments' sprite strips (BoardFXCardMoments.swift: tavern-fx-counter-*, tavern-fx-exile-ring), twelve frames each.
fx_out = out / 'fx'
fx_out.mkdir(parents=True, exist_ok=True)
for name in ('tavern-fx-counter-plus', 'tavern-fx-counter-minus', 'tavern-fx-counter-loyalty', 'tavern-fx-counter-coin', 'tavern-fx-exile-ring'):
    folder = repo / 'apps/ios/MagicMobile/Assets.xcassets' / f'{name}.imageset'
    pngs = sorted(folder.glob('*.png'))
    if pngs:
        shutil.copyfile(pngs[-1], fx_out / f'{name}.png')

# The engine's ability icons (Assets.xcassets xmage-icon-*), drawn as template images in the tiles' badge row.
icons_out = out / 'icons'
icons_out.mkdir(parents=True, exist_ok=True)
for folder in sorted((repo / 'apps/ios/MagicMobile/Assets.xcassets').glob('xmage-icon-*.imageset')):
    for svg in folder.glob('*.svg'):
        shutil.copyfile(svg, icons_out / f'{folder.stem}.svg')
