#!/usr/bin/env python3
"""Report upstream movement without automatically trusting, patching, or shipping new code."""
import json,subprocess
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
lock=json.loads((ROOT/'upstream.lock.json').read_text())
result=subprocess.check_output(['git','ls-remote',lock['repository'],'refs/heads/master'],text=True,timeout=30)
parts=result.split()
if len(parts)!=2:raise SystemExit('Cannot resolve upstream HEAD')
report={'pinned':lock['commit'],'upstreamHead':parts[0],'updateAvailable':parts[0]!=lock['commit'],
        'action':'Review changes; update the lock and source hashes; rebuild registry; run real rules and device gates. No automatic release.'}
(ROOT/'evidence').mkdir(exist_ok=True)
(ROOT/'evidence/upstream-status.json').write_text(json.dumps(report,indent=2)+'\n')
print(json.dumps(report,indent=2))
