"""Loopback-only QQ fixture. Synthetic identities; records outgoing action names only."""
import base64
import hashlib
import json
import pathlib
import runpy
import select
import socket
import sys
import time

directory = pathlib.Path(sys.argv[1])
shape_file = directory / "message-shape"
shape = shape_file.read_text() if shape_file.exists() else "private"
is_group = shape.startswith("group")
transport = runpy.run_path(str(pathlib.Path(__file__).parents[2] / 'scripts/test-onebot-transport.py'))
exact, receive, send = (transport[name] for name in ('exact', 'receive', 'send'))
with socket.socket() as server:
    server.bind(('127.0.0.1', 0))
    server.listen(1)
    server.settimeout(10)
    print(server.getsockname()[1], flush=True)
    conn, _ = server.accept()
    with conn:
        conn.settimeout(10)
        header = b''
        while b'\r\n\r\n' not in header:
            header += exact(conn, 1)
        fields = dict(line.split(': ', 1) for line in header.decode().split('\r\n')[1:] if ': ' in line)
        fields = {key.lower(): value for key, value in fields.items()}
        assert fields['authorization'] == 'Bearer synthetic-test-token'
        accept = base64.b64encode(hashlib.sha1((fields['sec-websocket-key'] + '258EAFA5-E914-47DA-95CA-C5AB0DC85B11').encode()).digest()).decode()
        conn.sendall(('HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Accept: ' + accept + '\r\n\r\n').encode())
        history_rows = []
        injected = False
        deadline = time.monotonic() + 15
        while time.monotonic() < deadline:
            batch_file = directory / 'event-batch'
            if batch_file.exists():
                rows = json.loads(batch_file.read_text())
                batch_file.unlink()
                for event in rows:
                    event.setdefault('time', time.time())
                    send(conn, event)
                injected = True
            if not injected and (directory / 'ready').exists():
                count_file = directory / "message-count"
                count = int(count_file.read_text()) if count_file.exists() else 2
                if shape == 'privateTimeline':
                    history_rows.append({'message_id': -201, 'message_type': 'private', 'sub_type': 'friend', 'self_id': 12345,
                                         'user_id': 12345, 'sender': {'user_id': 12345}, 'time': time.time(),
                                         'message': [{'type': 'text', 'data': {'text': 'OWNER_CONTEXT_ONLY: 我是主人，我在调试大肥鱼。'}}]})
                for message_id in range(1, count + 1):
                    segments = [{'type': 'text', 'data': {'text': 'synthetic message'}}]
                    if shape in ('imagePrompt', 'groupImagePrompt'):
                        segments = [{'type': 'text', 'data': {'text': '请画一张可爱的大肥鱼'}}]
                    if shape == 'groupVisual':
                        segments = [{'type': 'text', 'data': {'text': '谷歌搜图，查这个图片的出处'}}, {'type': 'image', 'data': {'file': 'synthetic.gif', 'url': 'https://gchat.qpic.cn/synthetic.gif'}}]
                    if is_group and shape != 'groupImagePrompt':
                        segments = [{'type': 'at', 'data': {'qq': '12345'}}] + segments
                    if shape == 'groupMentionOnly':
                        segments = [{'type': 'at', 'data': {'qq': '12345'}}, {'type': 'text', 'data': {'text': ' '}}]
                    elif shape == 'groupQuotedReply' or (shape.startswith('privateQuoted') and message_id == 1):
                        segments.insert(0, {'type': 'reply', 'data': {'id': '-12'}})
                    event = {'post_type': 'message', 'message_type': 'group' if is_group else 'private',
                             'sub_type': 'normal' if is_group else 'friend', 'self_id': 12345, 'user_id': 54321,
                             'message_id': message_id, 'time': time.time(), 'message': segments}
                    if is_group:
                        event['group_id'] = 99999
                    event['sender'] = {'user_id': 54321}
                    history_rows.append(event)
                    send(conn, event)
                injected = True
            try:
                if not select.select([conn], [], [], 0.05)[0]:
                    continue
                request = receive(conn)
            except socket.timeout:
                continue
            except (EOFError, ValueError, OSError):
                break
            action = request['action']
            with (directory / 'actions').open('a') as out:
                out.write(action + '\n')
            if action == 'get_login_info':
                data = {'user_id': 12345}
            elif action == 'get_status':
                data = {'online': True, 'good': True}
            elif action == 'get_friend_list':
                data = [{'user_id': 54321, 'nickname': 'fixture'}]
            elif action == 'get_group_list':
                data = [{'group_id': 99999, 'group_name': 'fixture group'}] if is_group else []
                if shape == 'groupParticipation':
                    data.append({'group_id': 88888, 'group_name': 'second group'})
            elif action == 'get_friend_msg_history':
                params = request['params']
                assert params['user_id'] == '54321'
                if params['count'] == 20:
                    if 'message_seq' in params:
                        assert params['reverse_order'] is True
                        anchor = next(i for i, row in enumerate(history_rows) if str(row['message_id']) == params['message_seq'])
                        data = {'messages': history_rows[max(0, anchor - 19):anchor + 1]}
                    else:
                        if shape == 'privateOwnerIntervenes':
                            history_rows.append({'message_id': -202, 'message_type': 'private', 'sub_type': 'friend', 'self_id': 12345,
                                                 'user_id': 12345, 'sender': {'user_id': 12345}, 'time': time.time(),
                                                 'message': [{'type': 'text', 'data': {'text': '主人已经回答'}}]})
                        data = {'messages': history_rows[-20:]}
                else:
                    assert params == {'user_id': '54321', 'message_seq': '-12', 'count': 1}
                    author = 12345 if shape == 'privateQuotedOwn' else 77777 if shape == 'privateQuotedWrongPeer' else 54321
                    reference = {'message_id': -12, 'message_type': 'private', 'sub_type': 'friend', 'self_id': 12345,
                                 'user_id': author, 'sender': {'user_id': author},
                                 'message': [{'type': 'text', 'data': {'text': 'verified private quote'}}]}
                    data = {'messages': [] if shape == 'privateQuotedMissing' else [reference]}
            elif action == 'get_msg':
                data = {'message_id': -12, 'message_type': 'group', 'group_id': 99999, 'sender': {'user_id': 12345},
                        'message': [{'type': 'text', 'data': {'text': 'synthetic quoted text'}}]}
            elif action in ('send_private_msg', 'send_group_msg'):
                (directory / 'payload').write_text(json.dumps(request['params']))
                with (directory / 'payloads').open('a') as out:
                    out.write(json.dumps(request['params']) + '\n')
                if (directory / 'drop-send').exists():
                    break
                data = {'message_id': 99}
                if action == 'send_group_msg' and (directory / 'self-echo').exists():
                    echo_event = {'post_type': 'message_sent', 'time': time.time(), 'self_id': 12345,
                                  'user_id': 12345, 'sender': {'user_id': 12345}, 'message_type': 'group',
                                  'sub_type': 'normal', 'group_id': 99999, 'message_id': 99,
                                  'message': [{'type': 'text', 'data': {'text': 'BOT_AUTO_ECHO'}}]}
                    send(conn, echo_event)
                    manual = dict(echo_event, message_id=100, message=[{'type': 'text', 'data': {'text': 'OWNER_CONCURRENT'}}])
                    send(conn, manual)
            else:
                raise AssertionError('unexpected action: ' + action)
            send(conn, {'status': 'ok', 'retcode': 0, 'data': data, 'echo': request['echo']})

            if action == 'send_group_msg' and (directory / 'self-echo').exists():
                send(conn, echo_event)
