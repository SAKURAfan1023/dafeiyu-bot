// Rebuild the documented joint extension from an explicit upstream checkout; no character artwork is copied.
import fs from 'node:fs/promises';
import path from 'node:path';
import os from 'node:os';
import { spawnSync } from 'node:child_process';
const source = path.resolve(process.argv[2] ?? 'local/avatar-player-source');
const output = path.resolve('packages/avatar/web/player');
const temp = await fs.mkdtemp(path.join(os.tmpdir(), 'dafeiyu-player-'));
try {
  await fs.cp(path.join(source, 'src'), path.join(temp, 'src'), { recursive: true });
  const speechFile = path.join(temp, 'src/runtime/speech.ts');
  let speech = await fs.readFile(speechFile, 'utf8');
  if (!speech.includes('beginStream(hooks: ClipHooks)')) {
    const marker = '  /** silence now: stop what plays, drop what is still loading */';
    if (!speech.includes(marker)) throw Error('Upstream SpeechPlayer changed');
    speech = speech.replace(marker, `  /** DaFeiYu: controller-owned PCM, using the existing heard clock and mouth envelope. */
  beginStream(hooks: ClipHooks) {
    this.unlock()
    const h = { ...hooks }, gen = this.gen
    if (!this.running) { h.onFail?.(); return null }
    this.owed.add(h); this.pending++
    let clip: Clip | null = null, ended = false
    return {
      push: (x: Float32Array) => { if (!ended && gen === this.gen) clip = this.play(clip, x, RATE, h) },
      end: () => {
        if (ended || gen !== this.gen) return
        ended = true; this.pending--
        if (clip) { clip.complete = true; this.update(clip); this.retire(clip) }
        else this.settle(h, false)
        this.check()
      },
    }
  }

` + marker);
    await fs.writeFile(speechFile, speech);
  }
  const puppetFile = path.join(temp, 'src/runtime/puppet.ts');
  let puppet = await fs.readFile(puppetFile, 'utf8');
  // Same clipped-role opacity correction used by agent-stage, applied once for all drawing paths.
  if (!puppet.includes('if (L.def.show || L.def.hide) alpha *= this.moodAlpha(L.def)')) {
    const draw = 'private drawLayer(L: GLLayer, tex: WebGLTexture, alpha: number, verts?: Float32Array, cut = 0) {';
    const oldOpacity = "const ma = d.show || d.hide ? this.moodAlpha(d) : 1\n      if (ma > 0.01) this.drawLayer(L, L.tex, ma)";
    if (!puppet.includes(draw) || !puppet.includes(oldOpacity)) throw Error('Upstream expression-opacity path changed');
    puppet = puppet.replace(draw, draw + '\n    if (L.def.show || L.def.hide) alpha *= this.moodAlpha(L.def)\n    if (alpha <= 0.01) return');
    puppet = puppet.replace(oldOpacity, 'this.drawLayer(L, L.tex, 1)');
  }
  const declaration = 'export class Puppet {';
  if (!puppet.includes(declaration)) throw Error('Upstream Puppet changed');
  puppet = puppet.replace(declaration, declaration + '\n  /** DaFeiYu: explicit public joint input, applied before the shared body transform. */\n  jointPose: Record<string, { pivot: [number, number]; angle: number; axis?: [number, number]; span?: number }[]> = {}\n');
  const vertex = 'let x = r[2 * i], y = r[2 * i + 1]';
  if (!puppet.includes(vertex)) throw Error('Upstream deformation loop changed');
  puppet = puppet.replace(vertex, vertex + `
        for (const joint of this.jointPose[d.id] ?? []) {
          let weight = 1
          if (joint.axis && joint.span) {
            const along = (x - joint.pivot[0]) * joint.axis[0] + (y - joint.pivot[1]) * joint.axis[1]
            const t = Math.max(0, Math.min(1, along / joint.span + 0.5))
            weight = t * t * (3 - 2 * t)
          }
          const a = joint.angle * weight * Math.PI / 180, c = Math.cos(a), s = Math.sin(a)
          const dx = x - joint.pivot[0], dy = y - joint.pivot[1]
          x = joint.pivot[0] + dx * c - dy * s
          y = joint.pivot[1] + dx * s + dy * c
        }`);
  await fs.writeFile(puppetFile, puppet);
  const entryFile = path.join(temp, 'src/index.ts');
  let entry = await fs.readFile(entryFile, 'utf8');
  const insertion = '  /** A flick at a point';
  if (!entry.includes(insertion)) throw Error('Upstream Player changed');
  entry = entry.replace(insertion, `  /** DaFeiYu joint extension. Angles are degrees; inner joint first, then its parents. */
  setJointPose(pose: Record<string, { pivot: [number, number]; angle: number; axis?: [number, number]; span?: number }[]>) {
    if (Object.keys(pose).length > 32) throw new Error('Too many joint layers')
    for (const chain of Object.values(pose)) {
      if (!Array.isArray(chain) || chain.length > 4) throw new Error('Invalid joint chain')
      for (const joint of chain) if (!Array.isArray(joint.pivot) || joint.pivot.length !== 2 ||
        ![...joint.pivot, joint.angle].every(Number.isFinite) || Math.abs(joint.angle) > 100) throw new Error('Invalid joint pose')
      for (const joint of chain) if (joint.axis && (joint.axis.length !== 2 || !joint.axis.every(Number.isFinite) ||
        !Number.isFinite(joint.span) || joint.span! < 8 || joint.span! > 160)) throw new Error('Invalid joint blend')
    }
    this.puppet.jointPose = pose
  }

` + insertion);
  await fs.writeFile(entryFile, entry);
  await fs.mkdir(output, { recursive: true });
  const config = path.join(temp, 'vite.config.mjs');
  await fs.writeFile(config, `export default {build:{outDir:${JSON.stringify(output)},emptyOutDir:true,target:'es2022',minify:true,
    lib:{entry:{index:${JSON.stringify(entryFile)},actions:${JSON.stringify(path.join(temp, 'src/runtime/actions.ts'))},speech:${JSON.stringify(path.join(temp, 'src/runtime/speech.ts'))}},formats:['es'],fileName:(_format,name)=>name+'.js'},
    rollupOptions:{output:{chunkFileNames:'chunks/[name]-[hash].js',minify:true}}}}`);
  const r = spawnSync(process.execPath, [path.join(source, 'node_modules/vite/bin/vite.js'), 'build', temp, '--config', config], { stdio: 'inherit' });
  if (r.status !== 0) throw Error('Player build failed');
  for (const name of ['LICENSE', 'NOTICE']) await fs.copyFile(path.join(source, name), path.join(output, name));
  await fs.writeFile(path.join(output, 'UPSTREAM.json'), JSON.stringify({
    repository: 'https://github.com/livliv-dev/player', commit: '0ffb70f2b815d924ab10b07fa892c413846a71cd',
    version: '0.3.0', license: 'Apache-2.0', modifications: 'Player.setJointPose and pre-body layer joint transforms; PCM streaming through SpeechPlayer heard-clock hooks; expression show/hide opacity applied once in drawLayer, including clipped roles, following agent-stage. Reproducible with scripts/build-avatar-player.mjs. No upstream or Graphite artwork included.',
  }, null, 2) + '\n');
} finally { await fs.rm(temp, { recursive: true, force: true }); }
