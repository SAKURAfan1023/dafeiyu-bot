#!/usr/bin/env node
import fs from 'node:fs/promises';
import path from 'node:path';
import os from 'node:os';
import assert from 'node:assert/strict';
import {spawn,execFile} from 'node:child_process';
import {promisify} from 'node:util';
import {fileURLToPath} from 'node:url';
import {Client} from '@modelcontextprotocol/sdk/client/index.js';
import {StdioClientTransport} from '@modelcontextprotocol/sdk/client/stdio.js';
import {StreamableHTTPClientTransport} from '@modelcontextprotocol/sdk/client/streamableHttp.js';

if(process.platform!=='darwin') throw new Error('Run this test on macOS');
const run=promisify(execFile),root=fileURLToPath(new URL('..',import.meta.url));
const archive=path.join(root,'dist',`dafeiyu-macos-mcp-${process.arch}-0.3.0-preview.2.zip`);
const temporary=await fs.mkdtemp(path.join(os.tmpdir(),'dafeiyu Mac 包 测试 '));
const data=path.join(temporary,'QQ data'),plugin=path.join(temporary,'dafeiyu-qq-macos-test');
const env={...process.env,PATH:'/usr/bin:/bin',DAFEIYU_MAC_TEST_DATA_DIR:data,
  DAFEIYU_QQ_ROOT:'/invalid/synthetic',DAFEIYU_RESOURCES:'/invalid/synthetic',DAFEIYU_NODE_DEPENDENCIES:'/invalid/synthetic',
  DAFEIYU_MODULES_DIR:'/invalid/synthetic',DAFEIYU_ONEBOT_TOKEN:'synthetic-must-not-leak',DAFEIYU_MODEL_KEY:'synthetic-must-not-leak'};
const script=name=>path.join(plugin,'bin',name);
const cli=async verb=>JSON.parse((await run('/bin/bash',[script('client.command'),verb],{env,timeout:30000})).stdout);
const expected=state=>({account:state.config.expectedSelfID,generation:state.runtime.generation,revision:state.configurationRevision});
const sleep=ms=>new Promise(resolve=>setTimeout(resolve,ms));
let stdio,httpClient,httpChild,backend;
try {
  await run('/usr/bin/unzip',['-q',archive,'-d',temporary]);
  const manifest=JSON.parse(await fs.readFile(path.join(plugin,'mcp.json'),'utf8'));
  assert.equal(manifest.mcpServers['dafeiyu-qq-macos-test'].type,'stdio');
  const build=JSON.parse(await fs.readFile(path.join(plugin,'build.json'),'utf8'));
  assert.equal(build.configuration,'release');assert.equal(build.architecture,process.arch);
  for(const binary of [path.join(plugin,'runtime','node'),path.join(plugin,'runtime','node_modules',`@sakurafan1023/qq-darwin-${process.arch}`,'dafeiyu-qq')]) {
    await run('/usr/bin/codesign',['--verify','--strict',binary]);
  }
  await run('/usr/bin/codesign',['--verify','--strict',path.join(plugin,'DaFeiYu MCP Test.app')]);
  stdio=new Client({name:'synthetic-macos-host',version:'1.0.0'});
  await stdio.connect(new StdioClientTransport({command:'/bin/bash',args:[script('mcp.sh')],env,stderr:'pipe'}));
  assert.equal((await stdio.listTools()).tools.length,7);
  const read=async()=>{const reply=await stdio.callTool({name:'qq_status',arguments:{}});assert.ok(!reply.isError);return reply.structuredContent;};
  let state=await read();backend=state.runtime;
  assert.equal(state.config.expectedSelfID,'');assert.equal(state.connected,false);assert.equal(state.running,false);
  assert.equal(state.temporaryCredentials,false);
  const save=await stdio.callTool({name:'qq_save_connection',arguments:{...expected(state),expectedSelfID:'12345',endpoint:'ws://127.0.0.1:30123'}});
  assert.ok(!save.isError);
  const conflict=await stdio.callTool({name:'qq_save_connection',arguments:{...expected(state),expectedSelfID:'12345',endpoint:'ws://127.0.0.1:30123'}});
  assert.equal(conflict.isError,true);assert.deepEqual(conflict.structuredContent,{code:'QQ_STATE_CHANGED',submitted:false});
  state=await read();
  const nativeState=await cli('status');
  assert.equal(nativeState.runtime.pid,backend.pid);assert.equal(nativeState.configurationRevision,state.configurationRevision);
  assert.equal(nativeState.config.expectedSelfID,'12345');
  // Check the exact packaged browser client's HTTP surface; this is not a browser screenshot acceptance.
  const record=JSON.parse(await fs.readFile(path.join(data,'qq-worker.json'),'utf8')),panel=new URL(record.controlURL);
  const html=await fetch(panel.origin);assert.equal(html.status,200);const page=await html.text();assert.match(page,/app.js/);assert.doesNotMatch(page,/data-module="(?:social|wechat)"/);
  assert.equal((await fetch(panel.origin+'/app.js')).status,200);
  assert.equal((await fetch(panel.origin+'/api/status')).status,403);
  const config=await fetch(panel.origin+'/api/status',{headers:{'X-QQ-Control':panel.hash.slice(1)}}).then(response=>response.json());
  assert.equal(config.runtime.pid,backend.pid);assert.equal(config.config.expectedSelfID,state.config.expectedSelfID);
  httpChild=spawn('/bin/bash',[script('http.command')],{env,stdio:['ignore','ignore','pipe']});
  const url=await new Promise((resolve,reject)=>{
    let text='';const timeout=setTimeout(()=>reject(new Error('HTTP entry startup timed out')),15000);
    httpChild.once('error',error=>{clearTimeout(timeout);reject(error);});
    httpChild.stderr.on('data',chunk=>{
      text+=chunk.toString();const match=text.match(/DAFEIYU_MCP_HTTP_URL=(http:\/\/127\.0\.0\.1:\d+\/mcp\/[a-f0-9]{64})/);
      if(match){clearTimeout(timeout);resolve(match[1]);}
      if(text.length>8192){clearTimeout(timeout);reject(new Error('Unexpected HTTP startup output'));}
    });
  });
  httpClient=new Client({name:'synthetic-streamable-host',version:'1.0.0'});
  await httpClient.connect(new StreamableHTTPClientTransport(new URL(url)));
  const httpState=(await httpClient.callTool({name:'qq_status',arguments:{}})).structuredContent;
  assert.equal(httpState.runtime.pid,backend.pid);assert.equal(httpState.config.expectedSelfID,'12345');
  assert.ok(!(await httpClient.callTool({name:'qq_run_control',arguments:{...expected(httpState),action:'pause'}})).isError);
  await httpClient.close();httpClient=undefined;
  httpChild.kill();await new Promise(resolve=>httpChild.once('exit',resolve));httpChild=undefined;
  await stdio.close();stdio=undefined;
  const alive=await cli('status');assert.equal(alive.runtime.pid,backend.pid);assert.equal(alive.running,false);
  assert.equal(alive.calls,0);assert.equal(alive.confirmed,0);
  await cli('stop');
  for(let i=0;i<100;i++){try{await fs.access(path.join(data,'qq-worker.json'));await sleep(50);}catch{break;}}
  await assert.rejects(fs.access(path.join(data,'qq-worker.json')));backend=undefined;
  // A restart must retain config, use a new generation, and remain disconnected/stopped.
  const restarted=await cli('status');backend=restarted.runtime;
  assert.notEqual(restarted.runtime.generation,alive.runtime.generation);assert.equal(restarted.config.expectedSelfID,'12345');
  assert.equal(restarted.connected,false);assert.equal(restarted.running,false);assert.equal(restarted.calls,0);
  await cli('stop');await sleep(500);backend=undefined;
  console.log('PASS: relocated release ZIP, bundled Node without developer PATH, code signatures, MCP stdio/HTTP, client HTTP sharing, first config, pause, Host exit, stop/restart; zero QQ/model calls');
} finally {
  await stdio?.close();await httpClient?.close();httpChild?.kill();
  if(backend){try{process.kill(backend.pid);}catch{}}
  await sleep(300);await fs.rm(temporary,{recursive:true,force:true});
}
