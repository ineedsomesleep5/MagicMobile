"""Records the target-question fixtures (apps/ios/MagicMobileTests/Fixtures/OnDevice/target-*.json) from the real engine.

Each scenario stages a board with the lesson recorder's XMage test cheat (engine/tools/LessonCli.java), plays to a target
question whose choices aren't permanents on the table as shown (abilities or spells on the stack, graveyard cards, another
opponent's creatures), and saves the viewer's poll there. ArenaBoardModelTests (iOS), ArenaBoardModelTest (Android) and
test/stackTargets.test.ts (web) read them; regenerate the parity goldens after re-recording
(MAGICMOBILE_WRITE_PARITY_GOLDENS=1 swift test --package-path apps/ios --filter ParityGoldenTests).

  python3 scripts/lessons/capture_targets.py --engine <checkout>/packages/ondevice-engine [scenario ...]
"""
import json, os, subprocess, sys, tempfile
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
args = sys.argv[1:]
if len(args) < 2 or args[0] != '--engine': sys.exit(__doc__)
ENG = Path(args[1])
sys.path.insert(0, str(REPO / 'packages/ondevice-engine/scripts'))
sys.path.insert(0, str(REPO / 'scripts/lessons'))
from jvm_client import EngineProcess  # noqa
from recorder import Catalogue, Recorder, PASS  # noqa

OUT = REPO / 'apps/ios/MagicMobileTests/Fixtures/OnDevice'
WANT = args[2:]
java = '/opt/homebrew/opt/openjdk@17/bin/java'
classpath = (ENG / 'build/runtime-classpath.txt').read_text().strip()
catalogue = Catalogue(ENG / 'build/generated/catalogue.jsonl')
tools = Path(tempfile.mkdtemp(prefix='probe-cli-'))
subprocess.run([str(Path(java).with_name('javac')), '--release', '17', '-cp', classpath, '-d', str(tools),
                str(REPO / 'packages/ondevice-engine/engine/tools/LessonCli.java')], check=True, stdout=subprocess.DEVNULL)
command = [java, '-Xmx768m', '-Djava.awt.headless=true', '-cp', f'{classpath}:{tools}', 'io.magicmobile.xmage.LessonCli']

YOU = {'seatId': 'you', 'name': 'You', 'commander': 'Zur the Enchanter', 'basic': 'Island'}
ROOK = {'seatId': 'rook', 'name': 'Rook', 'commander': 'Isamaru, Hound of Konda', 'basic': 'Plains'}
BRYN = {'seatId': 'bryn', 'name': 'Bryn', 'commander': 'Isamaru, Hound of Konda', 'basic': 'Plains'}
WREN = {'seatId': 'wren', 'name': 'Wren', 'commander': 'Isamaru, Hound of Konda', 'basic': 'Plains'}

SCENARIOS = {
    # Gogo copying Zur's attack trigger: two abilities on the stack to choose from.
    'stack-ability': dict(seats=[YOU, ROOK], stage={
        'you': {'battlefield': ['Zur the Enchanter', 'Gogo, Master of Mimicry'] + ['Island'] * 5}, 'rook': {'battlefield': ['Plains']}},
        plan=['attack:Zur the Enchanter', 'activate:Gogo, Master of Mimicry']),
    # Counterspell with two of your spells on the stack.
    'stack-spell': dict(seats=[YOU, ROOK], stage={
        'you': {'battlefield': ['Mountain'] * 3 + ['Island'] * 2, 'hand': ['Lightning Bolt', 'Shock', 'Counterspell']},
        'rook': {'battlefield': ['Plains']}},
        plan=['cast:Lightning Bolt', 'cast:Shock', 'cast:Counterspell']),
    # A creature card in your graveyard.
    'graveyard': dict(seats=[YOU, ROOK], stage={
        'you': {'battlefield': ['Swamp'] * 2, 'hand': ['Raise Dead'], 'graveyard': ['Grizzly Bears', 'Hill Giant']},
        'rook': {'battlefield': ['Plains']}},
        plan=['cast:Raise Dead']),
    # Any card in any graveyard (an ability on the table).
    'any-graveyard': dict(seats=[YOU, ROOK], stage={
        'you': {'battlefield': ['Scavenging Ooze', 'Forest', 'Forest'], 'graveyard': ['Grizzly Bears']},
        'rook': {'battlefield': ['Plains'], 'graveyard': ['Hill Giant', 'Shock']}},
        plan=['activate:Scavenging Ooze']),
    # Four players: creatures on two opponents' sides, only one shown at a time.
    'four-player': dict(seats=[YOU, ROOK, BRYN, WREN], stage={
        'you': {'battlefield': ['Mountain'] * 2, 'hand': ['Shock']},
        'rook': {'battlefield': ['Grizzly Bears']}, 'bryn': {'battlefield': ['Hill Giant']}, 'wren': {'battlefield': ['Plains']}},
        plan=['cast:Shock']),
    # Four players: only creatures can be chosen, all on opponents the board isn't showing.
    'four-player-creature': dict(seats=[YOU, ROOK, BRYN, WREN], stage={
        'you': {'battlefield': ['Swamp'] * 2, 'hand': ['Doom Blade']},
        'rook': {'battlefield': ['Grizzly Bears']}, 'bryn': {'battlefield': ['Hill Giant']}, 'wren': {'battlefield': ['Plains']}},
        plan=['cast:Doom Blade']),
}


def run(name, spec):
    with EngineProcess(timeout=60, command=command) as engine:
        r = Recorder(engine, catalogue, {'id': name, 'title': name})
        r.start(spec['seats'], 'you', spec['stage'])
        plan = list(spec['plan'])
        acting = None
        for _ in range(120):
            seat, poll = r.next_prompt()
            if seat is None: break
            prompt = poll['prompt']; payload = prompt['payload']; kind = prompt['kind']; mode = payload.get('selectMode')
            view = poll['snapshot']['gameView']
            if seat != 'you':
                r.answer(seat, prompt, PASS if kind == 'SELECT' else {'kind': 'boolean', 'value': False}); continue
            me = next(p for p in view['players'] if p['playerId'] == poll['snapshot']['enginePlayerId'])
            def mine(card):
                return next((c['id'] for c in me['battlefield'].values() if c['name'] == card), None)
            def in_hand(card):
                return next((i for i, c in (view.get('myHand') or {}).items() if c['name'] == card), None)
            step = plan[0] if plan else ''
            verb, _, card = step.partition(':')
            if kind == 'SELECT' and mode == 'attackers':
                if verb == 'attack': plan.pop(0); r.answer(seat, prompt, {'kind': 'uuid', 'value': mine(card)})
                else: r.answer(seat, prompt, {'kind': 'boolean', 'value': True})
                continue
            if kind == 'SELECT' and mode == 'priority':
                playable = (view.get('canPlayObjects') or {}).get('objects') or {}
                target = (in_hand(card) if verb == 'cast' else mine(card)) if verb in ('cast', 'activate') else None
                if target and target in playable:
                    plan.pop(0); acting = card; r.answer(seat, prompt, {'kind': 'uuid', 'value': target}); continue
                if not plan:
                    break
                r.answer(seat, prompt, PASS); continue
            if kind == 'CHOOSE_ABILITY':
                r.answer(seat, prompt, {'kind': 'uuid', 'value': payload['abilities'][0]['id']}); continue
            if kind == 'AMOUNT':
                r.answer(seat, prompt, {'kind': 'integer', 'value': max(1, prompt.get('minimum') or 0)}); continue
            if kind == 'PLAY_MANA':
                land = next(c['id'] for c in me['battlefield'].values() if 'LAND' in c.get('cardTypes', []) and not c.get('tapped'))
                r.answer(seat, prompt, {'kind': 'uuid', 'value': land}); continue
            if kind == 'ASK':
                r.answer(seat, prompt, {'kind': 'boolean', 'value': False}); continue
            if kind == 'PICK_TARGET':
                candidates = payload.get('candidates') or []
                players = {p['playerId'] for p in view['players']}
                if acting == plan_last(spec):
                    # The question the scenario is about: the last planned card's target.
                    path = OUT / f"target-{name}.json"
                    path.write_text(json.dumps(poll, separators=(',', ':')))
                    zone = (payload.get('options') or {}).get('targetZone')
                    print(f"{name}: {path.name}: zone={zone} candidates={len(candidates)} message={payload.get('message')!r}")
                    break
                # An earlier spell's target: the first player who isn't you, else the first candidate.
                pick = next((c for c in candidates if c in players and c != me['playerId']), candidates[0])
                r.answer(seat, prompt, {'kind': 'uuid', 'value': pick}); continue
            print(name, 'unhandled', kind, json.dumps(payload)[:300]); break
        else:
            print(name, 'ran out of steps')


def plan_last(spec):
    return spec['plan'][-1].partition(':')[2]


for name, spec in SCENARIOS.items():
    if WANT and name not in WANT: continue
    try:
        run(name, spec)
    except Exception as error:  # keep going with the other boards
        print(name, 'failed:', repr(error)[:400])
