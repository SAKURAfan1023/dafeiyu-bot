'use strict';
const $ = id => document.getElementById(id);
const numericUnits={maxCharacters:'字',stickerEveryReplies:'条',stickerIntervalSeconds:'秒',stickerRepeatHours:'小时',groupParticipationEvery:'条',daily:'次',cooldown:'秒',sendDaily:'条',globalInterval:'秒',chatDaily:'条',workStart:'时',workEnd:'时',artDaily:'张',artNetwork:'次',artRepeat:'天',artLong:'px',artShort:'px',artBookmarks:'',artHour:'时',artMinute:'分',memoryMessages:'条',memoryCharacters:'字',memoryMinutes:'分钟',memoryBudget:'字',customMaxInput:'字'};
const numberInputs=[...document.querySelectorAll('input[type=number]')];
for(const input of numberInputs) {
  const label=input.labels?.[0], name=label?.textContent.trim()||input.id;
  const control=document.createElement('div');control.className='number-control';
  if(input.parentElement===label) {
    const field=document.createElement('div');field.className='number-field';
    label.before(field);field.append(label,control);label.htmlFor=input.id;
  } else input.before(control);
  input.setAttribute('aria-label',name);input.inputMode='numeric';
  const minus=document.createElement('button'),plus=document.createElement('button'),unit=document.createElement('span');
  minus.type=plus.type='button';minus.textContent='−';plus.textContent='+';
  minus.setAttribute('aria-label','减少'+name);plus.setAttribute('aria-label','增加'+name);
  unit.className='number-unit';unit.textContent=numericUnits[input.id]||'';unit.setAttribute('aria-hidden','true');unit.hidden=!unit.textContent;
  control.append(minus,input,unit,plus);
  for(const [button,direction] of [[minus,-1],[plus,1]]) button.addEventListener('click',()=>stepNumber(input,direction));
  input.addEventListener('keydown',event=>{
    if(event.key==='ArrowUp'||event.key==='ArrowDown') {
      event.preventDefault();stepNumber(input,event.key==='ArrowUp'?1:-1);
    }
  });
}
function stepNumber(input,direction) {
  if(input.disabled||input.readOnly)return;
  const min=input.min===''?-Infinity:Number(input.min),max=input.max===''?Infinity:Number(input.max);
  const value=Number.isFinite(input.valueAsNumber)?input.valueAsNumber:Number(input.defaultValue||input.min||0);
  const base=Math.min(max,Math.max(min,value)),step=Number(input.dataset.step||input.step||1);
  input.value=String(Math.min(max,Math.max(min,base+direction*step)));
  input.dispatchEvent(new Event('input',{bubbles:true}));input.focus({preventScroll:true});
}
function syncNumberControls() {
  for(const input of numberInputs) {
    const control=input.parentElement,disabled=input.disabled||input.readOnly,value=input.valueAsNumber;
    control.dataset.disabled=disabled;
    control.firstElementChild.disabled=disabled||(input.min!==''&&value<=Number(input.min));
    control.lastElementChild.disabled=disabled||(input.max!==''&&value>=Number(input.max));
  }
}
document.addEventListener('input',syncNumberControls);
new MutationObserver(records=>{if(records.some(record=>record.target.matches('input[type=number]')))syncNumberControls();})
  .observe(document.body,{subtree:true,attributes:true,attributeFilter:['disabled','readonly']});
syncNumberControls();
// Show recommended values immediately, but wait for saved settings before editing.
document.querySelector('.grid').inert=true;
// Navigation only changes visibility. All editors and drafts stay mounted.
const panelPages = {connection:'连接与运行',reply:'范围与回复',tools:'图片与工具',memory:'记忆与记录',wechat:'客户端面板',guide:'使用指南'};
let activeTool=sessionStorage.getItem('panel-tool')||'artworkPanel';
function selectTool(tool) {
  if(!['artworkPanel','imagePanel','visionPanel'].includes(tool)) tool='artworkPanel';
  activeTool=tool; sessionStorage.setItem('panel-tool',tool);
  for(const id of ['artworkPanel','imagePanel','visionPanel']) $(id).hidden=document.body.dataset.page!=='tools'||id!==tool;
  document.querySelectorAll('[data-tool]').forEach(button=>{
    if(button.dataset.tool===tool) button.setAttribute('aria-current','page');
    else button.removeAttribute('aria-current');
  });
}
function selectPanelPage(page, focus = false) {
  if(!Object.hasOwn(panelPages,page)) page='connection';
  document.querySelectorAll('[data-pages]').forEach(element=>{ element.hidden=!element.dataset.pages.split(' ').includes(page); });
  document.querySelectorAll('[data-page]').forEach(button=>{
    if(button.dataset.page===page) button.setAttribute('aria-current','page');
    else button.removeAttribute('aria-current');
  });
  document.body.dataset.platform=page==='wechat'?'wechat':'qq';
  document.body.dataset.page=page;
  $('pageTitle').textContent=panelPages[page];
  sessionStorage.setItem('panel-page',page);
  selectTool(activeTool); renderDraftControls();
  if(focus) { $('pageTitle').focus({preventScroll:true}); window.scrollTo(0,0); }
}
document.querySelectorAll('[data-page]').forEach(button=>button.addEventListener('click',()=>selectPanelPage(button.dataset.page,true)));
document.querySelectorAll('[data-tool]').forEach(button=>button.addEventListener('click',()=>selectTool(button.dataset.tool)));
document.querySelectorAll('[data-go]').forEach(button=>button.addEventListener('click',()=>{
  selectPanelPage(button.dataset.go,true);
  if(button.dataset.scroll) $(button.dataset.scroll).scrollIntoView({block:'center'});
}));
document.querySelectorAll('.help-button').forEach(button=>{
  button.addEventListener('click',()=>{
    const open=button.getAttribute('aria-expanded')!=='true';
    document.querySelectorAll('.help-button').forEach(other=>other.setAttribute('aria-expanded','false'));
    button.setAttribute('aria-expanded',String(open));
    button.parentElement.classList.toggle('dismissed',!open);
  });
  button.parentElement.addEventListener('mouseleave',()=>button.parentElement.classList.remove('dismissed'));
});
document.addEventListener('keydown',event=>{
  if(event.key==='Escape') document.querySelectorAll('.help-button').forEach(button=>{
    if(button.getAttribute('aria-expanded')==='true'||button.parentElement.matches(':hover')) button.parentElement.classList.add('dismissed');
    button.setAttribute('aria-expanded','false');
  });
});
document.addEventListener('click',event=>{
  if(!event.target.closest('.help-wrap')) document.querySelectorAll('.help-button').forEach(button=>button.setAttribute('aria-expanded','false'));
});
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
let customPersonaBase='';
let stickerSignature='', stickerRenderSequence=0, importingStickers=false;
let stickerOffset=0, stickerLoading=false;
const credentialFields = {connection:['token','key'],image:['imageGenZhipuKey','imageGenCloudflareToken'],visual:['googleVisionKey']};
function renderDraftControls() {
  const replyDirty=dirtyForms.has('reply'), page=document.body.dataset.page;
  $('draftBanner').hidden=['wechat','guide'].includes(page)||dirtyForms.size===0;
  $('replySaveBar').hidden=!replyDirty||!['reply','memory'].includes(page);
  $('save').disabled=!replyDirty||!state||state.running||state.busy||pending;
}

$('restoreDefaults').addEventListener('click',()=>{
  const page=document.body.dataset.page;
  const sections=page==='reply' ? ['personaPanel','groupPanel','replyPanel'] : page==='memory' ? ['memoryPanel'] : [activeTool];
  let changedInput;
  for(const id of sections) {
    for(const input of $(id).querySelectorAll('input[type=number],input[type=checkbox],select,#model,#prompt,#artZone')) {
      if(input.closest('#artTargets')||['imageGenPersist','visualPersist'].includes(input.id)) continue;
      const before=input.type==='checkbox' ? input.checked : input.value;
      if(input.type==='checkbox') input.checked=input.defaultChecked;
      else if(input.tagName==='SELECT') input.value=([...input.options].find(option=>option.defaultSelected)||input.options[0]).value;
      else input.value=input.defaultValue;
      if(before!==(input.type==='checkbox' ? input.checked : input.value)) changedInput=input;
    }
  }
  if(changedInput) changedInput.dispatchEvent(new Event('input',{bubbles:true}));
});

$('reviewDrafts').addEventListener('click',()=>{
  const group=dirtyForms.keys().next().value;
  if(!group) return;
  selectPanelPage({connection:'connection',reply:'reply',artwork:'tools',image:'tools',visual:'tools'}[group],true);
  if(['artwork','image','visual'].includes(group)) selectTool({artwork:'artworkPanel',image:'imagePanel',visual:'visionPanel'}[group]);
});
let requestSequence = 0, activeActions = 0, actionError = '';
const inlineError=document.createElement('div'); inlineError.id='actionErrorInline'; inlineError.className='action-error';
let runtimeSignature = '';
let lastConfirmedAt = 0, syncError = '', statusRequestPending = false;
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
    $('customPersonaName').value=persona.customName??''; $('customPersonaPrompt').value=persona.customPrompt??'';
    $('stickerTrigger').value=persona.stickerTrigger??'contextual';
    $('stickerKeywords').value=(persona.stickerKeywords??[]).join('\n');
    $('stickerRepeatHours').value=persona.stickerRepeatHours??24;
    for(const option of $('stickerEmotions').options) option.selected=(persona.stickerEmotions??['joy','smug','sleepy']).includes(option.value);
    targetDraft.clear(); targetSignature='';
  }
  renderArtwork(shouldSync('artwork'));
  for(const id of ['workStart','workEnd']) $(id).disabled=state.running||state.busy||pending||!$('workHoursEnabled').checked;
  const conflicts=[...dirtyForms].filter(([group,draft])=>draft.base!==formSnapshot(group)).map(([group])=>formNames[group]);
  text('draftStatus', conflicts.length ? `配置冲突：${conflicts.join('、')}已在别处修改，草稿保留，请重新载入。` : dirtyForms.size ? `未保存：${[...dirtyForms.keys()].map(k=>formNames[k]).join('、')}` : '设置已同步');
  $('discardDrafts').hidden=dirtyForms.size===0;
  $('discardDrafts').disabled=pending;
  renderDraftControls(); renderPersonaPicker(); renderStickerTrigger();
}
function renderStickerTrigger() {
  $('stickerEmotionFields').hidden=$('stickerTrigger').value!=='emotions';
  $('stickerKeywordFields').hidden=$('stickerTrigger').value!=='keywords';
}
$('stickerTrigger').addEventListener('input',renderStickerTrigger);


function closePersonaPicker() {
  $('personaOptions').hidden=true; $('personaPicker').setAttribute('aria-expanded','false');
}
function renderPersonaPicker() {
  const busy=!state||state.running||state.busy||pending;
  $('personaPicker').disabled=busy; $('editCustomPersona').disabled=busy||!state?.personalities.some(item=>item.id==='custom'); $('customPersonaApply').disabled=busy;
  const style=state?.personalities.find(item=>item.id===$('personaStyle').value);
  $('personaPicker').textContent=(style?.name??'雌小鬼')+(style?.id==='custom'&&$('customPersonaName').value ? ' · '+$('customPersonaName').value : '')+' ⌄';
  for(const choice of $('personaOptions').children) {choice.disabled=busy;choice.setAttribute('aria-selected',String(choice.dataset.style===$('personaStyle').value));}
  if(busy) closePersonaPicker();
}
$('personaPicker').addEventListener('click',()=>{
  const open=$('personaOptions').hidden; $('personaOptions').hidden=!open; $('personaPicker').setAttribute('aria-expanded',String(open));
  if(open) ($('personaOptions').querySelector('[aria-selected=true]')??$('personaOptions').firstElementChild)?.focus();
});
$('personaPicker').addEventListener('keydown',event=>{if(['ArrowDown','ArrowUp'].includes(event.key)){event.preventDefault();if($('personaOptions').hidden)$('personaPicker').click();}});
$('personaOptions').addEventListener('keydown',event=>{
  const choices=[...$('personaOptions').children],index=choices.indexOf(document.activeElement);
  if(['ArrowDown','ArrowUp','Home','End'].includes(event.key)) {event.preventDefault();const next=event.key==='Home'?0:event.key==='End'?choices.length-1:(index+(event.key==='ArrowDown'?1:-1)+choices.length)%choices.length;choices[next]?.focus();}
  if(event.key==='Escape'){closePersonaPicker();$('personaPicker').focus();}
  if(event.key==='Tab') closePersonaPicker();
});
document.addEventListener('click',event=>{if(!event.target.closest('.persona-picker')) closePersonaPicker();});
function openCustomPersona() {
  customPersonaBase=dirtyForms.get('reply')?.base??formSnapshot('reply');
  $('customNameInput').value=$('customPersonaName').value;
  $('customPromptInput').value=$('customPersonaPrompt').value;
  $('customMaxInput').value=$('maxCharacters').value;
  $('customStickersInput').checked=$('stickersEnabled').checked;
  text('customPersonaError','');$('customPersonaDialog').showModal();
}
$('editCustomPersona').addEventListener('click',openCustomPersona);
$('customPersonaDialog').addEventListener('close',()=>$('editCustomPersona').focus());
for(const id of ['customPersonaCancel','customPersonaClose']) $(id).addEventListener('click',()=>$('customPersonaDialog').close());
const personaPresets={chat:'你是轻松自然的聊天搭子，认真接住对方的话，通常一两句。可以接梗，但不写动作描写、不套客服语气。',gentle:'你是温柔耐心的陪伴者，先理解再回应，不说教、不强行安慰，不编造亲密关系。熟悉后可以轻轻开玩笑。',banter:'你是嘴快但讲道理的游戏搭子，抓当前话题里的具体矛盾俏皮吐槽，承认自己答错；不攻击身份、身体或家人，认真求助时收起玩笑。'};
document.querySelectorAll('[data-persona-preset]').forEach(button=>button.addEventListener('click',()=>{$('customPromptInput').value=personaPresets[button.dataset.personaPreset];$('customPromptInput').focus();}));
$('customPersonaApply').addEventListener('click',()=>{
  const name=$('customNameInput').value.trim(),prompt=$('customPromptInput').value.trim();
  if(!prompt||prompt.length>4000||name.length>40) {text('customPersonaError','请填写性格 prompt（最多 4000 字），名称最多 40 字。');return;}
  if(!$('customMaxInput').checkValidity()){$('customMaxInput').reportValidity();return;}
  if(!state||state.running||state.busy||pending){text('customPersonaError','请先暂停并等待当前操作完成。');return;}
  if(customPersonaBase!==formSnapshot('reply')){text('customPersonaError','配置已在其他窗口修改，输入已保留；请先核对最新设置。');return;}
  $('customPersonaName').value=name;$('customPersonaPrompt').value=prompt;$('personaStyle').value='custom';
  $('maxCharacters').value=$('customMaxInput').value;$('stickersEnabled').checked=$('customStickersInput').checked;
  $('personaStyle').dispatchEvent(new Event('input',{bubbles:true}));$('customPersonaDialog').close();$('editCustomPersona').focus();
});

function showActionError(message, anchor=document.activeElement.closest('.buttons,.target')) {
  actionError=message; text('error',message); inlineError.textContent=message;
  if(message && anchor?.isConnected) anchor.after(inlineError);
  else inlineError.remove();
}
function validateNumericInputs(ids) {
  for(const id of ids) {
    const input=$(id);
    if(input.disabled) continue;
    input.required=true;
    if(!input.checkValidity()) {
      const page=input.closest('[data-pages]')?.dataset.pages.split(' ')[0];
      if(page) selectPanelPage(page,true);
      for(let parent=input.parentElement;parent;parent=parent.parentElement) if(parent.tagName==='DETAILS')parent.open=true;
      input.reportValidity(); return false;
    }
  }
  return true;
}
function text(id, value) { const element=$(id), next=String(value??''); if(element.textContent!==next) element.textContent=next; }
function renderFreshness() {
  const stale=!lastConfirmedAt || !!syncError || Date.now()-lastConfirmedAt>15000;
  const updated=lastConfirmedAt ? `上次确认：${new Date(lastConfirmedAt).toLocaleTimeString('zh-CN')}。` : '尚未取得后台状态。';
  text('syncUpdated',updated);
  text('syncMessage',stale ? `${syncError || (pending?'操作仍在等待回应。':'正在重新读取状态。')}下方数值仅供参考；当前连接与运行状态尚未确认，不能据此判断机器人已暂停。` : (pending?'操作正在提交，请等待结果。':'状态已同步。'));
  $('syncStatus').dataset.stale=stale;
  $('syncStatus').dataset.pending=pending;
  if(stale) {
    for(const id of ['stepConnection','stepScope','stepRun']) $(id).dataset.complete='false';
    text('status','后台当前状态待确认');
    text('connectionState','连接待确认'); text('runState','运行待确认');
    for(const id of ['connectionState','scopeState','runState']) $(id).dataset.ready=false;
    if(!dirtyForms.size) text('draftStatus','当前显示上次读取的设置；等待后台恢复后同步。');
  }
}
async function request(action) {
  const sequence=++requestSequence;
  const controller=new AbortController();
  const timeout=setTimeout(()=>controller.abort(),action ? 60000 : 10000);
  if(!action) statusRequestPending=true;
  try {
    const response = await fetch(action?.action==='importSticker' ? '/api/import-sticker' : action ? '/api/action' : '/api/status', {
      method: action ? 'POST' : 'GET', cache: 'no-store',
      signal:controller.signal,
      headers: {'X-QQ-Control': controlToken, ...(action ? {'Content-Type':'application/json'} : {})},
      body: action ? JSON.stringify(action) : undefined
    });
    if (!response.ok) throw new Error(response.status === 403 ? '控制页授权已失效，请使用本次启动时显示的完整地址重新打开。' : '本机服务暂不可用，请检查是否仍在运行。');
    const result=await response.json();
    if(sequence===requestSequence) { state=result; lastConfirmedAt=Date.now(); syncError=''; render(); }
    return result;
  } catch(e) {
    const message=controller.signal.aborted ? (action ? '操作等待超过 60 秒，结果尚未确认；不会自动重试。请等状态恢复后核对，草稿保留。' : '读取状态超过 10 秒，将继续尝试读取。') : (e instanceof TypeError ? '无法连接本机控制服务，请检查后台进程或使用当前控制地址重新打开。' : e.message);
    if(sequence===requestSequence) { syncError=message; renderFreshness(); }
    throw new Error(message);
  } finally {
    clearTimeout(timeout);
    if(!action) statusRequestPending=false;
  }
}
async function act(action) {
  if((!lastConfirmedAt || syncError || Date.now()-lastConfirmedAt>15000) && !['pause','disconnect','clear','takeOver','clearMemory'].includes(action.action)) {
    showActionError('后台状态尚未确认，请等状态恢复后再提交；未发送本次操作，草稿保留。'); return false;
  }
  if (pending && !['pause','disconnect','clear','takeOver'].includes(action.action)) return false;
  if(dirtyForms.has('reply') && ['add','remove','setPersona'].includes(action.action)) {
    showActionError('范围与回复有未保存草稿。请先保存或放弃，再增删会话或切换会话性格。'); return false;
  }
  showActionError('');
  const group=actionForms[action.action], draft=dirtyForms.get(group);
  if(draft && draft.base!==formSnapshot(group)) { showActionError('此区域存在配置冲突，草稿尚未提交。请先载入最新配置。'); return false; }
  action={...action,configurationRevision:draft?.revision??state?.configurationRevision};
  const focused=document.activeElement;
  const errorAnchor=focused.closest('.buttons,.target');
  let focusMoved=false;
  const observeInteraction=()=>{focusMoved=true;};
  activeActions++; pending=true; if(state) render();
  for(const event of ['focusin','pointerdown','keydown']) document.addEventListener(event,observeInteraction);
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
  finally {
    for(const event of ['focusin','pointerdown','keydown']) document.removeEventListener(event,observeInteraction);
    activeActions--; pending=activeActions>0; if(state) render(); if(failure) showActionError(failure,errorAnchor);
    if(!pending && !focusMoved && focused!==document.body && document.activeElement===document.body) {
      let destination=focused.isConnected && !focused.disabled ? focused : null;
      if(!destination && action.target) {
        const selector=focused.tagName==='SELECT' ? '#targets select' : '#targets input';
        destination=[...document.querySelectorAll(selector)].find(item=>item.dataset.target===action.target);
        if(!destination) destination=$('search');
      }
      if(!destination && action.action==='removeArtworkArtist') destination=$('artArtistInput');
      if(destination && !destination.disabled) destination.focus();
    }
  }
  return !failure;
}
function button(label, action, accessibleName) {
  const b = document.createElement('button'); b.textContent = label;
  if(accessibleName) b.setAttribute('aria-label',accessibleName);
  b.addEventListener('click', () => act(action)); return b;
}
function render() {
  text('status', state.status);
  text('connectionState',state.connected ? '账号已核对' : '等待连接'); $('connectionState').dataset.ready=state.connected;
  const activeTargets=state.config.targets.filter(t=>t.enabled).length;
  text('scopeState',`已启用 ${activeTargets} 个会话`); $('scopeState').dataset.ready=activeTargets>0;
  text('runState',state.running ? '正在自动回复' : '已暂停'); $('runState').dataset.ready=state.running; text('error',actionError || state.error);
  text('deadline', state.runDeadline ? `将在 ${new Date(state.runDeadline*1000).toLocaleString('zh-CN')} 自动暂停` : '');
  text('queue', `队列 ${state.queued} / ${state.queueCapacity}`);
  for (const id of ['calls','confirmed','uncertain','rejected']) text(id,state[id]);
  const hints=state.configurationHints??[];
  $('stepConnection').dataset.complete=state.connected;
  $('stepScope').dataset.complete=state.config.targets.some(target=>target.enabled);
  $('stepRun').dataset.complete=state.running;
  $('uncertain').parentElement.dataset.alert=state.uncertain>0;
  $('configurationChecks').hidden=hints.length===0; text('configurationHints',hints.map(item=>'• '+item).join('\n'));
  renderRuntimeRecords();
  text('credentials',state.temporaryCredentials ? '临时凭证已载入' : '');
  $('connect').disabled = state.connected || state.busy || pending;
  $('disconnect').disabled = !state.connected && !state.busy;
  $('start').disabled = !state.connected || state.running || state.busy || pending;
  $('once').disabled = $('start').disabled;
  for(const id of ['endpoint','account','token','key','saveConnection']) $(id).disabled = state.connected || state.busy || pending;
  for(const id of ['model','prompt','daily','cooldown','sendDaily','chatDaily','globalInterval','duration','personaStyle','maxCharacters','banter','stickersEnabled','stickerIntervalSeconds','stickerEveryReplies','onlineEnabled','visionEnabled','memoryEnabled','memoryMessages','memoryCharacters','memoryMinutes','memoryBudget','groupParticipationEnabled','groupParticipationEvery','workHoursEnabled','workStart','workEnd','save']) $(id).disabled = state.running || state.busy || pending;
  text('imageGenCredentials', `本次已载入：智谱 ${state.imageCredentials?.zhipu ? '有凭证' : '未载入'}；Cloudflare ${state.imageCredentials?.cloudflare ? '有凭证' : '未载入'}`);
  text('groupParticipationCounts', state.config.groupParticipationEnabled ? state.config.targets.filter(t=>t.enabled && t.group).map(t=>`${t.name}：${state.groupMessageCounts?.['group:'+t.number] ?? 0} / ${state.config.groupParticipationEvery ?? 10} 条`).join('；') || '尚未启用群聊' : '');
  text('memoryStatus', state.memoryStatus==='记忆等待新消息' ? '' : state.memoryStatus);
  text('imageGenStatus', state.imageGenerationStatus==='尚未调用生图' ? '' : state.imageGenerationStatus);
  for(const id of ['imageGenEnabled','imageGenPrimary','imageGenFallback','imageGenZhipuKey','imageGenAccount','imageGenCloudflareToken','imageGenPersist','imageGenSave']) $(id).disabled = state.running || state.busy || pending;
  text('visualCredentials', `Google 凭证：${state.googleVisionCredential ? '已载入' : '未载入'}`);
  text('visualStatus',state.visualStatus==='尚未调用外置识图或搜图' ? '' : state.visualStatus);
  for(const id of ['visionProvider','googleWebEnabled','googleVisionKey','visualPersist','visualSave']) $(id).disabled = state.running || state.busy || pending;
  if (state.supportsKeychain === false) {
    for (const id of ['imageGenPersist', 'visualPersist']) { $(id).checked = false; $(id).disabled = true; }
  }
  if(initial) {
    $('personaStyle').replaceChildren(); $('personaOptions').replaceChildren();
    for(const style of state.personalities) {
      const option=document.createElement('option');option.value=style.id;option.defaultSelected=style.id==='teasing';option.textContent=style.name;option.title=style.description;$('personaStyle').append(option);
      const choice=document.createElement('button');choice.type='button';choice.role='option';choice.dataset.style=style.id;choice.textContent=style.name;choice.title=style.description;
      choice.addEventListener('click',()=>{closePersonaPicker();if(style.id==='custom') openCustomPersona();else {$('personaStyle').value=style.id;$('personaStyle').dispatchEvent(new Event('input',{bubbles:true}));$('personaPicker').focus();}});
      $('personaOptions').append(choice);
    }
    if(state.runDeadline && state.runDeadline*1000-Date.now()>24*60*60*1000) $('duration').value='4320';
    initial=false;
  }
  const catalogSignature=JSON.stringify(state.stickers.map(item=>[item.id,item.title,item.source,item.context,item.emotion,item.author,item.license,item.local,item.publicSharing]));
  if(catalogSignature!==stickerSignature) {stickerSignature=catalogSignature;text('stickerCount',state.stickers.length);if($('stickerGallery').open)renderStickers(state.stickers);}
  for(const id of ['stickerTrigger','stickerEmotions','stickerKeywords','stickerRepeatHours','stickerFiles','importEmotion','importContext','importAuthor','importLicense','importSource','importPublic','importStickers']) $(id).disabled=state.running||state.busy||pending||importingStickers;
  syncForms();
  const signature = JSON.stringify(state.config.targets.map(t => [t.id,t.name,t.number,t.group,t.enabled,t.personaStyle]));
  if(signature !== targetSignature) {
    $('targets').replaceChildren(); targetSignature = signature;
    for(const target of state.config.targets) {
      const key = `${target.group?'group':'private'}:${target.number}`;
      const targetName = `${target.group?'群':'好友'} · ${target.name} (${target.number})`;
      const row = document.createElement('div'); row.className='target row';
      const label = document.createElement('label'), checkbox = document.createElement('input');
      checkbox.type='checkbox'; checkbox.dataset.target=key; checkbox.checked=targetDraft.get(key) ?? target.enabled;
      checkbox.addEventListener('change',()=>targetDraft.set(key,checkbox.checked));
      label.append(checkbox,document.createTextNode(targetName));
      const style=document.createElement('select');style.setAttribute('aria-label',`本会话性格：${targetName}`);style.dataset.target=key;
      for(const item of [{id:'default',name:'跟随默认'},...state.personalities]){const option=document.createElement('option');option.value=item.id;option.textContent=item.name;style.append(option);}
      style.value=target.personaStyle??'default';style.addEventListener('change',()=>act({action:'setPersona',target:key,personaStyle:style.value}));
      row.append(label,style,button('接管',{action:'takeOver',target:key},`接管：${targetName}`),button('清除记忆并暂停',{action:'clearMemory',target:key},`清除记忆并暂停：${targetName}`),button('移除',{action:'remove',target:key},`移除：${targetName}`));
      $('targets').append(row);
    }
  }
  renderScopeActions();
  $('memories').replaceChildren();
  for(const memory of state.memories ?? []) { const p=document.createElement('p');p.textContent=`${memory.key} · ${memory.items ?? 0} 项重点 / ${memory.pending ?? 0} 条待整理 / 容量丢弃 ${memory.dropped ?? 0} 条 · ${new Date(memory.updatedAt*1000).toLocaleString('zh-CN')}：${memory.summary}`;$('memories').append(p); }
  if(!state.memories?.length) text('memories','尚无会话记忆');
  document.querySelector('.grid').inert=false;
  $('restoreDefaults').disabled=state.running||state.busy||pending;
  syncNumberControls(); renderFreshness();
}
function renderScopeActions() {
  const busy=state.running||state.busy||pending, hasDraft=dirtyForms.has('reply');
  for(const checkbox of $('targets').querySelectorAll('input')) checkbox.disabled=busy;
  for(const select of $('targets').querySelectorAll('select')) {
    select.disabled=busy||hasDraft;
    const target=state.config.targets.find(t=>`${t.group?'group':'private'}:${t.number}`===select.dataset.target);
    select.value=target?.personaStyle??'default';
  }
  for(const row of $('targets').children) row.lastChild.disabled=busy||hasDraft;
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
  const editingBlocked=state.running||state.busy||pending||dirtyForms.has('reply');
  const signature=JSON.stringify([contacts,editingBlocked]);
  if(signature===contactSignature)return;
  contactSignature=signature; $('contacts').replaceChildren();
  for(const c of contacts){const row=document.createElement('div');row.className='target row';const name=document.createElement('span');name.textContent=`${c.group?'群':'好友'} · ${c.name} (${c.number})`;const add=button('添加',{action:'add',target:c.key},`添加：${name.textContent}`);add.disabled=editingBlocked;row.append(name,add);$('contacts').append(row);}
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
  const numeric=['daily','cooldown','sendDaily','chatDaily','globalInterval','maxCharacters','stickerIntervalSeconds','stickerEveryReplies','stickerRepeatHours','memoryMessages','memoryCharacters','memoryMinutes','memoryBudget','groupParticipationEvery','workStart','workEnd'];
  if(!validateNumericInputs(numeric)) return;
  const ai=structuredClone(state.config.ai);
  ai.model=$('model').value.trim();ai.prompt=$('prompt').value;
  ai.workHoursEnabled=$('workHoursEnabled').checked;
  if(ai.workHoursEnabled) { ai.workStart=Number($('workStart').value);ai.workEnd=Number($('workEnd').value); }
  ai.dailyLimit=Number($('daily').value);ai.cooldownSeconds=Number($('cooldown').value);
  ai.sendLimits={...(ai.sendLimits ?? {globalIntervalSeconds:3}),globalIntervalSeconds:Number($('globalInterval').value),daily:Number($('sendDaily').value),perChatDaily:Number($('chatDaily').value)};
  const persona={style:$('personaStyle').value,customName:$('customPersonaName').value,customPrompt:$('customPersonaPrompt').value,maxCharacters:Number($('maxCharacters').value),banter:Number($('banter').value),stickersEnabled:$('stickersEnabled').checked,stickerIntervalSeconds:Number($('stickerIntervalSeconds').value),stickerEveryReplies:Number($('stickerEveryReplies').value),stickerTrigger:$('stickerTrigger').value,stickerEmotions:[...$('stickerEmotions').selectedOptions].map(o=>o.value),stickerKeywords:$('stickerKeywords').value.split('\n').map(s=>s.trim()).filter(Boolean),stickerRepeatHours:Number($('stickerRepeatHours').value)};
  const success=await act({action:'save',persona,groupParticipationEnabled:$('groupParticipationEnabled').checked,groupParticipationEvery:Number($('groupParticipationEvery').value),onlineEnabled:$('onlineEnabled').checked,visionEnabled:$('visionEnabled').checked,memoryEnabled:$('memoryEnabled').checked,memoryOptions:{messageThreshold:Number($('memoryMessages').value),characterThreshold:Number($('memoryCharacters').value),intervalMinutes:Number($('memoryMinutes').value),retrievalCharacters:Number($('memoryBudget').value)},enabled:[...$('targets').querySelectorAll('input:checked')].map(c=>c.dataset.target),ai});
  if(success) {
    targetDraft.clear();
  }
});
document.addEventListener('input',event=>{
  if(!state) return;
  const input=event.target;
  if(['search','duration','artArtistInput'].includes(input.id)||input.matches('#targets select')||input.closest('#customPersonaDialog,#stickerImport')) return;
  const group=input.closest('#connectionPanel')?'connection':input.closest('#artworkPanel')?'artwork':input.closest('#imagePanel')?'image':input.closest('#visionPanel')?'visual':'reply';
  if(!dirtyForms.has(group)) dirtyForms.set(group,{base:formSnapshot(group),revision:state.configurationRevision});
  syncForms();
  renderScopeActions();
});
document.addEventListener('change',event=>{if(event.target.matches('select:not(#personaStyle)')&&!event.target.matches('#targets select')) event.target.dispatchEvent(new Event('input',{bubbles:true}));});
$('discardDrafts').addEventListener('click',()=>{
  showActionError(''); dirtyForms.clear(); syncedForms.clear(); targetDraft.clear(); targetSignature='';
  for(const id of ['token','key','imageGenZhipuKey','imageGenCloudflareToken','googleVisionKey']) $(id).value='';
  render();
});
window.addEventListener('beforeunload',event=>{if(dirtyForms.size){event.preventDefault();event.returnValue='';}});
selectPanelPage(sessionStorage.getItem('panel-page')||'connection');
request().catch(()=>{});
setInterval(()=>{renderFreshness();if(!pending && !statusRequestPending)request().catch(()=>{});},3000);

async function renderStickers(items,reset=true) {
  if(!reset&&stickerLoading)return;
  const sequence=reset?++stickerRenderSequence:stickerRenderSequence;
  if(reset){stickerOffset=0;$('stickers').replaceChildren();}
  const end=Math.min(stickerOffset+12,items.length);
  stickerLoading=true;$('loadMoreStickers').disabled=true;
  try {
    for(const item of items.slice(stickerOffset,end)) {
      if(sequence!==stickerRenderSequence)return;
      const card=document.createElement('div'), image=document.createElement('img'), link=document.createElement('a');
      image.width=120;image.height=120;image.style.objectFit='contain';image.alt=item.title;
      link.textContent=item.title+(item.source?' · 来源':' · 本机');if(item.source)link.href=item.source;link.target='_blank';link.rel='noreferrer';link.style.display='block';
      const caption=document.createElement('small');caption.textContent=[item.context,item.author,item.license,item.local?(item.publicSharing?'待手动发布':'仅本机'):null].filter(Boolean).join(' · ');caption.style.display='block';
      card.style.width='160px';card.append(image,link,caption);$('stickers').append(card);
      try {
        const r=await fetch('/api/sticker/'+encodeURIComponent(item.id),{headers:{'X-QQ-Control':controlToken}});
        if(!r.ok)throw new Error('图片不可用');
        const blob=await r.blob();if(sequence!==stickerRenderSequence)return;
        const url=URL.createObjectURL(blob);image.onload=image.onerror=()=>URL.revokeObjectURL(url);image.src=url;
      } catch {image.alt=item.title+'（不可用）';}
    }
    stickerOffset=end;
  }finally{
    if(sequence===stickerRenderSequence){stickerLoading=false;$('loadMoreStickers').disabled=false;$('loadMoreStickers').hidden=stickerOffset>=items.length;}
  }
}
$('stickerGallery').addEventListener('toggle',()=>{if($('stickerGallery').open&&state)renderStickers(state.stickers);});
$('loadMoreStickers').addEventListener('click',()=>{if(state)renderStickers(state.stickers,false);});
$('importStickers').addEventListener('click',async()=>{
  const files=[...$('stickerFiles').files];
  if(!files.length||files.length>50){text('stickerImportStatus','每次选择 1–50 张图片。');return;}
  if(!state||state.running||state.busy||pending||importingStickers){text('stickerImportStatus','请先暂停并等待当前操作完成。');return;}
  const metadata={emotion:$('importEmotion').value,context:$('importContext').value.trim(),author:$('importAuthor').value.trim(),license:$('importLicense').value.trim(),source:$('importSource').value.trim(),publicSharing:$('importPublic').checked};
  importingStickers=true;render();let imported=0;const failures=[];
  try {
    const isPack=files.some(file=>file.name.toLowerCase().endsWith('.json'));
    if(isPack&&files.length!==1)throw new Error('资源包请单独导入，不与图片混选。');
    const jobs=isPack?await readStickerPack(files[0]):files.map(file=>({file}));
    for(const job of jobs) {
      const name=job.file?.name||job.sticker.title;
      try {
        let payload=job;
        if(job.file){
          const file=job.file;
          if(!['image/png','image/jpeg','image/webp'].includes(file.type)||file.size>3000000)throw new Error('需要 3 MB 内的 PNG/JPEG/WebP');
          const bytes=await file.arrayBuffer();
          let binary='';for(const byte of new Uint8Array(bytes))binary+=String.fromCharCode(byte);
          payload={sticker:{...metadata,title:file.name.replace(/\.[^.]+$/,'').slice(0,80)},stickerImage:btoa(binary)};
        }
        const result=await request({action:'importSticker',...payload});
        if(result.error)throw new Error(result.error);imported++;
      }catch(error){failures.push(name+'：'+error.message);}
      text('stickerImportStatus',`已导入 ${imported} / ${jobs.length} 张`);
    }
    text('stickerImportStatus',`已导入 ${imported} 张。`+(failures.length?'\n'+failures.join('\n'):'仅保存到本机；公开分享由独立发布步骤完成。'));
    if(!failures.length)$('stickerFiles').value='';
  }catch(error){text('stickerImportStatus',error.message||'资源包解析失败，未开始导入。');}
  finally{importingStickers=false;render();}
});

function renderArtwork(first) {
  const a=state.artwork;
  if(!a) {text('artStatus','此服务尚未更新插画功能，请使用新版服务。');return;}
  text('artStatus',state.artworkStatus==='插画尚未请求' ? '' : `${state.artworkStatus} · 来源请求 ${state.artworkNetworkCalls} · 作品确认 ${state.artworkConfirmed}`);
  const roster=state.artworkArtists || a.pixivArtistIDs.map(id=>({id,name:a.artistNames?.[id] || `画师 ${id}`}));
  const rosterSignature=JSON.stringify(roster);
  if($('artArtistList').dataset.signature!==rosterSignature) {
    $('artArtistList').dataset.signature=rosterSignature;$('artArtistList').replaceChildren();
    for(const artist of roster) {
      const row=document.createElement('p'),link=document.createElement('a'),remove=button('移除',{action:'removeArtworkArtist',artistInput:artist.id},`移除画师：${artist.name}（${artist.id}）`);
      link.href=`https://www.pixiv.net/users/${artist.id}`;link.target='_blank';link.rel='noreferrer';link.textContent=`${artist.name}（${artist.id}）`;
      row.append(link,document.createTextNode(` · ${artist.deliveryStatus||'逐作检查公开图片可用性'} · 历史精选来源 `),remove);$('artArtistList').append(row);
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
  for(const item of $('artworkPanel').querySelectorAll('input,select,textarea,button:not(.help-button)')) item.disabled=state.running||state.busy||pending;
  $('artHour').disabled=$('artHour').disabled||$('artFrequency').value==='hourly';
  const hasDraft=dirtyForms.has('artwork');
  $('artArtistAdd').disabled=$('artArtistAdd').disabled||hasDraft;
  for(const button of $('artArtistList').querySelectorAll('button')) button.disabled=button.disabled||hasDraft;
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
