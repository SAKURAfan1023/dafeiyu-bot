import { Player } from './player/index.js';
import { ActionPlayer } from './player/actions.js';
import { SpeechPlayer } from './player/speech.js';
import { ease, poseTargets, layerJoints, customAction } from './motion.mjs';

const canvas = document.querySelector('#model');
export const player = new Player(canvas, { idle: true, followPointer: 'canvas', lang: 'zh' });
const speech = new SpeechPlayer(), jobs = new Map();
window.avatarPlayer = player;
let socket, stage, revision, modelId, connected = false, speechOwner, pointerBase;
const listeners = new Set();
export const onConnection = fn => { listeners.add(fn); return () => listeners.delete(fn); };
export const isConnected = () => connected;
export const showPortrait = () => Object.assign(player.view, stage?.default_view ?? { head: true, zoom: 2.9, x: 0, y: .14 });
const connection = message => listeners.forEach(fn => fn({ connected, message, model_id: modelId }));
const send = data => { if (socket?.readyState === WebSocket.OPEN) socket.send(JSON.stringify({ model_id: modelId, revision, ...data })); };
const reply = (id, extra = {}) => send({ id, ok: true, ...extra });
const phase = (job, value) => send({ type: 'phase', target: job.id, phase: value });
const pointer = () => {
  const owns = [...jobs.values()].some(j => j.visualActive && j.visualStarted !== null);
  if (owns) { pointerBase ??= player.followPointer; player.followPointer = false; }
  else if (pointerBase !== undefined) { player.followPointer = pointerBase; pointerBase = undefined; }
};
export const unlockAudio = () => speech.unlock();
speech.onState = () => {
  send({ type: 'audio_state', ready: speech.running });
  if (!speech.running && speechOwner) fail(speechOwner, 'AUDIO_PLAYBACK_FAILED');
};

function finish(job, ok = true, error_code) {
  if (!jobs.delete(job.id)) return;
  clearTimeout(job.timer); clearTimeout(job.visualTimer);
  if (speechOwner === job) { speechOwner = null; speech.stop(); }
  if (job.resources.has('expression')) player.setExpression(null);
  pointer(); player.resize();
  reply(job.id, { inputs_reset: ok, ...(error_code ? { error_code } : {}) });
}
function maybeFinish(job) { if (!job.speechActive && !job.visualActive) finish(job); }
function fail(job, code, reset = true) { finish(job, reset, code); }
function endVisual(job) {
  if (!job.visualActive) return;
  job.visualActive = false; clearTimeout(job.visualTimer);
  if (job.resources.has('expression')) player.setExpression(null);
  for (const key of job.visual_resources) job.resources.delete(key);
  phase(job, 'visual_done'); pointer(); maybeFinish(job);
}
function beginVisual(job) {
  if (!job.visualActive || job.visualStarted !== null) return;
  job.visualStarted = performance.now(); pointer();
  if (job.action && !['look-around', 'wave-left', 'wave-right'].includes(job.action)) job.actionPlayer.play(job.action);
  if (job.duration_seconds !== null) job.visualTimer = setTimeout(() => endVisual(job), job.duration_seconds * 1000);
}
function heardEnd(job) {
  if (!jobs.has(job.id) || !job.speechActive) return;
  job.speechActive = false;
  if (speechOwner === job) speechOwner = null;
  for (const key of job.speech_resources) job.resources.delete(key);
  phase(job, 'speech_done');
  if (job.visualActive && job.visual && job.visualStarted !== null) {
    job.releaseStarted = performance.now(); phase(job, 'releasing');
    job.releaseWeight = ease((job.releaseStarted - job.visualStarted) / 1000 / (job.visual.transition_seconds ?? .35));
    job.visualTimer = setTimeout(() => endVisual(job), (job.visual.return_seconds ?? .85) * 1000);
  } else if (job.visualActive && job.visualStarted === null) endVisual(job);
  maybeFinish(job);
}

function blend(frame, input, weight, job, joints) {
  for (const [name, value] of Object.entries(poseTargets(input, stage))) {
    const staticMouth = ['mouthOpen', 'vowel'].includes(name) && input.expression && ![...jobs.values()].some(j => j.resources.has(name));
    if (!job.resources.has(name) && !staticMouth) continue;
    frame.params[name] = ['eyeLOpen', 'eyeROpen'].includes(name) ? frame.params[name] * (1 + (value - 1) * weight) : frame.params[name] + (value - frame.params[name]) * weight;
  }
  if (input.expression && job.resources.has('expression')) player.setExpression(input.expression === 'neutral' ? null : input.expression, (input.intensity ?? 1) * weight);
  if (input.arms) for (const [layer, chain] of Object.entries(layerJoints(input.arms, stage, weight))) {
    const side = stage.joints[layer][0].control.split('_')[0];
    if (job.resources.has('arm:' + side)) joints[layer] = chain;
  }
}

player.use({ update(frame) {
  const joints = {};
  for (const job of [...jobs.values()]) {
    if (!job.visualActive || job.visualStarted === null) continue;
    const t = (performance.now() - job.visualStarted) / 1000;
    if (job.visual) {
      const enter = job.visual.transition_seconds ?? .35;
      let weight = ease(t / enter);
      if (job.releaseStarted !== null) weight = job.releaseWeight * ease(1 - (performance.now() - job.releaseStarted) / 1000 / (job.visual.return_seconds ?? .85));
      else if (!job.speech && t >= enter + job.visual.hold_seconds) weight = ease((job.duration_seconds - t) / job.visual.return_seconds);
      blend(frame, job.visual, weight, job, joints);
    } else if (['look-around', 'wave-left', 'wave-right'].includes(job.action)) {
      const sample = customAction(job.action, t, job.duration_seconds);
      blend(frame, sample.pose, sample.weight, job, joints);
    } else {
      const offsets = job.actionPlayer.update(frame.dt);
      for (const [key, value] of Object.entries(offsets)) if (job.resources.has(key)) frame.params[key] += value;
      if (job.resources.has('moveY')) frame.move.y += job.actionPlayer.y;
    }
  }
  player.setJointPose(joints);
  if (speechOwner?.speechActive) { frame.params.mouthOpen = speech.read(); frame.params.vowel = speech.vowel(); }
} });

export function connect(token) {
  if (socket && [WebSocket.OPEN, WebSocket.CONNECTING].includes(socket.readyState)) return;
  socket = new WebSocket(`ws://${location.host}/ws?token=${token}`);
  socket.onmessage = async event => {
    const c = JSON.parse(event.data);
    try {
      if (c.operation === 'load') {
        connected = false; connection('正在加载模型…');
        for (const job of [...jobs.values()]) finish(job, false);
        player.setJointPose({}); player.setExpression(null);
        stage = await fetch(c.stage_url).then(r => r.json());
        await player.load(c.model_url);
        modelId = c.model_id; revision = c.revision; showPortrait();
        connected = true; reply(c.id, { inputs_reset: true });
        send({ type: 'audio_state', ready: speech.running }); connection('模型已连接'); return;
      }
      if (!connected || c.model_id !== modelId || c.revision !== revision) throw Error('Model identity changed');
      if (c.type?.startsWith('speech_')) {
        const job = jobs.get(c.target);
        if (!job?.speechActive || speechOwner !== job) return;
        if (c.type === 'speech_error') { fail(job, c.error_code); return; }
        if (c.type === 'speech_end') { if (!job.chunks) throw Error('Empty audio'); job.stream.end(); return; }
        if (c.type !== 'speech_chunk' || c.index !== job.chunks || c.sample_rate !== 24000 || typeof c.pcm !== 'string' || c.pcm.length > 44000 || job.chunks >= 400) throw Error('Invalid audio stream');
        const bytes = atob(c.pcm), samples = new Float32Array(bytes.length / 2);
        if (!bytes.length || bytes.length % 2 || bytes.length > 32768 || (job.samples + samples.length) / 24000 >= 58) throw Error('Audio limit reached');
        for (let i = 0; i < samples.length; i++) { let n = bytes.charCodeAt(i * 2) | bytes.charCodeAt(i * 2 + 1) << 8; if (n >= 32768) n -= 65536; samples[i] = n / 32768; }
        job.chunks++; job.samples += samples.length; job.stream.push(samples); return;
      }
      if (c.operation === 'stop') {
        for (const job of [...jobs.values()].filter(j => !c.target || j.id === c.target)) {
          if (c.scope !== 'visual' && job.speechActive) { heardEnd(job); if (speechOwner === job) speechOwner = null; speech.stop(); }
          if (c.scope !== 'speech') endVisual(job);
          maybeFinish(job);
        }
        reply(c.id, { inputs_reset: true }); return;
      }
      if (!['pose', 'action', 'live'].includes(c.operation)) throw Error('Unknown operation');
      const resources = [...c.visual_resources, ...c.speech_resources];
      if (resources.some(k => [...jobs.values()].some(j => j.resources.has(k)))) throw Error('Renderer busy');
      if (c.speech && (!speech.running || speechOwner)) throw Error('Audio is not ready');
      const job = { ...c, resources: new Set(resources), visualActive: c.visual_resources.length > 0, speechActive: !!c.speech,
        visualStarted: null, releaseStarted: null, actionPlayer: new ActionPlayer(), chunks: 0, samples: 0 };
      jobs.set(c.id, job);
      job.timer = setTimeout(() => fail(job, 'RENDERER_TIMEOUT'), c.speech ? 245000 : c.duration_seconds * 1000 + 2500);
      if (!c.speech || c.sync === 'now') beginVisual(job);
      if (c.speech) {
        speechOwner = job;
        job.stream = speech.beginStream({
          onStart: () => { if (jobs.has(job.id) && job.speechActive) { phase(job, 'playing'); beginVisual(job); } },
          onEnd: () => heardEnd(job),
          onFail: () => { if (jobs.has(job.id) && job.speechActive) fail(job, 'AUDIO_PLAYBACK_FAILED'); },
        });
      }
    } catch (error) {
      const job = jobs.get(c.target);
      if (job) fail(job, 'AUDIO_PLAYBACK_FAILED');
      else send({ id: c.id, ok: false, error_code: 'RENDERER_REJECTED' });
      connection(error.message);
    }
  };
  socket.onclose = event => {
    connected = false;
    for (const job of [...jobs.values()]) finish(job, false);
    speech.stop(); player.setJointPose({}); player.setExpression(null);
    connection(event.reason === 'Renderer already attached' ? '已有其他预览连接。关闭另一页后点击重新连接。' : '连接已断开，动作未自动重放。');
  };
}
player.onContextLost = () => { connected = false; for (const job of [...jobs.values()]) finish(job, false); socket?.close(); connection('图形上下文丢失，请刷新预览。'); };
window.avatarRendererState = () => ({ model_id: modelId, revision, connected, active: jobs.keys().next().value ?? null, jobs: [...jobs.values()].map(j => ({ id: j.id, action_id: j.action_id, speech: j.speechActive, visual: j.visualActive, started: j.visualStarted, chunks: j.chunks })), audio_ready: speech.running, mouth: speech.read(), vowel: speech.vowel() });
