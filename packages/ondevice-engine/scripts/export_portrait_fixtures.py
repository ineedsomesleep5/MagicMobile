#!/usr/bin/env python3
"""Export unmodified real JVM poll results for portrait transport/projection tests."""
from __future__ import annotations

import argparse
import collections
import datetime
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import time
import uuid

# Importing the existing client must not write outside our dedicated build folder.
sys.dont_write_bytecode = True
from jvm_client import EngineProcess, ROOT

REPO = ROOT.parents[1]
BUILD = ROOT / 'build/test-portrait-fixtures'
EVIDENCE = ROOT / 'evidence/portrait-fixtures'
OUTPUT = REPO / 'apps/ios/MagicMobileTests/Fixtures/OnDevice'


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def write_json(path, value):
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + '\n')
    assert json.loads(path.read_text()) == value, f'JSON round trip failed: {path}'


def git(*args, cwd=REPO):
    return subprocess.check_output(['git', *args], cwd=cwd, text=True).strip()


def configuration(count):
    # The exact synthetic printing rows used by tests/decks/isamaru.txt and yargle.txt.
    # The production DeckLoader and upstream Commander validator approve these at create.
    templates = [
        ('Plains', 'CHK', '287', 'Isamaru, Hound of Konda', 'CHK', '19'),
        ('Swamp', 'DOM', '258', 'Yargle, Glutton of Urborg', 'DOM', '113'),
    ]
    seats = []
    for index in range(count):
        land, land_set, land_number, commander, commander_set, commander_number = templates[index % 2]
        seats.append({'seatId': f'player-{index + 1}', 'name': f'Fixture Player {index + 1}',
                      'controller': 'human', 'deck': {
                          'name': 'Synthetic portrait regression deck',
                          'main': [{'count': 99, 'name': land, 'setCode': land_set, 'collectorNumber': land_number}],
                          'commanders': [{'count': 1, 'name': commander, 'setCode': commander_set,
                                          'collectorNumber': commander_number}]}})
    return {'seats': seats}


def answer_for(state, attacks):
    """Same bounded human protocol driver as play_jvm.py; no state injection."""
    prompt = state['prompt']
    payload = prompt['payload']
    message = payload['message'].lower()
    snapshot = state['snapshot']
    view = snapshot['gameView']
    kind = prompt['kind']
    answer = {'kind': 'boolean', 'value': False}
    if kind == 'ASK':
        if 'mulligan' not in message:
            raise RuntimeError(f'Unhandled ASK: {message}')
    elif kind == 'PICK_TARGET':
        candidates = payload['candidates']
        target = snapshot['enginePlayerId'] if 'starting player' in message else candidates[0]
        assert target in candidates
        answer = {'kind': 'uuid', 'value': target}
    elif kind == 'SELECT':
        if 'attackers' in message:
            key = (state['viewerId'], view['turn'])
            if 'specialButton' in payload.get('options', {}) and key not in attacks:
                attacks.add(key)
                answer = {'kind': 'string', 'value': 'special'}
        elif 'blockers' not in message:
            objects = view.get('canPlayObjects', {}).get('objects', {})
            for ability_kind in ('basicPlayAbilities', 'basicCastAbilities'):
                card = next((card for card, abilities in objects.items() if abilities.get(ability_kind)), None)
                if card:
                    answer = {'kind': 'uuid', 'value': card}
                    break
    elif kind == 'PLAY_MANA':
        player = next(p for p in view['players'] if p['playerId'] == snapshot['enginePlayerId'])
        lands = [p for p in player['battlefield'].values()
                 if not p.get('tapped') and 'LAND' in p.get('cardTypes', [])]
        if not lands:
            raise RuntimeError('No legal fixture mana source found')
        answer = {'kind': 'uuid', 'value': lands[0]['id']}
    elif kind in ('CHOOSE_ABILITY', 'PICK_ABILITY'):
        answer = {'kind': 'uuid', 'value': payload['abilities'][0]['id']}
    else:
        raise RuntimeError(f'Unhandled prompt: {kind}')
    return answer


def capture_match(engine, count, timeout, fixtures):
    config = configuration(count)
    created = engine.call('create', configuration=config)
    assert created['engine']['engine'] == 'xmage'
    assert created['engine']['execution'] == 'jvm-integration'
    match = created['matchId']
    captured, mapping, cursors, seen, attacks = {}, {}, {}, set(), set()
    responses = collections.Counter()
    deadline = time.monotonic() + timeout
    required = {'initial', 'priority'}
    if count == 2:
        required |= {'mana', 'stack', 'battlefield', 'attackers', 'combat'}

    def poll(seat):
        state = engine.call('poll', matchId=match, viewerId=seat, after=cursors.get(seat, 0))
        cursors[seat] = state['revision']
        if state['phase'] in ('failed', 'ended'):
            raise RuntimeError(f'Match stopped before fixture coverage: {state["phase"]}, {state["failure"]}')
        return state

    def save(label, state):
        filename = f'{count}p-{label}.json'
        # Store the entire poll result unchanged, including events, prompt and all GameView fields.
        fixtures[filename] = state
        print(f'Captured {filename}: turn {state["snapshot"]["gameView"].get("turn")}', flush=True)

    try:
        while time.monotonic() < deadline:
            progressed = False
            for seat in created['seats']:
                state = poll(seat)
                prompt = state.get('prompt')
                if not prompt or prompt['submitted'] or prompt['promptId'] in seen:
                    continue
                view = state['snapshot']['gameView']
                kind = prompt['kind']
                message = prompt['payload']['message'].lower()
                if kind == 'ASK' and 'initial' not in captured:
                    # No response is submitted during this group, keeping each seat at the same decision.
                    for viewer in created['seats']:
                        initial = poll(viewer)
                        mapping[viewer] = initial['snapshot']['enginePlayerId']
                        save(f'initial-{viewer}', initial)
                    captured['initial'] = True
                conditions = {
                    'priority': kind == 'SELECT' and 'attackers' not in message and 'blockers' not in message
                                and bool(view.get('canPlayObjects', {}).get('objects')),
                    'mana': kind == 'PLAY_MANA',
                    'stack': kind == 'SELECT' and bool(view.get('stack')),
                    'battlefield': any('CREATURE' in card.get('cardTypes', [])
                                       for p in view['players'] for card in p['battlefield'].values()),
                    'attackers': kind == 'SELECT' and 'attackers' in message
                                 and 'specialButton' in prompt['payload'].get('options', {}),
                    'combat': bool(view.get('combat')) and 'attackers' not in message,
                }
                for label, matches in conditions.items():
                    if label in required and matches and label not in captured:
                        save(label, state)
                        captured[label] = True
                if required <= captured.keys():
                    assert len(set(mapping.values())) == count
                    return {'configuration': config, 'createResult': created, 'seatToEnginePlayerId': mapping,
                            'responses': dict(responses), 'lastTurn': view['turn'],
                            'captured': sorted(captured), 'completedGame': False, 'arbitraryGameSetup': False}
                answer = answer_for(state, attacks)
                engine.call('respond', matchId=match, viewerId=seat, command={
                    'requestId': str(uuid.uuid4()), 'promptId': prompt['promptId'],
                    'promptRevision': prompt['revision'], 'answer': answer})
                seen.add(prompt['promptId'])
                responses[kind] += 1
                progressed = True
                if len(seen) > 2000:
                    raise RuntimeError('Fixture response budget exceeded')
            if not progressed:
                time.sleep(.01)
        raise RuntimeError(f'Fixture timeout; missing {required - captured.keys()}')
    finally:
        engine.call('destroy', matchId=match)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--java-home', type=Path, required=True, help='JDK 21 home')
    parser.add_argument('--timeout', type=int, default=180, help='Per-match seconds, maximum 300')
    args = parser.parse_args()
    if not 1 <= args.timeout <= 300:
        parser.error('--timeout must be 1..300')
    java_home = args.java_home.resolve()
    java = java_home / 'bin/java'
    version = subprocess.check_output([str(java), '-version'], stderr=subprocess.STDOUT, text=True)
    if 'version "21' not in version:
        parser.error('JDK 21 is required')
    for directory in (BUILD, EVIDENCE, OUTPUT):
        directory.mkdir(parents=True, exist_ok=True)
    # Keep upstream logging/cache output inside the permitted ignored directory.
    os.chdir(BUILD)
    cp = (ROOT / 'build/runtime-classpath.txt').read_text().strip()
    sources = sorted((ROOT / 'engine/core/src/main/java').rglob('*.java'))
    sources += sorted((ROOT / 'engine/xmage/src/main/java').rglob('*.java'))
    source_hashes = {str(p.relative_to(REPO)): sha(p) for p in sources}
    classes = BUILD / 'classes'
    classes.mkdir(exist_ok=True)
    compile_command = [str(java_home / 'bin/javac'), '-J-Xmx384m', '--release', '17',
                       '-cp', cp, '-d', str(classes), *map(str, sources)]
    subprocess.run(compile_command, check=True)
    command = [str(java), '-Xmx512m', '-Djava.awt.headless=true', '-cp', f'{classes}{os.pathsep}{cp}',
               'io.magicmobile.xmage.EngineCli']
    fixtures = {}
    with EngineProcess(timeout=60, diagnostics=EVIDENCE / 'jvm-stderr.log', command=command) as engine:
        capabilities = engine.call('capabilities')
        assert capabilities['engine'] == 'xmage' and capabilities['execution'] == 'jvm-integration'
        upstream = git('rev-parse', 'HEAD', cwd=ROOT / '.upstream/mage')
        assert capabilities['upstream'] == upstream
        matches = [capture_match(engine, count, args.timeout, fixtures) for count in (2, 4)]
        engine.call('shutdown')
    assert source_hashes == {str(p.relative_to(REPO)): sha(p) for p in sources}, 'Sources changed during export; rerun'
    for filename, state in fixtures.items():
        match = next(m for m in matches if m['createResult']['matchId'] == state['matchId'])
        mapping = match['seatToEnginePlayerId']
        snapshot = state['snapshot']
        view = snapshot['gameView']
        assert snapshot['schema'] == 'xmage-gameview-v1'
        assert snapshot['enginePlayerId'] == mapping[state['viewerId']]
        assert set(mapping.values()) == {p['playerId'] for p in view['players']}
        if state['prompt']:
            uuid.UUID(state['prompt']['promptId'])
            assert isinstance(state['prompt']['revision'], int)
        write_json(OUTPUT / filename, state)
    manifest = {'formatVersion': 1, 'scope': 'real-XMage-JVM-poll-transport-and-projection',
                'generatedAtUTC': datetime.datetime.now(datetime.timezone.utc).isoformat(),
                'nativeRuntimeValidated': False, 'iOSRuntimeValidated': False,
                'capabilities': capabilities, 'repositoryCommit': git('rev-parse', 'HEAD'),
                'sourceSHA256': source_hashes, 'exporterSHA256': sha(Path(__file__).resolve()),
                'compiledClassSHA256': {str(p.relative_to(classes)): sha(p) for p in sorted(classes.rglob('*.class'))},
                'javaVersion': version.strip(), 'jvmCommand': command,
                'matches': matches, 'fixtures': [
                    {'file': name, 'sha256': sha(OUTPUT / name), 'bytes': (OUTPUT / name).stat().st_size,
                     'matchId': state['matchId'], 'viewerId': state['viewerId'],
                     'promptKind': state['prompt']['kind'] if state['prompt'] else None,
                     'revision': state['revision']} for name, state in sorted(fixtures.items())]}
    write_json(OUTPUT / 'manifest.json', manifest)
    write_json(EVIDENCE / 'export-result.json', {'result': 'passed', 'fixtures': len(fixtures),
               'totalPollBytes': sum((OUTPUT / name).stat().st_size for name in fixtures),
               'engine': capabilities['engine'], 'execution': capabilities['execution'],
               'manifest': str(OUTPUT / 'manifest.json')})
    print((EVIDENCE / 'export-result.json').read_text(), end='')


if __name__ == '__main__':
    main()
