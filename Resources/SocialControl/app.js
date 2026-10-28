'use strict';
const token = location.hash.slice(1) || sessionStorage.getItem('dafeiyu-social-control') || '';
if (location.hash) sessionStorage.setItem('dafeiyu-social-control', token);
history.replaceState(null, '', location.pathname + location.search);
const $ = s => document.querySelector(s);
let platform = new URLSearchParams(location.search).get('platform') || 'xiaohongshu', viewEpoch = 0;
let state, pending = false, settingsDirty = false, tab = new URLSearchParams(location.search).get('section') || 'connect';
const numeric = new Set(['durationMinutes','maxPosts','maxModelCalls','dailyWriteLimit','intervalSeconds','readIntervalSeconds','maxCharacters']);
function node(tag, text, cls) { const n = document.createElement(tag); if (text != null) n.textContent = text; if (cls) n.className = cls; return n; }
function showError(text) { $('#error').textContent = text; $('#error').hidden = !text; }
function selectTab(value) { tab = value; document.querySelectorAll('[data-panel]').forEach(n => n.hidden = n.dataset.panel !== tab); document.querySelectorAll('[data-tab]').forEach(n => n.classList.toggle('active', n.dataset.tab === tab)); }
document.querySelectorAll('[data-tab]').forEach(n => n.onclick = () => selectTab(n.dataset.tab));
async function api(path, body, target = platform) {
  path += (path.includes('?')?'&':'?')+'platform='+encodeURIComponent(target);
  const r = await fetch(path, { method: body ? 'POST' : 'GET', headers: {'X-Social-Control': token, ...(body ? {'Content-Type':'application/json'} : {})}, body: body ? JSON.stringify(body) : undefined });
  if (!r.ok) throw new Error(r.status === 403 ? '控制页授权已失效，请从客户端重新打开。' : `请求未完成（${r.status}）`);
  return r.json();
}
async function action(name, fields = {}) {
  if (pending && !['pause','reportWarning'].includes(name)) return;
  if(!state)return;
  const target=platform, epoch=viewEpoch, revision=state.revision;
  const requestID = crypto.randomUUID(); pending = true; showError('');
  try {
    const submitted = await api('/api/action', { requestID, platform:target, action:name, revision, ...fields }, target);
    for (let i = 0; i < 300; i++) {
      const job = await api('/api/job/' + submitted.requestID, undefined, target);
      if (job.state === 'failed') throw new Error(job.error);
      if (job.state === 'complete') break;
      if (i === 299) throw new Error('操作仍在进行，请核对状态，不要重复发送。');
      await new Promise(r => setTimeout(r, 500));
    }
    if(epoch===viewEpoch)await refresh(true);
  } catch (e) { if(epoch===viewEpoch)showError(e.message); }
  finally { if(epoch===viewEpoch)pending = false; }
}
function readSettings() {
  const result = {...state.settings};
  for (const id of ['settingsForm','modelForm']) for (const [key,value] of new FormData($('#'+id))) result[key] = numeric.has(key) ? Number(value) : value;
  result.memoryEnabled = $('[name=memoryEnabled]').checked;
  return result;
}
for (const id of ['settingsForm','modelForm']) {
  $('#'+id).oninput = () => settingsDirty = true;
  $('#'+id).onsubmit = async e => { e.preventDefault(); await action('save', {settings:readSettings()}); };
}
$('#keyForm').onsubmit = async e => { e.preventDefault(); const key = $('#key').value; $('#key').value = ''; await action('credentials', {key,persistKey:$('#persistKey').checked}); };
$('#pause').onclick = () => action('pause');
$('#reportWarning').onclick = () => action('reportWarning');
$('#acknowledgeWarning').onclick = () => {if($('#warningChecked').checked)action('acknowledgeWarning',{acknowledge:true});};
$('#warningChecked').onchange = () => $('#acknowledgeWarning').disabled=!$('#warningChecked').checked||state?.busy;
$('#platform').onchange = e => {
  const next=e.target.value;
  if(settingsDirty&&!confirm('当前平台还有未保存的修改，放弃并切换？')){e.target.value=platform;return;}
  viewEpoch++;platform=next;state=null;pending=false;settingsDirty=false;
  recordsSignature=postSignature=resultsSignature=personalitiesSignature='';
  $('#results').replaceChildren();$('#records').replaceChildren();$('#post').hidden=true;
  document.querySelectorAll('form').forEach(f=>f.inert=true);
  const url=new URL(location.href);url.searchParams.set('platform',platform);history.replaceState(null,'',url.pathname+url.search);
  showError('');selectTab('connect');refresh();
};
$('#login').onclick = () => action('login');
$('#identityCheck').onclick = () => action('identity');
$('#bind').onclick = () => { if (state?.observed && confirm(`确认绑定${state.platformName}账号 ${state.observed.id}？`)) action('bind',{expectedUID:state.observed.id}); };
$('#search').onclick = () => settingsDirty ? showError('请先保存任务设置。') : action('search');
$('#recommended').onclick = () => {
  if(!state || pending || state.running || state.busy)return;
  // Keep the user's keyword, persona, endpoint, model and credentials.
  for(const name of ['mode',...numeric])$('[name='+name+']').value=state.recommendedSettings[name];
  $('[name=memoryEnabled]').checked=true;
  settingsDirty=true;showError('');
};
$('#start').onclick = () => {
  if (settingsDirty) return showError('请先保存任务设置。');
  if (state.settings.mode === 'auto' && !confirm(`开始${state.platformName}自动任务？\n主题：${state.settings.keyword}\n本轮 ${state.settings.durationMinutes} 分钟，最多读 ${state.settings.maxPosts} 条、调用模型 ${state.settings.maxModelCalls} 次。\n每日最多发送 ${state.settings.dailyWriteLimit} 次，发送至少间隔 ${state.settings.intervalSeconds} 秒。\n将按相关性判断并真实发表评论，无话可接会跳过。`)) return;
  action('start');
};
let recordsSignature = '', postSignature = '', resultsSignature = '', personalitiesSignature = '';
function render(s) {
  document.title='大肥鱼 · '+s.platformName;
  const choice=$('#platform');
  if(JSON.stringify([...choice.options].map(x=>x.value))!==JSON.stringify(s.platforms.map(x=>x.id))){choice.replaceChildren();for(const p of s.platforms){const o=node('option',p.name);o.value=p.id;choice.append(o);}}
  choice.value=s.platform;
  const blocked=Boolean(s.warningAt);
  $('#warningActions').hidden=!blocked;$('.risk-notice').classList.toggle('warning',blocked);
  $('#riskTitle').textContent=blocked?'平台警告 · 自动访问已暂停':'自动访问可能触发平台警告';
  $('#capability').textContent=s.platform==='bilibili'?'B站支持自动评论及回复一级评论；依据标题、介绍和有限评论，画面、音轨与字幕尚未分析。':'小红书支持自动评论及回复一级评论；图片和视频主体尚未分析。';
  $('#autoMode').disabled=!s.canWrite;$('#autoMode').hidden=!s.canWrite;
  $('[name=mode] option[value=review]').textContent=s.canWrite?'先写草稿 · 我来确认':'只写草稿 · 手动发布';
  for(const name of ['dailyWriteLimit','intervalSeconds'])$('[name='+name+']').disabled=!s.canWrite;
  for(const id of ['login','identityCheck','bind','start','search'])$('#'+id).disabled=blocked||s.busy||s.running;
  $('#recommended').disabled=s.busy||s.running||pending;
  $('#acknowledgeWarning').disabled=s.busy||!$('#warningChecked').checked;
  if(!blocked)$('#warningChecked').checked=false;
  document.querySelectorAll('form').forEach(f=>f.inert=false);
  $('#status').textContent = s.status; $('#indicator').classList.toggle('running',s.running);
  const remaining=Math.max(0,Math.ceil((Date.parse(s.nextReadAt||'')-Date.now())/1000)||0);
  $('#counts').textContent = `模型 ${s.modelAttempts} 次 · 今日发送尝试 ${s.writesToday} · 未知阻断 ${s.blockingUnknown}`+(remaining?` · 阅读冷却 ${remaining}s`:'');
  $('#identity').textContent = s.boundUID ? '已绑定 · ' + s.boundUID : '尚未绑定';
  $('#bind').disabled = blocked || !s.observed || s.running || s.busy;
  $('#pause').disabled = !s.running && !s.busy;
  $('#start').disabled = blocked || s.running || s.busy || !s.boundUID;
  $('#start').textContent=s.settings.mode==='auto'?'开始自动运行':s.settings.mode==='review'?'开始生成草稿':'开始浏览';
  $('#search').disabled = blocked || s.running || s.busy || !s.boundUID;
  $('#qr').hidden = !s.qr; if (s.qr) $('#qr').src = 'data:image/png;base64,' + s.qr;
  const personalities = JSON.stringify(s.personalities);
  if (personalities !== personalitiesSignature) {
    personalitiesSignature = personalities; const select = $('#personality'); select.replaceChildren();
    for (const p of s.personalities) { const option=node('option',p.name);option.value=p.id;select.append(option); }
  }
  if (!settingsDirty) for (const form of ['settingsForm','modelForm']) for (const field of $('#'+form).elements) {
    if (field.type === 'checkbox') field.checked = s.settings[field.name] !== false;
    else if (field.name === 'personality') field.value = s.settings.personality || 'custom';
    else if(field.name==='readIntervalSeconds')field.value=s.settings.readIntervalSeconds??30;
    else if (field.name && s.settings[field.name] != null) field.value = s.settings[field.name];
  }
  $('#memoryCount').textContent = `已记忆 ${s.memoryCount} 个话题 · 保留 7 天`;
  const rs = JSON.stringify(s.candidates);
  if (rs !== resultsSignature) {
    resultsSignature = rs; $('#results').replaceChildren();
    for (const p of s.candidates) { const b = node('button',p.title || '无标题内容','result'); b.append(node('small',p.author)); b.onclick = () => action('read',{content:p.id}); $('#results').append(b); }
  }
  const ps = JSON.stringify([s.post,s.memory]);
  const editingMemory = document.activeElement?.id === 'memoryNote';
  if (ps !== postSignature && !editingMemory) {
    postSignature = ps; const area = $('#post'); area.hidden = !s.post; area.replaceChildren();
    if (s.post) {
      const p=s.post; area.append(node('h2',p.title),node('p',p.text,'body'),node('p',p.coverage,'hint'));
      const comments=node('div',null,'comments');
      for(const c of p.comments) {
        const row=node('div',null,'comment');row.append(node('p',`${c.authorID===s.boundUID?'我':c.author}：${c.text}`));
        if(!c.rootID&&c.authorID!==s.boundUID){const b=node('button','回复这条');b.onclick=async()=>{await action('draft',{content:c.id});selectTab('records');};row.append(b);}
        comments.append(row);
      }
      area.append(comments);
      const memory=node('details',null,'topic-memory');memory.append(node('summary','话题记忆'));
      memory.append(node('p',s.memory?.summary||'还没有摘要，生成草稿时会自动记录。','body'));
      const label=node('label','补充 / 校正背景'),note=node('textarea');note.id='memoryNote';note.rows=3;note.maxLength=1000;note.placeholder='例如：上一条是自嘲，不是认真求助。';note.value=s.memory?.note||'';label.append(note);memory.append(label);
      const controls=node('div',null,'actions'),save=node('button','保存背景'),forget=node('button','清除摘要');
      save.onclick=()=>action('memoryNote',{content:note.value});forget.onclick=()=>{if(confirm('清除此帖的摘要和补充背景？实际发送记录与防重复限制会保留。'))action('forgetMemory');};controls.append(save,forget);memory.append(controls);area.append(memory);
      const b=node('button','生成草稿','primary'); b.onclick=async()=>{await action('draft');selectTab('records');}; area.append(b);
    }
  }
  const sig = JSON.stringify(s.records);
  const editingRecord = document.activeElement?.tagName === 'TEXTAREA' && document.activeElement.closest('#records');
  if (sig !== recordsSignature && !editingRecord) {
    recordsSignature = sig; const area=$('#records'); area.replaceChildren();
    const names={draft:'待确认',skipped:'暂不参与',sending:'发送中',accepted:'平台已接受',confirmed:'当前账号可见',uncertain:'发送结果未知',rejected:'已阻止',cancelled:'已结束'};
    if(!s.records.length) area.append(node('p','从一个感兴趣的话题开始。','hint'));
    for(const r of s.records) {
      const card=node('article',null,'card record'), heading=node('div',null,'heading'); heading.append(node('h2',r.post.title),node('span',names[r.state]||r.state,'badge')); card.append(heading);
      const parent=r.post.comments.find(c=>c.id===r.parentID); card.append(node('div',parent?`回复 ${parent.author}：${parent.text}`:'评论这条内容','target'));
      card.append(node('p',`${new Date(r.createdAt).toLocaleString()} · ${r.reason}`,'meta'));
      if(r.summary) {const d=node('details');d.append(node('summary','阅读摘要'),node('p',r.summary,'body'));card.append(d);}
      const buttons=node('div',null,'actions');
      function button(text,act,fields={},primary=false){const b=node('button',text,primary?'primary':null);b.onclick=()=>action(act,{recordID:r.id,hash:r.hash,...fields});buttons.append(b);return b;}
      if(r.state==='draft') {
        const input=node('textarea'); input.value=r.text;input.rows=3; input.maxLength=s.settings.maxCharacters;card.append(input);
        const save=button('保存修改','edit'); save.onclick=()=>action('edit',{recordID:r.id,hash:r.hash,content:input.value});
        const send=button('确认发送','approve',{},true);send.disabled=!s.canWrite||blocked;send.onclick=()=>{if(input.value!==r.text)return showError('请先保存修改，再确认发送。');if(confirm(`将向这条${s.contentName}${parent?'中的指定评论':''}发送此回复，确认？`))action('approve',{recordID:r.id,hash:r.hash});};
        button('放弃','reject');
      } else if(r.text) card.append(node('p',r.text,'body'));
      if(['draft','cancelled','skipped'].includes(r.state)&&!s.running&&!r.reservedAt) button('重新审阅','rebase');
      if(['accepted','uncertain'].includes(r.state)) button('核对结果','reconcile');
      if(r.state==='uncertain'&&!r.acknowledgedAt&&!s.running){const b=button('处理未知结果','acknowledgeUnknown');b.onclick=()=>{if(confirm('这条回复可能已发出。确认保留未知记录与额度、解除这一条阻断？不会重发原评论。'))action('acknowledgeUnknown',{recordID:r.id,acknowledge:true});};}
      const link=node('a','打开原帖');link.href=(s.platform==='bilibili'?'https://www.bilibili.com/video/':'https://www.xiaohongshu.com/explore/')+encodeURIComponent(r.post.id);link.target='_blank';link.rel='noopener noreferrer';buttons.append(link); card.append(buttons);area.append(card);
    }
  }
}
async function refresh(force=false){
  const target=platform,epoch=viewEpoch;
  try{const s=await api('/api/status',undefined,target);if(epoch!==viewEpoch)return;state=s;if(force)settingsDirty=false;render(s);if(s.error&&!pending)showError(s.error);}
  catch(e){if(epoch!==viewEpoch)return;showError(e.message);$('#status').textContent='控制台连接中断';}
}
document.querySelectorAll('form').forEach(f=>f.inert=true);
selectTab(tab);refresh();setInterval(()=>{if(!document.hidden)refresh();},1500);
