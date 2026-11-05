#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Fail closed on common secrets/runtime files; print locations, never values."""
import argparse, hashlib, pathlib, re, subprocess, sys
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--staged', action='store_true', help='scan the Git index, exactly as prepared for commit')
args = parser.parse_args()
root = pathlib.Path(__file__).resolve().parents[1]
listing = ['git', '-C', str(root), 'ls-files', '-z']
if not args.staged: listing += ['--cached', '--others', '--exclude-standard']
result = subprocess.run(listing, capture_output=True)
if result.returncode:
    sys.exit('Unable to inspect tracked files; run inside the Git repository.')
paths = [root / name.decode() for name in result.stdout.split(b'\0') if name]
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
    if args.staged:
        entry = subprocess.run(['git', '-C', str(root), 'ls-files', '-s', '--', str(rel)], capture_output=True, check=True).stdout
        if entry.startswith(b'120000 '): failures.append((str(rel),0,'symlink'));continue
    elif p.is_symlink(): failures.append((str(rel),0,'symlink'));continue
    if any(x in {'.build','dist','config','private','local'} for x in rel.parts) or p.suffix in {'.log','.jsonl','.key','.pem','.p12','.db','.har'} or p.name in {'.env','qq-state.json','state.json'}:
        failures.append((str(rel),0,'runtime or credential file'));continue
    try:
        if args.staged:
            blob = subprocess.run(['git', '-C', str(root), 'show', ':' + rel.as_posix()], capture_output=True)
            if blob.returncode: failures.append((str(rel),0,'cannot read staged file'));continue
            data = blob.stdout
        else:
            data=p.read_bytes()
    except FileNotFoundError: failures.append((str(rel),0,'tracked file missing'));continue
    if p.suffix.lower() in {'.png','.jpg','.jpeg','.webp'}: continue  # Human visual review is required separately.
    try: text=data.decode('utf-8')
    except UnicodeDecodeError: failures.append((str(rel),0,'unreviewed binary'));continue
    # Preserve the public copyright contact in the byte-pinned official ICU license.
    official_icu = rel.as_posix() == 'docs/licenses/windows/ICU-74.1-LICENSE.txt' and hashlib.sha256(data.replace(b'\r\n', b'\n')).hexdigest() == '17510cf7a58b4879b887ec05a45d72cf1b73544dd9ec7e72f20110ed104229ee'
    for number,line in enumerate(text.splitlines(),1):
        for label,pattern in rules.items():
            if label == 'private email' and official_icu: continue
            if re.search(pattern,line):failures.append((str(rel),number,label))
for path,line,label in failures: print(f'{path}:{line}: {label}')
print(f'Checked {len(paths)} public files ({"index" if args.staged else "working tree"}); findings={len(failures)}. Images and commit metadata require separate review.')
sys.exit(bool(failures))
