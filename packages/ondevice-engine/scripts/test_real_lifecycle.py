#!/usr/bin/env python3
"""Regression checks against the real engine service, including waiting-thread cancellation."""
import json,time,uuid
from jvm_client import EngineProcess, ROOT

def code(reply,expected):
    assert not reply['ok'] and reply['error']['code']==expected,reply

def main():
    config=json.loads((ROOT/'build/match.json').read_text());checks=0
    with EngineProcess(timeout=90) as engine:
        for cycle in range(3):
            created=engine.call('create',configuration=config);match=created['matchId'];seats=created['seats']
            code(engine.request('create',configuration=config),'match_limit');checks+=1
            code(engine.request('poll',matchId=match,viewerId='not-a-seat',after=0),'unauthorized_seat');checks+=1
            deadline=time.monotonic()+30;prompt=None
            while time.monotonic()<deadline:
                for seat in seats:
                    state=engine.call('poll',matchId=match,viewerId=seat,after=0)
                    assert state['phase']!='failed',state['failure']
                    if state.get('prompt'):prompt=state['prompt'];owner=seat;break
                if prompt:break
                time.sleep(.01)
            assert prompt,'no real prompt'
            other=next(s for s in seats if s!=owner)
            assert engine.call('poll',matchId=match,viewerId=other,after=0)['prompt'] is None;checks+=1
            command={'requestId':str(uuid.uuid4()),'promptId':prompt['promptId'],
                'promptRevision':prompt['revision'],'answer':{'kind':'uuid','value':prompt['payload']['candidates'][0]}}
            code(engine.request('respond',matchId=match,viewerId=other,command=command),'stale_prompt');checks+=1
            receipt=engine.call('respond',matchId=match,viewerId=owner,command=command)
            assert engine.call('respond',matchId=match,viewerId=owner,command=command)==receipt;checks+=1
            changed=json.loads(json.dumps(command));changed['answer']['value']=str(uuid.uuid4())
            code(engine.request('respond',matchId=match,viewerId=owner,command=changed),'request_id_reused');checks+=1
            # Destroy as the worker advances to its next real choice, then recreate in this same engine.
            started=time.monotonic();engine.call('destroy',matchId=match)
            assert time.monotonic()-started<5;checks+=1
            code(engine.request('poll',matchId=match,viewerId=owner,after=0),'unknown_match');checks+=1
    report={'result':'passed','scope':'real-XMage-JVM-lifecycle','cycles':3,'assertions':checks,
        'waitingCancellation':True,'cancellationDuringComplexEffect':False,'iOS':False}
    (ROOT/'evidence/real-jvm-lifecycle.json').write_text(json.dumps(report,indent=2)+'\n');print(json.dumps(report,indent=2))

if __name__=='__main__':main()
