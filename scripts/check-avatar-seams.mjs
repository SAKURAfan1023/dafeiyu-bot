// Real Player renders at fixed source scale. Keep raw alpha for hole checks and enlarged head/arm evidence.
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import path from 'node:path';
import { chromium } from 'playwright';
import { AvatarRuntime } from '../packages/avatar/lib/runtime.mjs';

const output = path.resolve(process.argv[2] ?? 'local/avatar-authoring/qa-seams');
await fs.mkdir(output, { recursive: true });
const runtime = await AvatarRuntime.start({ ...(process.argv[3] ? { modelRoot: path.resolve(process.argv[3]) } : {}) });
const results = [], views = [], errors = [];
let browser;
const poses = [
  ['left', { head: { yaw: -1 } }], ['right', { head: { yaw: 1 } }],
  ['up', { head: { pitch: 1 } }], ['down', { head: { pitch: -1 } }],
  ['tilt-left', { head: { tilt: -1 } }], ['tilt-right', { head: { tilt: 1 } }],
  ['turn-blink-talk', { head: { yaw: -.85, pitch: .6, tilt: -.45 }, eyes: { left_close: .5, right_close: .5 }, features: { mouth_open: .8 } }],
  ['lean-left', { body: { lean: -1 } }], ['lean-right', { body: { lean: 1 } }],
  ['left-arm', { arms: { left: { shoulder: .4, elbow: .5, wrist: .55 } } }],
  ['right-arm', { arms: { right: { shoulder: .4, elbow: .5, wrist: -.55 } } }],
];
try {
  browser = await chromium.launch({ headless: true, ...(process.env.DAFEIYU_BROWSER_PATH ? { executablePath: process.env.DAFEIYU_BROWSER_PATH } : {}) });
  const page = await browser.newPage({ viewport: { width: 1484, height: 1578 }, deviceScaleFactor: 1 });
  page.on('pageerror', e => errors.push(e.message));
  await page.goto(runtime.url);
  const diagnosticStyle = await page.addStyleTag({ content: 'main{grid-template-columns:1026px 360px;gap:20px;max-width:none;height:1578px;padding:20px}.viewer{height:1538px}.camera,.view-state{visibility:hidden}' });
  await page.waitForFunction(() => window.avatarRendererState?.().connected);
  for (const model of runtime.catalog) {
    await runtime.dispatch('avatar_select', { model_id: model.id });
    await page.waitForTimeout(600);
    await page.locator('#model').screenshot({ path: path.join(output, `${model.id}-portrait.png`) });
    await page.evaluate(() => { avatarPlayer.idle = false; avatarPlayer.followPointer = false; Object.assign(avatarPlayer.view, { head: false, zoom: 1, x: 0, y: 0 }); });
    await page.waitForTimeout(800);
    for (const [name, input] of [['neutral', {}], ...poses]) {
      const started = await runtime.dispatch('avatar_pose', {
        expression: 'neutral', head: { yaw: 0, pitch: 0, tilt: 0 }, eyes: { gaze_x: 0, gaze_y: 0, left_close: 0, right_close: 0 },
        body: { lean: 0 }, features: { mouth_open: 0, brow_left: 0, brow_right: 0 },
        ...input, transition_seconds: .25, hold_seconds: 1, return_seconds: .25,
      });
      await page.waitForTimeout(650);
      const png = await page.locator('#model').evaluate(c => c.toDataURL('image/png').split(',')[1]);
      await fs.writeFile(path.join(output, `${model.id}-${name}.png`), Buffer.from(png, 'base64'));
      assert((await runtime.dispatch('avatar_stop', { action_id: started.action_id })).inputs_reset);
      results.push({ model: model.id, pose: name, inputs_reset: true });
    }
    const started = await runtime.dispatch('avatar_action', { action: 'look-around' });
    while (runtime.active) await page.waitForTimeout(100);
    const completed = runtime.recent.find(r => r.action_id === started.action_id);
    assert.equal(completed.state, 'completed'); assert(completed.inputs_reset);
    await page.waitForTimeout(500);
    await page.locator('#model').screenshot({ path: path.join(output, `${model.id}-returned.png`) });
    assert.equal(runtime.status().fault, null);
    console.log('Checked seams', model.id);
  }
  await diagnosticStyle.evaluate(element => element.remove());
  for (const [name, viewport] of [['normal', { width: 1300, height: 1080 }], ['mobile', { width: 390, height: 844 }]]) {
    await page.setViewportSize(viewport);
    for (const model of runtime.catalog) {
      await runtime.dispatch('avatar_select', { model_id: model.id });
      await page.evaluate(() => { avatarPlayer.idle = false; avatarPlayer.followPointer = false; });
      await page.waitForTimeout(500);
      await page.locator('#model').screenshot({ path: path.join(output, `${model.id}-${name}-portrait.png`) });
      views.push({ model: model.id, viewport: name });
    }
  }
  assert.deepEqual(errors, []);
} finally {
  await browser?.close(); await runtime.close();
  await fs.writeFile(path.join(output, 'report.json'), JSON.stringify({ results, views, errors }, null, 2));
}
