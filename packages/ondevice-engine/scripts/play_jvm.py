#!/usr/bin/env python3
"""Drive real human-seat Commander fixtures over the production protocol, not an AI backend."""
import argparse, collections, json, time, uuid
from pathlib import Path
from jvm_client import EngineProcess, ROOT

def play(config, timeout=180, mulligans=0, require_tokens=False):
    counts=collections.Counter(); attacks=set(); seen=set(); max_turn=0; private_ids={}; max_tokens=0
    with EngineProcess(timeout=120,diagnostics=ROOT/'build/gameplay-private.log') as engine:
        created=engine.call('create',configuration=config); match=created['matchId']
        deadline=time.monotonic()+timeout
        while time.monotonic()<deadline:
            progressed=False
            for seat in created['seats']:
                state=engine.call('poll',matchId=match,viewerId=seat,after=0)
                if state['phase']=='failed':raise RuntimeError(state['failure'])
                if state.get('snapshot'):
                    snapshot=state['snapshot']; view=snapshot['gameView']
                    token_count=sum(1 for player in view['players'] for card in player['battlefield'].values() if card.get('isToken'))
                    max_tokens=max(max_tokens,token_count)
                    private_ids[seat]=set(view.get('myHand',{}))
                    serialized=json.dumps(snapshot)
                    for other,ids in private_ids.items():
                        if other!=seat and any(card in serialized for card in ids):
                            # A formerly private card may have become public since that seat's last poll.
                            fresh=engine.call('poll',matchId=match,viewerId=other,after=0)
                            current=set(fresh['snapshot']['gameView'].get('myHand',{}))
                            if any(card in serialized for card in current):
                                raise AssertionError('Opponent hand identifier leaked across seat views')
                    counts['seat-hand-privacy-checks']+=1
                if state['phase']=='ended':
                    players=state['snapshot']['gameView']['players']
                    winners=[x for x in players if x['wins']==1]
                    if len(winners)!=1 or not counts['cast'] or not counts['attack']:
                        raise AssertionError('No real combat winner')
                    if require_tokens and not max_tokens:raise AssertionError('No real token creation observed')
                    result={'result':'passed','scope':'real-XMage-JVM-completed-game',
                        'seats':len(created['seats']),'responses':dict(counts),'turn':max_turn,
                        'completedGame':True,'iOS':False,'maximumTokensOnBattlefield':max_tokens,
                        'players':[{'name':x['name'],'life':x['life'],'wins':x['wins'],'hasLeft':x['hasLeft']} for x in players]}
                    engine.call('destroy',matchId=match)
                    return result
                p=state.get('prompt')
                if not p or p['submitted'] or p['promptId'] in seen:continue
                progressed=True; seen.add(p['promptId'])
                snap=state['snapshot']; view=snap['gameView']; payload=p['payload']
                turn=view.get('turn',0);max_turn=max(max_turn,turn)
                player=next(x for x in view['players'] if x['playerId']==snap['enginePlayerId'])
                kind=p['kind']; message=payload['message']; options=payload.get('options',{})
                answer={'kind':'boolean','value':False}
                if kind=='ASK':
                    if 'mulligan' not in message.lower():raise RuntimeError(('Unhandled ASK',message))
                    if seat==created['seats'][0] and counts['mulligan-taken']<mulligans:
                        answer={'kind':'boolean','value':True};counts['mulligan-taken']+=1
                elif kind=='PICK_TARGET':
                    candidates=payload['candidates']
                    if not candidates:raise RuntimeError(('No target',payload))
                    answer={'kind':'uuid','value':snap['enginePlayerId'] if 'starting player' in message.lower() else candidates[0]}
                elif kind=='SELECT':
                    if 'attackers' in message.lower():
                        key=(seat,turn)
                        if 'specialButton' in options and key not in attacks:
                            answer={'kind':'string','value':'special'}; attacks.add(key);counts['attack']+=1
                    elif 'blockers' not in message.lower():
                        objects=view.get('canPlayObjects',{}).get('objects',{})
                        for card,abilities in objects.items():
                            if abilities.get('basicPlayAbilities'):
                                answer={'kind':'uuid','value':card};counts['land']+=1;break
                        else:
                            for card,abilities in objects.items():
                                if abilities.get('basicCastAbilities'):
                                    answer={'kind':'uuid','value':card};counts['cast']+=1;break
                elif kind=='PLAY_MANA':
                    lands=[x for x in player['battlefield'].values() if not x.get('tapped') and 'LAND' in x.get('cardTypes',[])]
                    if not lands:raise RuntimeError(('No mana source',payload,player))
                    answer={'kind':'uuid','value':lands[0]['id']}; counts['mana-source']+=1
                elif kind in ('CHOOSE_ABILITY','PICK_ABILITY'):
                    answer={'kind':'uuid','value':payload['abilities'][0]['id']}
                else:raise RuntimeError(('Unhandled prompt',p))
                counts[kind]+=1
                if counts[kind]<4: print(json.dumps({'seat':seat,'turn':turn,'kind':kind,'message':message,'answer':answer,'options':options}),flush=True)
                if len(seen)>5000:raise RuntimeError('Response budget exhausted')
                engine.call('respond',matchId=match,viewerId=seat,command={
                    'requestId':str(uuid.uuid4()),'promptId':p['promptId'],'promptRevision':p['revision'],'answer':answer})
            if not progressed:time.sleep(.01)
        raise RuntimeError(('Gameplay deadline',dict(counts),max_turn))

if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('configuration',type=Path);parser.add_argument('--timeout',type=int,default=180)
    parser.add_argument('--report',type=Path,default=ROOT/'evidence/real-jvm-game.json')
    parser.add_argument('--four-seats',action='store_true')
    parser.add_argument('--mulligans',type=int,choices=(0,1,2),default=0)
    parser.add_argument('--require-tokens',action='store_true')
    args=parser.parse_args();config=json.loads(args.configuration.read_text())
    if args.four_seats:
        for i,seat in enumerate(list(config['seats'])):
            copy=json.loads(json.dumps(seat));copy.update(seatId=f'player-{i+3}',name=f'Player {i+3}')
            config['seats'].append(copy)
    report=play(config,args.timeout,args.mulligans,args.require_tokens)
    args.report.write_text(json.dumps(report,indent=2)+'\n')
    print(json.dumps({k:v for k,v in report.items() if k!='finalView'},indent=2))
