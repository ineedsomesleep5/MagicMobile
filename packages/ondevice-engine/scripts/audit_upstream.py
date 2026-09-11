#!/usr/bin/env python3
"""Static risk inventory; findings are NOT proof that a type is runtime-reachable."""
import argparse,json,re
from pathlib import Path
PATTERNS={
 'desktop_awt':r'\bjava\.awt\b','desktop_swing':r'\bjavax\.swing\b',
 'reflection':r'Class\.forName|getDeclared(Field|Method)|getConstructor|\.newInstance\(',
 'class_loading':r'ClassLoader|ClassScanner|PluginClassloader',
 'database':r'java\.sql|org\.h2|com\.j256|CardRepository',
 'java_serialization':r'ObjectInputStream|ObjectOutputStream|SerializationUtils',
 'process_launch':r'ProcessBuilder|Runtime\.getRuntime\(\)\.exec',
 'network':r'java\.net|jboss|mage\.remote|HttpServer'}
MODULES=['Mage','Mage.Common','Mage.Sets','Mage.Server.Plugins/Mage.Player.Human',
 'Mage.Server.Plugins/Mage.Deck.Constructed','Mage.Server.Plugins/Mage.Game.CommanderFreeForAll']
def audit(root):
    findings=[]
    for module in MODULES:
        for p in sorted((root/module).rglob('*.java')):
            if '/target/' in str(p):continue
            for line,text in enumerate(p.read_text(errors='replace').splitlines(),1):
                for kind,pattern in PATTERNS.items():
                    if re.search(pattern,text):findings.append({'path':str(p.relative_to(root)),'line':line,'kind':kind,'text':text.strip()[:240]})
    return {'kind':'static-risk-inventory-not-reachability-proof','counts':{k:sum(x['kind']==k for x in findings) for k in PATTERNS},'findings':findings}
if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('source',type=Path);p.add_argument('--output',type=Path,required=True);a=p.parse_args()
    if not (a.source/'Mage').is_dir():raise SystemExit('Expected a real XMage checkout')
    a.output.parent.mkdir(parents=True,exist_ok=True);a.output.write_text(json.dumps(audit(a.source),indent=2)+'\n')
