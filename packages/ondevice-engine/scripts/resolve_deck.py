#!/usr/bin/env python3
"""Resolve a simple text decklist against the generated, compiled XMage catalogue.
Syntax: `1 Card Name` or `1 Card Name (SET) COLLECTOR`. Commander names are explicit.
No online card lookup, guessed Java class names, or runtime code downloads.
"""
from __future__ import annotations
import argparse, json, re
from collections import defaultdict
from pathlib import Path

ENTRY=re.compile(r'^(\d+)x?\s+(.+?)(?:\s+\(([A-Za-z0-9]+)\)\s+(\S+))?$')

def resolve(text: str, catalogue: list[dict], commanders: list[str], companions: list[str]) -> dict:
    index=defaultdict(list)
    for row in catalogue:index[row['name'].casefold()].append(row)
    commander_keys={n.casefold() for n in commanders};companion_keys={n.casefold() for n in companions}
    if not commander_keys or commander_keys & companion_keys:raise ValueError('Specify distinct commander and companion names')
    result={'name':'Imported Commander deck','main':[],'commanders':[],'companions':[]}
    found=set()
    for line in text.splitlines():
        line=line.strip()
        if not line or line.startswith('#') or line.casefold() in {'deck','commander','commanders','companion','companions'}:continue
        match=ENTRY.fullmatch(line)
        if not match:raise ValueError('Unsupported decklist line: '+line)
        count,name,code,number=match.groups();count=int(count)
        if not 1<=count<=2000:raise ValueError('Invalid count: '+line)
        choices=index.get(name.casefold(),[])
        if code:choices=[c for c in choices if c['setCode'].casefold()==code.casefold() and c['collectorNumber']==number]
        if not choices:raise ValueError('Printing is not in the compiled catalogue: '+line)
        # A repeatable printing selection, not a claim about latest sets or legality.
        selected=min(choices,key=lambda c:(c['setCode'],c['collectorNumber'],c['className']))
        key=name.casefold();section='commanders' if key in commander_keys else 'companions' if key in companion_keys else 'main'
        result[section].append({'count':count,'name':selected['name'],'setCode':selected['setCode'],'collectorNumber':selected['collectorNumber']})
        found.add(key)
    if (commander_keys|companion_keys)-found:raise ValueError('Include your named commander/companion in the text list')
    if not result['main']:raise ValueError('Main deck is empty')
    if not result['companions']:del result['companions']
    return result

def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--catalogue',type=Path,required=True)
    p.add_argument('--input',type=Path,required=True);p.add_argument('--output',type=Path,required=True)
    p.add_argument('--commander',action='append',required=True);p.add_argument('--companion',action='append',default=[])
    a=p.parse_args();rows=[json.loads(line) for line in a.catalogue.read_text().splitlines() if line.strip()]
    deck=resolve(a.input.read_text(),rows,a.commander,a.companion)
    a.output.write_text(json.dumps(deck,ensure_ascii=False,indent=2)+'\n')
    print('Resolved printings. The real XMage validator still must approve the deck.')
if __name__=='__main__':main()
