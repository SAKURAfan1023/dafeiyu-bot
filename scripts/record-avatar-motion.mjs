// Opaque compositing before MediaRecorder preserves alpha correctly in the review video.
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import path from 'node:path';
import { chromium } from 'playwright';
import { AvatarRuntime } from '../packages/avatar/lib/runtime.mjs';
const output = path.resolve(process.argv[2] ?? 'local/avatar-authoring/motion-video');
const portrait = process.argv[3] === '--portrait';
await fs.mkdir(output, { recursive: true });
const runtime = await AvatarRuntime.start();
let browser;
const report = [];
try {
  browser = await chromium.launch({ headless: true, ...(process.env.DAFEIYU_BROWSER_PATH ? { executablePath: process.env.DAFEIYU_BROWSER_PATH } : {}) });
  const page = await browser.newPage({ viewport: { width: 1300, height: 1080 }, deviceScaleFactor: 1 });
  await page.goto(runtime.url); await page.waitForFunction(() => window.avatarRendererState?.().connected);
  const waitEnd = async id => {
    while (runtime.active) await page.waitForTimeout(100);
    const result = runtime.recent.find(r => r.action_id === id);
    assert.equal(result.state, 'completed'); assert(result.inputs_reset);
    return { state: result.state, inputs_reset: result.inputs_reset };
  };
  for (const model of runtime.catalog) {
    await runtime.dispatch('avatar_select', { model_id: model.id });
    await page.evaluate(portrait => { avatarPlayer.idle = false; avatarPlayer.followPointer = false; Object.assign(avatarPlayer.view, { head: portrait, zoom: portrait ? 2.9 : 1, x: 0, y: portrait ? .14 : 0 }); }, portrait);
    await page.waitForTimeout(600);
    await page.evaluate(() => {
      const source = document.querySelector('#model'); const target = document.createElement('canvas'); target.width = 576; target.height = 864;
      const ctx = target.getContext('2d'); let live = true;
      function draw() { if (!live) return; ctx.fillStyle = '#edf2f7'; ctx.fillRect(0, 0, target.width, target.height);
        const s = Math.min(target.width / source.width, target.height / source.height);
        ctx.drawImage(source, (target.width - source.width * s) / 2, (target.height - source.height * s) / 2, source.width * s, source.height * s); requestAnimationFrame(draw); }
      requestAnimationFrame(draw);
      const stream = target.captureStream(24); const recorder = new MediaRecorder(stream, { mimeType: 'video/webm;codecs=vp9', videoBitsPerSecond: 2400000 }); const chunks = [];
      recorder.ondataavailable = e => chunks.push(e.data); recorder.start();
      window.finishAvatarRecording = () => new Promise(resolve => { recorder.onstop = async () => { live = false; stream.getTracks().forEach(t => t.stop());
        const reader = new FileReader(); reader.onload = () => resolve(reader.result.split(',')[1]); reader.readAsDataURL(new Blob(chunks, { type: 'video/webm' })); }; recorder.stop(); });
    });
    await page.waitForTimeout(400);
    const actions = [];
    for (const action of ['nod', 'look-around', 'wave-left', 'wave-right']) {
      const started = await runtime.dispatch('avatar_action', { action }); actions.push({ action, ...await waitEnd(started.action_id) });
      await page.waitForTimeout(350);
    }
    const bytes = await page.evaluate(() => finishAvatarRecording());
    await fs.writeFile(path.join(output, model.id + '.webm'), Buffer.from(bytes, 'base64'));
    report.push({ model: model.id, actions }); console.log('Recorded', model.id);
  }
} finally { await browser?.close(); await runtime.close(); }
await fs.writeFile(path.join(output, 'report.json'), JSON.stringify(report, null, 2));
