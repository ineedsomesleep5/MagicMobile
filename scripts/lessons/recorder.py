"""Records a lesson from the real XMage engine on the JVM (docs/LESSONS_TUTORIAL.md).

A lesson script stages a board with XMage's own test cheat (engine/tools/LessonCli.java), then plays a
fixed line for every seat. The recorder keeps the learner's seat view after each change, and the
learner's own answers become the moves the lesson player waits for. Nothing here ships in an app.
"""
from __future__ import annotations
import json, os, sys, uuid
from pathlib import Path

PREFERRED_SETS = ['M20', 'M19', 'M21', 'M10', 'M11', 'M12', 'M13', 'M14', 'M15', 'ORI', '10E', '9ED', 'DOM', 'RIX', 'CHK']
DEBUG = bool(os.environ.get('LESSON_DEBUG'))
PASS = {'kind': 'boolean', 'value': True}


class Catalogue:
    def __init__(self, path: Path):
        self.rows: dict[str, list[dict]] = {}
        for line in path.read_text().splitlines():
            if line.strip():
                row = json.loads(line); self.rows.setdefault(row['name'].casefold(), []).append(row)

    def row(self, name: str) -> dict:
        choices = self.rows.get(name.casefold())
        if not choices: raise KeyError('Not in the engine catalogue: ' + name)
        def rank(c):
            preferred = PREFERRED_SETS.index(c['setCode']) if c['setCode'] in PREFERRED_SETS else len(PREFERRED_SETS)
            return (preferred, c['setCode'], c['collectorNumber'], c['className'])
        c = min(choices, key=rank)
        return {'name': c['name'], 'setCode': c['setCode'], 'collectorNumber': c['collectorNumber']}

    def deck(self, commander: str, basic: str) -> dict:
        """A legal 100-card deck: the commander and 99 of one basic land."""
        return {'name': commander, 'commanders': [{'count': 1, **self.row(commander)}],
                'main': [{'count': 99, **self.row(basic)}]}


class Step:
    """One scripted decision for a seat. `answers` yields answers for consecutive prompts of this step."""
    def __init__(self, seat, kind, coach=None, **args):
        self.seat, self.kind, self.coach, self.args = seat, kind, coach, args


class Recorder:
    def __init__(self, engine, catalogue: Catalogue, lesson: dict):
        self.engine, self.catalogue, self.lesson = engine, catalogue, lesson
        self.frames: list[dict] = []
        self.steps: list[Step] = []
        self.revision = 0
        self.names: dict[str, str] = {}

    # ---- setup -------------------------------------------------------------------------------
    def start(self, seats: list[dict], first: str, stage: dict, seed: int = 1):
        """seats: [{seatId, name, commander, basic}]; the first seat is the learner."""
        self.viewer = seats[0]['seatId']; self.created_seats = seats
        config = {'seed': seed, 'seats': [{'seatId': s['seatId'], 'name': s['name'], 'controller': 'human',
                                           'deck': self.catalogue.deck(s['commander'], s['basic'])} for s in seats]}
        self.capabilities = self.engine.call('capabilities')
        created = self.engine.call('create', configuration=config)
        self.match, self.seats = created['matchId'], created['seats']
        self.created = created
        # Who goes first, keep every opening hand, then stage at the first priority question.
        while True:
            seat, poll = self.next_prompt()
            prompt = poll['prompt']; payload = prompt['payload']
            if prompt['kind'] == 'PICK_TARGET' and 'starting player' in payload['message'].lower():
                self.answer(seat, prompt, {'kind': 'uuid', 'value': self.player_id(first)})
            elif prompt['kind'] == 'ASK' and 'mulligan' in payload['message'].lower():
                self.answer(seat, prompt, {'kind': 'boolean', 'value': False})
            elif prompt['kind'] == 'SELECT' and payload.get('selectMode') == 'priority':
                break
            else:
                raise RuntimeError(('Unexpected setup question', prompt))
        rows = {seat: {key: ([self.card_row(card) for card in value] if key in ('hand', 'library', 'graveyard') else
                             [self.battlefield_row(card) for card in value] if key == 'battlefield' else value)
                       for key, value in spec.items()} for seat, spec in stage.items()}
        staged = self.engine.call('lessonStage', matchId=self.match, seats=rows)['staged']
        for rows in staged.values():
            for row in rows: self.names.setdefault(row['id'], row['name'])
        self.capture(force=True)

    def card_row(self, name):
        return self.catalogue.row(name)

    def battlefield_row(self, card):
        if isinstance(card, str): return {'card': self.catalogue.row(card)}
        return {**card, 'card': self.catalogue.row(card['card'])}

    # ---- engine ------------------------------------------------------------------------------
    def poll(self, seat, after=0):
        return self.engine.call('poll', matchId=self.match, viewerId=seat, after=after)

    def next_prompt(self):
        """The seat with an open question, or None when the game ended."""
        for _ in range(400):
            for seat in self.seats:
                poll = self.poll(seat)
                if poll['phase'] == 'failed': raise RuntimeError(poll['failure'])
                if poll['phase'] == 'ended': return None, poll
                prompt = poll.get('prompt')
                if prompt and not prompt['submitted']: return seat, poll
            import time; time.sleep(0.05)
        raise RuntimeError('No seat was asked anything')

    def answer(self, seat, prompt, answer):
        self.engine.call('respond', matchId=self.match, viewerId=seat, command={
            'requestId': str(uuid.uuid4()), 'promptId': prompt['promptId'], 'promptRevision': prompt['revision'],
            'answer': answer})

    def player_id(self, seat):
        snapshot = self.poll(self.viewer)['snapshot']
        name = next(s['name'] for s in self.created_seats if s['seatId'] == seat)
        return next(p['playerId'] for p in snapshot['gameView']['players'] if p['name'] == name)

    # ---- frames ------------------------------------------------------------------------------
    def capture(self, force=False):
        """Keeps the learner's view when it changed since the last frame."""
        poll = self.poll(self.viewer, after=self.revision)
        last = self.frames[-1]['poll'] if self.frames else None
        if not force and last is not None and last['snapshot'] == poll['snapshot'] and last['phase'] == poll['phase'] \
                and (last.get('prompt') or {}).get('promptId') == (poll.get('prompt') or {}).get('promptId'):
            return None
        self.revision = poll['revision']
        frame = {'poll': poll}
        self.frames.append(frame)
        return frame

    # ---- the scripted game -------------------------------------------------------------------
    def play(self, steps: list[Step], until_end=True):
        """Answers every question: the next step when it applies to the asking seat, else the default."""
        self.steps = list(steps)
        while True:
            seat, poll = self.next_prompt()
            if seat is None:
                self.capture(); return
            prompt = poll['prompt']
            step = self.steps[0] if self.steps else None
            view = poll['snapshot']['gameView']
            if step is not None and step.kind == 'end' and seat == self.viewer and prompt['kind'] == 'SELECT' \
                    and not view.get('stack') and step.args.get('step') in (None, view['step']):
                self.capture(); self.frames[-1]['complete'] = True; self.frames[-1].update(coach_of(step.coach))
                self.steps.pop(0); return
            if step is not None and step.kind == 'note' and seat == self.viewer and prompt['kind'] == 'SELECT' \
                    and step.args.get('step') in (None, poll['snapshot']['gameView']['step']):
                # A coach card the learner reads before going on: it sits on the frame with no move.
                frame = self.capture(force=True); frame['note'] = True; frame['poll'] = strip_prompt(frame['poll'])
                frame.update(coach_of(step.coach)); self.steps.pop(0); continue
            answer, done, expected = None, False, False
            while step is not None and step.seat == seat and step.kind not in ('note', 'end'):
                answer, done = self.apply(step, poll)
                if answer != 'next': break
                # That step finished before this question: try the next one on it.
                self.steps.pop(0); step = self.steps[0] if self.steps else None; answer, done = None, False
            expected = answer is not None
            if answer is None:
                answer = default_answer(prompt)
            if seat == self.viewer:
                frame = self.capture(force=True)
                if expected:
                    frame['expect'] = answer
                    if step.coach and not step.args.get('_coached'):
                        frame.update(coach_of(step.coach)); step.args['_coached'] = True
                    elif step.args.get('then'):
                        frame.update(coach_of(step.args['then'].pop(0)) if step.args['then'] else {})
                else:
                    frame['auto'] = answer
                    frame['poll'] = strip_prompt(frame['poll'])
            if DEBUG:
                v = poll['snapshot']['gameView']
                print(f"  {seat:5} t{v['turn']} {v['step']:22} {prompt['kind']:10} {prompt['payload'].get('selectMode') or ''} "
                      f"{(prompt['payload'].get('message') or '')[:40]!r} -> {answer} {'[' + step.kind + ']' if expected else ''}", file=sys.stderr)
            self.answer(seat, prompt, answer)
            if done: self.steps.pop(0)
            if seat != self.viewer: self.capture()

    def apply(self, step: Step, poll):
        """(answer, finished) for this step at this question, or (None, False) when it doesn't apply."""
        prompt = poll['prompt']; payload = prompt['payload']; view = poll['snapshot']['gameView']
        mode = payload.get('selectMode'); kind = prompt['kind']; a = step.args
        state = a.setdefault('_state', {})
        if step.kind in ('play', 'cast'):
            if kind == 'SELECT' and mode == 'priority' and not state.get('cast'):
                if a.get('step') and view['step'] != a['step']: return None, False
                card = find_playable(poll['snapshot'], a['card'], 'basicPlayAbilities' if step.kind == 'play' else 'basicCastAbilities')
                if card is None: return None, False
                state['cast'] = card
                return {'kind': 'uuid', 'value': card}, step.kind == 'play'
            if state.get('cast') and kind == 'PICK_TARGET':
                target = self.target(view, payload, a['targets'][state.setdefault('target', 0)])
                state['target'] += 1
                return {'kind': 'uuid', 'value': target}, False
            if state.get('cast') and kind == 'PLAY_MANA':
                land = untapped_source(view, poll['snapshot']['enginePlayerId'], a.get('pay'))
                return {'kind': 'uuid', 'value': land}, False
            if state.get('cast'):
                # The spell is on the stack (or resolved): this question belongs to the next step.
                return 'next', False
            return None, False
        if step.kind == 'pass':
            mine = view['activePlayerId'] == poll['snapshot']['enginePlayerId']
            if kind == 'SELECT' and mode == 'priority' and (not a.get('step') or view['step'] == a['step']) \
                    and mine == (a.get('turn', 'mine') == 'mine') and (a.get('stack') is None or bool(view.get('stack')) == a['stack']):
                return PASS, True
            return None, False
        if step.kind == 'attack':
            if kind == 'SELECT' and mode == 'attackers':
                todo = state.setdefault('todo', list(a['cards']))
                if todo:
                    card = find_named(view, poll['snapshot']['enginePlayerId'], todo.pop(0), 'battlefield')
                    state['defender'] = a.get('defender')
                    return {'kind': 'uuid', 'value': card}, False
                return {'kind': 'boolean', 'value': True}, True
            if kind == 'PICK_TARGET' and state.get('defender'):
                return {'kind': 'uuid', 'value': self.target(view, payload, state['defender'])}, False
            return None, False
        if step.kind == 'block':
            if kind == 'SELECT' and mode == 'blockers':
                if not state.get('blocked'):
                    state['blocked'] = True
                    return {'kind': 'uuid', 'value': find_named(view, poll['snapshot']['enginePlayerId'], a['blocker'], 'battlefield')}, False
                return {'kind': 'boolean', 'value': True}, True
            if kind == 'PICK_TARGET' and state.get('blocked'):
                return {'kind': 'uuid', 'value': self.target(view, payload, a['attacker'])}, False
            return None, False
        if step.kind == 'yes':
            if kind == 'ASK': return {'kind': 'boolean', 'value': True}, True
            return None, False
        raise ValueError(step.kind)

    def target(self, view, payload, name):
        candidates = set(payload.get('candidates') or [])
        for player in view['players']:
            if player['name'] == name and (not candidates or player['playerId'] in candidates): return player['playerId']
            for card in player['battlefield'].values():
                if card['name'] == name and (not candidates or card['id'] in candidates): return card['id']
        for card in view.get('stack', {}).values():
            if card['name'] == name: return card['id']
        raise RuntimeError(('No target named', name, payload))

    # ---- output ------------------------------------------------------------------------------
    def write(self, path: Path, focus: str | None = None):
        for frame in self.frames:
            if focus:
                # The board's top shows the first opponent in the list: the one the lesson is about.
                players = frame['poll']['snapshot']['gameView']['players']
                players.sort(key=lambda p: (p['name'] != 'You', p['name'] != focus))
            # Only a frame waiting on the learner's move keeps its question open.
            if 'expect' not in frame and frame['poll'].get('prompt'): frame['poll'] = strip_prompt(frame['poll'])
        lesson = {'format': 'magicmobile-lesson', 'version': 1, **self.lesson,
                  'capabilities': {**self.capabilities, 'answerActions': [], 'saveResume': False,
                                   'checkpointOnDemand': False, 'gameRecord': 0, 'aiEnabled': False},
                  'create': {'matchId': self.match, 'seats': [self.viewer], 'engine': self.created['engine']},
                  'viewer': self.viewer, 'frames': self.frames}
        path.write_text(json.dumps(lesson, separators=(',', ':'), ensure_ascii=False))


def coach_of(coach):
    if coach is None: return {}
    if isinstance(coach, str): return {'coach': {'text': coach}}
    return {'coach': coach}


def strip_prompt(poll):
    """The learner's view with no question open and nothing glowing: the lesson player moves on by itself."""
    poll = json.loads(json.dumps(poll)); poll['prompt'] = None
    poll['snapshot']['gameView']['canPlayObjects'] = None
    return poll


def default_answer(prompt):
    kind, mode = prompt['kind'], prompt['payload'].get('selectMode')
    if kind == 'SELECT' and mode in ('attackers', 'blockers'): return {'kind': 'boolean', 'value': True}
    if kind == 'SELECT': return PASS
    if kind == 'ASK': return {'kind': 'boolean', 'value': False}
    raise RuntimeError(('No default answer for', prompt))


def find_playable(snapshot, name, ability):
    """A card in hand, or a commander in the command zone, that can be played now."""
    view = snapshot['gameView']
    names = {card_id: card['name'] for card_id, card in (view.get('myHand') or {}).items()}
    names.update({card_id: row['name'] for card_id, row in (snapshot.get('commanders') or {}).items()})
    for card_id, abilities in ((view.get('canPlayObjects') or {}).get('objects') or {}).items():
        if names.get(card_id) == name and abilities.get(ability): return card_id
    return None


def find_named(view, player_id, name, zone):
    player = next(p for p in view['players'] if p['playerId'] == player_id)
    for card in player[zone].values():
        if card['name'] == name: return card['id']
    raise RuntimeError(('No', name, 'in', zone))


def untapped_source(view, player_id, preferred=None):
    player = next(p for p in view['players'] if p['playerId'] == player_id)
    lands = sorted((c for c in player['battlefield'].values() if not c.get('tapped') and 'LAND' in c.get('cardTypes', [])),
                   key=lambda c: (preferred is not None and c['name'] != preferred, c['id']))
    if not lands: raise RuntimeError('No untapped land to pay with')
    return lands[0]['id']
