'use strict';
const $ = id => document.getElementById(id);
// Section anchors must never replace the authorization fragment on reload.
const fragment = location.hash.slice(1);
const controlToken = /^[a-f0-9-]{72}$/i.test(fragment) ? fragment : sessionStorage.getItem('qq-control-token') || '';
if(controlToken) sessionStorage.setItem('qq-control-token', controlToken);
history.replaceState(null, '', '/');
let state, initial = true, targetSignature = '', contactSignature = '', pending = false;
const targetDraft = new Map();
const dirtyForms = new Map(), syncedForms = new Map();
const formNames = {connection:'连接配置',reply:'范围与回复',artwork:'插画定时',image:'生图',visual:'识图'};
const actionForms = {saveConnection:'connection',connect:'connection',save:'reply',start:'reply',saveArtwork:'artwork',saveImageGeneration:'image',saveVisualTools:'visual'};
const credentialFields = {connection:['token','key'],image:['imageGenZhipuKey','imageGenCloudflareToken'],visual:['googleVisionKey']};
let requestSequence = 0, activeActions = 0, actionError = '';
let runtimeSignature = '';
// JSON object key order is not stable across server responses.
function fingerprint(value) {
  if(Array.isArray(value)) return '['+value.map(fingerprint).join(',')+']';
  if(value && typeof value==='object') return '{'+Object.keys(value).sort().map(key=>JSON.stringify(key)+':'+fingerprint(value[key])).join(',')+'}';
  return JSON.stringify(value);
}
function formSnapshot(group) {
  const c=state.config;
  const values={connection:[c.endpoint,c.expectedSelfID],reply:[c.ai,state.persona,c.targets,c.onlineEnabled,c.visionEnabled,c.memoryEnabled,state.memoryOptions,c.groupParticipationEnabled,c.groupParticipationEvery],artwork:[state.artwork,c.targets.map(t=>[t.number,t.group,t.name,t.enabled])],image:state.imageGeneration,visual:state.visualTools};
  return fingerprint([c.expectedSelfID,values[group]]);
}
function shouldSync(group) {
  const snapshot=formSnapshot(group), draft=dirtyForms.get(group);
  if(draft) { if(draft.base===snapshot) draft.revision=state.configurationRevision; return false; }
  if(syncedForms.get(group)===snapshot) return false;
  syncedForms.set(group,snapshot); return true;
}
function syncForms() {
  for(const [group,fields] of Object.entries(credentialFields)) {
    if(fields.some(id=>$(id).value) && !dirtyForms.has(group)) dirtyForms.set(group,{base:formSnapshot(group),revision:state.configurationRevision});
  }
  if(shouldSync('connection')) { $('endpoint').value=state.config.endpoint; $('account').value=state.config.expectedSelfID; }
  if(shouldSync('visual')) { $('visionProvider').value=state.visualTools?.provider??'deepseek'; $('googleWebEnabled').checked=state.visualTools?.googleWebEnabled??false; }
  if(shouldSync('image')) {
    const settings=state.imageGeneration??{};
    $('imageGenEnabled').checked=settings.enabled??false; $('imageGenPrimary').value=settings.primary??'zhipu';
    $('imageGenFallback').checked=settings.fallbackEnabled??true; $('imageGenAccount').value=settings.cloudflareAccountID??'';
  }
  if(shouldSync('reply')) {
    const ai=state.config.ai, persona=state.persona, memory=state.memoryOptions;
    for(const [id,value] of Object.entries({model:ai.model,prompt:ai.prompt,daily:ai.dailyLimit,cooldown:ai.cooldownSeconds,sendDaily:ai.sendLimits?.daily??100,chatDaily:ai.sendLimits?.perChatDaily??30,globalInterval:ai.sendLimits?.globalIntervalSeconds??3,workStart:ai.workStart,workEnd:ai.workEnd,groupParticipationEvery:state.config.groupParticipationEvery??10,personaStyle:persona.style??'teasing',maxCharacters:persona.maxCharacters,banter:persona.banter,stickerIntervalSeconds:persona.stickerIntervalSeconds,stickerEveryReplies:persona.stickerEveryReplies??3,memoryMessages:memory.messageThreshold,memoryCharacters:memory.characterThreshold,memoryMinutes:memory.intervalMinutes,memoryBudget:memory.retrievalCharacters})) $(id).value=value;
    for(const id of ['onlineEnabled','visionEnabled','memoryEnabled','groupParticipationEnabled']) $(id).checked=state.config[id]??false;
    $('workHoursEnabled').checked=ai.workHoursEnabled; $('stickersEnabled').checked=persona.stickersEnabled;
    targetDraft.clear(); targetSignature='';
  }
  renderArtwork(shouldSync('artwork'));
  const conflicts=[...dirtyForms].filter(([group,draft])=>draft.base!==formSnapshot(group)).map(([group])=>formNames[group]);
  text('draftStatus', conflicts.length ? `配置冲突：${conflicts.join('、')}已在别处修改。你的草稿仍保留，但不会覆盖新设置。请记录需要保留的修改，再放弃草稿并载入最新配置。` : dirtyForms.size ? `未提交：${[...dirtyForms.keys()].map(k=>formNames[k]).join('、')}。请使用对应区域的保存按钮；开始回复使用已保存配置。` : '所有显示设置均已同步；保存配置不会自动启动。');
  $('discardDrafts').hidden=dirtyForms.size===0;
  text('replyDraftStatus',dirtyForms.has('reply')?'范围或回复设置有未提交修改。':'范围与回复设置已同步；开始回复才会实际运行。');
}

function showActionError(message) { actionError=message; text('error',message); }
function validateNumericInputs(ids) {
  for(const id of ids) {
    const input=$(id);
    if(input.disabled) continue;
    input.required=true;
    if(!input.reportValidity()) return false;
  }
  return true;
}
function text(id, value) { const element=$(id), next=String(value??''); if(element.textContent!==next) element.textContent=next; }
async function request(action) {
  const sequence=++requestSequence;
  const response = await fetch(action ? '/api/action' : '/api/status', {
    method: action ? 'POST' : 'GET', cache: 'no-store',
    headers: {'X-QQ-Control': controlToken, ...(action ? {'Content-Type':'application/json'} : {})},
    body: action ? JSON.stringify(action) : undefined
  });
  if (!response.ok) throw new Error(response.status === 403 ? '控制页授权已失效，请使用本次启动时显示的完整地址重新打开。' : '本机服务暂不可用，请检查是否仍在运行。');
  const result=await response.json();
  if(sequence===requestSequence) { state=result; render(); }
  return result;
}
async function act(action) {
  if (pending && !['pause','disconnect','clear','takeOver'].includes(action.action)) return false;
  actionError='';
  const group=actionForms[action.action], draft=dirtyForms.get(group);
  if(draft && draft.base!==formSnapshot(group)) { showActionError('此区域存在配置冲突，草稿尚未提交。请先载入最新配置。'); return false; }
  action={...action,configurationRevision:draft?.revision??state?.configurationRevision};
  activeActions++; pending=true; if(state) render();
  let failure='';
  try {
    const result=await request(action); failure=state!==result ? '操作期间发生了更新的控制请求，请核对当前状态；未清除草稿。' : result.error||'';
    if(failure && group && state===result && result.configurationSaved) {
      // This request committed settings but not all credentials. Keep inputs and
      // rebase to that acknowledged save so a retry does not conflict with itself.
      dirtyForms.set(group,{base:formSnapshot(group),revision:result.configurationRevision});
    }
    if(!failure && group) {
      if(['connect','saveImageGeneration','saveVisualTools'].includes(action.action)) for(const id of credentialFields[group]??[]) $(id).value='';
      dirtyForms.delete(group); syncedForms.delete(group);
    }
  } catch(e) { failure=e.message; }
  finally { activeActions--; pending=activeActions>0; if(state) render(); if(failure) showActionError(failure); }
  return !failure;
}
function button(label, action) {
  const b = document.createElement('button'); b.textContent = label;
  b.addEventListener('click', () => act(action)); return b;
}
function render() {
  text('status', state.status);
  text('connectionState',state.connected ? '账号已核对' : '等待连接'); $('connectionState').dataset.ready=state.connected;
  const activeTargets=state.config.targets.filter(t=>t.enabled).length;
  text('scopeState',`已保存范围：${activeTargets} 个会话`); $('scopeState').dataset.ready=activeTargets>0;
  text('runState',state.running ? '正在自动回复' : '已暂停 / 尚未开始'); $('runState').dataset.ready=state.running; text('error',actionError || state.error);
  text('deadline', state.runDeadline ? `将在 ${new Date(state.runDeadline*1000).toLocaleString('zh-CN')} 自动暂停` : '');
  text('queue', `等待回复：${state.queued} / ${state.queueCapacity} 条（不含正在处理的消息）`);
  for (const id of ['calls','confirmed','uncertain','rejected']) text(id,state[id]);
  const hints=state.configurationHints??[];
  $('configurationChecks').hidden=hints.length===0; text('configurationHints',hints.map(item=>'• '+item).join('\n'));
  renderRuntimeRecords();
  text('credentials',state.temporaryCredentials ? '本次运行已有临时凭证，未持久化保存。' : (state.supportsKeychain === false ? '请填写本次运行的凭证；退出后需要重新填写。' : '将使用钥匙串凭证，也可填写本次运行的临时凭证。'));
  $('connect').disabled = state.connected || state.busy || pending;
  $('disconnect').disabled = !state.connected && !state.busy;
  $('start').disabled = !state.connected || state.running || state.busy || pending;
  $('once').disabled = $('start').disabled;
  for(const id of ['endpoint','account','token','key','saveConnection']) $(id).disabled = state.connected || state.busy;
  for(const id of ['model','prompt','daily','cooldown','sendDaily','chatDaily','globalInterval','duration','personaStyle','maxCharacters','banter','stickersEnabled','stickerIntervalSeconds','stickerEveryReplies','onlineEnabled','visionEnabled','memoryEnabled','memoryMessages','memoryCharacters','memoryMinutes','memoryBudget','groupParticipationEnabled','groupParticipationEvery','workHoursEnabled','workStart','workEnd','save']) $(id).disabled = state.running || state.busy || pending;
  text('imageGenCredentials', `本次已载入：智谱 ${state.imageCredentials?.zhipu ? '有凭证' : '未载入'}；Cloudflare ${state.imageCredentials?.cloudflare ? '有凭证' : '未载入'}`);
  text('groupParticipationCounts', state.config.groupParticipationEnabled ? state.config.targets.filter(t=>t.enabled && t.group).map(t=>`${t.name}：${state.groupMessageCounts?.['group:'+t.number] ?? 0} / ${state.config.groupParticipationEvery ?? 10} 条`).join('；') || '尚未启用群聊' : '主动接话未开启；群聊仍只响应真实 @');
  text('memoryStatus', state.memoryStatus ?? '记忆等待新消息');
  text('imageGenStatus', state.imageGenerationStatus ?? '尚未调用生图');
  for(const id of ['imageGenEnabled','imageGenPrimary','imageGenFallback','imageGenZhipuKey','imageGenAccount','imageGenCloudflareToken','imageGenPersist','imageGenSave']) $(id).disabled = state.running || state.busy || pending;
  text('visualCredentials', `Google 凭证：${state.googleVisionCredential ? '已载入' : '未载入'}`);
  text('visualStatus',state.visualStatus ?? '尚未调用识图');
  for(const id of ['visionProvider','googleWebEnabled','googleVisionKey','visualPersist','visualSave']) $(id).disabled = state.running || state.busy || pending;
  if (state.supportsKeychain === false) {
    for (const id of ['imageGenPersist', 'visualPersist']) { $(id).checked = false; $(id).disabled = true; }
  }
  if(initial) {
    for(const style of state.personalities){const option=document.createElement('option');option.value=style.id;option.textContent=style.name+' · '+style.description;$('personaStyle').append(option);}
    if(state.runDeadline && state.runDeadline*1000-Date.now()>24*60*60*1000) $('duration').value='4320';
    text('stickerCount',state.stickers.length);
    $('stickerGallery').addEventListener('toggle',()=>{if($('stickerGallery').open)renderStickers(state.stickers);},{once:true});
    initial=false;
  }
  syncForms();
  const signature = JSON.stringify(state.config.targets.map(t => [t.id,t.name,t.number,t.group,t.enabled,t.personaStyle]));
  if(signature !== targetSignature) {
    $('targets').replaceChildren(); targetSignature = signature;
    for(const target of state.config.targets) {
      const key = `${target.group?'group':'private'}:${target.number}`;
      const row = document.createElement('div'); row.className='target row';
      const label = document.createElement('label'), checkbox = document.createElement('input');
      checkbox.type='checkbox'; checkbox.dataset.target=key; checkbox.checked=targetDraft.get(key) ?? target.enabled;
      checkbox.addEventListener('change',()=>targetDraft.set(key,checkbox.checked));
      label.append(checkbox,document.createTextNode(`${target.group?'群':'好友'} · ${target.name} (${target.number})`));
      const style=document.createElement('select');style.setAttribute('aria-label','本会话性格');style.dataset.target=key;
      for(const item of [{id:'default',name:'跟随默认'},...state.personalities]){const option=document.createElement('option');option.value=item.id;option.textContent=item.name;style.append(option);}
      style.value=target.personaStyle??'default';style.addEventListener('change',()=>act({action:'setPersona',target:key,personaStyle:style.value}));
      row.append(label,style,button('接管',{action:'takeOver',target:key}),button('清除记忆并暂停',{action:'clearMemory',target:key}),button('移除',{action:'remove',target:key}));
      $('targets').append(row);
    }
  }
  for(const checkbox of $('targets').querySelectorAll('input')) checkbox.disabled=state.running;
  for(const select of $('targets').querySelectorAll('select')) {
    select.disabled=state.running||state.busy||pending;
    const target=state.config.targets.find(t=>`${t.group?'group':'private'}:${t.number}`===select.dataset.target);
    select.value=target?.personaStyle??'default';
  }
  for(const row of $('targets').children) row.lastChild.disabled=state.running;
  $('memories').replaceChildren();
  for(const memory of state.memories ?? []) { const p=document.createElement('p');p.textContent=`${memory.key} · ${memory.items ?? 0} 项重点 / ${memory.pending ?? 0} 条待整理 / 容量丢弃 ${memory.dropped ?? 0} 条 · ${new Date(memory.updatedAt*1000).toLocaleString('zh-CN')}：${memory.summary}`;$('memories').append(p); }
  if(!state.memories?.length) text('memories','尚无会话记忆');
  renderContacts();
}
function renderRuntimeRecords() {
  const records=state.runtimeRecords??[], signature=JSON.stringify(records);
  if(signature===runtimeSignature) return;
  runtimeSignature=signature;
  const list=$('runtimeRecords'), scrollTop=list.scrollTop;
  list.replaceChildren(); $('runtimeEmpty').hidden=records.length>0; list.hidden=records.length===0;
  for(const item of records) {
    const row=document.createElement('li'), meta=document.createElement('div'), badge=document.createElement('span');
    const target=document.createElement('span'), time=document.createElement('time'), detail=document.createElement('div');
    meta.className='runtime-meta'; badge.className='runtime-state'; badge.dataset.state=item.state; badge.textContent=item.title;
    target.textContent=item.target; time.dateTime=new Date(item.timestamp*1000).toISOString(); time.textContent=new Date(item.timestamp*1000).toLocaleString('zh-CN');
    detail.className='runtime-detail'; detail.textContent=item.detail;
    meta.append(badge,target,time); row.append(meta,detail); list.append(row);
  }
  list.scrollTop=scrollTop;
}
function renderContacts() {
  if(!state) return;
  const search=$('search').value.trim().toLowerCase();
  const contacts=state.contacts.filter(c => !state.config.targets.some(t => `${t.group?'group':'private'}:${t.number}`===c.key) && (!search || c.number.includes(search) || c.name.toLowerCase().includes(search))).slice(0,10);
  const signature=JSON.stringify([contacts,state.running]);
  if(signature===contactSignature)return;
  contactSignature=signature; $('contacts').replaceChildren();
  for(const c of contacts){const row=document.createElement('div');row.className='target row';const name=document.createElement('span');name.textContent=`${c.group?'群':'好友'} · ${c.name} (${c.number})`;const add=button('添加',{action:'add',target:c.key});add.disabled=state.running;row.append(name,add);$('contacts').append(row);}
}
$('visualSave').addEventListener('click',async()=>{
  const action={action:'saveVisualTools',visualTools:{provider:$('visionProvider').value,googleWebEnabled:$('googleWebEnabled').checked},googleVisionKey:$('googleVisionKey').value,persistVisualCredentials:$('visualPersist').checked};
  if(await act(action)) $('googleVisionKey').value='';
});
$('imageGenSave').addEventListener('click',async()=>{
  const action={action:'saveImageGeneration',imageGeneration:{enabled:$('imageGenEnabled').checked,primary:$('imageGenPrimary').value,fallbackEnabled:$('imageGenFallback').checked,cloudflareAccountID:$('imageGenAccount').value.trim()},zhipuKey:$('imageGenZhipuKey').value,cloudflareToken:$('imageGenCloudflareToken').value,persistImageCredentials:$('imageGenPersist').checked};
  if(await act(action)) { $('imageGenZhipuKey').value='';$('imageGenCloudflareToken').value=''; }
});
$('search').addEventListener('input',renderContacts);
$('saveConnection').addEventListener('click',()=>act({action:'saveConnection',endpoint:$('endpoint').value.trim(),expectedSelfID:$('account').value.trim()}));
$('connect').addEventListener('click',async()=>{if($('endpoint').value.trim()!==state.config.endpoint || $('account').value.trim()!==state.config.expectedSelfID){showActionError('请先保存地址与账号，再连接。输入已保留。');return;}const action={action:'connect',endpoint:$('endpoint').value.trim(),expectedSelfID:$('account').value.trim(),token:$('token').value,key:$('key').value};if(await act(action)){$('token').value='';$('key').value='';}});
for(const id of ['pause','disconnect','clear']) $(id).addEventListener('click',()=>act({action:id}));
for(const action of ['start','save','once']) $(action).addEventListener('click',async()=>{
  if(action!=='save') {
    if(dirtyForms.has('reply')) { showActionError('范围与回复有未保存草稿。请先保存或放弃草稿，再开始回复。'); return; }
    await act({action:'start',singleReply:action==='once',durationMinutes:Number($('duration').value)});
    return;
  }
  const numeric=['daily','cooldown','sendDaily','chatDaily','globalInterval','maxCharacters','stickerIntervalSeconds','stickerEveryReplies','memoryMessages','memoryCharacters','memoryMinutes','memoryBudget','groupParticipationEvery','workStart','workEnd'];
  if(!validateNumericInputs(numeric)) return;
  const ai=structuredClone(state.config.ai);
  ai.model=$('model').value.trim();ai.prompt=$('prompt').value;
  ai.workHoursEnabled=$('workHoursEnabled').checked;ai.workStart=Number($('workStart').value);ai.workEnd=Number($('workEnd').value);
  ai.dailyLimit=Number($('daily').value);ai.cooldownSeconds=Number($('cooldown').value);
  ai.sendLimits={...(ai.sendLimits ?? {globalIntervalSeconds:3}),globalIntervalSeconds:Number($('globalInterval').value),daily:Number($('sendDaily').value),perChatDaily:Number($('chatDaily').value)};
  const persona={style:$('personaStyle').value,maxCharacters:Number($('maxCharacters').value),banter:Number($('banter').value),stickersEnabled:$('stickersEnabled').checked,stickerIntervalSeconds:Number($('stickerIntervalSeconds').value),stickerEveryReplies:Number($('stickerEveryReplies').value)};
  const success=await act({action:'save',persona,groupParticipationEnabled:$('groupParticipationEnabled').checked,groupParticipationEvery:Number($('groupParticipationEvery').value),onlineEnabled:$('onlineEnabled').checked,visionEnabled:$('visionEnabled').checked,memoryEnabled:$('memoryEnabled').checked,memoryOptions:{messageThreshold:Number($('memoryMessages').value),characterThreshold:Number($('memoryCharacters').value),intervalMinutes:Number($('memoryMinutes').value),retrievalCharacters:Number($('memoryBudget').value)},enabled:[...$('targets').querySelectorAll('input:checked')].map(c=>c.dataset.target),ai});
  if(success) {
    targetDraft.clear();
    text('replyDraftStatus','范围与回复设置已保存，未启动回复。');
  }
});
document.addEventListener('input',event=>{
  if(!state) return;
  const input=event.target;
  if(['search','duration','artArtistInput'].includes(input.id)||input.matches('#targets select')) return;
  const group=input.closest('#connectionPanel')?'connection':input.closest('#artworkPanel')?'artwork':input.closest('#imagePanel')?'image':input.closest('#visionPanel')?'visual':'reply';
  if(!dirtyForms.has(group)) dirtyForms.set(group,{base:formSnapshot(group),revision:state.configurationRevision});
  syncForms();
});
$('discardDrafts').addEventListener('click',()=>{
  actionError=''; dirtyForms.clear(); syncedForms.clear(); targetDraft.clear(); targetSignature='';
  for(const id of ['token','key','imageGenZhipuKey','imageGenCloudflareToken','googleVisionKey']) $(id).value='';
  render();
});
window.addEventListener('beforeunload',event=>{if(dirtyForms.size){event.preventDefault();event.returnValue='';}});
request().catch(e=>text('error',e.message));
setInterval(()=>{if(!pending)request().catch(e=>text('error',e.message));},3000);

async function renderStickers(items) {
  for(const item of items) {
    const card=document.createElement('div'), image=document.createElement('img'), link=document.createElement('a');
    image.width=120;image.height=120;image.style.objectFit='contain';image.alt=item.title;
    link.textContent=item.title+' · 来源';link.href=item.source;link.target='_blank';link.rel='noreferrer';link.style.display='block';
    const caption=document.createElement('small');caption.textContent=item.context ?? '';caption.style.display='block';
    card.style.width='160px';card.append(image,link,caption);$('stickers').append(card);
    try {
      const r=await fetch('/api/sticker/'+encodeURIComponent(item.id),{headers:{'X-QQ-Control':controlToken}});
      if(!r.ok)throw new Error('图片不可用');
      const url=URL.createObjectURL(await r.blob());image.onload=()=>URL.revokeObjectURL(url);image.src=url;
    } catch {image.alt=item.title+'（不可用）';}
  }
}

function renderArtwork(first) {
  const a=state.artwork;
  if(!a) {text('artStatus','此服务尚未更新插画功能，请使用新版服务。');return;}
  text('artStatus',`${state.artworkStatus} · 来源请求 ${state.artworkNetworkCalls} · 历史作品确认 ${state.artworkConfirmed}`);
  const roster=state.artworkArtists || a.pixivArtistIDs.map(id=>({id,name:a.artistNames?.[id] || `画师 ${id}`}));
  const rosterSignature=JSON.stringify(roster);
  if($('artArtistList').dataset.signature!==rosterSignature) {
    $('artArtistList').dataset.signature=rosterSignature;$('artArtistList').replaceChildren();
    for(const artist of roster) {
      const row=document.createElement('p'),link=document.createElement('a'),remove=button('移除',{action:'removeArtworkArtist',artistInput:artist.id});
      link.href=`https://www.pixiv.net/users/${artist.id}`;link.target='_blank';link.rel='noreferrer';link.textContent=`${artist.name}（${artist.id}）`;
      row.append(link,document.createTextNode(` · ${artist.deliveryStatus||'逐作检查公开图片可用性'} · /artist ${artist.id} `),remove);$('artArtistList').append(row);
    }
  }
  if(first) {
    $('artFrequency').value=a.scheduleFrequency||'daily';
    for(const [id,key] of Object.entries({artEnabled:'enabled',artAgent:'agentEnabled',artSchedule:'scheduleEnabled'})) $(id).checked=a[key];
    for(const [id,key] of Object.entries({artDaily:'dailyPerChat',artNetwork:'networkDailyLimit',artRepeat:'repeatDays',artLong:'minLongEdge',artShort:'minShortEdge',artBookmarks:'searchMinBookmarks',artHour:'scheduleHour',artMinute:'scheduleMinute',artZone:'scheduleTimeZone',artMode:'scheduleMode'})) $(id).value=a[key] ?? (key==='searchMinBookmarks'?1000:'');
    $('artArtists').value=a.pixivArtistIDs.join(',');
    $('artPermissions').value=Object.entries(a.imagePermissions).map(([id,url])=>`${id} ${url}`).join('\n');
  }
  const signature=JSON.stringify(state.config.targets.map(t=>[t.number,t.group,t.name,t.enabled]));
  if(first || $('artTargets').dataset.signature!==signature) {
    const selected=first ? a.scheduleTargets : [...$('artTargets').querySelectorAll('input:checked')].map(x=>x.value);
    $('artTargets').replaceChildren();$('artTargets').dataset.signature=signature;
    for(const target of state.config.targets) {
      const label=document.createElement('label'),check=document.createElement('input');
      check.type='checkbox';check.value=`${target.group?'group':'private'}:${target.number}`;check.checked=selected.includes(check.value);
      label.append(check,document.createTextNode(`${target.name} (${target.number})${target.enabled?'':' · 会话未启用，不会发送'}`));$('artTargets').append(label);
    }
  }
  for(const item of $('artworkPanel').querySelectorAll('input,select,textarea,button')) item.disabled=state.running||state.busy||pending;
  $('artHour').disabled=$('artHour').disabled||$('artFrequency').value==='hourly';
  const hasDraft=dirtyForms.has('artwork');
  $('artArtistAdd').disabled=$('artArtistAdd').disabled||hasDraft;
  for(const button of $('artArtistList').querySelectorAll('button')) button.disabled=button.disabled||hasDraft;
  text('artDraftStatus',hasDraft?'插画设置有未保存草稿。请先保存或放弃草稿，再单独增删画师。':'插画设置已同步；单独增删画师会立即保存。');
}
$('artSave').addEventListener('click',()=>{
  try {
    const numbers={artDaily:'dailyPerChat',artNetwork:'networkDailyLimit',artRepeat:'repeatDays',artLong:'minLongEdge',artShort:'minShortEdge',artBookmarks:'searchMinBookmarks',artHour:'scheduleHour',artMinute:'scheduleMinute'};
    if(!validateNumericInputs(Object.keys(numbers))) return;
    const a=structuredClone(state.artwork);
    for(const [id,key] of Object.entries({artEnabled:'enabled',artAgent:'agentEnabled',artSchedule:'scheduleEnabled'})) a[key]=$(id).checked;
    for(const [id,key] of Object.entries(numbers)) if(!$(id).disabled) a[key]=Number($(id).value);
    a.scheduleTimeZone=$('artZone').value.trim();a.scheduleMode=$('artMode').value;a.scheduleFrequency=$('artFrequency').value;
    a.scheduleTargets=[...$('artTargets').querySelectorAll('input:checked')].map(x=>x.value);
    a.pixivArtistIDs=$('artArtists').value.split(/[,，\s]+/).filter(Boolean);
    a.artistNames=Object.fromEntries(Object.entries(a.artistNames||{}).filter(([id])=>a.pixivArtistIDs.includes(id)));
    a.imagePermissions={};
    for(const line of $('artPermissions').value.split('\n').filter(x=>x.trim())) {
      const parts=line.trim().split(/\s+/);if(parts.length!==2)throw new Error('许可格式应为：画师 ID 空格 HTTPS 链接');
      a.imagePermissions[parts[0]]=parts[1];
    }
    act({action:'saveArtwork',artwork:a});
  } catch(e) {showActionError(e.message);}
});
$('artArtistAdd').addEventListener('click',async()=>{
  const input=$('artArtistInput').value.trim();
  if(!input) {showActionError('请输入 Pixiv 主页链接或数字 ID');return;}
  if(await act({action:'addArtworkArtist',artistInput:input})) $('artArtistInput').value='';
});
$('artFrequency').addEventListener('change',()=>renderArtwork(false));
