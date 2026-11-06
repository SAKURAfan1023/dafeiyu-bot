#!/usr/bin/env node
// Exercise actual DMG/Setup installation, relocated bundled runtimes, and shared client/MCP ownership.
import fs from 'node:fs/promises';
import path from 'node:path';
import os from 'node:os';
import assert from 'node:assert/strict';
import {fileURLToPath} from 'node:url';
import {execFile} from 'node:child_process';
import {promisify} from 'node:util';
import {Client} from '@modelcontextprotocol/sdk/client/index.js';
import {StdioClientTransport} from '@modelcontextprotocol/sdk/client/stdio.js';

const root=fileURLToPath(new URL('..',import.meta.url)),run=promisify(execFile);
const {version}=JSON.parse(await fs.readFile(path.join(root,'desktop-release.json'),'utf8'));
const output=path.join(root,'dist','desktop');
const temporary=await fs.mkdtemp(path.join(os.tmpdir(),'DaFeiYu 安装 test '));
const data=path.join(temporary,'QQ data');
const env={...process.env,DAFEIYU_DATA_DIR:data,DAFEIYU_QQ_ROOT:'/invalid-synthetic-source',DAFEIYU_RESOURCES:'/invalid-synthetic-resources',
  DAFEIYU_MODULES_DIR:'/invalid-synthetic-modules',DAFEIYU_ONEBOT_TOKEN:'synthetic-must-not-be-inherited',DAFEIYU_MODEL_KEY:'synthetic-must-not-be-inherited',
  DAFEIYU_NAPCAT_DIR:path.join(temporary,'NapCat data with spaces')};
env.PATH=process.platform==='win32'?[process.env.SystemRoot,path.join(process.env.SystemRoot,'System32'),path.join(process.env.SystemRoot,'System32','WindowsPowerShell','v1.0')].join(';'):'/usr/bin:/bin';
const sleep=ms=>new Promise(resolve=>setTimeout(resolve,ms));
let installed,runtime,node,client,backend,mount,installer;
const invoke=verb=>run(node,[path.join(runtime,'launch.mjs'),verb],{env,cwd:temporary,timeout:60000,maxBuffer:500000});
try {
  if(process.platform==='darwin') {
    mount=path.join(temporary,'mounted');await fs.mkdir(mount);
    const image=path.join(output,`DaFeiYu-${version}-macos-arm64.dmg`);
    await run('/usr/bin/hdiutil',['verify',image],{timeout:120000});
    await run('/usr/bin/hdiutil',['attach','-readonly','-nobrowse','-mountpoint',mount,image],{timeout:120000});
    assert.equal(await fs.readlink(path.join(mount,'Applications')),'/Applications');
    installed=path.join(temporary,'Applications with spaces','DaFeiYu.app');
    await fs.mkdir(path.dirname(installed));await fs.cp(path.join(mount,'DaFeiYu.app'),installed,{recursive:true});
    await run('/usr/bin/hdiutil',['detach',mount]);mount=undefined;
    await run('/usr/bin/codesign',['--verify','--deep','--strict',installed]);
    runtime=path.join(installed,'Contents','Resources','QQRuntime');node=path.join(runtime,'node');
    // Test the native client's exact copied executable and packaged resources, without launching a user session.
    await run('/usr/bin/python3',[path.join(root,'scripts','test-control-panel.py'),path.join(installed,'Contents','MacOS','WeChatAIBot')],
      {env:{...env,DAFEIYU_QQ_ROOT:undefined,DAFEIYU_RESOURCES:undefined},timeout:120000,maxBuffer:1000000});
  } else if(process.platform==='win32') {
    installed=path.join(temporary,'Programs with spaces','DaFeiYuQQ');
    installer=path.join(output,`DaFeiYu-${version}-windows-x64-setup.exe`);
    await run(installer,['/VERYSILENT','/SUPPRESSMSGBOXES','/NORESTART','/SP-',`/DIR=${installed}`],{env,timeout:180000,maxBuffer:1000000});
    await fs.access(path.join(installed,'DaFeiYu.exe'));await fs.access(path.join(installed,'unins000.exe'));
    await fs.access(path.join(process.env.APPDATA,'Microsoft','Windows','Start Menu','Programs','大肥鱼 QQ.lnk'));
    await fs.access(path.join(process.env.APPDATA,'Microsoft','Windows','Start Menu','Programs','打开内置 NapCat.lnk'));
    runtime=path.join(installed,'runtime');node=path.join(runtime,'node.exe');
  } else throw new Error('Run desktop tests on Mac arm64 or Windows x64');
  const manifest=JSON.parse(await fs.readFile(path.join(process.platform==='darwin'?path.join(installed,'Contents','Resources'):installed,'desktop-build.json'),'utf8'));
  assert.equal(manifest.version,version);assert.equal(manifest.platform,process.platform);assert.equal(manifest.signedByDeveloper,false);
  assert.equal(manifest.napcatVersion,'4.18.42');
  const prepared=JSON.parse((await run(node,[path.join(runtime,'napcat-setup.mjs'),'--prepare-only'],{env,timeout:120000})).stdout);
  assert.equal(prepared.prepared,true);assert.equal(prepared.reusedExisting,false);assert.equal(prepared.bundledVersion,'4.18.42');
  await fs.access(path.join(env.DAFEIYU_NAPCAT_DIR,'napcat.mjs'));
  const retained=path.join(env.DAFEIYU_NAPCAT_DIR,'config','synthetic-retained.json');
  await fs.mkdir(path.dirname(retained),{recursive:true});await fs.writeFile(retained,'{"synthetic":true}');
  const again=JSON.parse((await run(node,[path.join(runtime,'napcat-setup.mjs'),'--prepare-only'],{env,timeout:120000})).stdout);
  assert.equal(again.reusedExisting,true);assert.equal(await fs.readFile(retained,'utf8'),'{"synthetic":true}');
  const archive=path.join(runtime,'napcat','NapCat.Shell.zip'),originalArchive=await fs.readFile(archive);
  try {
    await fs.appendFile(archive,'synthetic corruption');
    await assert.rejects(run(node,[path.join(runtime,'napcat-setup.mjs'),'--prepare-only'],{env,timeout:30000}),error=>error.code===1&&error.stderr.includes('integrity check failed'));
  } finally {await fs.writeFile(archive,originalArchive);}
  for(const binary of [node,path.join(runtime,'node_modules','@sakurafan1023',`qq-${process.platform}-${process.arch}`,process.platform==='win32'?'dafeiyu-qq.exe':'dafeiyu-qq')]) await fs.access(binary);
  client=new Client({name:'synthetic-desktop-installer-host',version:'1.0.0'});
  const transport=process.platform==='darwin'
    ?new StdioClientTransport({command:path.join(installed,'Contents','Resources','dafeiyu-mcp.command'),env,stderr:'pipe'})
    :new StdioClientTransport({command:node,args:[path.join(runtime,'launch.mjs'),'mcp'],env,stderr:'pipe'});
  await client.connect(transport);assert.equal((await client.listTools()).tools.length,7);
  const initial=(await client.callTool({name:'qq_status',arguments:{}})).structuredContent;backend=initial.runtime;
  assert.equal(initial.connected,false);assert.equal(initial.running,false);assert.equal(initial.temporaryCredentials,false);
  const expected={account:initial.config.expectedSelfID,generation:initial.runtime.generation,revision:initial.configurationRevision};
  const saved=await client.callTool({name:'qq_save_connection',arguments:{...expected,endpoint:'ws://127.0.0.1:30123',expectedSelfID:'12345'}});
  assert.ok(!saved.isError);
  const record=JSON.parse(await fs.readFile(path.join(data,'qq-worker.json'),'utf8')),url=new URL(record.controlURL);
  const html=await fetch(url.origin);assert.equal(html.status,200);assert.match(await html.text(),/app.js/);
  const script=await fetch(url.origin+'/app.js');assert.equal(script.status,200);assert.ok((await script.text()).length>0);
  const denied=await fetch(url.origin+'/api/status');assert.equal(denied.status,403);await denied.text();
  const state=await fetch(url.origin+'/api/status',{headers:{'X-QQ-Control':url.hash.slice(1)}}).then(r=>r.json());
  assert.equal(state.runtime.pid,backend.pid);assert.equal(state.config.expectedSelfID,'12345');
  if(process.platform==='win32') {
    const portable=path.join(temporary,'Portable with spaces');await fs.mkdir(portable);
    // Windows tar's argv uses the legacy code page; CreateProcess accepts a Unicode working directory.
    await run(path.join(process.env.SystemRoot,'System32','tar.exe'),['-xf',path.join(output,`DaFeiYu-${version}-windows-x64-portable.zip`)],{cwd:portable});
    const portableRuntime=path.join(portable,'DaFeiYu','runtime');
    const portableState=JSON.parse((await run(path.join(portableRuntime,'node.exe'),[path.join(portableRuntime,'launch.mjs'),'status'],{env,timeout:60000})).stdout);
    assert.equal(portableState.runtime.pid,backend.pid);
    // Exercise the installed graphical launcher, not only its underlying Node command.
    await run(path.join(installed,'DaFeiYu.exe'),[],{env,timeout:60000});
    assert.equal(JSON.parse((await invoke('status')).stdout).runtime.pid,backend.pid);
  }
  await client.close();client=undefined;
  const alive=JSON.parse((await invoke('status')).stdout);
  assert.equal(alive.runtime.pid,backend.pid);assert.equal(alive.calls,0);assert.equal(alive.confirmed,0);
  await invoke('disconnect');await invoke('stop');backend=undefined;
  for(let i=0;i<100;i++){try{await fs.access(path.join(data,'qq-worker.json'));await sleep(100);}catch{break;}}
  await assert.rejects(fs.access(path.join(data,'qq-worker.json')));
  if(process.platform==='win32') {
    // Reinstall with retained synthetic settings, then verify uninstall leaves user data intact.
    await run(installer,['/VERYSILENT','/SUPPRESSMSGBOXES','/NORESTART','/SP-',`/DIR=${installed}`],{env,timeout:180000});
  }
  const restarted=JSON.parse((await invoke('status')).stdout);backend=restarted.runtime;
  assert.equal(restarted.config.expectedSelfID,'12345');assert.equal(restarted.connected,false);assert.equal(restarted.running,false);
  assert.notEqual(restarted.runtime.generation,alive.runtime.generation);
  await invoke('stop');backend=undefined;await sleep(500);
  if(process.platform==='win32') {
    const before=await fs.readFile(path.join(data,'qq-state.json'));
    await run(path.join(installed,'unins000.exe'),['/VERYSILENT','/SUPPRESSMSGBOXES','/NORESTART'],{env,timeout:120000});
    for(let i=0;i<100;i++){try{await fs.access(path.join(installed,'DaFeiYu.exe'));await sleep(100);}catch{break;}}
    await assert.rejects(fs.access(path.join(installed,'DaFeiYu.exe')));
    assert.deepEqual(await fs.readFile(path.join(data,'qq-state.json')),before);
    assert.equal(await fs.readFile(retained,'utf8'),'{"synthetic":true}');
    await assert.rejects(fs.access(path.join(process.env.APPDATA,'Microsoft','Windows','Start Menu','Programs','大肥鱼 QQ.lnk')));
    await assert.rejects(fs.access(path.join(process.env.APPDATA,'Microsoft','Windows','Start Menu','Programs','打开内置 NapCat.lnk')));
  }
  const result={version,platform:process.platform,architecture:process.arch,result:'passed',install:'actual DMG copy or Setup.exe',
    freshData:true,externalNodeOrSwiftOnPath:false,mcpTools:7,clientHttp:true,sharedWorker:true,hostExit:true,stopRestart:true,
    reinstallAndUninstallPreserveData:process.platform==='win32'?'passed':'not applicable',
    bundledNapCat:'offline preparation, existing config retention, tamper rejection passed',realQQOrModelCalls:0};
  await fs.writeFile(path.join(output,`validation-${process.platform}.json`),JSON.stringify(result,null,2)+'\n');
  console.log('PASS: installed desktop artifact, spaces/Chinese paths, bundled Node with clean PATH, client HTTP, real MCP stdio, shared backend, Host exit, stop/restart'+(process.platform==='win32'?', graphical launcher, reinstall and uninstall preserve data':' and native client packaged HTTP boundary')+'; zero real QQ/model calls');
} finally {
  await client?.close();if(backend){try{process.kill(backend.pid);}catch{}}
  if(mount) await run('/usr/bin/hdiutil',['detach',mount]).catch(()=>{});
  if(process.platform==='win32'&&installed) {
    await run(path.join(installed,'unins000.exe'),['/VERYSILENT','/SUPPRESSMSGBOXES','/NORESTART'],{env,timeout:120000}).catch(()=>{});
  }
  await sleep(500);await fs.rm(temporary,{recursive:true,force:true});
}
