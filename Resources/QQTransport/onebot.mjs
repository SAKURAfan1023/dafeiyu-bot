import { createRequire } from 'node:module';
import path from 'node:path';
const require = createRequire(process.env.DAFEIYU_NODE_DEPENDENCIES
  ? path.join(process.env.DAFEIYU_NODE_DEPENDENCIES, 'package.json') : import.meta.url);
const WebSocket = require('ws');
let socket, buffer = Buffer.alloc(0), ended = false;
function output(value) {
  if (ended) return;
  if (process.stdout.writableLength > 6400000) return finish();
  if (!process.stdout.write(JSON.stringify(value) + '\n')) socket?.pause();
}
function finish() {
  if (ended) return;
  ended = true; socket?.terminate(); process.stdin.destroy();
  process.stdout.end();
}
function command(value) {
  if (value.type === 'connect' && !socket) {
    const url = new URL(value.url);
    if (url.protocol !== 'ws:' || url.hostname !== '127.0.0.1' || !url.port || url.username || url.password || url.search || url.hash || url.pathname !== '/' ||
        typeof value.token !== 'string' || !value.token || value.token.length > 16384 || /\s/.test(value.token)) throw new Error('invalid connection');
    socket = new WebSocket(url, { headers: { Authorization: 'Bearer ' + value.token }, maxPayload: 1048576,
      handshakeTimeout: 10000, followRedirects: false, perMessageDeflate: false });
    socket.on('open', () => output({ type: 'open' }));
    socket.on('message', data => output({ type: 'message', data: data.toString('utf8') }));
    socket.on('error', finish); socket.on('close', finish);
  } else if (value.type === 'send' && socket?.readyState === WebSocket.OPEN && typeof value.data === 'string' &&
             Buffer.byteLength(value.data) <= 4200000 && socket.bufferedAmount <= 4200000) {
    socket.send(value.data, error => { if (error) finish(); });
  } else throw new Error('invalid transport command');
}
process.stdin.on('data', data => {
  buffer = Buffer.concat([buffer, data]);
  if (buffer.length > 8500000) return finish();
  let end;
  while ((end = buffer.indexOf(10)) >= 0) {
    const line = buffer.subarray(0, end); buffer = buffer.subarray(end + 1);
    try { command(JSON.parse(line.toString('utf8'))); } catch { return finish(); }
  }
});
process.stdin.on('end', finish); process.stdin.on('error', finish);
process.stdout.on('error', finish);
process.stdout.on('drain', () => { if (!ended) socket?.resume(); });
process.on('SIGTERM', finish); process.on('SIGINT', finish);
