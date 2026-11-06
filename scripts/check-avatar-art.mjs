// Public HTTP controller -> browser Player. Fixed camera is diagnostic setup; snapshots are actual rendered meshes.
import { chromium } from 'playwright';
import fs from 'node:fs/promises';
import path from 'node:path';
import assert from 'node:assert/strict';
const root = path.resolve(process.argv[3] ?? 'local/avatar-authoring/qa-art');
await fs.mkdir(root, { recursive: true });
const browser = await chromium.launch({ headless: true, ...(process.env.DAFEIYU_BROWSER_PATH ? { executablePath: process.env.DAFEIYU_BROWSER_PATH } : {}) });
try {
  const page = await browser.newPage({ viewport: { width: 1484, height: 1578 }, deviceScaleFactor: 1 });
  const errors = []; page.on('pageerror', error => errors.push(error.message));
  await page.goto(process.argv[2] ?? 'http://127.0.0.1:55602/');
  await page.addStyleTag({ content: 'main{grid-template-columns:1026px 360px;gap:20px;max-width:none;height:1578px;padding:20px}.viewer{height:1538px}.camera,.view-state{visibility:hidden}' });
  await page.waitForFunction(() => window.avatarRendererState?.().connected);
  await page.evaluate(() => {
    window.avatarCall = async (tool, input = {}) => fetch('/api/tool', { method: 'POST', headers: { 'Content-Type': 'application/json', 'X-Avatar-Token': window.avatarToken }, body: JSON.stringify({ tool, input: { ...input, ...(['avatar_stop', 'avatar_status', 'avatar_list'].includes(tool) ? {} : { call_id: crypto.randomUUID() }) } }) }).then(r => r.json());
  });
  const call = async (tool, input) => { const result = await page.evaluate(([tool, input]) => avatarCall(tool, input), [tool, input]); assert(result.ok, JSON.stringify(result)); return result.data; };
  const results = [];
  for (const id of ['sailor', 'hoodie', 'researcher', 'ocean-dress', 'classic-maid']) {
    await call('avatar_select', { model_id: id });
    await page.evaluate(() => { avatarPlayer.idle = false; avatarPlayer.followPointer = false; Object.assign(avatarPlayer.view, { head: false, zoom: 1, x: 0, y: 0 }); });
    const neutral = await call('avatar_pose', { head: { yaw: 0, pitch: 0, tilt: 0 }, eyes: { gaze_x: 0, gaze_y: 0, left_close: 0, right_close: 0 }, body: { lean: 0 }, features: { mouth_open: 0, vowel: 0, brow_left: 0, brow_right: 0 }, expression: 'neutral', intensity: 0, transition_seconds: .25, hold_seconds: 8, return_seconds: .25 });
    await page.waitForTimeout(1500); await page.locator('#model').screenshot({ path: path.join(root, id + '-neutral.png') });
    assert((await call('avatar_stop')).inputs_reset);
    for (const [name, input] of [['turn', { head: { yaw: .8, pitch: .3, tilt: .15 }, eyes: { gaze_x: .3, gaze_y: -.2 } }], ['smile', { expression: 'smile', intensity: 1 }]]) {
      const action = await call('avatar_pose', { ...input, transition_seconds: .3, hold_seconds: 5, return_seconds: .5 });
      await page.waitForTimeout(800); await page.locator('#model').screenshot({ path: path.join(root, id + '-' + name + '.png') });
      assert((await call('avatar_stop', { action_id: action.action_id })).inputs_reset);
    }
    const wave = await call('avatar_action', { action: 'wave-left' });
    await page.waitForTimeout(1300); await page.locator('#model').screenshot({ path: path.join(root, id + '-wave.png') });
    const stopped = await call('avatar_stop', { action_id: wave.action_id }); assert(stopped.inputs_reset);
    const status = await call('avatar_status'); assert.equal(status.fault, null); assert.equal(status.active, null);
    results.push({ id, neutral: neutral.action_id, stopped, layers: status.controls, screenshot_size: await page.locator('#model').evaluate(c => [c.width, c.height]) });
  }
  await fs.writeFile(path.join(root, 'report.json'), JSON.stringify({ results, errors }, null, 2));
  assert.deepEqual(errors, []); console.log({ models: results.length, errors, output: root });
} finally { await browser.close(); }
