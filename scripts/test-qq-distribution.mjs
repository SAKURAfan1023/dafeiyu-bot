#!/usr/bin/env node
// Install only packed artifacts into an isolated path, then use the real SDK stdio client.
import fs from 'node:fs/promises';
import path from 'node:path';
import os from 'node:os';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { createRequire } from 'node:module';
import { promisify } from 'node:util';
import { execFile } from 'node:child_process';
import assert from 'node:assert/strict';
import { Client } from '@modelcontextprotocol/sdk/client/index.js';
import { StdioClientTransport } from '@modelcontextprotocol/sdk/client/stdio.js';

const run=promisify(execFile), root=fileURLToPath(new URL('..',import.meta.url));
const artifacts=path.resolve(root,process.argv[2]??'dist/npm');
if(!artifacts.startsWith(path.join(root,'dist')+path.sep))throw new Error('Use artifacts inside dist/');
const temporary=await fs.mkdtemp(path.join(os.tmpdir(),'dafeiyu 分包 test '));
const prefix=path.join(temporary,'modules with spaces'), directory=path.join(temporary,'QQ data');
let qq,runtime,client;
const sleep=ms=>new Promise(resolve=>setTimeout(resolve,ms));
try {
  const files=(await fs.readdir(artifacts)).filter(name=>name.endsWith('.tgz')).map(name=>path.join(artifacts,name));
  assert.equal(files.length,4);
  const npm=process.env.npm_execpath; assert.ok(npm,'Run through npm run test:distribution');
  await run(process.execPath,[npm,'install','--prefix',prefix,'--ignore-scripts','--omit=optional','--no-audit','--no-fund',...files],{timeout:120000,maxBuffer:2000000});
  const env={...process.env,DAFEIYU_MODULES_DIR:prefix,DAFEIYU_DATA_DIR:directory};
  delete env.DAFEIYU_QQ_ROOT;
  const require=createRequire(path.join(prefix,'package.json'));
  qq=await import(pathToFileURL(require.resolve('@sakurafan1023/qq')).href);
  // This test must resolve the installed platform package and verify its hashes.
  const oldRoot=process.env.DAFEIYU_QQ_ROOT; delete process.env.DAFEIYU_QQ_ROOT;
  try { runtime=await qq.ensureRuntime({directory}); } finally { if(oldRoot)process.env.DAFEIYU_QQ_ROOT=oldRoot; }
  client=new Client({name:'synthetic-distribution-host',version:'1.0.0'});
  const transport=new StdioClientTransport({command:process.execPath,args:[path.join(prefix,'node_modules','@sakurafan1023','mcp','bin','mcp.mjs'),'--modules','qq'],env,stderr:'pipe'});
  await client.connect(transport);
  assert.equal((await client.listTools()).tools.length,7);
  const initial=(await client.callTool({name:'qq_status',arguments:{}})).structuredContent;
  assert.equal(initial.runtime.pid,runtime.pid); assert.equal(initial.config.expectedSelfID,'');
  const saved=await client.callTool({name:'qq_save_connection',arguments:{...qq.expectation(initial),endpoint:'ws://127.0.0.1:30123',expectedSelfID:'12345'}});
  assert.ok(!saved.isError);
  await client.close(); client=undefined;
  const command=path.join(prefix,'node_modules','@sakurafan1023','cli','bin','dafeiyu.mjs');
  const cli=await run(process.execPath,[command,'qq','status'],{env,timeout:20000});
  const state=JSON.parse(cli.stdout);
  assert.equal(state.runtime.pid,runtime.pid); assert.equal(state.config.expectedSelfID,'12345');
  assert.equal(state.connected,false); assert.equal(state.running,false); assert.equal(state.calls,0); assert.equal(state.confirmed,0);
  await run(process.execPath,[command,'qq','stop'],{env,timeout:20000});
  for(let i=0;i<100;i++){try{await fs.access(path.join(directory,'qq-worker.json'));await sleep(50);}catch{break;}}
  await assert.rejects(fs.access(path.join(directory,'qq-worker.json')));
  runtime=undefined;
  const native=path.dirname(require.resolve(`@sakurafan1023/qq-${process.platform}-${process.arch}/module.json`));
  const script=path.join(native,'Resources','QQControl','app.js'), original=await fs.readFile(script);
  try {
    await fs.appendFile(script,'\n// synthetic integrity mutation\n');
    await assert.rejects(qq.verifyArtifact(native,process.platform==='win32'?'dafeiyu-qq.exe':'dafeiyu-qq'),/integrity/);
  } finally { await fs.writeFile(script,original); }
  console.log('PASS: tarball-only install, paths with spaces/Chinese, binary integrity, real MCP stdio, first setup, shared CLI, idle stop; zero real QQ/AI calls');
} finally {
  await client?.close();
  if(runtime){try{process.kill(runtime.pid);}catch{}}
  await sleep(200);
  await fs.rm(temporary,{recursive:true,force:true});
}
