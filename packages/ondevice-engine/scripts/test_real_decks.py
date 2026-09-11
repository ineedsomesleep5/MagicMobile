#!/usr/bin/env python3
"""Exercise the pinned upstream Commander validator and trusted-printing boundary."""
import copy,json
from jvm_client import EngineProcess, ROOT

def main():
    base=json.loads((ROOT/'build/match.json').read_text());cases=[]
    def candidate(label,expected='invalid_deck'):
        configuration=copy.deepcopy(base);cases.append((label,expected,configuration))
        return configuration['seats'][0]['deck']
    candidate('99-card deck')['main'][0]['count']=98
    candidate('101-card deck')['main'][0]['count']=100
    d=candidate('off-color basic land');d['main'][0]['count']=98
    d['main'].append(copy.deepcopy(base['seats'][1]['deck']['main'][0]));d['main'][1]['count']=1
    d=candidate('duplicate nonbasic commander card');d['main'][0]['count']=98
    d['main'].append(copy.deepcopy(d['commanders'][0]))
    d=candidate('nonlegendary commander');d['commanders']=[dict(d['main'][0],count=1)]
    candidate('untrusted printing name','printing_name_mismatch')['main'][0]['name']='Black Lotus'
    candidate('unknown printing','unknown_printing')['main'][0]['collectorNumber']='NO-SUCH-PRINTING'
    with EngineProcess(timeout=120) as engine:
        for label,expected,config in cases:
            result=engine.request('create',configuration=config)
            assert not result['ok'] and result['error']['code']==expected,(label,result)
        # Invalid creates must not reserve the one-game slot or poison future real initialization.
        created=engine.call('create',configuration=base)
        engine.call('destroy',matchId=created['matchId'])
    report={'result':'passed','scope':'pinned-XMage-Commander-validation','rejectedCases':[c[0] for c in cases],
        'validCreateAfterRejections':True,'iOS':False,'currentExternalBanlistVerified':False}
    (ROOT/'evidence/real-jvm-deck-validation.json').write_text(json.dumps(report,indent=2)+'\n')
    print(json.dumps(report,indent=2))

if __name__=='__main__':main()
