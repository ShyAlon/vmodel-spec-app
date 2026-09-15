#!/usr/bin/env python3
"""Idempotently copy legacy V-model runs into artifacts/<session>/{interview,spec}."""
from pathlib import Path
import argparse, re, shutil
p=argparse.ArgumentParser();p.add_argument('--root',type=Path,default=Path.home()/'development/require');p.add_argument('--session',action='append',default=[]);a=p.parse_args()
root=a.root.expanduser().resolve();destroot=root/'artifacts'; wanted=set(a.session)
# Interview legacy directories.
for old in root.glob('*/out/*'):
    if not old.is_dir(): continue
    sid=old.name
    if wanted and sid not in wanted: continue
    if not (old/'checkpoints.sqlite').exists() and not (old/'intent_model.json').exists(): continue
    dst=destroot/sid/'interview';dst.mkdir(parents=True,exist_ok=True)
    shutil.copytree(old,dst,dirs_exist_ok=True);print(f'interview: {old} -> {dst}')
# Spec legacy directories; timestamp names are matched to timestamp session ids.
sessions={p.name for p in destroot.iterdir() if p.is_dir()} | wanted if destroot.exists() else wanted
for old in destroot.glob('artifacts-*'):
    if not old.is_dir(): continue
    fresh=old.name.endswith('-fresh'); stem=old.name.removeprefix('artifacts-').removesuffix('-fresh')
    compact=re.sub(r'[-_:]','',stem)[:14]
    matches=[s for s in sessions if re.sub(r'[-_:]','',s).startswith(compact)]
    if len(matches)!=1: print(f'skip ambiguous: {old}');continue
    dst=destroot/matches[0]/('spec-fresh' if fresh else 'spec');dst.mkdir(parents=True,exist_ok=True)
    shutil.copytree(old,dst,dirs_exist_ok=True);print(f'spec: {old} -> {dst}')
