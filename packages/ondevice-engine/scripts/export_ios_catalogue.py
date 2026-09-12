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
import json
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT.parents[1] / 'apps/ios/MagicMobile/Resources/ondevice-catalogue.json'
UPSTREAM = '8aea65ae9ae3c89970fe865e1316105539e097ca'
CATALOGUE_SHA256 = '7ac98264dee413be459cdcdd01839de3af51d68060adb28f48881f3a1a5da2a0'
REPORT_SHA256 = '0ded410be118be4bbb5ae0f59c7657bacc97cfcef6493aeade7e3ac509fa0175'
REGISTRY_HASH = '807f3deda781f1e912c17c6648e4fb81dc4b00d08b33ee2c308e3f161206267a'
SET_ELIGIBILITY_SHA256 = '27902e939769f396d3d17bdb29cddbabc5da7db909466c816e37e5a8e4ae9ebb'


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
    cards, stats = normalize([json.loads(line) for line in source.splitlines() if line.strip()], set(eligibility['eternalLegalSetCodes']))
    payload = dict(schemaVersion=1, upstreamCommit=UPSTREAM, catalogueHash=REGISTRY_HASH,
                   sourceCatalogueSHA256=CATALOGUE_SHA256, sourceRegistrySHA256=REPORT_SHA256,
                   sourceSetEligibilitySHA256=SET_ELIGIBILITY_SHA256,
                   cards=cards, statistics=stats)
    return (json.dumps(payload, ensure_ascii=False, sort_keys=True, separators=(',', ':')) + '\n').encode('utf-8')


class ExportTests(unittest.TestCase):
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
        checked_bytes(ROOT / 'build/generated/catalogue.jsonl', CATALOGUE_SHA256)
        with self.assertRaisesRegex(ValueError, 'source SHA-256 mismatch'):
            checked_bytes(ROOT / 'build/generated/catalogue.jsonl', '0' * 64)


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
