#!/usr/bin/env python3
"""Combine 2–4 resolved deck JSON files into an explicit human-seat match configuration."""
import argparse,json
from pathlib import Path
p=argparse.ArgumentParser(description=__doc__);p.add_argument('decks',nargs='+',type=Path);p.add_argument('--output',type=Path,required=True)
a=p.parse_args()
if not 2<=len(a.decks)<=4:p.error('Provide 2–4 deck files')
seats=[{'seatId':f'player-{i+1}','name':f'Player {i+1}','controller':'human','deck':json.loads(path.read_text())} for i,path in enumerate(a.decks)]
a.output.write_text(json.dumps({'seats':seats},ensure_ascii=False,indent=2)+'\n')
