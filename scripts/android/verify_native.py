#!/usr/bin/env python3
"""Verify staged native inputs and exact source equivalence before a real APK build."""
import hashlib,json,subprocess,sys
from pathlib import Path
repo=Path(sys.argv[1]).resolve(); stage=repo/'apps/android/native-artifact'
m=json.loads((stage/'manifest.json').read_text())
assert m['schema']==1 and m['target']=='android-arm64'
for name, expected in m['files'].items():
 p=(stage/name).resolve(); assert p.is_relative_to(stage.resolve()) and p.is_file()
 assert hashlib.sha256(p.read_bytes()).hexdigest()==expected, 'Changed native input: '+name
for name in ['libmmengine.so','include/libmmengine.h','include/graal_isolate.h']:
 assert name in m['files'], 'Missing required ABI input'
paths=['packages/ondevice-engine','scripts/android/build_native.sh','scripts/android/prepare_toolchain.py','scripts/android/toolchain_archive.py','scripts/android/stage_native.py']
subprocess.run(['git','-C',str(repo),'diff','--exit-code',m['sourceCommit'],'HEAD','--',*paths],check=True)
subprocess.run(['git','-C',str(repo),'diff','--exit-code','HEAD','--',*paths],check=True)
print('Verified exact Android native files and equivalent guarded source',m['sourceCommit'])
