// Isolated real renderer: eye/mouth seams at rest, intermediate closure, expression and combined turn.
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import path from 'node:path';
import { chromium } from 'playwright';
import { AvatarRuntime } from '../packages/avatar/lib/runtime.mjs';
const output = path.resolve(process.argv[2] ?? 'local/avatar-authoring/qa-face');
await fs.mkdir(output, { recursive: true });
const calibration = JSON.parse(await fs.readFile('scripts/avatar-calibration.json', 'utf8'));
const runtime = await AvatarRuntime.start();
let browser;
const results = [], errors = [];
const poses = [
  ['neutral', {}],
  ['gaze', { eyes: { gaze_x: .85, gaze_y: -.5 } }],
  ['half-blink', { eyes: { left_close: .5, right_close: .5 } }],
  ['closed', { eyes: { left_close: 1, right_close: 1 } }],
  ['mouth-half', { features: { mouth_open: .3 } }],
  ['mouth-open', { features: { mouth_open: .85, vowel: -.8 } }],
  ['sad', { expression: 'sad' }],
  ['smile', { expression: 'smile' }],
  ['surprised', { expression: 'surprised' }],
  ['turn-talk', { head: { yaw: -.85, pitch: .4, tilt: -.3 }, eyes: { gaze_x: -.65, left_close: .45, right_close: .45 }, features: { mouth_open: .75 } }],
];
try {
  browser = await chromium.launch({ headless: true, ...(process.env.DAFEIYU_BROWSER_PATH ? { executablePath: process.env.DAFEIYU_BROWSER_PATH } : {}) });
  const page = await browser.newPage({ viewport: { width: 1484, height: 1578 }, deviceScaleFactor: 1 });
  page.on('pageerror', e => errors.push(e.message));
  await page.goto(runtime.url);
  await page.addStyleTag({ content: 'main{grid-template-columns:1026px 360px;gap:20px;max-width:none;height:1578px;padding:20px}.viewer{height:1538px}.camera,.view-state{visibility:hidden}' });
  await page.waitForFunction(() => window.avatarRendererState?.().connected);
  for (const model of runtime.catalog) {
    await runtime.dispatch('avatar_select', { model_id: model.id });
    assert(await page.evaluate(() => avatarPlayer.view.head === true));
    assert.equal(runtime.status().active, null);
    await page.waitForTimeout(250);
    await page.screenshot({ path: path.join(output, `${model.id}-default-portrait.png`) });
    await page.evaluate(() => { avatarPlayer.idle = false; avatarPlayer.followPointer = false; Object.assign(avatarPlayer.view, { head: false, zoom: 1, x: 0, y: 0 }); });
    const canvas = await page.locator('#model').boundingBox();
    const [cx, cy, rx, ry] = calibration[model.id].head;
    const clip = { x: canvas.x + Math.floor(cx - rx), y: canvas.y + Math.floor(cy - ry * .6), width: Math.ceil(rx * 2), height: Math.ceil(ry * 1.9) };
    for (const [name, input] of poses) {
      const started = await runtime.dispatch('avatar_pose', {
        expression: 'neutral', intensity: 1, head: { yaw: 0, pitch: 0, tilt: 0 }, body: { lean: 0 },
        ...input, transition_seconds: .25, hold_seconds: 3, return_seconds: .25,
      });
      await page.waitForTimeout(name === 'neutral' ? 1400 : 700);
      await page.screenshot({ path: path.join(output, `${model.id}-${name}.png`), clip });
      const stopped = await runtime.dispatch('avatar_stop', { action_id: started.action_id }); assert(stopped.inputs_reset);
      results.push({ model: model.id, pose: name, inputs_reset: stopped.inputs_reset });
    }
    console.log('Checked face', model.id);
  }
  assert.deepEqual(errors, []);
} finally {
  await browser?.close(); await runtime.close();
  await fs.writeFile(path.join(output, 'report.json'), JSON.stringify({ results, errors }, null, 2));
}
