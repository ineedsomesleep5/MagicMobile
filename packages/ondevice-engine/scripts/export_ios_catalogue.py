#!/usr/bin/env python3
"""Export exact-name iOS printings from the pinned REAL registry; no runtime class names.

Run from any directory: python3 export_ios_catalogue.py [--check | --self-test].
--check validates source SHA-256 pins and byte-for-byte regeneration without writing.
When rebuilding upstream, review and update these pins together with the native candidate.
"""
from __future__ import annotations

import argparse
from collections import Counter
import hashlib
import gzip
import math
import json
from pathlib import Path
import unittest
import tempfile

ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT.parents[1] / 'apps/ios/MagicMobile/Resources/ondevice-catalogue.json'
UPSTREAM = '4825513287ba6c42c32fd205d227f4a5fc44c2f3'
CATALOGUE_SHA256 = 'ef7fec6b51ce03aa89c353c964b6ea9c4cd5b4dbd9c768b38c9d111611070cda'
REPORT_SHA256 = 'a5c526e44c6d94dca87e5900d64b640e796901d2c1d03d9dd974998c19bf641d'
REGISTRY_HASH = 'f9b5676c5f84fb684d15176f740d13edccc4835b43a27ccbe4e8356a6fb407bf'
SET_ELIGIBILITY_SHA256 = 'a45158f9ea0cb57aaf0c1030cb8f0259d71a602376e85309c0d7871c03ab05f0'
METADATA_SHA256 = '2993fc9a3ea4b48a63513dc5196a223ffb1312488050d00b2bdbf2ce3d573d0e'
ROLE_TAGS_SHA256 = 'f0b9f48e4e0c43f6f847dcd8f51954ede58bcdaca58effbf6d8710237fcdbf86'


def checked_bytes(path: Path, expected: str) -> bytes:
    data = path.read_bytes()
    if hashlib.sha256(data).hexdigest() != expected:
        raise ValueError(f'{path.name}: source SHA-256 mismatch; review the real registry and native candidate before updating pins')
    return data


def normalize(rows: list[dict], eligible_codes: set[str] | None = None) -> tuple[list[dict], dict]:
    keys = ('name', 'setCode', 'collectorNumber')
    for row in rows:
        if any(not isinstance(row.get(key), str) or not row[key] for key in keys):
            raise ValueError('Catalogue has an invalid exact printing identity')
    frequencies = Counter((row['setCode'], row['collectorNumber']) for row in rows)
    selected = {}
    for row in rows:
        if eligible_codes is not None and row['setCode'] not in eligible_codes:
            continue
        # DeckLoader rejects any repeated collector number, even identical metadata rows.
        if frequencies[(row['setCode'], row['collectorNumber'])] != 1:
            continue
        name = row['name']
        candidate = {key: row[key] for key in keys}
        previous = selected.get(name)
        if previous is None or (row['setCode'], row['collectorNumber']) < (previous['setCode'], previous['collectorNumber']):
            selected[name] = candidate
    if not selected:
        raise ValueError('No uniquely addressable printings remain')
    stats = {
        'sourcePrintings': len(rows),
        'uniqueNames': len(selected),
        'excludedAmbiguousPrintings': sum(count for count in frequencies.values() if count > 1),
        'excludedNonEternalPrintings': sum(1 for row in rows if eligible_codes is not None and row['setCode'] not in eligible_codes),
        'unresolvableNames': sorted({row['name'] for row in rows} - selected.keys()),
    }
    return [selected[name] for name in sorted(selected)], stats


def name_aliases(cards: list[dict], metadata: list[dict]) -> dict[str, str]:
    """Only the selected exact printing can attest a double-faced front/back alias."""
    selected = {(c['name'], c['setCode'], c['collectorNumber']) for c in cards}
    canonical = {c['name'] for c in cards}
    seen = set()
    aliases = {}
    for row in metadata:
        key = (row.get('name'), row.get('setCode'), row.get('cardNumber'))
        if key not in selected:
            continue
        if key in seen:
            raise ValueError('Ambiguous selected printing metadata')
        seen.add(key)
        # CardInfo.doubleFaced means transformable. Modal spell/land and
        # creature/sorcery cards have a real reverse face but are not
        # transformable; doubleFacedCard records the actual DoubleFacedCard.
        if row.get('doubleFacedCard') is not True or row.get('nightCard') is not False:
            continue
        if row.get('splitCard') is True or row.get('splitCardHalf') is True:
            continue
        back = row.get('secondSideName')
        if not isinstance(back, str) or not back.strip() or back != back.strip():
            raise ValueError('Double-faced front has no exact second-side name')
        if row.get('doubleFacedSecondSideName') != back:
            raise ValueError('Conflicting double-faced second-side metadata')
        alias = row['name'] + ' // ' + back
        if alias in canonical:
            continue  # An exact compiled split-card name always wins.
        if alias in aliases and aliases[alias] != row['name']:
            raise ValueError('Ambiguous double-faced name alias')
        aliases[alias] = row['name']
    return dict(sorted(aliases.items()))


COLOR_SYMBOLS = ('W', 'U', 'B', 'R', 'G')


def color_identity(value) -> list[str] | None:
    """Validate XMage's build-time identity, including every face. Never infer
    legality from display text, which lacks reverse-face color indicators."""
    if value is None:
        return None
    if (not isinstance(value, list) or any(v not in COLOR_SYMBOLS for v in value)
            or len(set(value)) != len(value)):
        raise ValueError('Invalid XMage color identity')
    return [symbol for symbol in COLOR_SYMBOLS if symbol in value]


def card_metadata(cards: list[dict], metadata: list[dict], source_rows: list[dict]) -> dict:
    selected = {(c['name'], c['setCode'], c['collectorNumber']): c['name'] for c in cards}
    sets = {}
    for row in source_rows:
        sets.setdefault(row['name'], set()).add(row['setCode'])
    result = {}
    def tokens(value):
        return list(dict.fromkeys(v for v in value.split('@@@') if v)) if isinstance(value, str) else None
    for row in metadata:
        key = (row.get('name'), row.get('setCode'), row.get('cardNumber'))
        if key not in selected:
            continue
        name = selected[key]
        if name in result:
            raise ValueError('Ambiguous selected printing metadata')
        types, supers, subs = (tokens(row.get(k)) for k in ('types', 'supertypes', 'subtypes'))
        type_line = None
        if types is not None and supers is not None and subs is not None:
            type_line = ' '.join(v.title() for v in supers + types)
            if subs:
                type_line += ' — ' + ' '.join(subs)
        value = row.get('manaValue')
        if value is not None and (type(value) not in (int, float) or not math.isfinite(value) or value < 0):
            raise ValueError('Invalid metadata mana value')
        color_keys = [('W', 'white'), ('U', 'blue'), ('B', 'black'), ('R', 'red'), ('G', 'green')]
        colors = [symbol for symbol, key in color_keys if row[key]] if all(type(row.get(key)) is bool for _, key in color_keys) else None
        result[name] = dict(typeLine=type_line, types=types,
                            oracleText=row['rules'].replace('@@@', '\n').rstrip('\n') if isinstance(row.get('rules'), str) else None,
                            manaValue=value, manaCost=row['manaCosts'].replace('@@@', '') if isinstance(row.get('manaCosts'), str) else None,
                            colors=colors,
                            colorIdentity=color_identity(row.get('colorIdentity')),
                            setCodes=sorted(sets.get(name, set())))
    return dict(sorted(result.items()))


def apply_role_tags(metadata: dict, aliases: dict, tags: dict) -> tuple[dict, int]:
    """Attach curated Scryfall oracle-tag roles to catalogue entries.

    Scryfall names double-faced cards "Front // Back"; our metadata is keyed by the
    name the engine uses, so resolve through the same alias table the app uses. A
    card with no curated tag simply carries no "roles" key; the app falls back to its
    own explainable text patterns there, and a player's own tags always win."""
    resolved = {}
    for role, names in sorted(tags.items()):
        for name in names:
            key = name if name in metadata else aliases.get(name)
            if key is None and ' // ' in name:
                front = name.split(' // ', 1)[0]
                key = front if front in metadata else None
            if key is not None:
                resolved.setdefault(key, set()).add(role)
    order = list(tags)
    for name, roles in resolved.items():
        metadata[name]['roles'] = sorted(roles, key=order.index)
    return metadata, len(resolved)


def export() -> bytes:
    lock = json.loads((ROOT / 'upstream.lock.json').read_bytes())
    if lock['commit'] != UPSTREAM:
        raise ValueError('Upstream lock changed; regenerate and review the real registry first')
    source = checked_bytes(ROOT / 'build/generated/catalogue.jsonl', CATALOGUE_SHA256)
    report = json.loads(checked_bytes(ROOT / 'build/generated/registry-report.json', REPORT_SHA256))
    if report['registryHash'] != REGISTRY_HASH:
        raise ValueError('Registry does not match the pinned native capability hash')
    eligibility = json.loads(checked_bytes(ROOT / 'build/generated/commander-set-codes.json', SET_ELIGIBILITY_SHA256))
    if eligibility['upstreamCommit'] != UPSTREAM:
        raise ValueError('Commander set eligibility belongs to a different upstream')
    source_rows = [json.loads(line) for line in source.splitlines() if line.strip()]
    cards, stats = normalize(source_rows, set(eligibility['eternalLegalSetCodes']))
    metadata = gzip.decompress(checked_bytes(ROOT / 'build/engine/mage/mobile/card-metadata.jsonl.gz', METADATA_SHA256))
    metadata_rows = [json.loads(line) for line in metadata.splitlines() if line.strip()]
    aliases = name_aliases(cards, metadata_rows)
    role_tags = json.loads(checked_bytes(ROOT / 'engine/data/role-tags.json', ROLE_TAGS_SHA256))
    if role_tags['schemaVersion'] != 1:
        raise ValueError('Role tags use an unexpected schema version')
    entries, tagged = apply_role_tags(card_metadata(cards, metadata_rows, source_rows), aliases, role_tags['tags'])
    if any(entry['colorIdentity'] is None for entry in entries.values()):
        raise ValueError('Selected printing lacks XMage color identity; rebuild card metadata')
    stats = stats | dict(roleTaggedNames=tagged)
    payload = dict(schemaVersion=1, upstreamCommit=UPSTREAM, catalogueHash=REGISTRY_HASH,
                   sourceCatalogueSHA256=CATALOGUE_SHA256, sourceRegistrySHA256=REPORT_SHA256,
                   sourceSetEligibilitySHA256=SET_ELIGIBILITY_SHA256,
                   sourceMetadataSHA256=METADATA_SHA256, sourceRoleTagsSHA256=ROLE_TAGS_SHA256,
                   roleTagsFetchedAt=role_tags['fetchedAt'], roleTagProvider=role_tags['provider'],
                   nameAliases=aliases, cardMetadata=entries,
                   cards=cards, statistics=stats)
    return (json.dumps(payload, ensure_ascii=False, sort_keys=True, separators=(',', ':')) + '\n').encode('utf-8')


class ExportTests(unittest.TestCase):
    def test_metadata_preserves_unknowns_and_selected_printing(self):
        cards = [dict(name='Front', setCode='SET', collectorNumber='1')]
        row = dict(name='Front', setCode='SET', cardNumber='1', types='CREATURE@@@', supertypes='LEGENDARY@@@', subtypes='Elf@@@',
                   rules='First@@@Second@@@', manaCosts='{2}@@@{G/W}@@@', manaValue=3, white=True, blue=False, black=False, red=False, green=True,
                   colorIdentity=['W', 'G'])
        out = card_metadata(cards, [row, row | dict(cardNumber='2', manaValue=9)], cards)['Front']
        self.assertEqual(out['typeLine'], 'Legendary Creature — Elf')
        self.assertEqual(out['oracleText'], 'First\nSecond')
        self.assertEqual(out['manaCost'], '{2}{G/W}')
        self.assertEqual(out['manaValue'], 3)
        self.assertEqual(out['colors'], ['W', 'G'])
        self.assertEqual(out['colorIdentity'], ['W', 'G'])
        self.assertEqual(out['setCodes'], ['SET'])
        missing = card_metadata(cards, [dict(name='Front', setCode='SET', cardNumber='1')], cards)['Front']
        for key in ['typeLine', 'types', 'oracleText', 'manaValue', 'manaCost', 'colors', 'colorIdentity']:
            self.assertIsNone(missing[key])
        with self.assertRaises(ValueError):
            card_metadata(cards, [row, row], cards)

    def test_color_identity_preserves_engine_faces_and_unknowns(self):
        self.assertEqual(color_identity(['R', 'W']), ['W', 'R'])
        self.assertEqual(color_identity([]), [])
        self.assertIsNone(color_identity(None))
        for invalid in ['W', ['W', 'W'], ['C'], [True]]:
            with self.assertRaises(ValueError):
                color_identity(invalid)
        cards = [dict(name='Front', setCode='SET', collectorNumber='1')]
        row = dict(name='Front', setCode='SET', cardNumber='1', doubleFaced=True,
                   white=True, blue=False, black=False, red=False, green=False,
                   manaCosts='{W}', rules='Transform this.', colorIdentity=['W', 'R'])
        result = card_metadata(cards, [row], cards)['Front']
        self.assertEqual(result['colors'], ['W'])
        self.assertEqual(result['colorIdentity'], ['W', 'R'])

    def test_role_tags_resolve_through_aliases_and_front_faces(self):
        metadata = {'Sol Ring': {}, 'Aberrant Researcher': {}, 'Wrath of God': {}}
        aliases = {'Aberrant Researcher // Perfected Form': 'Aberrant Researcher'}
        tags = {'ramp': ['Sol Ring', 'Not In Catalogue'],
                'cardFlow': ['Aberrant Researcher // Perfected Form'],
                'boardWipe': ['Wrath of God'], 'protection': ['Wrath of God']}
        out, tagged = apply_role_tags(metadata, aliases, tags)
        self.assertEqual(tagged, 3)
        self.assertEqual(out['Sol Ring']['roles'], ['ramp'])
        self.assertEqual(out['Aberrant Researcher']['roles'], ['cardFlow'])
        # Multiple roles keep the declared role order, not alphabetical order.
        self.assertEqual(out['Wrath of God']['roles'], ['boardWipe', 'protection'])

    def test_untagged_cards_carry_no_roles_key(self):
        out, tagged = apply_role_tags({'Mystery Card': {}}, {}, {'ramp': ['Sol Ring']})
        self.assertNotIn('roles', out['Mystery Card'])
        self.assertEqual(tagged, 0)

    def test_front_face_fallback_without_an_alias_entry(self):
        out, _ = apply_role_tags({'Delver of Secrets': {}}, {},
                                 {'cardFlow': ['Delver of Secrets // Insectile Aberration']})
        self.assertEqual(out['Delver of Secrets']['roles'], ['cardFlow'])

    def test_uses_commander_eligible_printing_without_changing_card_name(self):
        rows = [dict(name='Hornet Queen', setCode='AKR', collectorNumber='196'),
                dict(name='Hornet Queen', setCode='C21', collectorNumber='194'),
                dict(name='Digital-only card', setCode='AKR', collectorNumber='1')]
        cards, stats = normalize(rows, {'C21'})
        self.assertEqual(cards, [dict(name='Hornet Queen', setCode='C21', collectorNumber='194')])
        self.assertEqual(stats['excludedNonEternalPrintings'], 2)
        self.assertEqual(stats['unresolvableNames'], ['Digital-only card'])

    def test_ambiguous_collectors_excluded_and_exact_names_deterministic(self):
        rows = [dict(name=name, setCode=code, collectorNumber=number, className='test-only')
                for name, code, number in [('Forest', 'A', '1'), ('Forest', 'A', '1'),
                                           ('Forest', 'C', '1'), ('Forest', 'B', '9'),
                                           ('Island', 'D', '2'), ('Other', 'D', '2'),
                                           ('forest', 'E', '1')]]
        cards, stats = normalize(rows)
        self.assertEqual(cards, [dict(name='Forest', setCode='B', collectorNumber='9'),
                                dict(name='forest', setCode='E', collectorNumber='1')])
        self.assertEqual(normalize(list(reversed(rows))), (cards, stats))
        self.assertEqual(stats['excludedAmbiguousPrintings'], 4)
        self.assertEqual(stats['unresolvableNames'], ['Island', 'Other'])

    def test_invalid_or_empty_catalogue_rejected(self):
        for rows in [[], [dict(name='Forest', setCode='A', collectorNumber=None)]]:
            with self.assertRaises(ValueError):
                normalize(rows)

    def test_pinned_sources_and_content_hash_mismatch(self):
        # Self-tests run before native metadata exists in bootstrap tooling jobs.
        # Production export/--check still require every actual pinned input.
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / 'source'
            path.write_bytes(b'exact fixture')
            checked_bytes(path, hashlib.sha256(b'exact fixture').hexdigest())
            with self.assertRaisesRegex(ValueError, 'source SHA-256 mismatch'):
                checked_bytes(path, '0' * 64)

    def test_alias_requires_selected_front_printing_and_exact_back(self):
        cards = [dict(name='Front', setCode='SET', collectorNumber='1')]
        front = dict(name='Front', setCode='SET', cardNumber='1', doubleFaced=True, doubleFacedCard=True,
                     nightCard=False, secondSideName='Back', doubleFacedSecondSideName='Back')
        self.assertEqual(name_aliases(cards, [front]), {'Front // Back': 'Front'})
        for changed in [dict(cardNumber='2'), dict(setCode='OTHER'), dict(nightCard=True),
                        dict(doubleFacedCard=False), dict(splitCard=True), dict(splitCardHalf=True)]:
            self.assertEqual(name_aliases(cards, [front | changed]), {})
        for rows in [[front, front], [front | dict(secondSideName='Wrong')], [front | dict(secondSideName='')]]:
            with self.assertRaises(ValueError):
                name_aliases(cards, rows)

    def test_modal_spell_face_alias_uses_double_faced_card_metadata(self):
        cards = [dict(name='Revitalizing Repast', setCode='MH3', collectorNumber='256')]
        row = dict(name='Revitalizing Repast', setCode='MH3', cardNumber='256',
                   doubleFaced=False, doubleFacedCard=True, nightCard=False,
                   splitCard=False, splitCardHalf=False,
                   secondSideName='Old-Growth Grove', doubleFacedSecondSideName='Old-Growth Grove')
        self.assertEqual(name_aliases(cards, [row]),
                         {'Revitalizing Repast // Old-Growth Grove': 'Revitalizing Repast'})

    def test_exact_split_name_wins_and_conflicting_aliases_reject(self):
        cards = [dict(name='Front', setCode='SET', collectorNumber='1'),
                 dict(name='Front // Back', setCode='SET', collectorNumber='2')]
        row = dict(name='Front', setCode='SET', cardNumber='1', doubleFaced=True, doubleFacedCard=True,
                   nightCard=False, secondSideName='Back', doubleFacedSecondSideName='Back')
        self.assertEqual(name_aliases(cards, [row]), {})
        cards[1]['name'] = 'Front // Middle'
        second = row | dict(name='Front // Middle', cardNumber='2', secondSideName='Back')
        with self.assertRaises(ValueError):
            name_aliases(cards, [row | dict(secondSideName='Middle // Back'), second])


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument('--check', action='store_true')
    mode.add_argument('--self-test', action='store_true')
    args = parser.parse_args()
    if args.self_test:
        result = unittest.TextTestRunner().run(unittest.defaultTestLoader.loadTestsFromTestCase(ExportTests))
        raise SystemExit(0 if result.wasSuccessful() else 1)
    try:
        data = export()
        if args.check:
            if not OUTPUT.exists() or OUTPUT.read_bytes() != data:
                raise ValueError('Bundled catalogue is stale or missing; run export_ios_catalogue.py to regenerate')
        else:
            OUTPUT.parent.mkdir(parents=True, exist_ok=True)
            OUTPUT.write_bytes(data)
        stats = json.loads(data)['statistics']
        print(f'{"Verified" if args.check else "Exported"} {len(data)} bytes; '
              f'{stats["uniqueNames"]} exact names; {stats["excludedNonEternalPrintings"]} non-eternal printings excluded; '
              f'{len(stats["unresolvableNames"])} names have no eligible printing')
    except (ValueError, KeyError, OSError) as error:
        parser.exit(1, f'{error}\n')


if __name__ == '__main__':
    main()
