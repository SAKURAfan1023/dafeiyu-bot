// Real stdio MCP -> controller -> WebSocket -> WebGL Player, in an isolated test browser.
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import path from 'node:path';
import { chromium } from 'playwright';
import { Client } from '@modelcontextprotocol/sdk/client/index.js';
import { StdioClientTransport } from '@modelcontextprotocol/sdk/client/stdio.js';

const output = path.resolve(process.argv[2] ?? 'local/avatar-authoring/qa-browser');
const entry = path.resolve(process.argv[3] ?? 'packages/avatar/bin/avatar.mjs');
await fs.mkdir(output, { recursive: true });
const transport = new StdioClientTransport({ command: process.execPath, args: [entry], stderr: 'pipe' });
transport.stderr?.resume(); // Ephemeral local token must not enter public logs or reports.
const client = new Client({ name: 'avatar-browser-check', version: '1.0.0' });
let browser;
const report = { models: [], actions: [], expressions: [], checks: [], errors: [] };
async function call(name, input = {}) {
  const result = await client.callTool({ name, arguments: input });
  assert(!result.isError, JSON.stringify(result));
  return result.structuredContent ?? JSON.parse(result.content[0].text);
}
async function ended(id) {
  for (let n = 0; n < 120; n++) {
    const state = await call('avatar_status');
    const result = state.recent.find(r => r.action_id === id);
    if (result) { assert(result.inputs_reset); assert.equal(result.state, 'completed'); return result; }
    await new Promise(resolve => setTimeout(resolve, 120));
  }
  throw Error('Motion did not complete');
}
// A screenshot on a loaded software GPU can outlive a bounded pose. Natural completion is also a confirmed reset.
async function stopOrConfirmCompleted(id) {
  const result = await client.callTool({ name: 'avatar_stop', arguments: { action_id: id } });
  if (!result.isError) { assert(result.structuredContent.inputs_reset); return; }
  assert.equal(result.structuredContent.code, 'STALE_ACTION');
  const state = await call('avatar_status', { action_id: id });
  assert.equal(state.action.state, 'completed'); assert(state.action.inputs_reset);
}
try {
  await client.connect(transport);
  assert.equal(client.getServerVersion().version, JSON.parse(await fs.readFile(path.join(path.dirname(entry), '../package.json'), 'utf8')).version);
  assert.equal((await client.listTools()).tools.length, 8);
  const catalog = await call('avatar_list'); assert.equal(catalog.models.length, 5);
  const initial = await call('avatar_status'); assert.equal(initial.renderer_ready, false);
  const offline = await client.callTool({ name: 'avatar_action', arguments: { action: 'nod' } }); assert(offline.isError);
  browser = await chromium.launch({ headless: true, ...(process.env.DAFEIYU_BROWSER_PATH ? { executablePath: process.env.DAFEIYU_BROWSER_PATH } : {}) });
  const context = await browser.newContext({ viewport: { width: 1200, height: 1050 }, deviceScaleFactor: 1 });
  const page = await context.newPage(); page.on('pageerror', e => report.errors.push(e.message));
  await page.goto(initial.preview_url);
  await page.waitForFunction(() => window.avatarRendererState?.().connected);
  await page.evaluate(() => { avatarPlayer.use({ order: 1000, update(frame) { window.avatarObserved = { ...frame.params }; } }); });
  for (const model of catalog.models) {
    const selected = await call('avatar_select', { model_id: model.id }); assert(selected.renderer_ready);
    assert.equal(await page.evaluate(() => avatarRendererState().model_id), model.id);
    assert(await page.evaluate(() => avatarPlayer.view.head === true));
    assert.equal(selected.active, null);
    await page.evaluate(() => { avatarPlayer.idle = false; avatarPlayer.followPointer = false; });
    const stopTest = await call('avatar_pose', { head: { yaw: .4 }, hold_seconds: 4 });
    await page.waitForTimeout(350);
    const stopped = await call('avatar_stop', { action_id: stopTest.action_id }); assert(stopped.inputs_reset); assert.equal(stopped.state, 'cancelled');
    for (const action of selected.actions) {
      const started = await call('avatar_action', { action, expected_model: model.id }); assert(started.accepted);
      await page.waitForTimeout(['wave-left', 'wave-right'].includes(action) ? 1200 : 330);
      await page.locator('#model').screenshot({ path: path.join(output, `${model.id}-${action}-peak.png`) });
      const result = await ended(started.action_id);
      report.actions.push({ model: model.id, action, state: result.state, inputs_reset: result.inputs_reset });
    }
    await page.locator('#face').click();
    for (const expression of selected.expressions) {
      const started = await call('avatar_pose', { expression, transition_seconds: .25, hold_seconds: .45, return_seconds: .25 });
      await page.waitForTimeout(400);
      await page.locator('#model').screenshot({ path: path.join(output, `${model.id}-expression-${expression}.png`) });
      await ended(started.action_id); report.expressions.push({ model: model.id, expression });
    }
    await page.locator('#full').click();
    report.models.push({ id: model.id, loaded: true, stop_reset: true });
    console.log('Verified model', model.id);
  }

  await call('avatar_select', { model_id: 'sailor' });
  await page.evaluate(() => { avatarPlayer.idle = false; avatarPlayer.followPointer = false; });
  for (const [label, input, parameter, expected] of [
    ['gaze-left', { eyes: { gaze_x: -.8 } }, 'eyeBallX', -.8],
    ['gaze-down', { eyes: { gaze_y: .7 } }, 'eyeBallY', -.7],
    ['head-left', { head: { yaw: -.8 } }, 'angleX', -19.2],
    ['head-up', { head: { pitch: .6 } }, 'angleY', 13.2],
    ['lean-right', { body: { lean: .5 } }, 'bodyZ', 2],
    ['left-wink', { eyes: { left_close: 1 } }, 'eyeLOpen', 0],
    ['mouth-open', { features: { mouth_open: .8 } }, 'mouthOpen', .8],
    ['zero-expression', { expression: 'smile', intensity: 0 }, 'eyeLOpen', 1],
  ]) {
    const started = await call('avatar_pose', { ...input, transition_seconds: .25, hold_seconds: 8, return_seconds: .25 });
    await page.waitForTimeout(500);
    const observed = await page.evaluate(k => window.avatarObserved[k], parameter);
    assert(Math.abs(observed - expected) < .005, `${label}: ${observed}`);
    await page.locator('#model').screenshot({ path: path.join(output, `fine-${label}.png`) });
    await stopOrConfirmCompleted(started.action_id);
    report.checks.push(label);
  }
  for (const joint of ['shoulder', 'elbow', 'wrist']) {
    const started = await call('avatar_pose', { arms: { left: { [joint]: .8 } }, transition_seconds: .25, hold_seconds: 8, return_seconds: .25 });
    await page.waitForTimeout(550);
    await page.locator('#model').screenshot({ path: path.join(output, `fine-left-${joint}.png`) });
    await stopOrConfirmCompleted(started.action_id);
    report.checks.push('independent-' + joint);
  }
  // Same retry resolves to the original action; busy switching and stale stops cannot steal its ownership.
  const input = { action: 'wave-left', call_id: 'browser-retry' };
  const first = await call('avatar_action', input); assert.equal((await call('avatar_action', input)).action_id, first.action_id);
  for (const [name, args] of [['avatar_select', { model_id: 'hoodie' }], ['avatar_stop', { action_id: 'stale' }]]) {
    assert((await client.callTool({ name, arguments: args })).isError);
  }
  assert((await call('avatar_stop')).inputs_reset); report.checks.push('retry-busy-stale-stop');

  const second = await context.newPage(); await second.goto(initial.preview_url);
  await second.waitForFunction(() => document.querySelector('#connection').textContent.includes('已有其他预览'));
  assert(await second.locator('[data-action="nod"]').isDisabled()); await second.close();
  report.checks.push('second-renderer-refused');
  // Renderer loss is uncertain, and a replacement page does not replay the interrupted motion.
  await call('avatar_action', { action: 'wave-right' }); await page.close();
  let state;
  for (let n = 0; n < 40; n++) { state = await call('avatar_status'); if (state.fault) break; await new Promise(r => setTimeout(r, 50)); }
  assert.equal(state.recent.at(-1).state, 'uncertain'); assert.equal(state.recent.at(-1).inputs_reset, false);
  const mobile = await context.newPage(); await mobile.setViewportSize({ width: 390, height: 844 }); await mobile.goto(initial.preview_url);
  await mobile.waitForFunction(() => window.avatarRendererState?.().connected);
  const recovered = await call('avatar_status'); assert.equal(recovered.active, null); assert.equal(recovered.fault, null);
  assert(await mobile.evaluate(() => document.documentElement.scrollWidth <= innerWidth));
  await mobile.screenshot({ path: path.join(output, 'mobile.png'), fullPage: true });
  await mobile.locator('[data-model="hoodie"]').click();
  await mobile.waitForFunction(() => window.avatarRendererState().model_id === 'hoodie' && !document.querySelector('[data-action="nod"]').disabled);
  await mobile.locator('[data-action="nod"]').click();
  await mobile.waitForFunction(() => document.querySelector('#outcome').textContent.includes('播放完成'));
  report.checks.push('disconnect-uncertain-no-replay', 'mobile-layout-selection-action');
  assert.deepEqual(report.errors, []);
} catch (error) {
  report.failure = error.message;
  throw error;
} finally {
  await browser?.close(); await client.close();
  await fs.writeFile(path.join(output, 'report.json'), JSON.stringify(report, null, 2));
}
console.log({ models: report.models.length, actions: report.actions.length, expressions: report.expressions.length, checks: report.checks.length, errors: report.errors });
