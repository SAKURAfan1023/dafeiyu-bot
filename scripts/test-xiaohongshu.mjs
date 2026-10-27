import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';
import { requestMatchesTarget, claimWrite } from '../Resources/Xiaohongshu/page-contract.mjs';
const target = {id:'note-a', parentID:'comment-a', content:'收到[笑哭R]'};
assert(requestMatchesTarget({note_id:'note-a',target_comment_id:'comment-a',content:target.content},target));
assert(!requestMatchesTarget({note_id:'note-b',target_comment_id:'comment-a',content:target.content},target));
assert(!requestMatchesTarget({note_id:'note-a',target_comment_id:'comment-b',content:target.content},target));
assert(!requestMatchesTarget({note_id:'note-a',content:target.content},target));
assert(!requestMatchesTarget({note_id:'note-a',target_comment_id:'comment-a',content:'被修改的文字'},target));
assert(!requestMatchesTarget(null,target));
assert(requestMatchesTarget({note_id:'note-a',content:'顶层评论'}, {id:'note-a',content:'顶层评论'}));
const permit={expected:{...target, deadline:Date.now()+10000},used:false};
const payload={note_id:'note-a',target_comment_id:'comment-a',content:target.content};
assert(claimWrite(permit,payload));
assert(!claimWrite(permit,payload));
assert(!claimWrite(null,payload)); // Late retry after the submission permit has been revoked.
assert(!claimWrite({expected:{...target,deadline:Date.now()-1},used:false},payload));
const storage = new Map();
const sessionStorage = {getItem:k=>storage.get(k),setItem:(k,v)=>storage.set(k,v)};
const bootstrap = fs.readFileSync(new URL('../Resources/SocialControl/app.js',import.meta.url),'utf8').split('const $ =')[0];
const load = hash => vm.runInNewContext(bootstrap+'\ntoken;', {location:{hash,pathname:'/',search:'?section=records'},sessionStorage,history:{replaceState:(_a,_b,url)=>assert.equal(url,'/?section=records')}});
assert.equal(load('#synthetic-control-token'),'synthetic-control-token');
assert.equal(load(''),'synthetic-control-token');
// Exercise the production page readers against an asynchronously hydrated page.
const adapterSource = fs.readFileSync(new URL('../Resources/Xiaohongshu/browser.mjs',import.meta.url),'utf8');
let detail, readiness;
const page = {
  locator:()=>({first:()=>({scrollIntoViewIfNeeded:async()=>{}})}),
  waitForFunction:async(predicate,arg)=>{
    const state={search:{feeds:[]},note:{noteDetailMap:{sample:detail}}};
    const evaluate=()=>vm.runInNewContext(`(${predicate})(${JSON.stringify(arg)})`,{window:{__INITIAL_STATE__:state}});
    if(arg==null){
      assert.equal(evaluate(),false,'empty bootstrap must not complete search');
      state.search.feeds=[{modelType:'note',id:'sample',xsecToken:'synthetic-locator',noteCard:{displayTitle:'合成笔记'}}];
    }
    if(!evaluate())throw new Error('not ready');
  },
  evaluate:async(fn,arg)=>vm.runInNewContext(`(${fn})(${JSON.stringify(arg)})`,{window:{__INITIAL_STATE__:{search:{feeds:[{modelType:'note',id:'sample',xsecToken:'synthetic-locator',noteCard:{displayTitle:'合成笔记'}}]},note:{noteDetailMap:{sample:detail}}}}}),
};
const readers=vm.runInNewContext(adapterSource.slice(adapterSource.indexOf('async function search('),adapterSource.indexOf('// Match only an exact comment ID.'))+'\n({search,read});',{
  page,navigate:async()=>{},origin:'https://www.xiaohongshu.com',clean:v=>String(v??'').trim(),validID:v=>/^[a-zA-Z0-9_-]{1,100}$/.test(v),
});
assert.equal((await readers.search('合成主题')).posts.length,1);
detail={note:{noteId:'sample',desc:'合成正文',interactInfo:{commentCount:2}},comments:{list:[],hasMore:true}};
readiness=await readers.read({id:'sample',locator:'synthetic-locator'});
assert(readiness.coverage.includes('不代表没有评论'));
detail.comments.list=[{id:'comment-a',content:'合成评论',userInfo:{userId:'author-a'}}];
readiness=await readers.read({id:'sample',locator:'synthetic-locator'});
assert.equal(readiness.comments.length,1);
assert(!readiness.coverage.includes('尚未加载'));
detail={note:{noteId:'sample',interactInfo:{commentCount:0}},comments:{list:[],hasMore:false}};
assert(!(await readers.read({id:'sample',locator:'synthetic-locator'})).coverage.includes('尚未加载'));
let replyLoaded = false, expanded = 0, evidenceParent = 'comment-a';
const replyNode={evaluate:async()=>({content:'合成回复',author:'/user/profile/synthetic-account',parentID:evidenceParent})};
const expand={count:async()=>1,click:async()=>{expanded++;replyLoaded=true;}};
const parentNode={scrollIntoViewIfNeeded:async()=>{},locator:()=>({filter:()=>({first:()=>expand})})};
const verify=vm.runInNewContext(adapterSource.slice(adapterSource.indexOf('async function verify('),adapterSource.indexOf('async function submit('))+'\nverify;',{
  read:async()=>{},identity:async()=>({id:'synthetic-account'}),validID:v=>/^[a-zA-Z0-9_-]{1,100}$/.test(v),commentEvidence:()=>{},
  page:{locator:selector=>{assert.equal(selector,'#comment-reply-a');return{waitFor:async()=>{}};}},
  visibleComment:async id=>{if(id==='comment-a')return parentNode;if(id==='reply-a'&&replyLoaded)return replyNode;throw new Error('missing');},
});
const verification={expectedUID:'synthetic-account',externalID:'reply-a',parentID:'comment-a',content:'合成回复'};
assert.equal((await verify(verification)).state,'confirmed');assert.equal(expanded,1);
evidenceParent='another-parent';assert.equal((await verify(verification)).state,'accepted');
console.log('Xiaohongshu contracts: 11 outgoing assertions plus refresh/query bootstrap passed; synthetic data only.');
console.log('Page readers: empty search bootstrap, unloaded comments, loaded comments and confirmed empty comments passed.');
console.log('Read-back: one bounded expansion of the exact parent; mismatched reply root never confirms.');
