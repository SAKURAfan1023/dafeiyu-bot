// Fixed video/comment operations in an isolated login session. No model or arbitrary URLs.
import {restrictedResponse} from './access-contract.mjs';
import {createHash} from 'node:crypto';
const clean = v => String(v ?? '').trim();
const videoID = v => /^BV[0-9A-Za-z]{10}$/.test(v);
const text = v => clean(v).slice(0, 6000);
const snapshots = new WeakMap();
const decimalID = v => typeof v === 'string' && /^[1-9]\d{0,24}$/.test(v) ? v : Number.isSafeInteger(v) && v > 0 ? String(v) : '';
// The route claims exactly one fixed POST. Unknown fields, targets and repeated attempts fail closed.
export function claimBilibiliWrite(permit, payload) {
  const e=permit?.expected, parent=e?.parentID||'0';
  if(!e || permit.used || !Number.isFinite(e.deadline) || e.deadline<=Date.now() || !decimalID(e.aid) ||
    !payload || Object.keys(payload).some(k=>!['type','oid','root','parent','message','plat','csrf'].includes(k)) ||
    payload.type!=='1' || payload.oid!==e.aid || payload.root!==parent || payload.parent!==parent ||
    payload.message!==e.content || payload.plat!=='1' || typeof payload.csrf!=='string' || !/^[a-fA-F0-9]{32}$/.test(payload.csrf))return false;
  permit.used=true;return true;
}
// Receipts and read-back must prove the exact account, video, text and parent, not just code=0.
export function matchesBilibiliReply(reply, expected) {
  return Boolean(decimalID(reply?.rpid_str ?? reply?.rpid)) && decimalID(reply?.oid)===expected.aid && reply?.type===1 &&
    decimalID(reply?.member?.mid ?? reply?.mid)===expected.expectedUID && reply?.content?.message===expected.content &&
    String(reply?.root_str ?? reply?.root ?? '')===(expected.parentID||'0') &&
    String(reply?.parent_str ?? reply?.parent ?? '')===(expected.parentID||'0');
}
export function mapVideo(value, expectedID, replies = null) {
  if (!videoID(expectedID) || value?.bvid !== expectedID) throw new Error('target_changed');
  const comments = (replies?.replies ?? []).slice(0, 20).flatMap(c => {
    const id=decimalID(c.rpid_str ?? c.rpid);
    if (!id) return [];
    return [{id,rootID:null,authorID:decimalID(c.member?.mid),
      author:clean(c.member?.uname).slice(0,80),text:text(c.content?.message).slice(0,1500)}];
  });
  return {id:expectedID,title:clean(value.title).slice(0,200),text:text(value.desc),
    author:clean(value.owner?.name).slice(0,80),authorID:clean(value.owner?.mid),kind:'video',imageCount:0,comments,
    platform:'bilibili',coverage:'仅读取标题、介绍与首批一级评论；画面、音频和字幕未分析；' +
      (replies ? '评论未读完，不含楼中楼' : '评论尚未取得，不代表没有评论')};
}
export async function executeBilibili(input, {page, navigate, browser, permit}) {
  const api = async path => {
    const result = await page.evaluate(async path => {
      const r=await fetch('https://api.bilibili.com'+path,{credentials:'include'});
      return {status:r.status,body:await r.json().catch(()=>null)};
    },path);
    if (restrictedResponse('https://api.bilibili.com'+path,result.status,result.body?.code)) throw new Error('platform_restricted');
    if(result.body?.code===-101)throw new Error('login_required');
    if (result.status !== 200 || result.body?.code !== 0) throw new Error('page_unavailable');
    return result.body.data;
  };
  if (input.action === 'login') {
    await navigate('https://www.bilibili.com/'); await page.bringToFront();
    const login=page.getByText('登录',{exact:true}).filter({visible:true}).first();
    await login.waitFor({state:'visible',timeout:12000}).catch(()=>{throw new Error('login_button_missing');});
    await login.click();
    // Current header first opens a benefits menu, whose button opens the QR dialog.
    const confirmLogin=page.getByText('立即登录',{exact:true}).filter({visible:true}).first();
    await confirmLogin.waitFor({state:'visible',timeout:3000}).catch(()=>{});
    if(await confirmLogin.isVisible())await confirmLogin.click();
    const qr=await page.locator('.login-scan-box img,.login-scan-box canvas,.qrcode-img img,.qrcode-img canvas,.qrcode-img').first().screenshot({timeout:8000}).catch(()=>{throw new Error('login_qr_missing');});
    return {qr:qr.toString('base64')};
  }
  await browser();
  if (input.action === 'identity') {
    if (!['www.bilibili.com','search.bilibili.com'].includes(new URL(page.url()).hostname)) await navigate('https://www.bilibili.com/');
    const who=await api('/x/web-interface/nav');
    if(who?.isLogin!==true || !/^\d+$/.test(String(who.mid)))throw new Error('login_required');
    return {id:String(who.mid),name:clean(who.uname).slice(0,80)};
  }
  if (input.action === 'search') {
    if (!clean(input.keyword) || input.keyword.length>80)throw new Error('invalid_keyword');
    await navigate('https://search.bilibili.com/all?keyword='+encodeURIComponent(input.keyword));
    await page.waitForFunction(()=>[...document.querySelectorAll('a[href]')].some(a=>/\/video\/BV[0-9A-Za-z]{10}/.test(a.href)),null,{timeout:15000});
    const posts=await page.evaluate(()=>{
      const found=new Map();
      for(const a of document.querySelectorAll('a[href]')){
        const u=new URL(a.href),id=u.pathname.match(/^\/video\/(BV[0-9A-Za-z]{10})\/?$/)?.[1];
        if(!id||u.hostname!=='www.bilibili.com'||found.has(id))continue;
        const card=a.closest('.bili-video-card,.video-item'),title=a.querySelector('[title]')?.getAttribute('title')||a.getAttribute('title')||a.textContent?.trim();
        if(!title)continue;
        found.set(id,{id,locator:id,title:title.slice(0,200),author:card?.querySelector('.bili-video-card__info--author,.bili-video-card__info--owner')?.textContent?.trim().slice(0,80)||'',kind:'video'});
        if(found.size>=10)break;
      }
      return [...found.values()];
    });
    if(!posts.length)throw new Error('page_unavailable');
    return {posts};
  }
  if (input.action === 'read') {
    snapshots.delete(page);
    if(!videoID(input.id) || input.locator!==input.id)throw new Error('invalid_target');
    // Observe the page's own signed first-page request, without issuing another comment request.
    const firstComments=page.waitForResponse(response=>{
      const url=new URL(response.url());
      return url.hostname==='api.bilibili.com' && ['/x/v2/reply/wbi/main','/x/v2/reply/main'].includes(url.pathname) && url.searchParams.get('type')==='1';
    },{timeout:20000}).catch(()=>null);
    await navigate('https://www.bilibili.com/video/'+input.id+'/');
    await page.waitForFunction(id=>window.__INITIAL_STATE__?.videoData?.bvid===id,input.id,{timeout:12000});
    const value=await page.evaluate(()=>JSON.parse(JSON.stringify(window.__INITIAL_STATE__.videoData)));
    await page.locator('#commentapp').scrollIntoViewIfNeeded({timeout:2000}).catch(()=>{});
    let replies=null;
    const response=await firstComments;
    if(response && Number.isSafeInteger(value.aid) && value.aid>0 && new URL(response.url()).searchParams.get('oid')===String(value.aid)){
      const body=await response.json().catch(()=>null);
      if(restrictedResponse(response.url(),response.status(),body?.code))throw new Error('platform_restricted');
      if(body?.code===0 && body.data && (Array.isArray(body.data.replies)||body.data.replies===null))replies=body.data;
    }
    const post=mapVideo(value,input.id,replies);
    snapshots.set(page,{post,aid:decimalID(value.aid)});
    return post;
  }
  if(input.action==='submit'){
    const snapshot=snapshots.get(page), parent=input.parentID ? snapshot?.post.comments.find(c=>c.id===input.parentID&&!c.rootID) : null;
    if(!snapshot?.aid || !videoID(input.id) || input.locator!==input.id || snapshot.post.id!==input.id ||
      new URL(page.url()).pathname!==('/video/'+input.id+'/'))throw new Error('invalid_target');
    if(input.parentID && (!parent || !decimalID(input.parentID) || parent.authorID===input.expectedUID))throw new Error('target_missing');
    if(!clean(input.content) || [...input.content].length>300 || !decimalID(input.expectedUID))throw new Error('invalid_content');
    // Check the loaded page again without navigating or issuing another comment list request.
    const value=await page.evaluate(()=>JSON.parse(JSON.stringify(window.__INITIAL_STATE__?.videoData ?? null)));
    const current=mapVideo(value,input.id);
    if(decimalID(value.aid)!==snapshot.aid || current.authorID===input.expectedUID)throw new Error('target_changed');
    const fingerprint=createHash('sha256').update(current.id+'\n'+current.title+'\n'+current.text+'\n'+(parent?parent.id+parent.authorID+parent.text:'')).digest('hex');
    if(fingerprint!==input.fingerprint)throw new Error('target_changed');
    const who=await api('/x/web-interface/nav');
    if(who?.isLogin!==true || decimalID(who.mid)!==input.expectedUID)throw new Error('account_changed');
    if(!permit || !Number.isFinite(input.deadline) || input.deadline<=Date.now())throw new Error('operation_cancelled');
    permit.expected={...input,aid:snapshot.aid};
    // CSRF remains in this profile/page. Never return it or pass it to the model/control panel.
    const result=await page.evaluate(async ({aid,parentID,content})=>{
      const csrf=document.cookie.split(';').map(v=>v.trim()).find(v=>v.startsWith('bili_jct='))?.slice(9);
      if(!csrf || !/^[a-fA-F0-9]{32}$/.test(csrf))return {missingCSRF:true};
      const body=new URLSearchParams({type:'1',oid:aid,root:parentID||'0',parent:parentID||'0',message:content,plat:'1',csrf});
      const response=await fetch('https://api.bilibili.com/x/v2/reply/add',{method:'POST',credentials:'include',body,redirect:'error'});
      return {status:response.status,body:await response.json().catch(()=>null)};
    },{aid:snapshot.aid,parentID:input.parentID,content:input.content});
    if(result.missingCSRF)return {state:'rejected',reason:'login_required'};
    if(permit.blocked&&!permit.used)return {state:'rejected',reason:'request_target_mismatch'};
    const raw=result.body;
    if(restrictedResponse('https://api.bilibili.com/x/v2/reply/add',result.status,raw?.code) || raw?.data?.need_captcha===true)throw new Error('platform_restricted');
    if(result.status===200 && Number.isInteger(raw?.code) && raw.code!==0)return {state:'rejected',reason:'platform_rejected'};
    if(result.status!==200 || raw?.code!==0 || !permit.used || !matchesBilibiliReply(raw?.data?.reply,permit.expected))return {state:'uncertain'};
    const externalID=decimalID(raw.data.reply.rpid_str ?? raw.data.reply.rpid);
    if(snapshot.post.comments.some(c=>c.id===externalID))return {state:'uncertain'};
    return {state:'accepted',externalID,authorID:input.expectedUID};
  }
  if(input.action==='verify'){
    if(!decimalID(input.externalID) || !decimalID(input.expectedUID) || input.parentID && !decimalID(input.parentID))throw new Error('invalid_target');
    await executeBilibili({...input,action:'read'},{page,navigate,browser});
    const snapshot=snapshots.get(page);
    if(!snapshot?.aid)throw new Error('invalid_target');
    const who=await api('/x/web-interface/nav');
    if(who?.isLogin!==true || decimalID(who.mid)!==input.expectedUID)throw new Error('account_changed');
    if(!input.parentID){
      const c=snapshot.post.comments.find(c=>c.id===input.externalID);
      if(c?.authorID===input.expectedUID && c.text===input.content)return {state:'confirmed',externalID:input.externalID,authorID:input.expectedUID};
    }else{
      // One bounded first page under the exact root, never an unbounded crawl or send retry.
      const data=await api('/x/v2/reply/reply?type=1&oid='+snapshot.aid+'&root='+input.parentID+'&pn=1&ps=20');
      const c=(data?.replies??[]).slice(0,20).find(c=>decimalID(c.rpid_str??c.rpid)===input.externalID);
      if(matchesBilibiliReply(c,{...input,aid:snapshot.aid}))return {state:'confirmed',externalID:input.externalID,authorID:input.expectedUID};
    }
    return {state:'accepted',externalID:input.externalID};
  }
  throw new Error('unknown_action');
}
