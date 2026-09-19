#!/usr/bin/env python3
"""Fetch curated functional role tags from Scryfall into build/generated/role-tags.json.

These are Scryfall's community-curated *oracle tags* (tagger.scryfall.com), not a
derivation of our own. They are fetched at build time and baked into the on-device
catalogue, so role analysis on the phone stays fully offline.

Run: python3 fetch_role_tags.py [--out PATH] [--self-test]

Scryfall asks callers to identify themselves, space requests, and honour 429s; this
script does all three. Their data is CC-BY licensed and requires attribution, which
the app carries in its Deck Studio analysis copy.
"""
from __future__ import annotations

import argparse
import csv
import hashlib
import io
import json
import sys
import time
import unittest
import urllib.error
import urllib.parse
import urllib.request
from datetime import date
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / 'build/generated/role-tags.json'
ENDPOINT = 'https://api.scryfall.com/cards/search'
USER_AGENT = 'MagicMobile-RoleTags/1.0 (+https://github.com/calebfeliciano/MagicMobile)'
REQUEST_SPACING = 0.25
MAX_ATTEMPTS = 6
MAX_PAGES = 200
SCHEMA_VERSION = 1

# DeckStudioRole case name -> the Scryfall oracle tag(s) that mean the same thing.
# Keep these keys in sync with DeckStudioRole in DeckStudioRoleAnalysis.swift.
# "Targeted interaction" covers both removal and countermagic, which Scryfall tags
# separately, so a role may draw on more than one tag.
ROLE_QUERIES = {
    'ramp': ('otag:ramp',),
    # 'draw' is literal card draw; 'card-advantage' adds effects that fill your hand
    # without the word draw, such as Necropotence and Fact or Fiction.
    'cardFlow': ('otag:draw', 'otag:card-advantage'),
    'interaction': ('otag:spot-removal', 'otag:counterspell'),
    'boardWipe': ('otag:mass-removal',),
    'protection': ('otag:protection',),
    'graveyardHate': ('otag:graveyard-hate',),
    'recursion': ('otag:recursion',),
    'tutor': ('otag:tutor',),
}


def request(query: str, page: int) -> bytes:
    params = urllib.parse.urlencode(
        {'q': query, 'unique': 'cards', 'order': 'name', 'format': 'csv', 'page': page})
    req = urllib.request.Request(f'{ENDPOINT}?{params}', headers={
        'User-Agent': USER_AGENT, 'Accept': 'text/csv'})
    with urllib.request.urlopen(req, timeout=30) as response:
        if response.status != 200:
            raise RuntimeError(f'Scryfall returned HTTP {response.status} for {query} page {page}')
        return response.read()


def retry_after(error: urllib.error.HTTPError, attempt: int) -> float:
    """Honour Retry-After when the service sends one; otherwise back off exponentially."""
    header = error.headers.get('Retry-After') if error.headers else None
    if header:
        try:
            return max(1.0, min(60.0, float(header)))
        except ValueError:
            pass
    return min(30.0, 2.0 ** attempt)


def request_with_backoff(query: str, page: int, sleep=time.sleep) -> bytes:
    for attempt in range(MAX_ATTEMPTS):
        try:
            return request(query, page)
        except urllib.error.HTTPError as error:
            if error.code != 429 or attempt == MAX_ATTEMPTS - 1:
                raise
            delay = retry_after(error, attempt)
            print(f'    rate limited; waiting {delay:.0f}s', file=sys.stderr)
            sleep(delay)
    raise RuntimeError('unreachable')


def names_in(payload: bytes) -> list[str]:
    rows = csv.DictReader(io.StringIO(payload.decode('utf-8')))
    if rows.fieldnames is None or 'name' not in rows.fieldnames:
        raise RuntimeError('Scryfall CSV is missing the name column')
    return [row['name'] for row in rows if row.get('name')]


def fetch(query: str, sleep=time.sleep) -> list[str]:
    """Page through one tag. Scryfall signals the end by 404-ing past the last page."""
    seen: dict[str, None] = {}
    for page in range(1, MAX_PAGES + 1):
        try:
            rows = names_in(request_with_backoff(query, page, sleep=sleep))
        except urllib.error.HTTPError as error:
            if error.code == 404 and page > 1:
                break
            if error.code == 429:
                raise RuntimeError('Scryfall kept rate limiting this build; retry later') from error
            raise
        if not rows:
            break
        for name in rows:
            seen.setdefault(name, None)
        if len(rows) < 175:
            break
        sleep(REQUEST_SPACING)
    else:
        raise RuntimeError(f'{query} exceeded {MAX_PAGES} pages; refusing to loop')
    return sorted(seen)


def build(queries=None, fetcher=fetch, today=None) -> dict:
    queries = ROLE_QUERIES if queries is None else queries
    tags = {}
    for role, group in queries.items():
        group = (group,) if isinstance(group, str) else tuple(group)
        names: dict[str, None] = {}
        for query in group:
            found = fetcher(query)
            if not found:
                raise RuntimeError(f'{query} returned no cards; refusing to bake an empty role')
            for name in found:
                names.setdefault(name, None)
            print(f'  {role:<14} {query:<24} {len(found):>5} cards', file=sys.stderr)
        tags[role] = sorted(names)
    return dict(schemaVersion=SCHEMA_VERSION,
                fetchedAt=(today or date.today()).isoformat(),
                provider='Scryfall oracle tags (tagger.scryfall.com), CC-BY',
                queries={role: list(g) if not isinstance(g, str) else [g]
                         for role, g in sorted(queries.items())},
                tags={role: tags[role] for role in sorted(tags)})


def serialize(payload: dict) -> bytes:
    return (json.dumps(payload, ensure_ascii=False, sort_keys=True, separators=(',', ':')) + '\n').encode('utf-8')


class FetchTests(unittest.TestCase):
    def test_names_in_reads_the_name_column(self):
        self.assertEqual(names_in(b'set,name,cmc\nLEA,Sol Ring,1\nLEA,Black Lotus,0\n'),
                         ['Sol Ring', 'Black Lotus'])
        with self.assertRaises(RuntimeError):
            names_in(b'set,cmc\nLEA,1\n')

    def test_fetch_pages_until_a_short_page_and_deduplicates(self):
        pages = {1: ['Card %d' % i for i in range(175)], 2: ['Card 0', 'Late Card']}
        calls = []

        def fake(query, page):
            calls.append(page)
            rows = pages.get(page, [])
            return ('name\n' + ''.join(r + '\n' for r in rows)).encode('utf-8')

        global request
        original, request = request, fake
        try:
            names = fetch('otag:test', sleep=lambda _: None)
        finally:
            request = original
        self.assertEqual(calls, [1, 2])
        self.assertEqual(len(names), 176)
        self.assertEqual(names.count('Card 0'), 1)
        self.assertEqual(names, sorted(names))

    def test_build_refuses_an_empty_role(self):
        with self.assertRaises(RuntimeError):
            build(queries={'ramp': ('otag:ramp',)}, fetcher=lambda q: [])

    def test_build_is_deterministic_and_dated(self):
        payload = build(queries={'tutor': ('otag:tutor',), 'ramp': ('otag:ramp',)},
                        fetcher=lambda q: ['B', 'A'], today=date(2026, 9, 17))
        self.assertEqual(payload['fetchedAt'], '2026-09-17')
        self.assertEqual(list(payload['tags']), ['ramp', 'tutor'])
        self.assertEqual(serialize(payload), serialize(payload))

    def test_a_role_may_merge_several_tags(self):
        payload = build(queries={'interaction': ('otag:spot-removal', 'otag:counterspell')},
                        fetcher=lambda q: ['Counterspell'] if 'counter' in q else ['Swords to Plowshares', 'Counterspell'],
                        today=date(2026, 9, 17))
        self.assertEqual(payload['tags']['interaction'], ['Counterspell', 'Swords to Plowshares'])
        self.assertEqual(payload['queries']['interaction'], ['otag:spot-removal', 'otag:counterspell'])

    def test_role_queries_cover_every_deck_studio_role(self):
        source = (ROOT.parents[1] / 'apps/ios/MagicMobile/DeckStudio/Core/DeckStudioRoleAnalysis.swift').read_text()
        declared = source.split('case ramp,', 1)[1].split('\n', 1)[0]
        roles = {'ramp'} | {value.strip() for value in declared.split(',') if value.strip()}
        self.assertEqual(roles, set(ROLE_QUERIES))


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--out', type=Path, default=OUTPUT)
    parser.add_argument('--self-test', action='store_true')
    args = parser.parse_args()
    if args.self_test:
        return 0 if unittest.main(argv=[sys.argv[0]], exit=False).result.wasSuccessful() else 1
    print('Fetching Scryfall oracle tags:', file=sys.stderr)
    data = serialize(build())
    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_bytes(data)
    total = sum(len(v) for v in json.loads(data)['tags'].values())
    print(f'Wrote {args.out} ({len(data)} bytes, {total} tagged entries)', file=sys.stderr)
    print(f'ROLE_TAGS_SHA256 = {hashlib.sha256(data).hexdigest()}', file=sys.stderr)
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
