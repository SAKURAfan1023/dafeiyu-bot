#!/usr/bin/env python3
"""Real loopback HTTP checks, isolated state, no QQ connection/model requests."""
import json, os, pathlib, select, socket, subprocess, sys, tempfile, urllib.error, urllib.parse, urllib.request

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
        assert state['calls'] == 0 and state['confirmed'] == 0
        assert request('/api/status', dict(headers, Origin='https://invalid.example'))[0] == 403
        assert request('/api/status', dict(headers, Host='invalid.example'))[0] == 400
        assert request('/api/action', headers, b'{"action":"pause"}')[0] == 403
        assert request('/api/action', dict(headers, **{'Content-Type': 'application/json'}), b'{"action":"pause"}')[0] == 200
        for raw in [f'GET /api/status HTTP/1.1\r\nHost: {url.netloc}\r\nHost: {url.netloc}\r\n\r\n',
                    f'POST /api/action HTTP/1.1\r\nHost: {url.netloc}\r\nTransfer-Encoding: chunked\r\n\r\n',
                    f'POST /api/action HTTP/1.1\r\nHost: {url.netloc}\r\nContent-Length: 9999999\r\n\r\n']:
            with socket.create_connection(('127.0.0.1', url.port), timeout=5) as connection:
                connection.sendall(raw.encode()); assert connection.recv(128).startswith(b'HTTP/1.1 400')
        assert request('/api/status', headers)[0] == 200
        print('PASS: assets, authentication, Origin/Host, malformed requests, pause, isolated zero-send state')
    finally:
        process.terminate()
        try: process.wait(timeout=5)
        except subprocess.TimeoutExpired: process.kill(); process.wait()
