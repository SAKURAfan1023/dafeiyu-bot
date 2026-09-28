'use strict';
const $ = id => document.getElementById(id);
const controlToken = location.hash.slice(1) || sessionStorage.getItem('qq-control-token') || '';
if(controlToken) sessionStorage.setItem('qq-control-token', controlToken);
history.replaceState(null, '', '/');
let state, initial = true, targetSignature = '', contactSignature = '', pending = false;
function text(id, value) { $(id).textContent = value; }
async function request(action) {
  const response = await fetch(action ? '/api/action' : '/api/status', {
    method: action ? 'POST' : 'GET', cache: 'no-store',
    headers: {'X-QQ-Control': controlToken, ...(action ? {'Content-Type':'application/json'} : {})},
    body: action ? JSON.stringify(action) : undefined
  });
  if (!response.ok) throw new Error(response.status === 403 ? '控制页授权已失效，请使用本次启动时显示的完整地址重新打开。' : '本机服务暂不可用，请检查是否仍在运行。');
  state = await response.json(); render();
}
async function act(action) {
  if (pending && !['pause','disconnect','clear'].includes(action.action)) return;
  pending = true;
  try { await request(action); } catch (e) { text('error', e.message); }
  finally { pending = false; if(state) render(); }
}
function button(label, action) {
  const b = document.createElement('button'); b.textContent = label;
  b.addEventListener('click', () => act(action)); return b;
}
function render() {
  text('status', state.status); text('error', state.error);
  text('deadline', state.runDeadline ? `将在 ${new Date(state.runDeadline*1000).toLocaleString('zh-CN')} 自动暂停` : '');
  text('queue', `等待回复：${state.queued} / ${state.queueCapacity} 条（不含正在处理的消息）`);
  for (const id of ['calls','confirmed','uncertain','rejected']) text(id,state[id]);
  text('credentials',state.temporaryCredentials ? '本次运行已有临时凭证，未持久化保存。' : '将使用钥匙串凭证，也可填写本次运行的临时凭证。');
  $('connect').disabled = state.connected || state.busy || pending;
  $('disconnect').disabled = !state.connected && !state.busy;
  $('start').disabled = !state.connected || state.running || state.busy || pending;
  $('once').disabled = $('start').disabled;
  for(const id of ['account','token','key']) $(id).disabled = state.connected || state.busy;
  for(const id of ['model','prompt','daily','cooldown','sendDaily','chatDaily','globalInterval','duration','personaStyle','maxCharacters','banter','stickersEnabled','stickerIntervalSeconds','stickerEveryReplies','onlineEnabled','visionEnabled','memoryEnabled','memoryMessages','memoryCharacters','memoryMinutes','memoryBudget','groupParticipationEnabled','groupParticipationEvery','save']) $(id).disabled = state.running;
  text('imageGenCredentials', `本次已载入：智谱 ${state.imageCredentials?.zhipu ? '有凭证' : '未载入'}；Cloudflare ${state.imageCredentials?.cloudflare ? '有凭证' : '未载入'}`);
  text('groupParticipationCounts', state.config.groupParticipationEnabled ? state.config.targets.filter(t=>t.enabled && t.group).map(t=>`${t.name}：${state.groupMessageCounts?.['group:'+t.number] ?? 0} / ${state.config.groupParticipationEvery ?? 10} 条`).join('；') || '尚未启用群聊' : '主动接话未开启；群聊仍只响应真实 @');
  text('memoryStatus', state.memoryStatus ?? '记忆等待新消息');
  text('imageGenStatus', state.imageGenerationStatus ?? '尚未调用生图');
  for(const id of ['imageGenEnabled','imageGenPrimary','imageGenFallback','imageGenZhipuKey','imageGenAccount','imageGenCloudflareToken','imageGenPersist','imageGenSave']) $(id).disabled = state.running || state.busy || pending;
  text('visualCredentials', `Google 凭证：${state.googleVisionCredential ? '已载入' : '未载入'}`);
  text('visualStatus',state.visualStatus ?? '尚未调用识图');
  for(const id of ['visionProvider','googleWebEnabled','googleVisionKey','visualPersist','visualSave']) $(id).disabled = state.running || state.busy || pending;
  renderArtwork(initial);
  if(initial) {
    $('visionProvider').value = state.visualTools?.provider ?? 'deepseek';
    $('googleWebEnabled').checked = state.visualTools?.googleWebEnabled ?? false;
    $('groupParticipationEnabled').checked = state.config.groupParticipationEnabled ?? false;
    $('groupParticipationEvery').value = state.config.groupParticipationEvery ?? 10;
    const imageGen = state.imageGeneration ?? {};
    $('imageGenEnabled').checked = imageGen.enabled ?? false;
    $('imageGenPrimary').value = imageGen.primary ?? 'zhipu';
    $('imageGenFallback').checked = imageGen.fallbackEnabled ?? true;
    $('imageGenAccount').value = imageGen.cloudflareAccountID ?? '';
    $('account').value = state.config.expectedSelfID;
    const ai = state.config.ai;
    for(const [id,value] of Object.entries({model:ai.model,prompt:ai.prompt,daily:ai.dailyLimit,cooldown:ai.cooldownSeconds,sendDaily:ai.sendLimits?.daily ?? 100,chatDaily:ai.sendLimits?.perChatDaily ?? 30,globalInterval:ai.sendLimits?.globalIntervalSeconds ?? 3})) $(id).value = value;
    $('personaStyle').replaceChildren();
    for(const style of state.personalities){const option=document.createElement('option');option.value=style.id;option.textContent=style.name+' · '+style.description;$('personaStyle').append(option);}
    $('personaStyle').value=state.persona.style??'teasing';
    for(const id of ['maxCharacters','banter','stickerIntervalSeconds']) $(id).value = state.persona[id];
    if(state.runDeadline && state.runDeadline*1000 - Date.now() > 24*60*60*1000) $('duration').value = '4320';
    $('stickerEveryReplies').value = state.persona.stickerEveryReplies ?? 3;
    const memoryOptions=state.memoryOptions ?? {messageThreshold:20,characterThreshold:6000,intervalMinutes:10,retrievalCharacters:1800};
    for(const [id,key] of Object.entries({memoryMessages:'messageThreshold',memoryCharacters:'characterThreshold',memoryMinutes:'intervalMinutes',memoryBudget:'retrievalCharacters'})) $(id).value=memoryOptions[key];
    for(const id of ['onlineEnabled','visionEnabled','memoryEnabled']) $(id).checked = state.config[id] ?? false;
    $('stickersEnabled').checked = state.persona.stickersEnabled;
    text('stickerCount',state.stickers.length);
    $('stickerGallery').addEventListener('toggle',()=>{if($('stickerGallery').open)renderStickers(state.stickers);},{once:true});
    initial = false;
  }
  const signature = JSON.stringify(state.config.targets.map(t => [t.id,t.name,t.number,t.group,t.enabled,t.personaStyle]));
  if(signature !== targetSignature) {
    $('targets').replaceChildren(); targetSignature = signature;
    for(const target of state.config.targets) {
      const key = `${target.group?'group':'private'}:${target.number}`;
      const row = document.createElement('div'); row.className='target row';
      const label = document.createElement('label'), checkbox = document.createElement('input');
      checkbox.type='checkbox'; checkbox.dataset.target=key; checkbox.checked=target.enabled;
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
function renderContacts() {
  if(!state) return;
  const search=$('search').value.trim().toLowerCase();
  const contacts=state.contacts.filter(c => !state.config.targets.some(t => `${t.group?'group':'private'}:${t.number}`===c.key) && (!search || c.number.includes(search) || c.name.toLowerCase().includes(search))).slice(0,10);
  const signature=JSON.stringify([contacts,state.running]);
  if(signature===contactSignature)return;
  contactSignature=signature; $('contacts').replaceChildren();
  for(const c of contacts){const row=document.createElement('div');row.className='target row';const name=document.createElement('span');name.textContent=`${c.group?'群':'好友'} · ${c.name} (${c.number})`;const add=button('添加',{action:'add',target:c.key});add.disabled=state.running;row.append(name,add);$('contacts').append(row);}
}
$('visualSave').addEventListener('click',()=>{
  const action={action:'saveVisualTools',visualTools:{provider:$('visionProvider').value,googleWebEnabled:$('googleWebEnabled').checked},googleVisionKey:$('googleVisionKey').value,persistVisualCredentials:$('visualPersist').checked};
  $('googleVisionKey').value='';act(action);
});
$('imageGenSave').addEventListener('click',()=>{
  const action={action:'saveImageGeneration',imageGeneration:{enabled:$('imageGenEnabled').checked,primary:$('imageGenPrimary').value,fallbackEnabled:$('imageGenFallback').checked,cloudflareAccountID:$('imageGenAccount').value.trim()},zhipuKey:$('imageGenZhipuKey').value,cloudflareToken:$('imageGenCloudflareToken').value,persistImageCredentials:$('imageGenPersist').checked};
  $('imageGenZhipuKey').value='';$('imageGenCloudflareToken').value='';act(action);
});
$('search').addEventListener('input',renderContacts);
$('connect').addEventListener('click',()=>{const action={action:'connect',expectedSelfID:$('account').value.trim(),token:$('token').value,key:$('key').value};$('token').value='';$('key').value='';act(action);});
for(const id of ['pause','disconnect','clear']) $(id).addEventListener('click',()=>act({action:id}));
for(const action of ['start','save','once']) $(action).addEventListener('click',()=>{
  const ai=structuredClone(state.config.ai);
  ai.model=$('model').value.trim();ai.prompt=$('prompt').value;
  ai.dailyLimit=Number($('daily').value);ai.cooldownSeconds=Number($('cooldown').value);
  ai.sendLimits={...(ai.sendLimits ?? {globalIntervalSeconds:3}),globalIntervalSeconds:Number($('globalInterval').value),daily:Number($('sendDaily').value),perChatDaily:Number($('chatDaily').value)};
  const persona={style:$('personaStyle').value,maxCharacters:Number($('maxCharacters').value),banter:Number($('banter').value),stickersEnabled:$('stickersEnabled').checked,stickerIntervalSeconds:Number($('stickerIntervalSeconds').value),stickerEveryReplies:Number($('stickerEveryReplies').value)};
  act({action:action==='once'?'start':action,singleReply:action==='once',persona,groupParticipationEnabled:$('groupParticipationEnabled').checked,groupParticipationEvery:Number($('groupParticipationEvery').value),onlineEnabled:$('onlineEnabled').checked,visionEnabled:$('visionEnabled').checked,memoryEnabled:$('memoryEnabled').checked,memoryOptions:{messageThreshold:Number($('memoryMessages').value),characterThreshold:Number($('memoryCharacters').value),intervalMinutes:Number($('memoryMinutes').value),retrievalCharacters:Number($('memoryBudget').value)},enabled:[...$('targets').querySelectorAll('input:checked')].map(c=>c.dataset.target),ai,durationMinutes:Number($('duration').value)});
});
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
    $('artArtists').value=a.pixivArtistIDs.join(',');
    $('artPermissions').value=Object.entries(a.imagePermissions).map(([id,url])=>`${id} ${url}`).join('\n');
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
  if($('artTargets').dataset.signature!==signature) {
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
}
$('artSave').addEventListener('click',()=>{
  try {
    const a=structuredClone(state.artwork);
    for(const [id,key] of Object.entries({artEnabled:'enabled',artAgent:'agentEnabled',artSchedule:'scheduleEnabled'})) a[key]=$(id).checked;
    for(const [id,key] of Object.entries({artDaily:'dailyPerChat',artNetwork:'networkDailyLimit',artRepeat:'repeatDays',artLong:'minLongEdge',artShort:'minShortEdge',artBookmarks:'searchMinBookmarks',artHour:'scheduleHour',artMinute:'scheduleMinute'})) a[key]=Number($(id).value);
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
  } catch(e) {text('error',e.message);}
});
$('artArtistAdd').addEventListener('click',async()=>{
  const input=$('artArtistInput').value.trim();
  if(!input) {text('error','请输入 Pixiv 主页链接或数字 ID');return;}
  await act({action:'addArtworkArtist',artistInput:input});
  if(state && !state.error) $('artArtistInput').value='';
});
$('artFrequency').addEventListener('change',()=>renderArtwork(false));
