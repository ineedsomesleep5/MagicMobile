#!/usr/bin/env python3
"""Add card pictures to data.json as sprite sheets the Card Support page can show.

Artifact pages cannot load pictures from other sites, so the pictures ship with the page.
Needs network access to api.scryfall.com and cards.scryfall.io (a GitHub Actions runner has it;
the Claude cloud container does not). Uses Scryfall's 'small' image (146x204), 100 per sheet.

    python3 scripts/card-support/make_sprites.py --data out/data.json --out out/img [--cache .scryfall-cache]
"""
import argparse
import io
import json
import time
import urllib.error
import urllib.request
from pathlib import Path

from PIL import Image  # pip install pillow

UA = {'User-Agent': 'MagicMobileCardSupport/1.0', 'Accept': 'application/json'}
W, H, COLS, PER = 146, 204, 10, 100


def http(url, body=None, tries=6):
    """Retries rate limits (429, honouring Retry-After) and server errors with growing waits."""
    req = urllib.request.Request(url, data=json.dumps(body).encode() if body else None,
                                 headers={**UA, **({'Content-Type': 'application/json'} if body else {})})
    for attempt in range(tries):
        try:
            with urllib.request.urlopen(req, timeout=60) as r:
                return r.read()
        except urllib.error.HTTPError as e:
            if attempt == tries - 1 or (e.code != 429 and e.code < 500):
                raise
            wait = e.headers.get('Retry-After') if e.headers else None
            time.sleep(float(wait) if wait and wait.replace('.', '', 1).isdigit() else 2 ** (attempt + 1))
        except urllib.error.URLError:
            if attempt == tries - 1:
                raise
            time.sleep(2 ** (attempt + 1))


def lookup(cards):
    """Scryfall /cards/collection, 75 at a time: exact printing first, then by name."""
    found = {}
    for pass_ in ('print', 'name'):
        todo = [c for c in cards if c['name'] not in found]
        for i in range(0, len(todo), 75):
            chunk = todo[i:i + 75]
            ids = ([{'set': c['set'].lower(), 'collector_number': str(c['num'])} for c in chunk] if pass_ == 'print'
                   else [{'name': c['name'].split(' // ')[0]} for c in chunk])
            res = json.loads(http('https://api.scryfall.com/cards/collection', {'identifiers': ids}))
            for card in res.get('data', []):
                uris = card.get('image_uris') or (card.get('card_faces') or [{}])[0].get('image_uris') or {}
                if not uris.get('small'):
                    continue
                for c in chunk:
                    if c['name'] not in found and (
                            (pass_ == 'print' and c['set'].lower() == card['set'] and str(c['num']) == card['collector_number'])
                            or (pass_ == 'name' and c['name'].split(' // ')[0].lower() == card['name'].split(' // ')[0].lower())):
                        found[c['name']] = uris['small']
            time.sleep(0.6)  # Scryfall allows about 2 requests a second on /cards/collection.
    return found


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--data', required=True)
    ap.add_argument('--out', required=True, help='folder for sheet-N.jpg, published as img/')
    ap.add_argument('--cache', default='.scryfall-cache')
    a = ap.parse_args()
    data = json.loads(Path(a.data).read_text())
    cards = data['newCards'] + data['commanders']
    urls = lookup(cards)
    cache, out = Path(a.cache), Path(a.out)
    cache.mkdir(parents=True, exist_ok=True); out.mkdir(parents=True, exist_ok=True)
    names, missing = [], 0
    for name in dict.fromkeys(c['name'] for c in cards if c['name'] in urls):
        key = cache / urls[name].split('/')[-1].split('?')[0]
        if not key.exists():
            try:
                key.write_bytes(http(urls[name])); time.sleep(0.05)
            except Exception:
                missing += 1
                continue
        names.append(name)
    at, sheets = {}, []
    for s in range(0, len(names), PER):
        sheet = Image.new('RGB', (W * COLS, H * (PER // COLS)), (43, 27, 17))
        for i, name in enumerate(names[s:s + PER]):
            key = cache / urls[name].split('/')[-1].split('?')[0]
            img = Image.open(io.BytesIO(key.read_bytes())).convert('RGB').resize((W, H))
            sheet.paste(img, ((i % COLS) * W, (i // COLS) * H))
            at[name] = [len(sheets), i]
        path = f'img/sheet-{len(sheets)}.jpg'
        sheet.save(out / Path(path).name, quality=78, optimize=True, progressive=True)
        sheets.append(path)
    data['images'] = {'sheets': sheets, 'cols': COLS, 'perSheet': PER, 'at': at}
    Path(a.data).write_text(json.dumps(data, ensure_ascii=False, separators=(',', ':')))
    print(f'{len(at)} of {len(cards)} cards pictured on {len(sheets)} sheets ({missing} downloads failed)')


if __name__ == '__main__':
    main()
