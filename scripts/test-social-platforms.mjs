import assert from 'node:assert/strict';
import {mapVideo,executeBilibili,claimBilibiliWrite,matchesBilibiliReply} from '../Resources/SocialBrowser/bilibili.mjs';
import {restrictedResponse} from '../Resources/SocialBrowser/access-contract.mjs';
import fs from 'node:fs';
import vm from 'node:vm';
import {createHash} from 'node:crypto';
const id='BV1234567890';
const video={bvid:id,title:'合成标题',desc:'仅视频介绍，不是字幕',owner:{mid:123,name:'合成作者'}};
const value=mapVideo(video,id,{replies:[{rpid_str:'9999999999999999999',member:{mid:456,uname:'合成评论者'},content:{message:'合成评论'}}]});
assert.equal(value.platform,'bilibili');assert.equal(value.comments[0].id,'9999999999999999999');
assert.equal(value.authorID,'123');assert(value.coverage.includes('字幕未分析'));assert(value.coverage.includes('不含楼中楼'));
assert(mapVideo(video,id).coverage.includes('不代表没有评论'));
assert.throws(()=>mapVideo(video,'BV0987654321'),/target_changed/);
assert.throws(()=>mapVideo(video,'bad'),/target_changed/);
assert(restrictedResponse('https://edith.xiaohongshu.com/api/sns/web/v1/search/notes',200,300011));
assert(restrictedResponse('https://api.bilibili.com/x/web-interface/nav',412));
assert(!restrictedResponse('https://unrelated.invalid/',403));
assert(!restrictedResponse('https://api.bilibili.com/x/web-interface/nav',200,0));
const page={evaluate:async()=>({status:412,body:null})};
await assert.rejects(()=>executeBilibili({action:'identity'},{page:{...page,url:()=> 'https://www.bilibili.com/'},browser:async()=>{},navigate:async()=>{}}),/platform_restricted/);
await assert.rejects(()=>executeBilibili({action:'submit'},{page,browser:async()=>{}}),/invalid_target/);
await assert.rejects(()=>executeBilibili({action:'read',id:'bad'},{page,browser:async()=>{}}),/invalid_target/);
// Login controls hydrate after navigation. Do not report success before a QR exists.
const loginSteps=[];
const loginPage={bringToFront:async()=>{},getByText:name=>({filter(){return this;},first(){return this;},waitFor:async()=>{if(name==='登录')loginSteps.push('ready');},isVisible:async()=>true,click:async()=>loginSteps.push(name==='登录'?'click':'confirmLogin')}),locator:selector=>({first(){return this;},
  screenshot:async()=>{assert.deepEqual(loginSteps,['navigate','ready','click','confirmLogin']);return Buffer.from('synthetic QR');}})};
const loginResult=await executeBilibili({action:'login'},{page:loginPage,navigate:async()=>loginSteps.push('navigate'),browser:async()=>{}});
assert.equal(Buffer.from(loginResult.qr,'base64').toString(),'synthetic QR');
const noQR={...loginPage,locator:selector=>({first(){return this;},waitFor:async()=>{},click:async()=>{},screenshot:async()=>{throw new Error('qr_not_loaded');}})};
await assert.rejects(()=>executeBilibili({action:'login'},{page:noQR,navigate:async()=>{},browser:async()=>{}}),/login_qr_missing/);
// Consume only the current page's signed reply response, and never call a legacy reply API.
const observedVideo={...video,aid:123};
let observedOID='123',replyCode=0;
const observedPage={waitForResponse:async predicate=>{
  const reply={url:()=> 'https://api.bilibili.com/x/v2/reply/wbi/main?type=1&oid='+observedOID,
    status:()=>200,json:async()=>({code:replyCode,data:{replies:[{rpid_str:'1234',member:{mid:456,uname:'合成评论者'},content:{message:'已加载评论'}}]}})};
  assert(predicate(reply));return reply;
},waitForFunction:async()=>{},evaluate:async()=>observedVideo,locator:()=>({scrollIntoViewIfNeeded:async()=>{}})};
const readInput={action:'read',id,locator:id};
const loadedPost=await executeBilibili(readInput,{page:observedPage,navigate:async()=>{},browser:async()=>{}});
assert.equal(loadedPost.comments[0].id,'1234');
observedOID='999';
const wrongPage=await executeBilibili(readInput,{page:observedPage,navigate:async()=>{},browser:async()=>{}});
assert.equal(wrongPage.comments.length,0);assert(wrongPage.coverage.includes('尚未取得'));
observedOID='123';replyCode=-403;
await assert.rejects(()=>executeBilibili(readInput,{page:observedPage,navigate:async()=>{},browser:async()=>{}}),/platform_restricted/);
const noReplies={...observedPage,waitForResponse:async()=>{throw new Error('timeout');}};
const incompletePost=await executeBilibili(readInput,{page:noReplies,navigate:async()=>{},browser:async()=>{}});
assert(incompletePost.coverage.includes('尚未取得'));
// Exercise the real page callbacks against synthetic DOM/fetch, never a real account.
const outgoing=[],expected={id,locator:id,expectedUID:'789',content:'这段介绍很有意思',parentID:'1234',deadline:Date.now()+60000};
const fingerprint=createHash('sha256').update(id+'\n'+video.title+'\n'+video.desc+'\n1234456已加载评论').digest('hex');
expected.fingerprint=fingerprint;
let activePermit,navUID=789,receiptCode=0,receiptMutation=c=>c,dropWrite=false,replyChildren=[];
const receipt=()=>receiptMutation({rpid_str:'9999999999999999999',oid:123,type:1,root_str:expected.parentID||'0',parent_str:expected.parentID||'0',
  member:{mid:789},content:{message:expected.content}});
const writePage={...observedPage,url:()=> 'https://www.bilibili.com/video/'+id+'/',evaluate:async(fn,arg)=>{
  const scope={window:{__INITIAL_STATE__:{videoData:observedVideo}},document:{cookie:'bili_jct='+'a'.repeat(32)},URLSearchParams,
    fetch:async(url,options)=>{
      if(url.endsWith('/nav'))return {status:200,json:async()=>({code:0,data:{isLogin:true,mid:navUID}})};
      if(url.includes('/reply/reply?'))return {status:200,json:async()=>({code:0,data:{replies:replyChildren}})};
      assert.equal(url,'https://api.bilibili.com/x/v2/reply/add');
      const payload=Object.fromEntries(options.body);
      assert(claimBilibiliWrite(activePermit,payload),'outgoing request must consume one permit');
      outgoing.push(payload);
      if(dropWrite)throw new Error('synthetic_connection_lost');
      return {status:200,json:async()=>({code:receiptCode,data:{reply:receipt()}})};
    }};
  vm.createContext(scope);scope.argument=arg;
  return vm.runInContext('('+fn.toString()+')(argument)',scope);
}};
replyCode=0;
await executeBilibili(readInput,{page:writePage,navigate:async()=>{},browser:async()=>{}});
async function write(fields={}){
  activePermit={expected:{...expected,...fields},used:false,blocked:false};
  return executeBilibili({action:'submit',...expected,...fields},{page:writePage,browser:async()=>{},permit:activePermit});
}
const sent=await write();assert.equal(sent.state,'accepted');assert.equal(sent.externalID,'9999999999999999999');assert.equal(outgoing.length,1);
assert(!claimBilibiliWrite(activePermit,outgoing[0]),'same permit cannot send twice');
for(const changed of [{oid:'999'},{root:'999'},{parent:'999'},{message:'changed'},{type:'2'},{csrf:''},{extra:'unknown'}]){
  assert(!claimBilibiliWrite({expected:{...expected,aid:'123'},used:false},{...outgoing[0],...changed}));
}
assert(!claimBilibiliWrite({expected:{...expected,aid:'123',deadline:Date.now()-1}},outgoing[0]));
await assert.rejects(()=>write({fingerprint:'old'}),/target_changed/);
await assert.rejects(()=>write({parentID:'999'}),/target_missing/);
await assert.rejects(()=>write({deadline:Date.now()-1}),/operation_cancelled/);
navUID=999;await assert.rejects(()=>write(),/account_changed/);navUID=789;
assert.equal(outgoing.length,1,'preflight failures must not reach the write request');
for(const mutation of [c=>({...c,oid:456}),c=>({...c,member:{mid:999}}),c=>({...c,root_str:'9'}),c=>({...c,content:{message:'wrong'}}),c=>({...c,rpid_str:undefined,rpid:9999999999999999999})]){
  receiptMutation=mutation;assert.equal((await write()).state,'uncertain');
}
receiptMutation=c=>c;receiptCode=12003;assert.equal((await write()).state,'rejected');
receiptCode=12015;await assert.rejects(()=>write(),/platform_restricted/);
receiptCode=0;dropWrite=true;const beforeDrop=outgoing.length;
await assert.rejects(()=>write(),/synthetic_connection_lost/);assert.equal(outgoing.length,beforeDrop+1,'no automatic send retry');dropWrite=false;
replyChildren=[receipt()];
const confirmed=await executeBilibili({...expected,action:'verify',externalID:sent.externalID},{page:writePage,navigate:async()=>{},browser:async()=>{}});
assert.equal(confirmed.state,'confirmed');
replyChildren=[{...receipt(),parent_str:'999'}];
assert.equal((await executeBilibili({...expected,action:'verify',externalID:sent.externalID},{page:writePage,navigate:async()=>{},browser:async()=>{}})).state,'accepted');
assert(!matchesBilibiliReply({...receipt(),rpid_str:undefined,rpid:9999999999999999999},{...expected,aid:'123'}));
assert(restrictedResponse('https://api.bilibili.com/x/v2/reply/add',200,12015));
// Test the actual browser route, not just the payload predicate.
const routeSource=fs.readFileSync(new URL('../Resources/SocialBrowser/browser.mjs',import.meta.url),'utf8');
let handleWriteRoute;
const routeScope={platform:'bilibili',URL,URLSearchParams,claimBilibiliWrite,cancelled:false,restricted:false,
  writePermit:null,context:{route:async(pattern,handler)=>{handleWriteRoute=handler;}}};
vm.createContext(routeScope);
await vm.runInContext('(async()=>{'+routeSource.slice(routeSource.indexOf("  if(platform==='bilibili')await context.route"),routeSource.indexOf("  context.on('response'"))+'})()',routeScope);
async function routed(overrides={},control={}){
  routeScope.writePermit={expected:{...expected,aid:'123'},used:false,blocked:false};
  routeScope.cancelled=Boolean(control.cancelled);routeScope.restricted=Boolean(control.restricted);
  let passed=false;
  const req={url:()=>overrides.url||'https://api.bilibili.com/x/v2/reply/add',method:()=>overrides.method||'POST',
    postData:()=>overrides.body||new URLSearchParams(outgoing[0]).toString()};
  await handleWriteRoute({request:()=>req,continue:async()=>passed=true,abort:async()=>{}});
  return passed;
}
assert(await routed());
for(const overrides of [{method:'GET'},{url:'https://api.bilibili.com/x/v2/reply/del'},{url:'https://api.bilibili.com/x/v2/reply/add?oid=999'},
  {url:'https://untrusted.invalid/x/v2/reply/add'},{body:new URLSearchParams(outgoing[0]).toString()+'&oid=123'}])assert(!await routed(overrides));
assert(!await routed({}, {cancelled:true}));assert(!await routed({}, {restricted:true}));
// The recommended preset fills only task controls and never starts or changes identity/model data.
const presetSource=fs.readFileSync(new URL('../Resources/SocialControl/app.js',import.meta.url),'utf8');
const presetFields=new Map();const getPresetField=name=>{if(!presetFields.has(name))presetFields.set(name,{value:'unchanged'});return presetFields.get(name);};
const presetScope={pending:false,settingsDirty:false,numeric:new Set(['durationMinutes','maxPosts','maxModelCalls','dailyWriteLimit','intervalSeconds','readIntervalSeconds','maxCharacters']),
  state:{running:false,busy:false,recommendedSettings:{mode:'auto',durationMinutes:15,maxPosts:5,maxModelCalls:5,dailyWriteLimit:3,intervalSeconds:300,readIntervalSeconds:60,maxCharacters:80}},
  showError:()=>{},$:getPresetField};
vm.createContext(presetScope);
vm.runInContext(presetSource.slice(presetSource.indexOf("$('#recommended').onclick"),presetSource.indexOf("$('#start').onclick")),presetScope);
getPresetField('#recommended').onclick();
assert(presetScope.settingsDirty);assert.equal(getPresetField('[name=mode]').value,'auto');
assert.equal(getPresetField('[name=dailyWriteLimit]').value,3);assert.equal(getPresetField('[name=intervalSeconds]').value,300);
assert.equal(getPresetField('[name=keyword]').value,'unchanged');assert.equal(getPresetField('[name=model]').value,'unchanged');
// A blocked main document must latch the same stop as a blocked API response.
const browserSource=fs.readFileSync(new URL('../Resources/SocialBrowser/browser.mjs',import.meta.url),'utf8');
let navigations=0;
const navigationSandbox={URL,cancelled:false,restricted:false,allowedOrigins:['https://www.bilibili.com'],browser:async()=>{},
  page:{goto:async()=>{navigations++;return {status:()=>412};},url:()=> 'https://www.bilibili.com/'}};
vm.createContext(navigationSandbox);
vm.runInContext(browserSource.slice(browserSource.indexOf('async function navigate('),browserSource.indexOf('async function identity('))+'\nthis.navigate=navigate;',navigationSandbox);
await assert.rejects(()=>navigationSandbox.navigate('https://www.bilibili.com/'),/platform_restricted/);
await assert.rejects(()=>navigationSandbox.navigate('https://www.bilibili.com/'),/platform_restricted/);
assert.equal(navigations,1);assert(navigationSandbox.restricted);
// Keep a whole in-flight action bound to its original platform after a view switch.
const source=fs.readFileSync(new URL('../Resources/SocialControl/app.js',import.meta.url),'utf8');
let completeJob;const requests=[];let refreshed=0;
const sandbox={token:'synthetic-local-token',platform:'xiaohongshu',viewEpoch:0,pending:false,state:{revision:1},crypto:{randomUUID:()=> 'synthetic-request'},
  showError:()=>{},refresh:async()=>refreshed++,setTimeout,
  fetch:async(url,options)=>{
    requests.push({url,body:options.body});
    if(url.startsWith('/api/action'))return{ok:true,json:async()=>({requestID:'synthetic-request'})};
    return{ok:true,json:()=>new Promise(resolve=>completeJob=()=>resolve({state:'complete'}))};
  }};
vm.createContext(sandbox);
vm.runInContext(source.slice(source.indexOf('async function api('),source.indexOf('function readSettings()'))+'\nthis.runAction=action;',sandbox);
const running=sandbox.runAction('search');
for(let i=0;i<100&&!completeJob;i++)await new Promise(resolve=>setTimeout(resolve,0));
assert(completeJob,'action must reach its job before switching');
sandbox.platform='bilibili';sandbox.viewEpoch++;
completeJob();await running;
assert(requests.every(r=>r.url.includes('platform=xiaohongshu')));
assert.equal(JSON.parse(requests[0].body).platform,'xiaohongshu');assert.equal(refreshed,0);
console.log('Social platform contracts: scoped video/comment mapping, incomplete coverage, risk signals and Bilibili exact-once writes passed; synthetic only.');
console.log('Panel race: late completion remains on the original platform and cannot refresh the newly selected platform.');
