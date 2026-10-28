#!/usr/bin/env python3
"""EDHREC commander pages for the Deck Helper test bed (docs/DECK_HELPER.md), fetched once and trimmed to data files.

  fetch-edhrec.py list  --cache DIR [--min-decks 1000]        commanders from EDHREC's past-two-years ranking
  fetch-edhrec.py fetch --cache DIR [--min-decks 1000] [--extra "Name" …]   their commander pages (cached, 0.6 s apart)
  fetch-edhrec.py build --cache DIR --out DIR                  one trimmed file per first letter, keyed by commander name

Same source and manners as scripts/ranked/build_ai_decks.py (json.edhrec.com, a one-off User-Agent, a pause between
requests, everything cached). EDHREC's numbers are theirs: this feeds a private test bed, and shipping them in the app
is a separate question for Caleb (docs/DECK_HELPER.md).
"""
from __future__ import annotations
import argparse, json, re, sys, time, unicodedata, urllib.error, urllib.request
from pathlib import Path

BASE = 'https://json.edhrec.com/pages/'
UA = 'MagicMobile deck helper test bed (one-off, cached)'
CATEGORIES = {'topcards': 'top', 'highliftcards': 'lift', 'newcards': 'new', 'creatures': 'creature', 'instants': 'instant', 'sorceries': 'sorcery',
              'utilityartifacts': 'artifact', 'manaartifacts': 'mana', 'enchantments': 'enchantment', 'planeswalkers': 'planeswalker',
              'battles': 'battle', 'utilitylands': 'utilityland', 'lands': 'land'}


def fold(s: str) -> str:
    return unicodedata.normalize('NFD', s).encode('ascii', 'ignore').decode().lower()


def slug(name: str) -> str:
    """EDHREC's sanitized name: front face, lowercase ASCII, punctuation dropped, spaces to hyphens."""
    s = fold(name.split(' // ')[0]).replace('&', 'and')
    s = re.sub(r"[^a-z0-9 -]", '', s)
    return re.sub(r'\s+', '-', s.strip())


def get(path: str, cache: Path, pause: float = 0.6) -> dict | None:
    target = cache / (path.replace('/', '__'))
    if target.exists():
        return json.loads(target.read_text())
    request = urllib.request.Request(BASE + path, headers={'User-Agent': UA, 'Accept': 'application/json'})
    try:
        with urllib.request.urlopen(request, timeout=30) as response:
            data = response.read()
    except urllib.error.HTTPError as error:
        if error.code == 404:
            target.write_text('null')
            time.sleep(pause)
            return None
        raise
    target.write_bytes(data)
    time.sleep(pause)
    return json.loads(data)


def commander_list(cache: Path, min_decks: int) -> list[dict]:
    """(name, slug, decks) from the past-two-years ranking, walking its pages until decks drop under min_decks."""
    out, path = [], 'commanders/year.json'
    while path:
        page = get(path, cache) or {}
        # The first page nests its list in container.json_dict.cardlists; the paginated pages are a bare list.
        if 'cardviews' in page:
            views, more = page.get('cardviews', []), page.get('more')
        else:
            lists = page.get('container', {}).get('json_dict', {}).get('cardlists', [])
            views, more = (lists[0].get('cardviews', []), lists[0].get('more')) if lists else ([], None)
        for view in views:
            out.append({'name': view['name'], 'slug': view['sanitized'], 'decks': view.get('num_decks', 0)})
        if not views or views[-1].get('num_decks', 0) < min_decks or not more:
            break
        path = more if more.endswith('.json') else more + '.json'
    return [c for c in out if c['decks'] >= min_decks]


def trim(page: dict) -> dict | None:
    jd = page.get('container', {}).get('json_dict', {})
    card = jd.get('card') or {}
    if not card.get('name'):
        return None
    seen, cards = {}, []
    for cardlist in jd.get('cardlists', []):
        cat = CATEGORIES.get(cardlist.get('tag'), cardlist.get('tag') or '')
        for view in cardlist.get('cardviews', []):
            name = view.get('name')
            potential = view.get('potential_decks') or card.get('num_decks') or 1
            inc = round(100 * (view.get('num_decks') or 0) / potential)
            syn = round(100 * (view.get('synergy') or 0))
            if name in seen:  # keep the type list's category, remember the top/lift flag
                entry = cards[seen[name]]
                if cat in ('top', 'lift', 'new'):
                    entry[4] |= {'top': 1, 'lift': 2, 'new': 4}[cat]
                elif entry[3] in ('top', 'lift', 'new'):
                    entry[3] = cat
                continue
            seen[name] = len(cards)
            flags = {'top': 1, 'lift': 2, 'new': 4}.get(cat, 0)
            cards.append([name, inc, syn, cat, flags])
    counts = {k: int(page.get(k) or 0) for k in ('creature', 'instant', 'sorcery', 'artifact', 'enchantment', 'planeswalker', 'battle', 'land', 'basic', 'nonbasic')}
    tags = [[t.get('value'), t.get('count')] for t in (page.get('tag_counts') or [])[:8]]
    return {'name': card['name'], 'decks': card.get('num_decks') or 0, 'counts': counts, 'tags': tags,
            'brackets': page.get('bracket_counts') or {}, 'similar': (page.get('similar') or [])[:8], 'cards': cards}


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('command', choices=['list', 'fetch', 'build'])
    parser.add_argument('--cache', type=Path, required=True)
    parser.add_argument('--out', type=Path)
    parser.add_argument('--min-decks', type=int, default=1000)
    parser.add_argument('--extra', nargs='*', default=[], help='commander names to add to the ranking')
    parser.add_argument('--extra-file', type=Path, help='a file of commander names, one per line, added to the ranking')
    args = parser.parse_args()
    args.cache.mkdir(parents=True, exist_ok=True)
    if args.command == 'list':
        commanders = commander_list(args.cache, args.min_decks)
        print(f'{len(commanders)} commanders with at least {args.min_decks} decks; last: {commanders[-1] if commanders else None}')
        return
    if args.command == 'fetch':
        commanders = commander_list(args.cache, args.min_decks)
        extra = list(args.extra) + ([l.strip() for l in args.extra_file.read_text().splitlines() if l.strip()] if args.extra_file else [])
        slugs = {c['slug'] for c in commanders} | {slug(n) for n in extra}
        done = missing = 0
        for i, s in enumerate(sorted(slugs)):
            page = get(f'commanders/{s}.json', args.cache)
            done += page is not None
            missing += page is None
            if i % 100 == 0:
                print(f'{i}/{len(slugs)} … {s}', flush=True)
        print(f'fetched {done} commander pages, {missing} missing')
        return
    if not args.out:
        sys.exit('build needs --out')
    args.out.mkdir(parents=True, exist_ok=True)
    shards: dict[str, dict] = {}
    for path in sorted(args.cache.glob('commanders__*.json')):
        if path.name.startswith('commanders__year') or path.name.startswith('commanders__month') or path.name.startswith('commanders__week'):
            continue
        page = json.loads(path.read_text())
        entry = trim(page) if page else None
        if not entry:
            continue
        key = fold(entry['name'].split(' // ')[0])
        letter = key[0] if key[:1].isalpha() else '0'
        shards.setdefault(letter, {})[key] = entry
    total = n = 0
    for letter, entries in shards.items():
        text = json.dumps(entries, ensure_ascii=False, separators=(',', ':'))
        (args.out / f'{letter}.json').write_text(text)
        total += len(text)
        n += len(entries)
    (args.out / 'index.json').write_text(json.dumps({'built': time.strftime('%Y-%m-%d'), 'source': 'EDHREC commander pages (json.edhrec.com)', 'commanders': n, 'shards': sorted(shards)}))
    print(f'wrote {n} commanders in {len(shards)} files, {total / 1e6:.1f} MB')


if __name__ == '__main__':
    main()
