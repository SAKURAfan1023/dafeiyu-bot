'use strict';
const $=id=>document.getElementById(id);
const emotions={neutral:'日常',joy:'开心',smug:'得意',annoyed:'不满',sad:'委屈',sleepy:'晚安',flustered:'害羞',teasing:'调皮'};
const styles=['全部','文字梗','搞怪','可爱'];
const batchSize=16,maxPackBytes=24000000;
let catalog=[],filtered=[],style='全部',visible=0,current=0,toastTimer,exporting=false;
const selected=new Map();
function notify(message){$('toast').textContent=message;$('toast').classList.add('visible');clearTimeout(toastTimer);toastTimer=setTimeout(()=>$('toast').classList.remove('visible'),3200);}
function filter(){
  const query=$('search').value.trim().toLocaleLowerCase(),collection=$('collection').value,emotion=$('emotion').value;
  filtered=catalog.filter(item=>(style==='全部'||item.tags.includes(style))&&(collection==='all'||item.collection===collection)&&(emotion==='all'||item.emotion===emotion)&&[item.title,item.context,item.author,item.collection,...item.tags].join(' ').toLocaleLowerCase().includes(query));
  visible=0;$('gallery').replaceChildren();appendBatch();
  $('status').textContent=filtered.length?'':'没有找到，换个词试试。';
  for(const button of $('filters').children)button.setAttribute('aria-pressed',String(button.dataset.style===style));
}
function appendBatch(){
  const end=Math.min(visible+batchSize,filtered.length),fragment=document.createDocumentFragment();
  for(let index=visible;index<end;index++){
    const item=filtered[index],card=document.createElement('article'),preview=document.createElement('button'),img=document.createElement('img'),footer=document.createElement('label'),checkbox=document.createElement('input'),title=document.createElement('span');
    card.className='card';img.src=item.file;img.alt=item.title;img.loading='lazy';img.decoding='async';img.width=280;img.height=280;
    preview.className='preview-button';preview.setAttribute('aria-label','预览：'+item.title);preview.append(img);preview.addEventListener('click',()=>open(index));
    footer.className='card-selection';checkbox.type='checkbox';checkbox.dataset.pick=item.id;checkbox.setAttribute('aria-label','选择：'+item.title);title.textContent=item.title;
    checkbox.addEventListener('change',()=>pick(item,checkbox.checked));footer.append(checkbox,title);card.append(preview,footer);fragment.append(card);
  }
  $('gallery').append(fragment);visible=end;$('more').hidden=visible>=filtered.length;updateSelection();
}
function pick(item,checked){
  if(exporting)return;
  if(!checked)selected.delete(item.id);
  else if(!selected.has(item.id)){
    const estimated=[...selected.values(),item].reduce((sum,entry)=>sum+Math.ceil(entry.bytes/3)*4+3000,100000);
    if(selected.size>=50||estimated>maxPackBytes){notify('本包已达 50 张或 24 MB 上限，可分批导出。');updateSelection();return;}
    selected.set(item.id,item);
  }
  updateSelection();
}
function updateSelection(){
  $('selectionBar').hidden=selected.size===0;$('selectionCount').textContent='已选 '+selected.size+' / 50 张';
  $('clearSelection').disabled=exporting;$('selectVisible').disabled=exporting||!visible;
  $('exportSelection').disabled=exporting||!selected.size;
  for(const checkbox of document.querySelectorAll('[data-pick]')){
    checkbox.checked=selected.has(checkbox.dataset.pick);checkbox.disabled=exporting;
    checkbox.closest('.card').classList.toggle('selected',checkbox.checked);
  }
  const item=filtered[current];$('pickPreview').textContent=item&&selected.has(item.id)?'从资源包移除':'选入资源包';$('pickPreview').disabled=exporting;
}
function open(index){
  if(!filtered.length)return;
  current=(index+filtered.length)%filtered.length;const item=filtered[current];
  $('preview').src=item.file;$('preview').alt=item.title;$('viewerTitle').textContent=item.title;$('context').textContent=item.context;
  $('credit').textContent=[item.collection,item.author,item.license].filter(Boolean).join(' · ');$('source').href=item.source;
  $('download').href=item.file;$('download').download=item.id+'.'+item.file.split('.').pop();updateSelection();
  if(!$('viewer').open)$('viewer').showModal();
}
async function fetchResource(path){
  const controller=new AbortController(),timeout=setTimeout(()=>controller.abort(),20000);
  try{const response=await fetch(path,{signal:controller.signal});if(!response.ok)throw new Error('资源暂时不可用，请重试。');return await response.arrayBuffer();}finally{clearTimeout(timeout);}
}
async function exportSelection(){
  if(exporting||!selected.size)return;
  const choices=[...selected.values()];exporting=true;updateSelection();
  try{
    const items=[];
    for(const item of choices){
      $('exportSelection').textContent='准备 '+(items.length+1)+' / '+choices.length;
      const bytes=await fetchResource(item.file);if(bytes.byteLength>3000000)throw new Error('单张图片超过 3 MB。');
      const hash=[...new Uint8Array(await crypto.subtle.digest('SHA-256',bytes))].map(value=>value.toString(16).padStart(2,'0')).join('');
      if(hash!==item.sha256)throw new Error('图片校验未通过，请刷新后重试。');
      let binary='';for(const byte of new Uint8Array(bytes))binary+=String.fromCharCode(byte);
      const metadata={};for(const key of ['title','emotion','context','source','author','license','sha256'])metadata[key]=item[key];
      items.push({...metadata,imageBase64:btoa(binary)});
    }
    const licenseNotice=new TextDecoder().decode(await fetchResource('LICENSES.txt'));
    const blob=new Blob([JSON.stringify({format:'dafeiyu-stickers',version:1,licenseNotice,items})],{type:'application/json'});
    if(blob.size>maxPackBytes)throw new Error('资源包超过 24 MB，请减少几张后导出。');
    const url=URL.createObjectURL(blob),link=document.createElement('a');link.href=url;link.download='photos-'+new Date().toISOString().slice(0,10)+'.dafeiyu.json';link.click();setTimeout(()=>URL.revokeObjectURL(url),30000);
    notify('资源包已导出，在面板“导入本机表情”中选择该文件即可。');
  }catch(error){notify(error.message||'导出失败，已选内容保留。');}
  finally{exporting=false;$('exportSelection').textContent='导出导入包 ↓';updateSelection();}
}
$('search').addEventListener('input',filter);$('collection').addEventListener('change',filter);$('emotion').addEventListener('change',filter);
$('shuffle').addEventListener('click',()=>{for(let i=catalog.length-1;i>0;i--){const j=Math.floor(Math.random()*(i+1));[catalog[i],catalog[j]]=[catalog[j],catalog[i]];}filter();});
$('more').addEventListener('click',appendBatch);
if('IntersectionObserver' in window){const batches=new IntersectionObserver(entries=>{if(entries.some(entry=>entry.isIntersecting)&&!$('more').hidden)appendBatch();},{rootMargin:'100px'});batches.observe($('more'));}
$('selectVisible').addEventListener('click',()=>{for(const item of filtered.slice(0,visible))pick(item,true);});
$('clearSelection').addEventListener('click',()=>{selected.clear();updateSelection();});$('exportSelection').addEventListener('click',exportSelection);
$('pickPreview').addEventListener('click',()=>{const item=filtered[current];pick(item,!selected.has(item.id));});
$('close').addEventListener('click',()=>$('viewer').close());$('previous').addEventListener('click',()=>open(current-1));$('next').addEventListener('click',()=>open(current+1));
$('viewer').addEventListener('keydown',event=>{if(event.key==='ArrowLeft'){event.preventDefault();open(current-1);}if(event.key==='ArrowRight'){event.preventDefault();open(current+1);}});
$('help').addEventListener('click',()=>$('importGuide').showModal());$('closeGuide').addEventListener('click',()=>$('importGuide').close());
async function load(){
  try{
    const response=await fetch('stickers.json',{cache:'no-cache'});if(!response.ok)throw new Error('catalog');
    const data=await response.json();if(!Array.isArray(data))throw new Error('catalog');
    catalog=data.filter(item=>item.character==='deepseek-whale-maid'&&/^[a-f0-9]{64}$/.test(item.sha256)&&item.file==='images/'+item.sha256+'.'+item.file.split('.').pop()&&/\.(png|webp|jpg|jpeg)$/.test(item.file)&&/^https:\/\//.test(item.source)&&Array.isArray(item.tags)&&Number.isInteger(item.bytes)&&item.bytes>0&&item.bytes<=3000000);
    const groups=[...new Set(catalog.map(item=>item.collection))].map(name=>catalog.filter(item=>item.collection===name));
    catalog=[];while(groups.some(group=>group.length))for(const group of groups)if(group.length)catalog.push(group.shift());
    for(const collection of new Set(catalog.map(item=>item.collection))){const option=document.createElement('option');option.value=collection;option.textContent=collection;$('collection').append(option);}
    for(const [key,label] of Object.entries(emotions)){if(!catalog.some(item=>item.emotion===key))continue;const option=document.createElement('option');option.value=key;option.textContent=label;$('emotion').append(option);}
    for(const label of styles){const button=document.createElement('button');button.textContent=label;button.dataset.style=label;button.addEventListener('click',()=>{style=label;filter();});$('filters').append(button);}
    const art=['whale-hello','whale-smile','whale-delighted'].map(id=>catalog.find(item=>item.id===id)).filter(Boolean);
    for(const item of art){const image=document.createElement('img');image.src=item.file;image.alt='';$('heroArt').append(image);}
    filter();
  }catch{$('status').textContent='图库暂时没有加载成功，请稍后刷新。';}
}
load();
