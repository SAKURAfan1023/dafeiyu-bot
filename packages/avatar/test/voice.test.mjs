import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import { once } from 'node:events';
import { WebSocket } from 'ws';
import { LocalVoice } from '../lib/voice.mjs';
import { AvatarRuntime } from '../lib/runtime.mjs';
import { PreviewBridge } from '../lib/bridge.mjs';

// Synthetic worker exercises the real child-process/JSONL boundary; it is not a speech-quality test.
async function fixture() {
  const root = await fs.mkdtemp(path.join(os.tmpdir(), 'avatar-voice-'));
  await fs.mkdir(path.join(root, 'model'));
  await fs.writeFile(path.join(root, 'model/config.json'), JSON.stringify({ tts_model_type: 'voice_design' }));
  const python = path.join(root, 'python');
  await fs.writeFile(python, `#!${process.execPath}\nimport { createInterface } from 'node:readline';
console.log(JSON.stringify({type:'ready',protocol:2,sample_rate:24000}));
createInterface({input:process.stdin}).on('line',line=>{
 const r=JSON.parse(line);
 if(r.text==='slow')return;
 if(r.text==='fail'){console.log(JSON.stringify({id:r.id,type:'end',ok:false}));return;}
 const chunk={id:r.id,type:'chunk',index:r.text==='bad'?2:0,sample_rate:24000,pcm:Buffer.alloc(480).toString('base64')};
 console.log(JSON.stringify(chunk));
 console.log(JSON.stringify({id:r.id,type:'end',ok:true,chunks:1,seconds:.01,synthesis_seconds:.001}));
});\n`, { mode: 0o700 });
  const config = path.join(root, 'config.json');
  await fs.writeFile(config, JSON.stringify({ python, model: 'model', cache: 'cache', instruct: '清甜女声' }));
  return { root, config, async close() { await fs.rm(root, { recursive: true, force: true }); } };
}
const until = async fn => { for (let i = 0; i < 200; i++) { if (fn()) return; await new Promise(r => setTimeout(r, 5)); } throw Error('Timed out'); };

test('owned offline worker: reuse, PCM validation, failure, cancellation and explicit restart', { skip: process.platform === 'win32' && 'The local MLX worker uses a POSIX Python environment' }, async () => {
  const f = await fixture(), voice = await LocalVoice.create(f.config);
  try {
    await voice.prewarm(); const first = voice.child;
    const chunks = [];
    const metrics = await voice.stream('hello', c => chunks.push(c), new AbortController().signal);
    assert.equal(metrics.chunks, 1); assert.equal(metrics.audio_seconds, .01); assert.equal(chunks[0].index, 0);
    await voice.stream('hello again', () => {}, new AbortController().signal);
    assert.equal(voice.child, first);
    await assert.rejects(voice.stream('bad', () => {}, new AbortController().signal), { code: 'VOICE_PROTOCOL_FAILED' });
    assert.equal(voice.ready, false);
    await voice.prewarm(); assert.notEqual(voice.child, first);
    await assert.rejects(voice.stream('fail', () => {}, new AbortController().signal), { code: 'TTS_FAILED' });
    const abort = new AbortController(), running = voice.stream('slow', () => {}, abort.signal);
    await until(() => voice.pending); const cancelled = voice.child;
    abort.abort(); await assert.rejects(running, { code: 'VOICE_CANCELLED' });
    await until(() => cancelled.signalCode !== null);
    await voice.stream('retry', () => {}, new AbortController().signal);
    assert(voice.ready); assert.equal('python' in voice.status(), false);
  } finally { await voice.close(); await f.close(); }
});

test('composable resources, atomic preflight, scoped replacement, shared host and stale identity', { skip: process.platform === 'win32' && 'The local MLX worker uses a POSIX Python environment' }, async () => {
  const f = await fixture(), host = await AvatarRuntime.start({ voiceConfig: f.config });
  let renderer;
  const commands = new Map();
  try {
    renderer = new WebSocket(host.origin.replace('http:', 'ws:') + '/ws?token=' + host.token, { origin: host.origin });
    const reply = (cmd, extra = {}) => renderer.send(JSON.stringify({ id: cmd.id, ok: true, model_id: cmd.model_id, revision: cmd.revision, inputs_reset: true, ...extra }));
    renderer.on('message', raw => {
      const cmd = JSON.parse(raw);
      if (cmd.operation === 'load') { reply(cmd); renderer.send(JSON.stringify({ type: 'audio_state', ready: true, model_id: cmd.model_id, revision: cmd.revision })); }
      else if (cmd.operation === 'stop') {
        const target = commands.get(cmd.target);
        if (target && cmd.scope === 'all') { reply(target); commands.delete(cmd.target); }
        reply(cmd);
      } else if (cmd.operation) commands.set(cmd.id, cmd);
    });
    await once(renderer, 'open'); await until(() => host.ready && host.audioReady);
    const speaking = await host.dispatch('avatar_say', { text: 'slow', call_id: 'speech' });
    await until(() => host.voice.pending);
    const pose = await host.dispatch('avatar_pose', { head: { yaw: .4 }, expression: 'shy' });
    assert.equal(host.status().active_actions.length, 2);
    await assert.rejects(host.dispatch('avatar_pose', { features: { mouth_open: .5 } }), { code: 'BUSY' });
    await assert.rejects(host.dispatch('avatar_perform', { speech: { text: 'invalid combination' }, visual: { features: { mouth_open: .5 } }, on_conflict: 'replace' }), { code: 'RESOURCE_CONFLICT' });
    assert(host.jobs.has(speaking.action_id)); assert(host.jobs.has(pose.action_id));
    const replacement = await host.dispatch('avatar_pose', { head: { yaw: -.3 }, on_conflict: 'replace' });
    assert(host.jobs.has(speaking.action_id)); assert(!host.jobs.has(pose.action_id)); assert(host.jobs.has(replacement.action_id));
    await host.dispatch('avatar_stop', { scope: 'visual' });
    assert.equal(host.jobs.size, 1); assert(host.jobs.has(speaking.action_id));
    const bridge = await PreviewBridge.connect(host.url);
    assert.equal((await bridge.dispatch('avatar_status')).session_id, host.session);
    await assert.rejects(PreviewBridge.connect('https://example.com/'), { code: 'INVALID_PREVIEW_URL' });
    await assert.rejects(bridge.dispatch('avatar_action', { action: 'nod', expected_session: '00000000-0000-4000-8000-000000000000' }), { code: 'HOST_CHANGED' });
    const stopped = await bridge.dispatch('avatar_stop', { scope: 'speech', action_id: speaking.action_id }); assert(stopped.inputs_reset);
    assert.equal(host.active, null);
    await assert.rejects(host.dispatch('avatar_pose', { head: {} }), { code: 'INVALID_INPUT' });
    await assert.rejects(host.dispatch('avatar_say', { text: '!!!' }), { code: 'INVALID_INPUT' });
    await bridge.close(); assert(host.ready);
    const action = await host.dispatch('avatar_action', { action: 'nod' });
    await until(() => [...commands.values()].some(c => c.action_id === action.action_id));
    const cmd = [...commands.values()].find(c => c.action_id === action.action_id);
    reply(cmd, { revision: 'stale' });
    await until(() => host.fault);
    assert.equal(host.recent.at(-1).state, 'uncertain');
  } finally { renderer?.terminate(); await host.close(); await f.close(); }
});
