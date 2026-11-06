import fs from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { spawn } from 'node:child_process';
import { randomBytes } from 'node:crypto';
import { z } from 'zod';
import { AvatarError } from './contracts.mjs';

const configSchema = z.object({
  python: z.string().min(1), model: z.string().min(1), cache: z.string().min(1),
  label: z.string().min(1).max(48).default('清甜少女'),
  instruct: z.string().min(1).max(600), speaker: z.string().regex(/^[A-Za-z_]{1,32}$/).default('Vivian'),
  seed: z.number().int().min(0).max(4294967295).nullable().default(1729),
}).strict();
const failure = code => new AvatarError(code, 'Local voice failed; inspect the private worker log. No automatic replay.');

/** Owns exactly one offline worker and one bounded utterance; never downloads a model. */
export class LocalVoice {
  static async create(configFile) {
    if (!configFile) return null;
    const filename = path.resolve(configFile), base = path.dirname(filename);
    const result = configSchema.safeParse(JSON.parse(await fs.readFile(filename, 'utf8')));
    if (!result.success) throw new AvatarError('VOICE_CONFIG_INVALID', 'Invalid voice configuration');
    const config = result.data;
    // path.resolve preserves the venv's executable symlink; realpath would break its environment.
    for (const name of ['python', 'model', 'cache']) config[name] = path.resolve(base, config[name]);
    await fs.access(config.python, fs.constants.X_OK);
    const model = JSON.parse(await fs.readFile(path.join(config.model, 'config.json'), 'utf8'));
    if (!['voice_design', 'custom_voice'].includes(model.tts_model_type)) throw new AvatarError('VOICE_CONFIG_INVALID', 'Use a local Qwen3 VoiceDesign or CustomVoice directory');
    await fs.mkdir(config.cache, { recursive: true, mode: 0o700 });
    return new LocalVoice(config, filename);
  }

  constructor(config, filename) {
    this.config = config; this.filename = filename; this.phase = 'idle'; this.ready = false;
    this.metrics = {}; this.closed = false; this.child = null; this.pending = null; this.warm = null;
  }
  status() { return { configured: true, ready: this.ready, label: this.config.label, phase: this.phase, sample_rate: 24000, ...this.metrics }; }

  prewarm() {
    if (this.closed) return Promise.reject(failure('VOICE_CLOSED'));
    if (this.ready) return Promise.resolve();
    if (this.warm) return this.warm;
    this.phase = 'warming';
    const child = spawn(this.config.python, ['-I', fileURLToPath(new URL('../voice/qwen_worker.py', import.meta.url)), this.config.model, this.filename], {
      cwd: this.config.cache, stdio: ['pipe', 'pipe', 'pipe'],
      env: { PATH: process.env.PATH ?? '/usr/bin:/bin', HOME: this.config.cache, HF_HOME: path.join(this.config.cache, 'hf'), HF_HUB_OFFLINE: '1', TRANSFORMERS_OFFLINE: '1', HF_HUB_DISABLE_TELEMETRY: '1', PYTHONDONTWRITEBYTECODE: '1', TOKENIZERS_PARALLELISM: 'false' },
    });
    this.child = child;
    let buffer = '';
    const warm = this.warm = new Promise((resolve, reject) => {
      const timer = setTimeout(() => fail('VOICE_WARMUP_TIMEOUT'), 180000);
      let ready = false;
      const fail = code => {
        if (this.child !== child) return;
        clearTimeout(timer); this.child = null; this.ready = false; this.warm = null;
        this.phase = this.closed || code === 'VOICE_CANCELLED' ? 'idle' : 'failed';
        child.kill('SIGKILL'); reject(failure(code));
        this.pending?.reject(failure(code)); this.pending = null;
      };
      this.kill = () => fail('VOICE_CANCELLED');
      child.once('error', () => fail('VOICE_WORKER_FAILED'));
      child.once('exit', () => fail('VOICE_WORKER_EXITED'));
      // A bounded, private log; stdout is exclusively protocol, never an MCP diagnostic stream.
      let logged = 0;
      const log = fs.open(path.join(this.config.cache, 'worker.log'), 'w', 0o600);
      child.stderr.on('data', bytes => { if (logged < 1000000) { logged += bytes.length; log.then(f => f.write(bytes)).catch(() => {}); } });
      child.once('close', () => { log.then(f => f.close()).catch(() => {}); });
      child.stdout.setEncoding('utf8');
      child.stdout.on('data', chunk => {
        if (this.child !== child) return;
        buffer += chunk;
        try {
          let newline;
          while ((newline = buffer.indexOf('\n')) >= 0) {
            if (newline > 60000) throw Error();
            const packet = JSON.parse(buffer.slice(0, newline)); buffer = buffer.slice(newline + 1);
            if (!ready) {
              if (packet.type !== 'ready' || packet.protocol !== 2 || packet.sample_rate !== 24000) throw Error();
              ready = true; clearTimeout(timer); this.ready = true; this.phase = 'idle'; resolve();
            } else {
              if (!this.pending) throw Error();
              this.pending.packet(packet);
            }
          }
          if (buffer.length > 60000) throw Error();
        } catch { fail('VOICE_PROTOCOL_FAILED'); }
      });
    });
    // Prewarming is also started without an await by the host; retain observable failure in status.
    warm.catch(() => {});
    return warm;
  }

  async stream(text, onChunk, signal) {
    if (signal.aborted) throw failure('VOICE_CANCELLED');
    const abort = () => this.kill?.();
    signal.addEventListener('abort', abort, { once: true });
    try {
      await this.prewarm();
      if (signal.aborted) throw failure('VOICE_CANCELLED');
      if (this.pending) throw failure('VOICE_BUSY');
      this.phase = 'generating'; this.metrics = { chunks: 0, audio_seconds: 0 };
      const id = randomBytes(16).toString('hex'), started = Date.now();
      await new Promise((resolve, reject) => {
        const timer = setTimeout(() => { this.kill?.(); reject(failure('VOICE_GENERATION_TIMEOUT')); }, 180000);
        const settle = (fn, value) => { clearTimeout(timer); this.pending = null; fn(value); };
        this.pending = {
          reject: error => settle(reject, error),
          packet: packet => {
            if (packet.id !== id) throw Error();
            if (packet.type === 'chunk') {
              if (packet.index !== this.metrics.chunks || packet.sample_rate !== 24000 || typeof packet.pcm !== 'string' || !/^(?:[A-Za-z0-9+/]{4})*(?:[A-Za-z0-9+/]{2}==|[A-Za-z0-9+/]{3}=)?$/.test(packet.pcm) || packet.pcm.length > 44000) throw Error();
              const bytes = Buffer.from(packet.pcm, 'base64');
              if (!bytes.length || bytes.length > 32768 || bytes.length % 2 || bytes.toString('base64') !== packet.pcm || this.metrics.chunks >= 400) throw Error();
              this.metrics.chunks++; this.metrics.audio_seconds += bytes.length / 48000;
              if (this.metrics.audio_seconds >= 58) throw Error();
              this.metrics.first_chunk_seconds ??= (Date.now() - started) / 1000;
              onChunk({ index: packet.index, pcm: packet.pcm, sample_rate: 24000 });
            } else if (packet.type === 'end' && packet.ok === true && packet.chunks === this.metrics.chunks && packet.chunks > 0 && Number.isFinite(packet.seconds) && Math.abs(packet.seconds - this.metrics.audio_seconds) < .001 && Number.isFinite(packet.synthesis_seconds) && packet.synthesis_seconds >= 0) {
              this.metrics.synthesis_seconds = packet.synthesis_seconds;
              settle(resolve);
            } else if (packet.type === 'end' && packet.ok === false) { this.phase = 'failed'; settle(reject, failure('TTS_FAILED')); }
            else throw Error();
          },
        };
        this.child.stdin.write(JSON.stringify({ id, text }) + '\n', error => { if (error) this.kill?.(); });
      });
      return { ...this.metrics };
    } finally { signal.removeEventListener('abort', abort); }
  }

  async close() {
    this.closed = true;
    const child = this.child;
    this.kill?.();
    if (child && child.exitCode === null && child.signalCode === null) await new Promise(resolve => { const timer = setTimeout(resolve, 3000); child.once('exit', () => { clearTimeout(timer); resolve(); }); });
  }
}
