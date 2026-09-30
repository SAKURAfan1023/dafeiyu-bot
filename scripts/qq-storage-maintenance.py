#!/usr/bin/env python3
"""Daily QQ retention through NapCat; only enabled scopes, never outbound messages."""
import argparse
import datetime
import fcntl
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile
import time
import urllib.request

WEEK = 7 * 86400
SWIFT_EPOCH = 978307200
PLUGIN = 'dafeiyu-retention'


def prune_state(state, now):
    ledger = state.get('artworkLedger') or {}
    ledger['deliveries'] = [x for x in ledger.get('deliveries', []) if now - (x['at'] + SWIFT_EPOCH) < WEEK][-20000:]
    ledger['schedules'] = {k: v for k, v in ledger.get('schedules', {}).items() if now - (v + SWIFT_EPOCH) < WEEK}
    if state.get('artworkLedger') is not None:
        state['artworkLedger'] = ledger
    artwork = state.get('config', {}).get('artwork')
    if artwork is not None:
        artwork['repeatDays'] = min(7, max(1, artwork.get('repeatDays', 7)))
    state['logs'] = [x for x in state.get('logs', []) if now - (x['date'] + SWIFT_EPOCH) < WEEK][-1000:]
    return state


def rotate_records(file, now, limit=1000):
    rows = []
    if file.exists():
        for line in file.read_text().splitlines():
            row = json.loads(line)
            if now - row['timestamp'] < WEEK:
                rows.append(row)
    return rows[-limit:]


def write_json(file, value):
    file.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
    with tempfile.NamedTemporaryFile(mode='w', dir=file.parent, delete=False) as stream:
        name = stream.name
        os.chmod(name, 0o600)
        json.dump(value, stream, ensure_ascii=False, separators=(',', ':'))
        stream.flush()
        os.fsync(stream.fileno())
    os.replace(name, file)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('mode', choices=['install', 'dry-run', 'run', 'watch'])
    parser.add_argument('--state', type=Path, default=Path.home() / 'Library/Application Support/WeChatAIBot/qq-state.json')
    parser.add_argument('--runtime', type=Path, default=Path.home() / '.local/qq-runtime')
    parser.add_argument('--lima', default=os.environ.get('LIMA_BIN', str(Path.home() / '.local/qq-runtime/lima/bin/limactl')))
    args = parser.parse_args()
    args.runtime.mkdir(parents=True, exist_ok=True, mode=0o700)
    # A process lock owns the scheduler. No boot service or automatic restart/login.
    lock = os.open(args.runtime / 'maintenance.lock', os.O_CREAT | os.O_RDWR, 0o600)
    fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
    is_watch = args.mode == 'watch'
    if is_watch:
        os.ftruncate(lock, 0)
        os.write(lock, str(os.getpid()).encode())

    def guest(*command):
        r = subprocess.run([args.lima, 'shell', 'qq-ai', 'sudo', 'docker', *command], capture_output=True, text=True, timeout=60)
        if r.returncode:
            raise RuntimeError('QQ container command failed')
        return r.stdout

    def api(route, body=None, credential=None):
        headers = {'Content-Type': 'application/json'}
        if credential:
            headers['Authorization'] = 'Bearer ' + credential
        request = urllib.request.Request('http://127.0.0.1:6099/api' + route, headers=headers,
                                         data=json.dumps(body).encode() if body is not None else None)
        data = json.load(urllib.request.urlopen(request, timeout=60))
        if data.get('code') != 0:
            raise RuntimeError('Authenticated NapCat request failed')
        return data.get('data')

    def copy_file(local, destination):
        # SCP first: docker cp runs inside the guest and cannot read host paths.
        with tempfile.TemporaryDirectory(prefix='qq-retention-') as temp:
            name = Path(temp) / Path(local).name
            name.write_bytes(Path(local).read_bytes())
            os.chmod(name, 0o600)
            target = '/tmp/' + Path(temp).name + '-' + name.name
            r = subprocess.run([args.lima, 'copy', str(name), 'qq-ai:' + target], capture_output=True, timeout=30)
            if r.returncode:
                raise RuntimeError('Retention file transfer failed')
            try:
                guest('cp', target, 'qq-ai:' + destination)
            finally:
                subprocess.run([args.lima, 'shell', 'qq-ai', 'rm', '-f', target], capture_output=True, timeout=15)

    def clean_host(now):
        result = {'botStateTrimmed': False, 'backupsRemoved': 0}
        state_lock = os.open(args.state.parent / 'qq-engine.lock', os.O_CREAT | os.O_RDWR, 0o600)
        try:
            try:
                fcntl.flock(state_lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
                write_json(args.state, prune_state(json.loads(args.state.read_text()), now))
                result['botStateTrimmed'] = True
            except BlockingIOError:
                pass
        finally:
            os.close(state_lock)
        backups = sorted([p for p in args.runtime.glob('*.json') if re.fullmatch(r'(pre-.*-state|.*-state-backup).json', p.name) and not p.is_symlink()], key=lambda p: p.stat().st_mtime, reverse=True)
        for file in backups[3:]:
            if now - file.stat().st_mtime > WEEK:
                file.unlink(); result['backupsRemoved'] += 1
        return result

    def record_result(result):
        now = result['timestamp']
        marker = args.runtime / 'maintenance-status.json'
        previous = json.loads(marker.read_text()) if marker.exists() else {}
        if not result.get('error') and result.get('errors') == 0 and not result.get('capped'):
            previous['lastSuccessfulRun'] = now
        previous['lastResult'] = result
        write_json(marker, previous)
        file = args.runtime / 'maintenance-checks.jsonl'
        records = rotate_records(file, now)
        records.append(result)
        text = '\n'.join(json.dumps(x, separators=(',', ':')) for x in records[-1000:]) + '\n'
        with tempfile.NamedTemporaryFile(mode='w', dir=file.parent, delete=False) as stream:
            name = stream.name
            os.chmod(name, 0o600)
            stream.write(text)
        os.replace(name, file)

    current_host_result = {}

    def run_once(mode):
        nonlocal current_host_result
        current_host_result = {}
        now = time.time()
        marker = args.runtime / 'maintenance-status.json'
        previous = json.loads(marker.read_text()) if marker.exists() else {}
        if is_watch and now - previous.get('lastSuccessfulRun', 0) < 86400:
            return
        host_result = clean_host(now) if mode == 'run' else {}
        current_host_result = host_result
        state = json.loads(args.state.read_text())
        config = state['config']
        account = config['expectedSelfID']
        targets = [{'type': 'group' if x['group'] else 'private', 'id': x['number']}
                   for x in config['targets'] if x['enabled']]
        if not re.fullmatch(r'[1-9]\d{4,19}', account) or not targets:
            raise RuntimeError('No validated enabled QQ scopes')
        webui = json.loads((args.runtime / 'config/webui.json').read_text())
        digest = hashlib.sha256((webui['token'] + '.napcat').encode()).hexdigest()
        credential = api('/auth/login', {'hash': digest}).get('Credential')
        if not credential:
            raise RuntimeError('NapCat authentication unavailable')
        if mode == 'install':
            guest('exec', 'qq-ai', 'mkdir', '-p', '/app/napcat/plugins/' + PLUGIN)
            for source in (Path(__file__).resolve().parents[1] / 'Resources/NapCatRetention').iterdir():
                copy_file(source, '/app/napcat/plugins/' + PLUGIN + '/' + source.name)
        login = api('/QQLogin/CheckLoginStatus', {}, credential)
        if login.get('isLogin') is not True or login.get('coreReady') is not True:
            raise RuntimeError('QQ login/core unavailable; cleanup pending')
        plugins = api('/Plugin/List', credential=credential)
        if plugins.get('pluginManagerNotFound'):
            api('/Plugin/RegisterManager', {}, credential)
        api('/Plugin/SetStatus', {'id': PLUGIN, 'enable': True}, credential)
        roots = guest('exec', 'qq-ai', 'sh', '-c', 'find /app/.config/QQ -maxdepth 1 -type d -name "nt_qq_*"').splitlines()
        if len(roots) != 1 or not re.fullmatch(r'/app/\.config/QQ/nt_qq_[a-f0-9]+', roots[0]):
            raise RuntimeError('Account media folder ambiguous; refuse cleanup')
        policy = {'enabled': True, 'account': account, 'targets': targets, 'mediaRoot': roots[0] + '/nt_data'}
        directory = '/app/napcat/config/plugins/' + PLUGIN
        guest('exec', 'qq-ai', 'mkdir', '-p', directory)
        with tempfile.TemporaryDirectory(prefix='qq-policy-') as temp:
            file = Path(temp) / 'config.json'
            write_json(file, policy)
            copy_file(file, directory + '/config.next.json')
        guest('exec', 'qq-ai', 'sh', '-c', 'chmod 600 ' + directory + '/config.next.json && mv ' + directory + '/config.next.json ' + directory + '/config.json')
        dry_run = mode in ['install', 'dry-run']
        if not dry_run:
            preview = api('/Plugin/ext/' + PLUGIN + '/cleanup', {'account': account, 'dryRun': True}, credential)
            if preview['errors'] != 0:
                raise RuntimeError('QQ cleanup preflight failed; no QQ deletion attempted')
        result = api('/Plugin/ext/' + PLUGIN + '/cleanup', {'account': account, 'dryRun': dry_run}, credential)
        result['timestamp'] = now
        result.update(host_result)
        if not dry_run:
            record_result(result)
        print(json.dumps(result, ensure_ascii=False), flush=True)

    while True:
        try:
            run_once('run' if is_watch else args.mode)
        except Exception as error:
            # Avoid exception responses/URLs leaking auth, account IDs or chat text.
            result = {'timestamp': time.time(), 'error': str(error) if isinstance(error, RuntimeError) else type(error).__name__, 'cleanupSuccessful': False}
            result.update(current_host_result)
            if is_watch or args.mode == 'run':
                record_result(result)
            print(json.dumps(result), flush=True)
            if not is_watch:
                return 1
        if not is_watch:
            return 0
        time.sleep(6 * 3600)


if __name__ == '__main__':
    sys.exit(main())
