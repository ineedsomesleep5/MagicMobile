#!/usr/bin/env python3
import os,sys
from pathlib import Path
u=Path(sys.argv[1]);entries=[]
for p in sorted(u.rglob('target/mobile-classpath.txt')):
    for e in p.read_text().strip().split(os.pathsep):
        if e and e not in entries:entries.append(e)
    classes=p.parent/'classes'
    if classes.is_dir() and str(classes) not in entries:entries.insert(0,str(classes))
if not entries:raise SystemExit('No Maven classpaths generated')
Path(sys.argv[2]).write_text(os.pathsep.join(entries))
