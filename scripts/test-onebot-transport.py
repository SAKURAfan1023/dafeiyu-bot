#!/usr/bin/env python3
"""Local WebSocket fixture: real Swift transport, synthetic QQ identity; never calls QQ or AI."""
import base64
import hashlib
import json
import socket
import struct
import subprocess
import sys
import threading

TOKEN = 'synthetic-test-token'

def exact(conn, count):
    out = b''
    while len(out) < count:
        chunk = conn.recv(count - len(out))
        if not chunk:
            raise EOFError()
        out += chunk
    return out

def receive(conn):
    first, second = exact(conn, 2)
    size = second & 127
    if size == 126:
        size = struct.unpack('!H', exact(conn, 2))[0]
    elif size == 127:
        size = struct.unpack('!Q', exact(conn, 8))[0]
    assert size < 4_100_000  # bounded text + one reviewed image (up to 3 MB before Base64)
    mask = exact(conn, 4) if second & 128 else b'\0' * 4
    raw = exact(conn, size)
    return json.loads(bytes(b ^ mask[i % 4] for i, b in enumerate(raw)))

def send(conn, value):
    data = json.dumps(value).encode()
    header = bytes([0x81, len(data)]) if len(data) < 126 else b'\x81\x7e' + struct.pack('!H', len(data))
    conn.sendall(header + data)

def scenario(mode):
    errors = []
    with socket.socket() as server:
        server.bind(('127.0.0.1', 0)); server.listen(1); server.settimeout(10)
        port = server.getsockname()[1]
        def serve():
            try:
                conn, _ = server.accept()
                with conn:
                    conn.settimeout(10)
                    header = b''
                    while b'\r\n\r\n' not in header:
                        header += exact(conn, 1)
                    fields = dict(line.split(': ', 1) for line in header.decode().split('\r\n')[1:] if ': ' in line)
                    fields = {key.lower(): value for key, value in fields.items()}
                    assert fields['authorization'] == 'Bearer ' + TOKEN
                    accept = base64.b64encode(hashlib.sha1((fields['sec-websocket-key'] + '258EAFA5-E914-47DA-95CA-C5AB0DC85B11').encode()).digest()).decode()
                    conn.sendall(('HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Accept: ' + accept + '\r\n\r\n').encode())
                    requests = [receive(conn), receive(conn)]
                    assert {r['action'] for r in requests} == {'get_login_info', 'get_status'}
                    assert len({r['echo'] for r in requests}) == 2
                    if mode == 'disconnect':
                        return
                    # Reverse the responses and interleave an unsolicited event to verify echo routing.
                    send(conn, {'post_type': 'meta_event', 'self_id': 12345, 'meta_event_type': 'heartbeat'})
                    for request in reversed(requests):
                        data = {'user_id': 54321 if mode == 'wrong-account' else 12345} if request['action'] == 'get_login_info' else {'online': mode != 'offline', 'good': True}
                        send(conn, {'status': 'ok', 'retcode': 0, 'data': data, 'echo': request['echo']})
                    try:
                        conn.recv(256)
                    except OSError:
                        pass
            except Exception as exc:
                errors.append(exc)
        thread = threading.Thread(target=serve, daemon=True); thread.start()
        result = subprocess.run([binary, '--qq-check', f'ws://127.0.0.1:{port}', '12345'], input=TOKEN+'\n', text=True, capture_output=True, timeout=20)
        thread.join(timeout=10)
        assert not thread.is_alive(), mode + ': server did not finish'
        assert not errors, str(errors) + ': ' + result.stdout + result.stderr
        assert (result.returncode == 0) == (mode == 'success'), mode + ': ' + result.stdout + result.stderr
        print('PASS', mode)

if __name__ == '__main__':
    binary = sys.argv[1]
    for mode in ['success', 'wrong-account', 'offline', 'disconnect']:
        scenario(mode)
