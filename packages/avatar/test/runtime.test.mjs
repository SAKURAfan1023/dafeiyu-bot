import test from 'node:test';
import assert from 'node:assert/strict';
import { once } from 'node:events';
import { WebSocket } from 'ws';
import { AvatarRuntime } from '../lib/runtime.mjs';

const until = async fn => { for (let i = 0; i < 150; i++) { if (fn()) return; await new Promise(r => setTimeout(r, 10)); } throw Error('Timed out waiting for state'); };

test('loopback HTTP, browser origin and finite tool inputs fail closed', async () => {
  const runtime = await AvatarRuntime.start();
  try {
    assert.equal((await fetch(runtime.origin + '/api/state')).status, 403);
    assert.equal((await fetch(runtime.origin + '/api/state', { headers: { 'X-Avatar-Token': runtime.token, Origin: 'https://untrusted.example' } })).status, 403);
    assert.equal((await fetch(runtime.origin + '/web/style.css')).headers.get('Content-Type'), 'text/css');
    assert.equal((await fetch(runtime.origin + '/web/../lib/runtime.mjs')).status, 404);
    assert.equal((await fetch(runtime.origin + '/models/classic-maid/private.json')).status, 404);
    assert.equal(runtime.list().models.length, 5);
    assert.equal(runtime.list().models.find(m => m.id === 'classic-maid').license.id, 'CC-BY-NC-SA-4.0');
    await assert.rejects(runtime.dispatch('avatar_pose', { head: { yaw: 2 } }), { code: 'INVALID_INPUT' });
    await assert.rejects(runtime.dispatch('avatar_pose', { arms: { left: { fingers: { index: 1 } } } }), { code: 'INVALID_INPUT' });
    await assert.rejects(runtime.dispatch('avatar_pose', { expression: 'unknown' }), { code: 'INVALID_INPUT' });
    await assert.rejects(runtime.dispatch('avatar_action', { action: 'nod' }), { code: 'NOT_READY' });
  } finally { await runtime.close(); }
});

test('one owner, model identity, idempotency, completion, stop, switch, loss and recovery', async () => {
  const runtime = await AvatarRuntime.start();
  let renderer, pending;
  const received = [];
  const attach = async () => {
    renderer = new WebSocket(runtime.origin.replace('http:', 'ws:') + '/ws?token=' + runtime.token, { origin: runtime.origin });
    renderer.on('message', raw => {
      const cmd = JSON.parse(raw); received.push(cmd);
      if (cmd.operation === 'load') renderer.send(JSON.stringify({ id: cmd.id, ok: true, model_id: cmd.model_id, revision: cmd.revision, inputs_reset: true }));
      else if (cmd.operation === 'stop') {
        if (pending) { renderer.send(JSON.stringify({ id: pending.id, ok: true, model_id: pending.model_id, revision: pending.revision, inputs_reset: true })); pending = null; }
        renderer.send(JSON.stringify({ id: cmd.id, ok: true, model_id: cmd.model_id, revision: cmd.revision, inputs_reset: true }));
      } else pending = cmd;
    });
    await once(renderer, 'open'); await until(() => runtime.ready);
  };
  try {
    await attach();
    assert.equal(runtime.status().expression_profiles.shy.label, '害羞');
    const bindings = runtime.model.model.expressions;
    runtime.model.model.expressions = bindings.filter(e => e.id !== 'shy');
    await assert.rejects(runtime.dispatch('avatar_pose', { expression: 'shy' }), { code: 'EXPRESSION_UNAVAILABLE' });
    assert.equal(runtime.active, null);
    runtime.model.model.expressions = bindings;
    const second = new WebSocket(runtime.origin.replace('http:', 'ws:') + '/ws?token=' + runtime.token, { origin: runtime.origin });
    const [code] = await once(second, 'close'); assert.equal(code, 1008);
    const input = { expression: 'smile', arms: { left: { elbow: .6 } }, call_id: 'same', expected_model: 'classic-maid' };
    const result = await runtime.dispatch('avatar_pose', input);
    assert.deepEqual(await runtime.dispatch('avatar_pose', input), result);
    await assert.rejects(runtime.dispatch('avatar_pose', { ...input, expression: 'sad' }), { code: 'CALL_ID_CONFLICT' });
    await assert.rejects(runtime.dispatch('avatar_select', { model_id: 'sailor' }), { code: 'BUSY' });
    await assert.rejects(runtime.dispatch('avatar_action', { action: 'wave-left' }), { code: 'BUSY' });
    await assert.rejects(runtime.dispatch('avatar_stop', { action_id: 'wrong' }), { code: 'STALE_ACTION' });
    await until(() => pending);
    assert.equal(pending.input.arms.left.elbow, .6);
    const stopped = await runtime.dispatch('avatar_stop', { action_id: result.action_id });
    assert.equal(stopped.state, 'cancelled'); assert(stopped.inputs_reset);
    const selected = await runtime.dispatch('avatar_select', { model_id: 'sailor' }); assert(selected.renderer_ready);
    await assert.rejects(runtime.dispatch('avatar_action', { action: 'nod', expected_model: 'classic-maid' }), { code: 'MODEL_CHANGED' });
    const completed = await runtime.dispatch('avatar_action', { action: 'nod' }); await until(() => pending);
    renderer.send(JSON.stringify({ id: pending.id, ok: true, model_id: pending.model_id, revision: pending.revision, inputs_reset: true })); pending = null;
    await until(() => !runtime.active); assert.equal(runtime.recent.at(-1).state, 'completed'); assert.equal(runtime.recent.at(-1).action_id, completed.action_id);
    await runtime.dispatch('avatar_pose', { head: { yaw: .4 } }); await until(() => pending);
    renderer.terminate(); await until(() => runtime.fault && !runtime.active);
    assert.equal(runtime.recent.at(-1).state, 'uncertain'); assert.equal(runtime.recent.at(-1).inputs_reset, false);
    const previousCount = received.filter(c => c.operation === 'pose').length;
    pending = null; await attach();
    assert.equal(received.filter(c => c.operation === 'pose').length, previousCount); assert.equal(runtime.fault, null);
    await runtime.dispatch('avatar_select', { model_id: 'classic-maid' }); assert.equal(runtime.status().model_id, 'classic-maid');
  } finally { renderer?.terminate(); await runtime.close(); }
});
