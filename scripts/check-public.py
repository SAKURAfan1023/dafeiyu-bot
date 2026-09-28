#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Fail closed on common secrets/runtime files; print locations, never values."""
import pathlib, re, subprocess, sys
root = pathlib.Path(__file__).resolve().parents[1]
result = subprocess.run(['git', '-C', str(root), 'ls-files', '-z'], capture_output=True)
paths = [root / name.decode() for name in result.stdout.split(b'\0') if name]
if not paths:
    paths = [p for p in root.rglob('*') if p.is_file() and not any(x in {'.git', '.build', '.swiftpm', 'dist', '__pycache__'} for x in p.relative_to(root).parts)]
rules = {
    'provider credential': r'\b(?:sk-[A-Za-z0-9_-]{24,}|cfut_[A-Za-z0-9]{32,}|gh[pousr]_[A-Za-z0-9]{30,}|github_pat_[A-Za-z0-9_]{30,}|AKIA[A-Z0-9]{16})\b',
    'dotted provider credential': r'\b[a-f0-9]{32}\.[A-Za-z0-9]{16,}\b',
    'private key': r'-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----',
    'personal absolute path': r'/(?:Users|home)/[A-Za-z0-9_.-]+/',
    'private email': r'\b[\w.+-]+@(?:gmail|qq|hotmail|outlook)\.com\b',
    'control URL token': r'https?://127\.0\.0\.1:\d+/#\S{16,}',
}
failures=[]
for p in paths:
    rel=p.relative_to(root)
    if p.is_symlink(): failures.append((str(rel),0,'symlink'));continue
    if any(x in {'.build','dist','config','private','local'} for x in rel.parts) or p.suffix in {'.log','.jsonl','.key','.pem','.p12','.db','.har'} or p.name in {'.env','qq-state.json','state.json'}:
        failures.append((str(rel),0,'runtime or credential file'));continue
    try: data=p.read_bytes()
    except FileNotFoundError: failures.append((str(rel),0,'tracked file missing'));continue
    if p.suffix.lower() in {'.png','.jpg','.jpeg','.webp'}: continue  # Human visual review is required separately.
    try: text=data.decode('utf-8')
    except UnicodeDecodeError: failures.append((str(rel),0,'unreviewed binary'));continue
    for number,line in enumerate(text.splitlines(),1):
        for label,pattern in rules.items():
            if re.search(pattern,line):failures.append((str(rel),number,label))
for path,line,label in failures: print(f'{path}:{line}: {label}')
print(f'Checked {len(paths)} public files; findings={len(failures)}. Images and commit metadata require separate review.')
sys.exit(bool(failures))
