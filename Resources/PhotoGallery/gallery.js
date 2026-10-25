'use strict';
const $=id=>document.getElementById(id);
const emotions={all:'全部',neutral:'日常',joy:'开心',smug:'得意',annoyed:'不满',sad:'委屈',sleepy:'晚安',flustered:'害羞',teasing:'调皮'};
let catalog=[],filtered=[],emotion='all',visible=48,current=0,toastTimer;
function notify(message){$('toast').textContent=message;$('toast').classList.add('visible');clearTimeout(toastTimer);toastTimer=setTimeout(()=>$('toast').classList.remove('visible'),2200);}
function filter(){
  const query=$('search').value.trim().toLocaleLowerCase();
  filtered=catalog.filter(item=>(emotion==='all'||item.emotion===emotion)&&[item.title,item.context,item.author].join(' ').toLocaleLowerCase().includes(query));
  visible=48;render();
}
function render(){
  $('gallery').replaceChildren();
  for(const [index,item] of filtered.slice(0,visible).entries()){
    const card=document.createElement('article'),button=document.createElement('button'),img=document.createElement('img'),title=document.createElement('h2');
    card.className='card';img.src=item.file;img.alt=item.title;img.loading='lazy';img.decoding='async';img.width=280;img.height=280;title.textContent=item.title;
    button.setAttribute('aria-label','预览：'+item.title);button.append(img);button.addEventListener('click',()=>open(index));card.append(button,title);$('gallery').append(card);
  }
  $('status').textContent=filtered.length?'':'没有找到，换个词试试。';$('more').hidden=visible>=filtered.length;
  for(const button of $('filters').children)button.setAttribute('aria-pressed',String(button.dataset.emotion===emotion));
}
function open(index){
  if(!filtered.length)return;
  current=(index+filtered.length)%filtered.length;const item=filtered[current];
  $('preview').src=item.file;$('preview').alt=item.title;$('viewerTitle').textContent=item.title;$('context').textContent=item.context;
  $('credit').textContent=[item.author,item.license].filter(Boolean).join(' · ');$('source').href=item.source;
  $('download').href=item.file;$('download').download=item.id+'.'+item.file.split('.').pop();
  if(!$('viewer').open)$('viewer').showModal();
}
$('search').addEventListener('input',filter);
$('shuffle').addEventListener('click',()=>{for(let i=catalog.length-1;i>0;i--){const j=Math.floor(Math.random()*(i+1));[catalog[i],catalog[j]]=[catalog[j],catalog[i]];}filter();});
$('more').addEventListener('click',()=>{visible+=48;render();});
$('close').addEventListener('click',()=>$('viewer').close());
$('previous').addEventListener('click',()=>open(current-1));$('next').addEventListener('click',()=>open(current+1));
$('viewer').addEventListener('keydown',event=>{if(event.key==='ArrowLeft'){event.preventDefault();open(current-1);}if(event.key==='ArrowRight'){event.preventDefault();open(current+1);}});
$('copy').addEventListener('click',async()=>{try{await navigator.clipboard.writeText(new URL(filtered[current].file,location.href).href);notify('图片链接已复制');}catch{notify('复制失败，可直接下载图片');}});
async function load(){
  try{
    const response=await fetch('stickers.json',{cache:'no-cache'});if(!response.ok)throw new Error('catalog');
    const data=await response.json();if(!Array.isArray(data))throw new Error('catalog');
    catalog=data.filter(item=>/^[a-f0-9]{64}$/.test(item.sha256)&&item.file==='images/'+item.sha256+'.'+item.file.split('.').pop()&&/\.(png|webp|jpg|jpeg)$/.test(item.file)&&/^https:\/\//.test(item.source));
    for(const [key,label] of Object.entries(emotions)){
      if(key!=='all'&&!catalog.some(item=>item.emotion===key))continue;
      const button=document.createElement('button');button.textContent=label;button.dataset.emotion=key;button.addEventListener('click',()=>{emotion=key;filter();});$('filters').append(button);
    }
    for(const item of ['joy','flustered','sleepy'].map(mood=>catalog.find(entry=>entry.emotion===mood)).filter(Boolean)){
      const image=document.createElement('img');image.src=item.file;image.alt='';$('heroArt').append(image);
    }
    filter();
  }catch{$('status').textContent='图库暂时没有加载成功，请稍后刷新。';}
}
load();
