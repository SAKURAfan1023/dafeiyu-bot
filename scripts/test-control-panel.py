#!/usr/bin/env python3
"""Real loopback HTTP + synthetic OneBot checks; no real QQ or model requests."""
import base64, contextlib, hashlib, runpy, threading, time
import json, os, pathlib, select, socket, subprocess, sys, tempfile, urllib.error, urllib.parse, urllib.request, uuid

transport = runpy.run_path(str(pathlib.Path(__file__).with_name('test-onebot-transport.py')))

@contextlib.contextmanager
def onebot(mode='success', queue_control=None):
    """Local synthetic roster; optional events stop at held history requests, before models."""
    errors, connections = [], []
    with socket.socket() as server:
        server.bind(('127.0.0.1', 0)); server.listen(1); server.settimeout(5)
        def serve():
            try:
                conn, _ = server.accept(); connections.append(conn)
                with conn:
                    conn.settimeout(90)
                    header = b''
                    while b'\r\n\r\n' not in header:
                        header += transport['exact'](conn, 1)
                    fields = dict(line.split(': ', 1) for line in header.decode().split('\r\n')[1:] if ': ' in line)
                    fields = {key.lower(): value for key, value in fields.items()}
                    assert fields['authorization'] == 'Bearer synthetic-test-token'
                    accept = base64.b64encode(hashlib.sha1((fields['sec-websocket-key'] + '258EAFA5-E914-47DA-95CA-C5AB0DC85B11').encode()).digest()).decode()
                    conn.sendall(('HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Accept: ' + accept + '\r\n\r\n').encode())
                    injected, held_history, last_heartbeat = False, [], time.monotonic()
                    while True:
                        if queue_control is not None:
                            if time.monotonic() - last_heartbeat >= 5:
                                transport['send'](conn, {'post_type':'meta_event','meta_event_type':'heartbeat',
                                    'self_id':12345,'status':{'online':True,'good':True},'interval':5000})
                                last_heartbeat = time.monotonic()
                            if queue_control.get('inject') and not injected:
                                for number in range(1, 11):
                                    transport['send'](conn, {'post_type':'message','message_type':'private','sub_type':'friend',
                                        'self_id':12345,'user_id':54321,'sender':{'user_id':54321},'message_id':number,
                                        'time':time.time(),'message':[{'type':'text','data':{'text':'synthetic queue check'}}]})
                                injected = True
                            if queue_control.get('release'):
                                for req in held_history:
                                    # Empty history also prevents model admission if an epoch guard regresses.
                                    transport['send'](conn, {'status':'ok','retcode':0,'data':{'messages':[]},'echo':req['echo']})
                                    queue_control['released'] = queue_control.get('released', 0) + 1
                                held_history.clear()
                        if not select.select([conn], [], [], 0.05)[0]:
                            continue
                        try: req = transport['receive'](conn)
                        except (EOFError, ValueError, OSError): break
                        action = req['action']
                        if queue_control is not None and action == 'get_friend_msg_history':
                            held_history.append(req)
                            queue_control['history_requests'] = queue_control.get('history_requests', 0) + 1
                            continue
                        assert action in ('get_login_info','get_status','get_friend_list','get_group_list'), 'unexpected OneBot action'
                        data = {'get_login_info': {'user_id': 54321 if mode=='wrong-account' else 12345},
                                'get_status': {'online': mode!='offline', 'good': True},
                                'get_friend_list': [{'user_id': 54321, 'nickname': 'synthetic friend'}],
                                'get_group_list': [{'group_id': 99999, 'group_name': 'synthetic group'}]}[action]
                        transport['send'](conn, {'status':'ok','retcode':0,'data':data,'echo':req['echo']})
            except Exception as exc: errors.append(exc)
        thread = threading.Thread(target=serve, daemon=True); thread.start()
        try: yield f'ws://127.0.0.1:{server.getsockname()[1]}'
        finally:
            for conn in connections:
                try: conn.shutdown(socket.SHUT_RDWR)
                except OSError: pass
            thread.join(timeout=6)
            assert not thread.is_alive(), 'synthetic OneBot did not close'
            assert not errors, str(errors)

with tempfile.TemporaryDirectory(prefix='dafeiyu-panel-test-') as folder:
    env = dict(os.environ, DAFEIYU_DATA_DIR=folder)
    env.pop("DAFEIYU_RESOURCES", None)  # Verify packaged assets, not the source checkout.
    process = subprocess.Popen([sys.argv[1], '--qq-control-panel'], stdout=subprocess.PIPE, stderr=subprocess.PIPE, env=env)
    try:
        if not select.select([process.stdout], [], [], 20)[0]:
            raise RuntimeError('Panel did not start')
        line = process.stdout.readline().decode().strip()
        if not line.startswith('QQ_CONTROL_URL='):
            raise RuntimeError('Panel did not report its address')
        url = urllib.parse.urlsplit(line.split('=', 1)[1]); origin = f'http://{url.netloc}'
        def request(path, headers=None, body=None):
            req = urllib.request.Request(origin + path, data=body, headers=headers or {})
            try:
                with urllib.request.urlopen(req, timeout=5) as response: return response.status, response.read()
            except urllib.error.HTTPError as error: return error.code, error.read()
        assert request('/')[0] == 200
        assert request('/api/status')[0] == 403
        headers = {'X-QQ-Control': url.fragment, 'Origin': origin}
        code, data = request('/api/status', headers)
        state = json.loads(data); assert code == 200 and not state['connected'] and not state['running']
        assert state['configurationHints'] == []
        assert state['runtimeRecords'] == []
        assert state['calls'] == 0 and state['confirmed'] == 0
        assert request('/api/status', dict(headers, Origin='https://invalid.example'))[0] == 403
        assert request('/api/status', dict(headers, Host='invalid.example'))[0] == 400
        assert request('/api/action', headers, b'{"action":"pause"}')[0] == 403
        assert request('/api/action', dict(headers, **{'Content-Type': 'application/json'}), b'{"action":"pause"}')[0] == 200
        revision = [state['configurationRevision']]
        def action(payload):
            payload.setdefault('configurationRevision', revision[0])
            code, data = request('/api/action', dict(headers, **{'Content-Type': 'application/json'}), json.dumps(payload).encode())
            assert code == 200
            result = json.loads(data)
            revision[0] = result['configurationRevision']
            return result
        saved = action({'action': 'saveConnection', 'expectedSelfID': '12345', 'endpoint': 'ws://127.0.0.1:3101'})
        assert saved['configurationSaved'] and not saved['error'] and saved['config']['endpoint'] == 'ws://127.0.0.1:3101'
        invalid = action({'action': 'saveConnection', 'expectedSelfID': '54321', 'endpoint': 'ws://example.invalid:3101'})
        assert invalid['error'] and invalid['config'] == saved['config']
        ai = dict(saved['config']['ai'], workHoursEnabled=True, workStart=22, workEnd=7)
        old_revision = saved['configurationRevision']
        saved = action({'action': 'save', 'ai': ai, 'enabled': []})
        assert not saved['error'] and saved['config']['ai']['workStart'] == 22 and not saved['running']
        assert saved['configurationRevision'] != old_revision
        conflict = action({'action': 'save', 'ai': dict(ai, dailyLimit=17), 'configurationRevision': old_revision})
        assert conflict['error'] and conflict['config'] == saved['config']
        # Safety operations are intentionally available even with a stale editor.
        paused = action({'action': 'pause', 'configurationRevision': old_revision})
        assert not paused['error'] and not paused['running'] and paused['config'] == saved['config']
        invalid = action({'action': 'save', 'enabled': ['group:99999']})
        assert invalid['error'] and invalid['config'] == saved['config']
        # Independent tool editors persist only their own configuration, without credentials or sends.
        prior_ai = saved['config']['ai']
        image_settings = dict(saved['imageGeneration'], enabled=True, fallbackEnabled=False)
        saved = action({'action': 'saveImageGeneration', 'imageGeneration': image_settings, 'persistImageCredentials': False})
        assert saved['configurationSaved'] and not saved['error'] and saved['imageGeneration'] == image_settings and saved['config']['ai'] == prior_ai
        invalid = action({'action': 'saveImageGeneration', 'imageGeneration': dict(image_settings, cloudflareAccountID='invalid')})
        assert invalid['error'] and invalid['config'] == saved['config']
        visual_settings = dict(saved['visualTools'], provider='zhipu', googleWebEnabled=True)
        saved = action({'action': 'saveVisualTools', 'visualTools': visual_settings, 'persistVisualCredentials': False})
        assert saved['configurationSaved'] and not saved['error'] and saved['visualTools'] == visual_settings and saved['imageGeneration'] == image_settings
        assert any('启用识图' in hint for hint in saved['configurationHints'])
        assert any('联网开关未启用' in hint for hint in saved['configurationHints'])
        artwork_settings = dict(saved['artwork'], scheduleMinute=19)
        saved = action({'action': 'saveArtwork', 'artwork': artwork_settings})
        assert not saved['error'] and saved['artwork']['scheduleMinute'] == 19 and saved['visualTools'] == visual_settings
        invalid = action({'action': 'saveArtwork', 'artwork': dict(artwork_settings, scheduleTargets=['group:99999'])})
        assert invalid['error'] and invalid['config'] == saved['config']
        assert saved['calls'] == 0 and saved['confirmed'] == 0 and not saved['running']
        disk = json.loads((pathlib.Path(folder) / 'qq-state.json').read_text())
        assert disk['config'] == saved['config']
        for raw in [f'GET /api/status HTTP/1.1\r\nHost: {url.netloc}\r\nHost: {url.netloc}\r\n\r\n',
                    f'POST /api/action HTTP/1.1\r\nHost: {url.netloc}\r\nTransfer-Encoding: chunked\r\n\r\n',
                    f'POST /api/action HTTP/1.1\r\nHost: {url.netloc}\r\nContent-Length: 9999999\r\n\r\n']:
            with socket.create_connection(('127.0.0.1', url.port), timeout=5) as connection:
                connection.sendall(raw.encode()); assert connection.recv(128).startswith(b'HTTP/1.1 400')
        # Configuration changes must be saved explicitly before connecting.
        before = saved['config']
        invalid = action({'action':'connect', 'endpoint':'ws://127.0.0.1:3199', 'expectedSelfID':'12345'})
        assert invalid['error'] and invalid['config'] == before and not invalid['connected']
        invalid = action({'action':'connect', 'token':'synthetic-test-token'})
        assert invalid['error'] and not invalid['temporaryCredentials'] and invalid['config'] == before
        for mode in ('wrong-account', 'offline', 'success'):
            with onebot(mode) as endpoint:
                saved = action({'action':'saveConnection', 'endpoint':endpoint, 'expectedSelfID':'12345'})
                assert not saved['error']
                connected = action({'action':'connect', 'token':'synthetic-test-token', 'key':'synthetic-test-key'})
                assert connected['connected'] == (mode=='success') and not connected['running']
                if mode!='success':
                    assert connected['error'] and connected['config'] == saved['config']
                    continue
                assert not connected['error'] and len(connected['contacts']) == 2
                # No selected scope: startup fails without mutating saved settings.
                failed = action({'action':'start', 'durationMinutes':1})
                assert failed['error'] and not failed['running'] and failed['config'] == saved['config']
                added = action({'action':'add','target':'private:54321'})
                assert not added['error'] and len(added['config']['targets']) == 1
                saved = action({'action':'save','enabled':['private:54321']})
                assert not saved['error']
                invalid = action({'action':'start','durationMinutes':1,'ai':dict(saved['config']['ai'],dailyLimit=17)})
                assert invalid['error'] and invalid['config'] == saved['config'] and not invalid['running']
                invalid = action({'action':'start','durationMinutes':4321})
                assert invalid['error'] and not invalid['running']
                started = action({'action':'start','durationMinutes':1})
                assert not started['error'] and started['running'] and started['config'] == saved['config']
                assert 50 < started['runDeadline'] - time.time() <= 60
                failed_save = action({'action':'save','enabled':[]})
                assert failed_save['error'] and failed_save['running'] and failed_save['config'] == saved['config']
                if '--wait-for-expiry' in sys.argv:
                    expiry_limit = time.monotonic() + 65
                    while time.monotonic() < expiry_limit:
                        expired = json.loads(request('/api/status', headers)[1])
                        if not expired['running']: break
                        time.sleep(0.25)
                    assert expired['connected'] and not expired['running'] and expired['queued'] == 0 and not expired['runDeadline']
                    assert '已达到运行时限' in expired['status']
                    print('PASS: actual one-minute expiry pauses connected engine and clears queue', flush=True)
                paused = action({'action':'pause'})
                assert not paused['running'] and paused['queued'] == 0 and not paused['runDeadline']
                once = action({'action':'start','singleReply':True,'durationMinutes':4320})
                assert once['running'] and 890 < once['runDeadline'] - time.time() <= 900
                paused = action({'action':'pause'})
                unlimited = action({'action':'start','durationMinutes':0})
                assert unlimited['running'] and not unlimited['runDeadline']
                cleared = action({'action':'clear'})
                assert not cleared['connected'] and not cleared['running'] and not cleared['temporaryCredentials']
                assert cleared['calls'] == 0 and cleared['confirmed'] == 0
                assert json.loads((pathlib.Path(folder)/'qq-state.json').read_text())['config'] == saved['config']
        queue_control = {}
        with onebot(queue_control=queue_control) as endpoint:
            configured = action({'action':'saveConnection','endpoint':endpoint,'expectedSelfID':'12345'})
            assert not configured['error']
            connected = action({'action':'connect','token':'synthetic-test-token','key':'synthetic-test-key'})
            assert connected['connected'] and not connected['error']
            configured = action({'action':'save','ai':dict(connected['config']['ai'], workHoursEnabled=False),
                                 'enabled':['private:54321'],'memoryEnabled':False,'visionEnabled':False,'onlineEnabled':False})
            assert not configured['error']
            started = action({'action':'start','durationMinutes':1})
            assert started['running']
            queue_control['inject'] = True
            deadline = time.monotonic() + 5
            while time.monotonic() < deadline:
                queued = json.loads(request('/api/status', headers)[1])
                if queued['queued'] == 9 and queue_control.get('history_requests') == 1: break
                time.sleep(0.05)
            assert queued['running'] and queued['queued'] == 9 and queue_control.get('history_requests') == 1, {
                'running':queued['running'],'queued':queued['queued'],'history_requests':queue_control.get('history_requests'),
                'rejected':queued['rejected'],'error':queued['error']}
            assert queued['calls'] == 0 and queued['confirmed'] == 0
            paused = action({'action':'pause'})
            assert paused['connected'] and not paused['running'] and paused['queued'] == 0 and not paused['runDeadline']
            # Start a new epoch before releasing the previous worker's response.
            restarted = action({'action':'start','durationMinutes':1})
            assert restarted['running'] and restarted['queued'] == 0
            queue_control['release'] = True
            deadline = time.monotonic() + 2
            while time.monotonic() < deadline:
                current = json.loads(request('/api/status', headers)[1])
                assert current['connected'] and current['running'] and current['queued'] == 0
                assert current['calls'] == 0 and current['confirmed'] == 0 and current['uncertain'] == 0
                time.sleep(0.05)
            assert queue_control.get('history_requests') == 1 and queue_control.get('released') == 1
            action({'action':'pause'})
            cleared = action({'action':'clear'})
            assert not cleared['connected'] and not cleared['running']
        print('PASS: ten synthetic events produce nine queued replies; pause clears queue, restart ignores late history, zero model/send calls')
        assert request('/api/status', headers)[0] == 200
        print('PASS: assets, authentication, Origin/Host, malformed requests, connection/reply persistence, stale editor rejection, stale pause, unknown scope rejection, independent image/vision/artwork persistence, invalid tool configuration rollback, identity/online rejection, saved-config start, pause/clear lifecycle, isolated zero-send state')
    finally:
        process.terminate()
        try: process.wait(timeout=5)
        except subprocess.TimeoutExpired: process.kill(); process.wait()
    # Reopen only this temporary state with synthetic historical outcomes. No
    # messages, model calls, or send actions are needed to verify the API display.
    file = pathlib.Path(folder) / 'qq-state.json'
    stored = json.loads(file.read_text())
    stored['logs'] = [{'id':str(uuid.uuid4()), 'date':time.time()-978307200,
                       'state':'uncertain' if index==34 else 'skipped',
                       'detail':f'合成结果 {index}；token=synthetic-private-secret https://example.invalid/?key=hidden'} for index in range(35)]
    file.write_text(json.dumps(stored))
    process = subprocess.Popen([sys.argv[1], '--qq-control-panel'], stdout=subprocess.PIPE, stderr=subprocess.PIPE, env=env)
    try:
        assert select.select([process.stdout], [], [], 20)[0], 'Panel did not reopen'
        line = process.stdout.readline().decode().strip()
        assert line.startswith('QQ_CONTROL_URL=')
        url = urllib.parse.urlsplit(line.split('=', 1)[1]); origin = f'http://{url.netloc}'
        code, data = request('/api/status', {'X-QQ-Control':url.fragment, 'Origin':origin})
        state = json.loads(data); records = state['runtimeRecords']
        assert code==200 and len(records)==30
        assert records[0]['title']=='发送结果未知' and records[-1]['detail'].startswith('合成结果 5；')
        assert abs(records[0]['timestamp'] - time.time()) < 10
        assert set(records[0]) == {'id','timestamp','state','title','target','detail'}
        assert 'synthetic-private-secret' not in data.decode() and 'example.invalid' not in data.decode()
        assert state['calls']==0 and state['confirmed']==0 and not state['running']
        print('PASS: restored runtime records are bounded, newest first, redacted, and do not alter counters')
    finally:
        process.terminate()
        try: process.wait(timeout=5)
        except subprocess.TimeoutExpired: process.kill(); process.wait()
