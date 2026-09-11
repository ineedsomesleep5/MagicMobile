#!/usr/bin/env python3
"""REAL XMage boot-to-first-prompt gate. Never counts as a completed game or iOS proof."""
from __future__ import annotations
import argparse,json,queue,subprocess,threading,time
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]

def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('configuration',type=Path);p.add_argument('--timeout',type=float,default=90)
    a=p.parse_args();cpfile=ROOT/'build/runtime-classpath.txt'
    if not cpfile.exists():raise SystemExit('Run scripts/build_jvm.sh successfully first')
    config=json.loads(a.configuration.read_text())
    proc=subprocess.Popen(['java','-Xmx3g','-cp',cpfile.read_text().strip(),'io.magicmobile.xmage.EngineCli'],
                          stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True,bufsize=1)
    replies=queue.Queue();deadline=time.monotonic()+a.timeout
    def read():
        for line in proc.stdout:
            try:
                value=json.loads(line)
                if isinstance(value,dict) and value.get('protocol')==1 and 'ok' in value:replies.put(value)
            except (ValueError,TypeError):pass
        replies.put(None)
    # Drain diagnostic stderr, but don't publish hands/card-bearing logs into checked-in evidence.
    def drain():
        for _ in proc.stderr:pass
    threading.Thread(target=read,daemon=True).start();threading.Thread(target=drain,daemon=True).start()
    def call(op,**fields):
        proc.stdin.write(json.dumps({'protocol':1,'op':op,**fields})+'\n');proc.stdin.flush()
        timeout=max(0.001,deadline-time.monotonic())
        try:reply=replies.get(timeout=timeout)
        except queue.Empty:raise RuntimeError('Real engine timed out')
        if reply is None:raise RuntimeError('Real engine process exited')
        if not reply.get('ok'):raise RuntimeError(str(reply.get('error')))
        return reply['result']
    try:
        cap=call('capabilities')
        if cap.get('engine')!='xmage' or cap.get('execution')!='jvm-integration':raise RuntimeError('Not the real JVM integration backend')
        created=call('create',configuration=config);seen=[]
        while time.monotonic()<deadline and not seen:
            for seat in created['seats']:
                state=call('poll',matchId=created['matchId'],viewerId=seat,after=0)
                if state['phase']=='failed':raise RuntimeError(str(state['failure']))
                if state.get('prompt'):seen.append({'seat':seat,'kind':state['prompt']['kind']})
            if not seen:time.sleep(0.05)
        if not seen:raise RuntimeError('Engine did not produce a prompt')
        call('destroy',matchId=created['matchId'])
        report={'result':'passed','scope':'real-XMage-JVM-boot-to-first-prompt','completedGame':False,'iOS':False,
                'upstream':cap['upstream'],'catalogueHash':cap['catalogueHash'],'prompts':seen}
        (ROOT/'evidence/real-jvm-first-prompt.json').write_text(json.dumps(report,indent=2)+'\n')
        print(json.dumps(report,indent=2))
    finally:
        proc.terminate()
        try:proc.wait(timeout=3)
        except subprocess.TimeoutExpired:proc.kill();proc.wait()
        for f in (proc.stdin,proc.stdout,proc.stderr):f.close()
if __name__=='__main__':main()
