#!/usr/bin/env python3
"""Install this package on a NEW LOCAL branch of MagicMobile. No commit/push/remote writes.
Defaults to a dry run. Refuses dirty trees and existing destination folders.
"""
from __future__ import annotations
import argparse,datetime,shutil,subprocess
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
EXCLUDE={'.git','.build','build','.upstream','__pycache__','.DS_Store','ios-app','integration'}

def git(repo,*args):return subprocess.check_output(['git','-C',str(repo),*args],text=True).strip()

def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('repository',type=Path)
    p.add_argument('--apply',action='store_true');p.add_argument('--branch',default='codex/ondevice-xmage')
    a=p.parse_args();repo=a.repository.resolve()
    if not (ROOT/'ios-app').is_dir() or not (ROOT/'integration').is_dir():
        raise SystemExit('Run this installer from the original extracted delivery, not from an already-installed module.')
    if Path(git(repo,'rev-parse','--show-toplevel')).resolve()!=repo:raise SystemExit('Pass the repository root')
    if repo==ROOT or ROOT in repo.parents:raise SystemExit('Do not install into the delivery folder itself')
    if git(repo,'status','--porcelain'):raise SystemExit('Working tree is not clean. Preserve your changes before installing; nothing was modified.')
    destinations=[repo/'packages/ondevice-engine',repo/'apps/ios-ondevice',repo/'.github/workflows/magicmobile-ondevice.yml']
    if any(p.exists() for p in destinations):raise SystemExit('An installation destination exists. Review/merge manually instead of overwriting it.')
    head=git(repo,'rev-parse','HEAD')
    print('Base commit:',head);print('Local branch:',a.branch)
    for d in destinations:print('Add:',d.relative_to(repo))
    print('Append new-direction notes to README.md; keep existing apps unchanged as references.')
    if not a.apply:print('Dry run only. Re-run with --apply to install.');return
    git(repo,'check-ref-format','--branch',a.branch)
    git(repo,'switch','-c',a.branch)
    def ignore(path,names):return [n for n in names if n in EXCLUDE or n.endswith('.pyc')]
    shutil.copytree(ROOT,destinations[0],ignore=ignore)
    shutil.copytree(ROOT/'ios-app',destinations[1])
    for name in ['project.yml','project.native.yml']:
        path=destinations[1]/name;text=path.read_text()
        for old,new in [('../swift','../../packages/ondevice-engine/swift'),('../native','../../packages/ondevice-engine/native'),('../build/ios','../../packages/ondevice-engine/build/ios')]:text=text.replace(old,new)
        path.write_text(text)
    destinations[2].parent.mkdir(parents=True,exist_ok=True)
    shutil.copy2(ROOT/'integration/magicmobile-ondevice.yml',destinations[2])
    with (repo/'README.md').open('a') as f:
        f.write('\n\n## New primary direction: embedded iOS XMage\n\nThe on-device migration lives in `packages/ondevice-engine`; its native iOS harness is `apps/ios-ondevice`. Read `packages/ondevice-engine/CODEX_START_HERE.md` first. The old gateway/client path is retained for regression/reference, not a production on-device fallback. This is an experimental port, not a completed iPhone engine.\n')
    print('Installed on a local branch. No commit or push was performed. Review git diff/status and follow CODEX_START_HERE.md.')
if __name__=='__main__':main()
