import http from 'node:http';
import { randomBytes, randomUUID, timingSafeEqual } from 'node:crypto';
import fs from 'node:fs/promises';
import path from 'node:path';
import { WebSocketServer, WebSocket } from 'ws';
import { loadCatalog, packageRoot } from './catalog.mjs';
import { AvatarError, actions, parseInput } from './contracts.mjs';
import { LocalVoice } from './voice.mjs';
import { planCommand } from './commands.mjs';

const mime = { '.html': 'text/html; charset=utf-8', '.css': 'text/css', '.js': 'text/javascript', '.mjs': 'text/javascript', '.json': 'application/json', '.png': 'image/png' };

export class AvatarRuntime {
  constructor(catalog) {
    this.catalog = catalog;
    this.model = catalog.find(m => m.id === 'classic-maid');
    this.token = randomBytes(24).toString('hex');
    this.revision = randomUUID();
    this.ready = false;
    this.switching = false;
    this.jobs = new Map();
    this.session = randomUUID();
    this.mutations = Promise.resolve();
    this.audioReady = false;
    this.fault = null;
    this.recent = [];
    this.pending = new Map();
    this.ledger = new Map();
    this.socket = null;
  }

  static async start({ port = 0, modelRoot, voiceConfig } = {}) {
    const runtime = new AvatarRuntime(await loadCatalog(modelRoot));
    runtime.voice = await LocalVoice.create(voiceConfig);
    runtime.modelRoot = modelRoot ?? path.join(packageRoot, 'models');
    runtime.server = http.createServer((req, res) => runtime.http(req, res).catch(() => { if (!res.headersSent) res.writeHead(500); res.end('Request failed'); }));
    runtime.ws = new WebSocketServer({ noServer: true, maxPayload: 32000 });
    runtime.server.on('upgrade', (req, socket, head) => {
      if (req.headers.host !== runtime.host || req.headers.origin !== runtime.origin || req.url !== '/ws?token=' + runtime.token) {
        socket.end('HTTP/1.1 403 Forbidden\r\nConnection: close\r\n\r\n'); return;
      }
      runtime.ws.handleUpgrade(req, socket, head, ws => runtime.attach(ws));
    });
    await new Promise((resolve, reject) => { runtime.server.once('error', reject); runtime.server.listen(port, '127.0.0.1', resolve); });
    runtime.host = '127.0.0.1:' + runtime.server.address().port;
    runtime.origin = 'http://' + runtime.host;
    runtime.url = runtime.origin + '/#' + runtime.token;
    runtime.voice?.prewarm();
    return runtime;
  }

  get active() { return this.jobs.values().next().value ?? null; }

  list() {
    return { models: this.catalog.map(m => ({ id: m.id, name: m.label, license: m.model.meta.license, actions, expressions: ['neutral', ...m.model.expressions.map(e => e.id)], expression_profiles: m.rig.expression_profiles, controls: m.rig.controls, ready: m.id === this.model.id && this.ready })), selected: this.model.id };
  }

  status(actionId) {
    return { session_id: this.session, model_id: this.model.id, model_name: this.model.label, revision: this.revision, renderer_ready: this.ready,
      preview_url: this.url, voice: { ...(this.voice?.status() ?? { configured: false, ready: false, phase: 'unconfigured' }), audio_ready: this.audioReady && this.ready }, active_actions: [...this.jobs.values()].map(j => this.publicAction(j)), action: actionId ? this.publicAction(this.jobs.get(actionId)) ?? this.recent.find(j => j.action_id === actionId) ?? null : undefined, switching: this.switching, active: this.publicAction(this.active), fault: this.fault,
      recent: this.recent, controls: this.model.rig.controls, actions, expressions: ['neutral', ...this.model.model.expressions.map(e => e.id)], expression_profiles: this.model.rig.expression_profiles, simulated: false,
      limitations: ['No independent finger joints', 'No camera or microphone tracking', 'LivLiv 2.5D with DaFeiYu arm joints; not a Cubism MOC model'] };
  }

  publicAction(job) {
    if (!job) return null;
    const { controller, command, request_id, ...result } = job;
    return { ...result, resources: [...job.resources], children: { ...job.children } };
  }

  async dispatch(tool, raw = {}) {
    const input = parseInput(tool, raw);
    if (tool === 'avatar_list') return this.list();
    if (tool === 'avatar_status') {
      const deadline = Date.now() + input.wait_seconds * 1000;
      while (Date.now() < deadline && (input.action_id ? this.jobs.has(input.action_id) : this.jobs.size)) await new Promise(r => setTimeout(r, 50));
      return this.status(input.action_id);
    }
    const fingerprint = JSON.stringify({ tool, input: { ...input, call_id: undefined } });
    if (input.call_id && this.ledger.has(input.call_id)) {
      const previous = this.ledger.get(input.call_id);
      if (previous.fingerprint !== fingerprint) throw new AvatarError('CALL_ID_CONFLICT', 'A call id cannot identify different commands');
      return previous.promise;
    }
    const promise = this.mutations.then(async () => {
      if (input.expected_session && input.expected_session !== this.session) throw new AvatarError('HOST_CHANGED', 'Host session changed; read status and issue a new intent');
      if (input.expected_model && input.expected_model !== this.model.id) throw new AvatarError('MODEL_CHANGED', 'The selected model changed; read status again');
      if (tool === 'avatar_stop') return this.stop(input.action_id, input.scope);
      return tool === 'avatar_select' ? this.select(input.model_id) : this.run(tool, input);
    });
    this.mutations = promise.catch(() => {});
    if (input.call_id) {
      this.ledger.set(input.call_id, { fingerprint, promise });
      if (this.ledger.size > 256) this.ledger.delete(this.ledger.keys().next().value);
    }
    return promise;
  }

  async select(id) {
    const model = this.catalog.find(m => m.id === id);
    if (!model) throw new AvatarError('MODEL_UNAVAILABLE', 'Unknown avatar');
    if (this.active || this.switching) throw new AvatarError('BUSY', 'Stop the current motion before switching');
    this.model = model;
    this.revision = randomUUID();
    this.ready = false;
    if (this.socket?.readyState === WebSocket.OPEN) await this.loadRenderer();
    return this.status();
  }

  async run(tool, input) {
    if (!this.ready) throw new AvatarError('NOT_READY', 'Open preview_url and wait for this renderer to connect');
    if (this.fault) throw new AvatarError('CONTROLLER_FAULT', 'Previous restoration was unconfirmed; explicitly reselect the avatar');
    if (this.switching) throw new AvatarError('BUSY', 'Avatar is switching');
    const command = planCommand(tool, input, this.model.rig);
    const expression = command.visual?.expression;
    if (expression && expression !== 'neutral' && !this.model.model.expressions.some(e => e.id === expression)) throw new AvatarError('EXPRESSION_UNAVAILABLE', 'This avatar has no bound artwork for that expression');
    if (command.speech) {
      if (!this.voice) throw new AvatarError('VOICE_NOT_CONFIGURED', 'Start with --voice-config and an explicit local model');
      if (!this.audioReady) throw new AvatarError('AUDIO_NOT_READY', 'Click 开启声音 in this preview first');
      if (command.visual?.features && ['mouth_open', 'vowel'].some(k => command.visual.features[k] !== undefined)) throw new AvatarError('RESOURCE_CONFLICT', 'Speech and manual mouth controls cannot own the same parameters');
    }
    const resources = [...command.visual_resources, ...command.speech_resources];
    const conflicts = [...this.jobs.values()].filter(j => j.resources.some(k => resources.includes(k)));
    if (conflicts.length && input.on_conflict !== 'replace') throw new AvatarError('BUSY', 'Requested parameters are already owned; use disjoint controls or explicitly replace');
    // All validation precedes replacement: an invalid composition never interrupts an existing owner.
    for (const job of conflicts) {
      const speechConflict = job.command.speech_resources.some(k => resources.includes(k));
      const visualConflict = job.command.visual_resources.some(k => resources.includes(k));
      await this.stop(job.action_id, speechConflict && visualConflict ? 'all' : speechConflict ? 'speech' : 'visual');
    }
    const action = { action_id: randomUUID(), model_id: this.model.id, state: 'running', kind: tool, started_at: Date.now(), duration_seconds: command.duration_seconds, stop_requested: false, resources, children: { ...(command.speech ? { speech: 'generating' } : {}), ...(command.visual_resources.length ? { visual: command.speech && command.sync === 'speech_start' ? 'waiting_audio' : 'running' } : {}) }, controller: new AbortController(), command };
    this.jobs.set(action.action_id, action);
    const operation = command.speech ? 'live' : command.action ? 'action' : 'pose';
    const completion = this.request({ operation, input, ...command, action_id: action.action_id, model_id: this.model.id, revision: this.revision }, command.speech ? 250000 : command.duration_seconds * 1000 + 4000, id => { action.request_id = id; });
    completion.then(result => this.finish(action, result.inputs_reset === true ? (action.stop_requested ? 'cancelled' : result.error_code ? 'failed' : 'completed') : 'uncertain', result.inputs_reset === true, result.error_code))
      .catch(error => this.finish(action, 'uncertain', false, error.code ?? 'RENDERER_UNCONFIRMED'));
    if (command.speech) this.synthesize(action);
    return { ...this.publicAction(action), accepted: true, inputs_reset: false };
  }

  send(command) {
    if (this.socket?.readyState !== WebSocket.OPEN) throw new AvatarError('RENDERER_DISCONNECTED', 'Renderer disconnected; command will not replay');
    this.socket.send(JSON.stringify({ ...command, model_id: this.model.id, revision: this.revision }));
  }

  async synthesize(action) {
    try {
      const metrics = await this.voice.stream(action.command.speech.text, chunk => {
        if (!this.jobs.has(action.action_id) || action.controller.signal.aborted) return;
        this.send({ type: 'speech_chunk', target: action.request_id, ...chunk });
      }, action.controller.signal);
      if (!action.controller.signal.aborted && this.jobs.has(action.action_id)) {
        action.voice_metrics = metrics;
        this.send({ type: 'speech_end', target: action.request_id });
      }
    } catch (error) {
      if (!action.controller.signal.aborted && this.jobs.has(action.action_id)) {
        action.error = error.code ?? 'TTS_FAILED';
        try { this.send({ type: 'speech_error', target: action.request_id, error_code: action.error }); }
        catch { this.finish(action, 'uncertain', false, action.error); }
      }
    }
  }

  finish(action, state, inputs_reset, code) {
    if (!this.jobs.has(action.action_id)) return;
    this.jobs.delete(action.action_id);
    action.controller.abort();
    const result = { ...this.publicAction(action), state, inputs_reset, ended_at: Date.now() };
    for (const part of Object.keys(result.children)) if (!['completed', 'cancelled', 'failed'].includes(result.children[part])) result.children[part] = state;
    if (code) result.error = code;
    if (!inputs_reset) { result.error ??= 'CLEANUP_FAILED'; this.fault = { code: 'CLEANUP_FAILED', action_id: action.action_id }; }
    this.recent = [...this.recent.slice(-19), result];
    if (action.command.speech && this.voice && ![...this.jobs.values()].some(j => j.command.speech_resources.length)) this.voice.phase = state === 'failed' ? 'failed' : 'idle';
  }

  async stop(id, scope = 'all') {
    const targets = id ? [this.jobs.get(id)].filter(Boolean) : [...this.jobs.values()];
    if (id && !targets.length) throw new AvatarError('STALE_ACTION', 'This action no longer owns the avatar');
    if (!targets.length) return { state: 'idle', inputs_reset: !this.fault, fault: this.fault };
    for (const action of targets) {
      const stopSpeech = scope !== 'visual' && action.command.speech_resources.length;
      const stopVisual = scope !== 'speech' && action.command.visual_resources.length;
      if (!stopSpeech && !stopVisual) continue;
      action.stop_requested = true;
      if (stopSpeech) action.children.speech = 'cancelled';
      if (stopVisual) action.children.visual = 'cancelled';
      if (stopSpeech) action.controller.abort();
      try {
        const result = await this.request({ operation: 'stop', target: action.request_id, scope, model_id: this.model.id, revision: this.revision }, 3000);
        if (result.inputs_reset !== true) throw new AvatarError('CLEANUP_FAILED', 'Reset was not confirmed');
      } catch (error) {
        this.finish(action, 'uncertain', false, error.code ?? 'CLEANUP_FAILED');
        throw error;
      }
      if (stopSpeech) { action.command.speech_resources = []; action.children.speech = 'cancelled'; }
      if (stopVisual) { action.command.visual_resources = []; action.children.visual = 'cancelled'; }
      action.resources = [...action.command.visual_resources, ...action.command.speech_resources];
      if (!action.resources.length) this.finish(action, 'cancelled', true);
    }
    return { state: 'stopped', scope, inputs_reset: true, ...(id && this.recent.find(j => j.action_id === id)), active_actions: [...this.jobs.values()].map(j => this.publicAction(j)) };
  }

  request(command, timeout = 20000, onId) {
    if (this.socket?.readyState !== WebSocket.OPEN) return Promise.reject(new AvatarError('RENDERER_DISCONNECTED', 'Renderer disconnected; command will not replay'));
    const id = randomUUID();
    onId?.(id);
    return new Promise((resolve, reject) => {
      const timer = setTimeout(() => { this.pending.delete(id); reject(new AvatarError('RENDERER_TIMEOUT', 'Renderer did not confirm completion')); }, timeout);
      this.pending.set(id, { resolve, reject, timer, revision: this.revision, model_id: this.model.id });
      this.socket.send(JSON.stringify({ ...command, id }));
    });
  }

  async loadRenderer() {
    this.switching = true;
    try {
      const result = await this.request({ operation: 'load', model_id: this.model.id, revision: this.revision,
        model_url: '/models/' + this.model.id + '/model.json', stage_url: '/models/' + this.model.id + '/stage.json' });
      if (result.model_id !== this.model.id || result.revision !== this.revision || !result.inputs_reset) throw new AvatarError('MODEL_MISMATCH', 'Renderer model identity was not confirmed');
      this.ready = true;
      this.fault = null;
    } finally { this.switching = false; }
  }

  attach(ws) {
    if (this.socket) { ws.close(1008, 'Renderer already attached'); return; }
    this.socket = ws;
    ws.on('message', raw => {
      try {
        const reply = JSON.parse(raw);
        if (reply.type === 'audio_state') { if (reply.model_id === this.model.id && reply.revision === this.revision) this.audioReady = reply.ready === true; return; }
        if (reply.type === 'phase') {
          const job = [...this.jobs.values()].find(j => j.request_id === reply.target);
          if (job && reply.model_id === job.model_id && reply.revision === this.revision && ['playing', 'releasing', 'speech_done', 'visual_done'].includes(reply.phase)) {
            if (reply.phase === 'visual_done') {
              job.command.visual_resources = []; if (job.children.visual !== 'cancelled') job.children.visual = 'completed';
            } else if (reply.phase === 'speech_done') {
              job.command.speech_resources = []; if (job.children.speech !== 'cancelled') job.children.speech = 'completed';
            } else {
              if (job.children.speech !== 'cancelled' && reply.phase === 'playing') job.children.speech = 'playing';
              if (reply.phase === 'releasing' && job.children.visual !== 'cancelled') job.children.visual = 'releasing';
              if (reply.phase === 'playing' && job.children.visual === 'waiting_audio') job.children.visual = 'running';
              if (this.voice) this.voice.phase = reply.phase;
            }
            job.resources = [...job.command.visual_resources, ...job.command.speech_resources];
          }
          return;
        }
        const pending = this.pending.get(reply.id);
        if (!pending) return;
        if (reply.model_id !== pending.model_id || reply.revision !== pending.revision) { ws.close(1008, 'Model identity mismatch'); return; }
        this.pending.delete(reply.id); clearTimeout(pending.timer);
        if (reply.ok === true) pending.resolve(reply);
        else pending.reject(new AvatarError(reply.error_code ?? 'RENDERER_REJECTED', 'Renderer rejected the operation'));
      } catch { ws.close(1008, 'Invalid renderer response'); }
    });
    ws.on('close', () => {
      if (this.socket !== ws) return;
      this.socket = null; this.ready = false; this.audioReady = false;
      for (const pending of this.pending.values()) { clearTimeout(pending.timer); pending.reject(new AvatarError('RENDERER_DISCONNECTED', 'Renderer lost; no automatic replay')); }
      this.pending.clear();
    });
    this.loadRenderer().catch(() => { this.ready = false; ws.close(1011, 'Model load failed'); });
  }

  authorized(value) {
    if (typeof value !== 'string') return false;
    const a = Buffer.from(value), b = Buffer.from(this.token);
    return a.length === b.length && timingSafeEqual(a, b);
  }

  async http(req, res) {
    if (req.headers.host !== this.host) { res.writeHead(403).end('Invalid host'); return; }
    const url = new URL(req.url, this.origin);
    res.setHeader('Cache-Control', 'no-store');
    res.setHeader('X-Content-Type-Options', 'nosniff');
    if (url.pathname.startsWith('/api/')) {
      if (!this.authorized(req.headers['x-avatar-token']) || (req.headers.origin && req.headers.origin !== this.origin)) { res.writeHead(403).end('Forbidden'); return; }
      res.setHeader('Content-Type', 'application/json');
      if (req.method === 'GET' && url.pathname === '/api/state') { res.end(JSON.stringify(this.status())); return; }
      if (req.method === 'GET' && url.pathname === '/api/models') { res.end(JSON.stringify(this.list())); return; }
      if (req.method === 'POST' && url.pathname === '/api/tool') {
        let body = '';
        for await (const chunk of req) { body += chunk; if (Buffer.byteLength(body) > 16000) { res.writeHead(413).end('{}'); return; } }
        try {
          const { tool, input } = JSON.parse(body);
          res.end(JSON.stringify({ ok: true, data: await this.dispatch(tool, input) }));
        } catch (error) { res.end(JSON.stringify({ ok: false, error: { code: error.code ?? 'INVALID_INPUT', message: error.message } })); }
        return;
      }
      res.writeHead(404).end('{}'); return;
    }
    if (!['GET', 'HEAD'].includes(req.method)) { res.writeHead(405).end(); return; }
    let file;
    if (url.pathname === '/') file = path.join(packageRoot, 'web/index.html');
    else if (/^\/web\/[A-Za-z0-9_./-]+$/.test(url.pathname) && !url.pathname.includes('..')) file = path.join(packageRoot, url.pathname);
    else {
      const match = url.pathname.match(/^\/models\/([a-z-]+)\/(.+)$/);
      if (match && this.catalog.find(m => m.id === match[1])?.files.has(match[2])) file = path.join(this.modelRoot, match[1], match[2]);
    }
    if (!file) { res.writeHead(404).end(); return; }
    try {
      let data = await fs.readFile(file);
      if (url.pathname === '/') data = Buffer.from(data.toString().replace('<!--LOCAL-TOKEN-->', '<script>window.avatarToken=' + JSON.stringify(this.token) + '</script>'));
      res.writeHead(200, { 'Content-Type': mime[path.extname(file)] ?? 'text/plain', 'Content-Length': data.length }); res.end(req.method === 'HEAD' ? undefined : data);
    }
    catch { res.writeHead(404).end(); }
  }

  async close() {
    if (this.active && this.ready) await this.stop().catch(() => {});
    this.socket?.terminate();
    for (const pending of this.pending.values()) { clearTimeout(pending.timer); pending.reject(new AvatarError('SHUTDOWN', 'Host stopped')); }
    this.pending.clear();
    await this.voice?.close();
    this.ws.close();
    await new Promise(resolve => this.server.close(resolve));
  }
}
