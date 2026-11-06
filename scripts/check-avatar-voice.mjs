// Real local Qwen -> stdio MCP -> streamed PCM -> browser audio clock and five rendered avatars.
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import path from 'node:path';
import { chromium } from 'playwright';
import { Client } from '@modelcontextprotocol/sdk/client/index.js';
import { StdioClientTransport } from '@modelcontextprotocol/sdk/client/stdio.js';
const output = path.resolve(process.argv[2] ?? 'local/avatar-authoring/voice-qa');
const config = process.argv[3];
if (!config) throw Error('Supply output directory and explicit private local voice config');
await fs.mkdir(output, { recursive: true });
const report = { backend: 'real-offline-qwen3-mlx', models: [], checks: [], errors: [] };
const transport = new StdioClientTransport({ command: process.execPath, args: [path.resolve(process.argv[4] ?? 'packages/avatar/bin/avatar.mjs'), '--voice-config', path.resolve(config)], stderr: 'pipe' });
transport.stderr?.resume();
const client = new Client({ name: 'avatar-voice-acceptance', version: '1' });
let browser, bridge;
async function call(name, input = {}) { const result = await client.callTool({ name, arguments: input }); assert(!result.isError, JSON.stringify(result)); return result.structuredContent; }
async function until(fn, seconds = 200) { const end = Date.now() + seconds * 1000; while (Date.now() < end) { const value = await fn(); if (value) return value; await new Promise(r => setTimeout(r, 50)); } throw Error('Timed out'); }
async function ended(id) { return until(async () => { const state = await call('avatar_status', { action_id: id }); const r = state.action; if (r?.state !== 'running') { assert.equal(r.state, 'completed', JSON.stringify(r)); assert(r.inputs_reset); return r; } }); }
try {
  await client.connect(transport);
  const initial = await call('avatar_status');
  assert(initial.voice.configured);
  const tools = (await client.listTools()).tools;
  assert.equal(tools.length, 8);
  for (const tool of tools) assert.equal(tool.annotations.readOnlyHint, ['avatar_status', 'avatar_list'].includes(tool.name));
  browser = await chromium.launch({ headless: true, executablePath: process.env.DAFEIYU_BROWSER_PATH });
  const context = await browser.newContext({ viewport: { width: 1200, height: 1050 } });
  const page = await context.newPage(); page.on('pageerror', error => report.errors.push(error.message));
  await page.goto(initial.preview_url);
  await page.waitForFunction(() => window.avatarRendererState?.().connected);
  assert((await client.callTool({ name: 'avatar_say', arguments: { text: '你好。' } })).isError);
  report.checks.push('audio-gesture-required');
  await page.locator('#audio-unlock').click();
  await until(async () => { const s = await call('avatar_status'); return s.voice.ready && s.voice.audio_ready; });
  await page.evaluate(() => { window.voiceFrames = []; avatarPlayer.use({ order: 1000, update(frame) { if (window.voiceFrames.length < 30000) window.voiceFrames.push({ at: performance.now(), mouth: frame.params.mouthOpen, yaw: frame.params.angleX, eye: frame.params.eyeLOpen, state: avatarRendererState() }); } }); });
  for (const id of ['sailor', 'hoodie', 'researcher', 'ocean-dress', 'classic-maid']) {
    await call('avatar_select', { model_id: id });
    await page.evaluate(() => { window.voiceFrames = []; });
    const started = await call('avatar_perform', { speech: { text: '你好呀，一起加油。' }, visual: { expression: 'shy', head: { yaw: .12 }, transition_seconds: .4, return_seconds: .85 }, expected_model: id, call_id: id + '-voice' });
    assert.equal((await call('avatar_perform', { speech: { text: '你好呀，一起加油。' }, visual: { expression: 'shy', head: { yaw: .12 }, transition_seconds: .4, return_seconds: .85 }, expected_model: id, call_id: id + '-voice' })).action_id, started.action_id);
    await until(() => page.evaluate(() => avatarRendererState().mouth > .12));
    await page.locator('#model').screenshot({ path: path.join(output, id + '-speaking.png') });
    const finished = await ended(started.action_id);
    const frames = await page.evaluate(() => window.voiceFrames);
    const speaking = frames.filter(f => f.state.jobs.some(j => j.speech && j.started !== null));
    assert(speaking.length > 5);
    assert(Math.max(...speaking.map(f => f.mouth)) - Math.min(...speaking.map(f => f.mouth)) > .1);
    const waiting = frames.filter(f => f.state.jobs.some(j => j.speech && j.chunks === 0));
    assert(waiting.every(f => f.state.jobs.every(j => j.started === null)));
    assert(finished.voice_metrics.chunks > 1);
    report.models.push({ id, state: finished.state, inputs_reset: finished.inputs_reset, voice: finished.voice_metrics, sampled_speaking_frames: speaking.length, mouth_range: [Math.min(...speaking.map(f => f.mouth)), Math.max(...speaking.map(f => f.mouth))] });
    console.log('Voice verified', id);
  }
  // A speech owns mouth/audio only. A separate look and head pose can run without resetting it.
  const speaking = await call('avatar_say', { text: '我在这里，慢慢说给你听。', call_id: 'parallel' });
  await until(() => page.evaluate(() => avatarRendererState().mouth > .1));
  const head = await call('avatar_pose', { head: { yaw: -.4 }, eyes: { gaze_x: -.5 }, transition_seconds: .25, hold_seconds: 3, return_seconds: .5 });
  const invalid = await client.callTool({ name: 'avatar_perform', arguments: { speech: { text: '你好' }, visual: { features: { mouth_open: .8 } }, on_conflict: 'replace' } });
  assert(invalid.isError); assert((await call('avatar_status')).active_actions.some(j => j.action_id === speaking.action_id));
  assert((await client.callTool({ name: 'avatar_pose', arguments: { features: { mouth_open: .8 } } })).isError);
  await call('avatar_stop', { scope: 'visual', action_id: head.action_id });
  assert((await call('avatar_status')).active_actions.some(j => j.action_id === speaking.action_id));
  await call('avatar_stop', { scope: 'speech', action_id: speaking.action_id });
  assert.equal((await call('avatar_status')).active, null);
  report.checks.push('independent-speech-head-gaze', 'manual-mouth-conflict', 'atomic-invalid-perform-no-interruption', 'scoped-stops');
  // Replacing a combination's head track must leave its speech alive and retain truthful child results.
  const combined = await call('avatar_perform', { speech: { text: '我会继续说话，你可以轻轻调整我的方向。' }, visual: { head: { tilt: .2 } } });
  await until(() => page.evaluate(() => avatarRendererState().mouth > .1));
  const replaced = await call('avatar_pose', { head: { tilt: -.2 }, on_conflict: 'replace', transition_seconds: .25, hold_seconds: .2, return_seconds: .25 });
  const during = await call('avatar_status', { action_id: combined.action_id });
  assert(during.action.resources.includes('audio')); assert.equal(during.action.children.visual, 'cancelled');
  await ended(replaced.action_id);
  const group = await until(async () => { const state = await call('avatar_status', { action_id: combined.action_id }); return state.action.state !== 'running' ? state.action : null; });
  assert.equal(group.state, 'cancelled'); assert.equal(group.children.speech, 'completed'); assert.equal(group.children.visual, 'cancelled'); assert(group.inputs_reset);
  report.checks.push('replace-visual-preserves-combined-speech', 'partial-cancel-child-results');
  // A short utterance finishes while the one-shot greeting retains its natural duration.
  const greeting = await call('avatar_perform', { speech: { text: '你好。' }, action: 'wave-left' });
  await until(async () => { const s = await call('avatar_status', { action_id: greeting.action_id }); return s.action.state === 'running' && s.action.children.speech === 'completed'; });
  const nextSpeech = await call('avatar_say', { text: '你好。' });
  await ended(greeting.action_id); await ended(nextSpeech.action_id);
  report.checks.push('one-shot-keeps-natural-duration', 'finished-speech-releases-mouth-before-motion');
  // A second stdio MCP connects to the same preview/worker; closing it cannot close the owner.
  const bridgeTransport = new StdioClientTransport({ command: process.execPath, args: [path.resolve(process.argv[4] ?? 'packages/avatar/bin/avatar.mjs'), 'connect-preview', '--url', initial.preview_url], stderr: 'pipe' }); bridgeTransport.stderr?.resume();
  bridge = new Client({ name: 'avatar-bridge-acceptance', version: '1' }); await bridge.connect(bridgeTransport);
  const shared = (await bridge.callTool({ name: 'avatar_status', arguments: {} })).structuredContent;
  assert.equal(shared.session_id, initial.session_id);
  const moved = (await bridge.callTool({ name: 'avatar_action', arguments: { action: 'nod' } })).structuredContent; await ended(moved.action_id);
  await bridge.close(); bridge = null; assert((await call('avatar_status')).renderer_ready);
  report.checks.push('bridge-same-session-no-second-renderer', 'bridge-close-preserves-owner');
  // Stop during generation and start a fresh utterance after the owned worker is rewarmed.
  const cancelled = await call('avatar_say', { text: '这句话将在开始生成时被取消。' });
  await call('avatar_stop', { action_id: cancelled.action_id });
  const retry = await call('avatar_say', { text: '你好。' }); await ended(retry.action_id);
  report.checks.push('generation-cancel-owned-worker', 'explicit-retry-after-cancel');
  // Disconnect is uncertain and never automatically replays.
  await call('avatar_say', { text: '断开连接前的测试。' }); await page.close();
  const lost = await until(async () => { const s = await call('avatar_status'); return s.fault ? s : null; });
  assert.equal(lost.recent.at(-1).state, 'uncertain');
  const recovered = await context.newPage(); await recovered.goto(initial.preview_url); await recovered.waitForFunction(() => window.avatarRendererState?.().connected);
  assert.equal((await call('avatar_status')).active, null);
  assert.equal((await call('avatar_status')).voice.audio_ready, false);
  report.checks.push('disconnect-uncertain-no-replay', 'new-page-requires-audio-gesture');
  assert.deepEqual(report.errors, []);
} catch (error) { report.failure = error.stack; throw error; }
finally { await bridge?.close(); await browser?.close(); await client.close(); await fs.writeFile(path.join(output, 'report.json'), JSON.stringify(report, null, 2)); }
console.log({ models: report.models.length, checks: report.checks.length, errors: report.errors });
