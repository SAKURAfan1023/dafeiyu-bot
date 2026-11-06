import { connect, isConnected, onConnection, player, showPortrait, unlockAudio } from './renderer.mjs';
const $ = selector => document.querySelector(selector);
const token = location.hash.slice(1) || window.avatarToken;
let status, pending = false, expressionKey;
const labels = { sailor: '水手服', hoodie: '帽衫', researcher: '研究员', 'ocean-dress': '海洋礼装', 'classic-maid': '经典女仆' };
const actions = [['nod', '点头'], ['shake', '摇头'], ['tilt', '侧头倾听'], ['hop', '轻跃'], ['shy', '含蓄低头'], ['look-around', '自然环视'], ['wave-left', '左手招呼'], ['wave-right', '右手招呼']];
const directions = [['yaw', '头部左右'], ['pitch', '头部俯仰'], ['tilt', '头部歪头'], ['gaze_x', '注视左右'], ['gaze_y', '注视上下'], ['lean', '身体轻倾'], ...['left', 'right'].flatMap((side, i) => [['shoulder', '肩部轻举'], ['elbow', '肘部弯曲'], ['wrist', '手腕轻摆']].map(([key, label]) => [side + '_' + key, (i ? '右' : '左') + label]))];
const features = [['left_close', '左眼闭合', 0], ['right_close', '右眼闭合', 0], ['mouth_open', '嘴部开合', 0], ['vowel', '圆口/宽口', -1], ['brow_left', '左眉高低', -1], ['brow_right', '右眉高低', -1]];
for (const [container, fields] of [['#directions', directions], ['#features', features]]) for (const [id, label, min = -1] of fields) {
  const row = document.createElement('label'); const input = document.createElement('input'); const output = document.createElement('output');
  input.id = id; input.type = 'range'; input.min = min; input.max = 1; input.step = '.01'; input.value = 0; output.textContent = '0.00';
  input.oninput = () => { output.textContent = Number(input.value).toFixed(2); if (container === '#features') $('#override-face').checked = true; };
  row.append(label, input, output); $(container).append(row);
}
$('#intensity').oninput = () => $('#intensity').nextElementSibling.textContent = Number($('#intensity').value).toFixed(2);

async function read(endpoint) {
  const response = await fetch('/api/' + endpoint, { headers: { 'X-Avatar-Token': token } });
  if (!response.ok) throw Error('请使用 MCP 返回的完整本机预览地址。');
  return response.json();
}

async function invoke(tool, input = {}) {
  pending = true; update();
  try {
    const response = await fetch('/api/tool', { method: 'POST', headers: { 'Content-Type': 'application/json', 'X-Avatar-Token': token },
      body: JSON.stringify({ tool, input: { ...input, ...(['avatar_stop', 'avatar_status'].includes(tool) ? {} : { call_id: crypto.randomUUID(), expected_model: status?.model_id, expected_session: status?.session_id }) } }) });
    const result = await response.json(); $('#result').textContent = JSON.stringify(result, null, 2);
    if (!result.ok) throw Error(result.error.code + '：' + result.error.message);
    status = await read('state');
    $('#outcome').textContent = tool === 'avatar_stop' ? '已停止，复位已确认。' : tool === 'avatar_select' ? '形象已切换。' : '已接受，正在播放；完成后恢复自然状态。';
  } catch (error) { $('#outcome').textContent = error.message; }
  finally { pending = false; update(); }
}

for (const [id, label] of Object.entries(labels)) {
  const button = document.createElement('button'); button.className = 'character'; button.dataset.model = id;
  const img = new Image(); img.src = '/models/' + id + '/cover.png'; img.alt = label; const text = document.createElement('span'); text.textContent = label;
  button.append(img, text); button.onclick = () => invoke('avatar_select', { model_id: id }); $('#characters').append(button);
}
function renderExpressions(profiles) {
  const previous = $('#expression').value;
  $('#expressions').replaceChildren(); $('#expression').replaceChildren();
  const groups = new Map();
  for (const [id, profile] of Object.entries(profiles)) {
    if (!groups.has(profile.category)) {
      const group = document.createElement('div'); group.className = 'expression-category';
      const label = document.createElement('small'); label.textContent = profile.category;
      const buttons = document.createElement('div'); buttons.className = 'buttons'; group.append(label, buttons);
      $('#expressions').append(group); groups.set(profile.category, buttons);
    }
    const option = document.createElement('option'); option.value = id; option.textContent = profile.label; $('#expression').append(option);
    const button = document.createElement('button'); button.textContent = profile.label; button.title = profile.usage; button.dataset.pose = id;
    button.onclick = () => { $('#expression').value = id; invoke('avatar_pose', { expression: id, intensity: profile.intensity,
      transition_seconds: profile.transition_seconds, hold_seconds: profile.hold_seconds, return_seconds: profile.return_seconds }); };
    groups.get(profile.category).append(button);
  }
  $('#expression').value = previous in profiles ? previous : 'neutral';
}
for (const [id, label] of actions) {
  const button = document.createElement('button'); button.textContent = label; button.dataset.action = id; button.onclick = () => invoke('avatar_action', { action: id }); $('#actions').append(button);
}
$('#audio-unlock').onclick = unlockAudio;
$('#say').onclick = () => invoke('avatar_say', { text: $('#speech-text').value });
$('#perform').onclick = () => invoke('avatar_perform', { speech: { text: $('#speech-text').value }, visual: { expression: $('#expression').value } });
$('#stop-speech').onclick = () => invoke('avatar_stop', { scope: 'speech' });
$('#stop').onclick = () => invoke('avatar_stop');
$('#reconnect').onclick = () => connect(token);
$('#full').onclick = () => Object.assign(player.view, { head: false, x: 0, y: 0, zoom: 1 });
$('#face').onclick = showPortrait;
$('#zoom-in').onclick = () => player.view.zoom = Math.min(4, player.view.zoom * 1.2);
$('#zoom-out').onclick = () => player.view.zoom = Math.max(.6, player.view.zoom / 1.2);
$('#apply').onclick = () => {
  const value = id => Number($('#' + id).value);
  const eyes = { gaze_x: value('gaze_x'), gaze_y: value('gaze_y') }, face = {};
  if ($('#override-face').checked) { for (const id of ['left_close', 'right_close']) eyes[id] = value(id); for (const id of ['mouth_open', 'vowel', 'brow_left', 'brow_right']) face[id] = value(id); }
  invoke('avatar_pose', { head: { yaw: value('yaw'), pitch: value('pitch'), tilt: value('tilt') }, eyes, body: { lean: value('lean') },
    arms: Object.fromEntries(['left', 'right'].map(side => [side, Object.fromEntries(['shoulder', 'elbow', 'wrist'].map(joint => [joint, value(side + '_' + joint)]))])),
    expression: $('#expression').value, intensity: value('intensity'), ...($('#override-face').checked ? { features: face } : {}),
    transition_seconds: value('enter'), hold_seconds: value('hold'), return_seconds: value('return') });
};

function update() {
  const key = JSON.stringify(status?.expression_profiles);
  if (status?.expression_profiles && key !== expressionKey) { expressionKey = key; renderExpressions(status.expression_profiles); }
  const busy = pending || !isConnected() || !status?.renderer_ready || !!status?.switching;
  document.querySelectorAll('[data-pose],[data-action],#apply').forEach(button => button.disabled = busy || !!status?.fault);
  document.querySelectorAll('[data-model]').forEach(button => { button.disabled = busy || !!status?.active; button.setAttribute('aria-pressed', String(button.dataset.model === status?.model_id)); });
  const voice = status?.voice;
  const speechBusy = status?.active_actions?.some(j => j.resources.includes('audio'));
  $('#voice-state').textContent = !voice?.configured ? '语音未配置。使用 --voice-config 启动后可试听。' : `${voice.label} · ${({ warming: '本机预热中', generating: '正在生成', playing: '正在说话', releasing: '正在回位', idle: '已就绪', failed: '生成失败，可重新尝试' })[voice.phase] ?? voice.phase}${voice.audio_ready ? '' : ' · 请先开启声音'}`;
  $('#audio-unlock').disabled = !!voice?.audio_ready;
  $('#audio-unlock').textContent = voice?.audio_ready ? '声音已开启' : '开启声音';
  $('#say').disabled = $('#perform').disabled = busy || !voice?.configured || !voice?.audio_ready || speechBusy || !!status?.fault;
  $('#stop-speech').disabled = pending || !speechBusy;
  $('#stop').disabled = pending || !isConnected() || !status?.active;
  if (status) { $('#model-name').textContent = status.model_name; $('#credits').textContent = status.model_id === 'classic-maid' ? '原角色：上善无形；女仆设计：ZipZipPipe；本项目 AI 重绘与绑定。经典款素材单独遵循 CC BY-NC-SA 4.0。' : '本项目 AI 原创角色素材，非 DeepSeek 官方形象。'; }
}
onConnection(state => { $('#connection').textContent = state.message; update(); });
if (!token) $('#connection').textContent = '请从 MCP 状态工具打开完整预览地址。'; else connect(token);
async function poll() {
  try {
    const previous = status; status = await read('state');
    if (previous?.active && !status.active) {
      const ended = status.recent.find(r => r.action_id === previous.active.action_id);
      if (ended) $('#outcome').textContent = ended.state === 'completed' ? '播放完成，复位已确认。' : ended.state === 'cancelled' ? '已停止，复位已确认。' : '复位未确认，请检查连接状态。';
    }
    if (status.fault) $('#outcome').textContent = '上一次复位未确认，请检查连接并重新选择形象。';
    update();
  } catch (error) { $('#connection').textContent = error.message; }
  setTimeout(poll, 250);
}
poll();
