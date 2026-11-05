#!/usr/bin/env node
// Exercise the documented npx -> selected-module install -> MCP flow against real tarballs.
import fs from 'node:fs/promises';
import path from 'node:path';
import os from 'node:os';
import http from 'node:http';
import assert from 'node:assert/strict';
import {fileURLToPath} from 'node:url';
import {createHash} from 'node:crypto';
import {execFile} from 'node:child_process';
import {promisify} from 'node:util';
import {Client} from '@modelcontextprotocol/sdk/client/index.js';
import {StdioClientTransport} from '@modelcontextprotocol/sdk/client/stdio.js';

const root=fileURLToPath(new URL('..',import.meta.url)),run=promisify(execFile);
const args=process.argv.slice(2);let publicRegistry=false,artifactDirectory='dist/npm-release';
for(let i=0;i<args.length;i++){
  if(args[i]==='--public')publicRegistry=true;
  else if(args[i]==='--directory'&&args[i+1])artifactDirectory=args[++i];
  else throw new Error('Usage: test-npm-install.mjs [--public] [--directory dist/npm-release]');
}
artifactDirectory=path.resolve(root,artifactDirectory);
if(!artifactDirectory.startsWith(path.join(root,'dist')+path.sep))throw new Error('Use artifacts inside dist/');
const plan=JSON.parse(await fs.readFile(path.join(root,'release-plan.json'),'utf8'));
assert.ok(plan.platforms.includes(`${process.platform}-${process.arch}`),'Run on a platform in this release');
const npm=process.env.npm_execpath;assert.ok(npm,'Run through npm run test:npm-install');
const temporary=await fs.mkdtemp(path.join(os.tmpdir(),'dafeiyu npm 安装 '));
const prefix=path.join(temporary,'modules'),directory=path.join(temporary,'QQ data');
const packages=new Map(),tarballs=new Map(),requested=new Set();
for(const name of await fs.readdir(artifactDirectory)) {
  if(!name.endsWith('.tgz'))continue;
  const archive=path.join(artifactDirectory,name);
  const text=await run('tar',['-xOf',archive,'package/package.json']);
  const metadata=JSON.parse(text.stdout);
  if(metadata.name.startsWith('@sakurafan1023/qq-')&&metadata.name!==`@sakurafan1023/qq-${process.platform}-${process.arch}`)continue;
  assert.equal(metadata.version,plan.version);
  const bytes=await fs.readFile(archive);
  packages.set(metadata.name,{metadata,filename:name,bytes});tarballs.set('/tarballs/'+name,bytes);
}
assert.equal(packages.size,4);
const registry=http.createServer((request,response)=>{
  response.setHeader('Cache-Control','no-store');
  if(tarballs.has(request.url)){response.writeHead(200,{'Content-Type':'application/octet-stream'});response.end(tarballs.get(request.url));return;}
  let name;try{name=decodeURIComponent(request.url.split('?')[0].slice(1));}catch{response.writeHead(400).end();return;}
  const item=packages.get(name);
  if(!item){response.writeHead(404,{'Content-Type':'application/json'});response.end('{"error":"not found"}');return;}
  requested.add(name);
  const metadata={...item.metadata,dist:{tarball:`http://127.0.0.1:${registry.address().port}/tarballs/${item.filename}`,
    integrity:'sha512-'+createHash('sha512').update(item.bytes).digest('base64')}};
  response.writeHead(200,{'Content-Type':'application/json'});
  response.end(JSON.stringify({name,versions:{[plan.version]:metadata},'dist-tags':{[plan.tag]:plan.version}}));
});
await new Promise(resolve=>registry.listen(0,'127.0.0.1',resolve));
const config=path.join(temporary,'user.npmrc');
await fs.writeFile(config,`registry=${plan.registry}\n${publicRegistry?'':`@sakurafan1023:registry=http://127.0.0.1:${registry.address().port}/\n`}audit=false\nfund=false\n`,{mode:0o600});
const globalconfig=path.join(temporary,'global.npmrc');await fs.writeFile(globalconfig,'',{mode:0o600});
const env={...process.env,DAFEIYU_MODULES_DIR:prefix,DAFEIYU_DATA_DIR:directory};
for(const key of Object.keys(env))if(/^npm_config_/i.test(key))delete env[key];
Object.assign(env,{npm_config_userconfig:config,npm_config_globalconfig:globalconfig,npm_config_cache:path.join(temporary,'npm cache'),npm_config_audit:'false',npm_config_fund:'false'});
for(const key of Object.keys(env))if(/(?:npm|node).*?(?:auth|token|password)/i.test(key))delete env[key];
delete env.DAFEIYU_QQ_ROOT;delete env.DAFEIYU_RESOURCES;
const cli=(verb,args=[])=>run(process.execPath,[npm,'exec','--yes',`--package=@sakurafan1023/cli@${plan.tag}`,'--','dafeiyu',verb,...args],{cwd:temporary,env,timeout:90000,maxBuffer:500000});
let client,backend;
try {
  await cli('setup',['qq']);
  await fs.access(path.join(prefix,'node_modules/@sakurafan1023/qq/lib/runtime.mjs'));
  await fs.access(path.join(prefix,`node_modules/@sakurafan1023/qq-${process.platform}-${process.arch}/module.json`));
  const state=JSON.parse((await cli('qq',['status'])).stdout);backend=state.runtime;
  assert.equal(state.config.expectedSelfID,'');assert.equal(state.running,false);assert.equal(state.connected,false);
  client=new Client({name:'synthetic-npx-host',version:'1.0.0'});
  await client.connect(new StdioClientTransport({command:process.execPath,args:[npm,'exec','--yes',`--package=@sakurafan1023/mcp@${plan.tag}`,'--','dafeiyu-mcp','--modules','qq'],env,cwd:temporary,stderr:'pipe'}));
  assert.equal((await client.listTools()).tools.length,7);
  const result=await client.callTool({name:'qq_status',arguments:{}});
  assert.equal(result.structuredContent.runtime.pid,backend.pid);assert.equal(result.structuredContent.calls,0);assert.equal(result.structuredContent.confirmed,0);
  await client.close();client=undefined;
  assert.equal(JSON.parse((await cli('qq',['status'])).stdout).runtime.pid,backend.pid);
  await cli('qq',['stop']);await new Promise(resolve=>setTimeout(resolve,500));backend=undefined;
  if(!publicRegistry)assert.deepEqual([...requested].sort(),[...packages.keys()].sort());
  console.log('PASS: actual npx @next, QQ-only stable install with native optional dependency, real MCP stdio, shared CLI, zero QQ/model calls; '+(publicRegistry?'public npm registry with fresh anonymous cache':'local fixture registry, not public publication'));
} finally {
  await client?.close();if(backend){try{process.kill(backend.pid);}catch{}}
  registry.closeAllConnections();await new Promise(resolve=>registry.close(resolve));
  await new Promise(resolve=>setTimeout(resolve,300));await fs.rm(temporary,{recursive:true,force:true});
}
