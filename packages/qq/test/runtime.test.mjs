import { test } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import { randomUUID } from 'node:crypto';
import { ensureRuntime, status, action, expectation, parseRecord, dataDirectory } from '../lib/runtime.mjs';

test('private discovery rejects remote addresses and incompatible runtime identities', () => {
  const base = { schema: 1, module: 'qq', version: '0.3.0-preview.2', pid: process.pid, generation: randomUUID(),
    controlURL: 'http://127.0.0.1:1234/#' + randomUUID() + randomUUID() };
  assert.equal(parseRecord(base).origin, 'http://127.0.0.1:1234');
  for (const change of [{controlURL:base.controlURL.replace('127.0.0.1','example.com')},{version:'different'},{module:'wechat'},{pid:0}]) {
    assert.throws(() => parseRecord({...base,...change}));
  }
  assert.match(dataDirectory({LOCALAPPDATA:'C:\\Users\\synthetic\\AppData\\Local'},'win32'), /DaFeiYu$/);
  assert.throws(() => dataDirectory({},'win32'));
});

test('missing backend with start disabled does not create an engine', async () => {
  const directory = await fs.mkdtemp(path.join(os.tmpdir(),'dafeiyu-missing-'));
  try { await assert.rejects(ensureRuntime({directory,start:false}), /not running/); }
  finally { await fs.rm(directory,{recursive:true,force:true}); }
});

test('real QQ worker is shared by concurrent clients; revisions, scope and restart remain bounded', {skip:!process.env.DAFEIYU_QQ_ROOT}, async () => {
  const directory = await fs.mkdtemp(path.join(os.tmpdir(),'dafeiyu-worker-'));
  let runtime;
  try {
    const [a,b] = await Promise.all([ensureRuntime({directory}),ensureRuntime({directory})]);
    runtime = a; assert.equal(a.pid,b.pid); assert.equal(a.generation,b.generation);
    let state = await status(a);
    assert.equal(state.running,false); assert.equal(state.connected,false); assert.equal(state.calls,0); assert.equal(state.confirmed,0);
    assert.equal(state.memories,undefined);
    const stale = expectation(state);
    await action(a,{action:'saveConnection',endpoint:'ws://127.0.0.1:30123',expectedSelfID:'12345'},stale);
    await assert.rejects(action(a,{action:'saveConnection',endpoint:'ws://127.0.0.1:30124',expectedSelfID:'12345'},stale), error=>error.code==='QQ_STATE_CHANGED' && /changed/.test(error.message));
    state = await status(b);
    assert.equal(state.config.expectedSelfID,'12345');
    assert.equal(state.config.endpoint,'ws://127.0.0.1:30123');
    await assert.rejects(action(a,{action:'send_private_msg',user_id:'54321',message:'not allowed'},expectation(state)),/Unsupported/);
    await assert.rejects(action(a,{action:'start'},expectation(state)),/did not complete/);
    assert.equal((await status(a)).running,false);
    await action(a,{action:'pause'},expectation(await status(a)));
  } finally {
    if (runtime) { try { process.kill(runtime.pid); } catch {} }
    await new Promise(resolve=>setTimeout(resolve,200));
    await fs.rm(directory,{recursive:true,force:true});
  }
});

test('Windows discovery rejects an extra reader ACE on its private record', {skip:process.platform!=='win32'||!process.env.DAFEIYU_QQ_ROOT,timeout:90000}, async () => {
  const {execFile}=await import('node:child_process'), {promisify}=await import('node:util');
  const directory=await fs.mkdtemp(path.join(os.tmpdir(),'dafeiyu-acl-test-'));
  let runtime;
  try {
    runtime=await ensureRuntime({directory});
    const script="$ErrorActionPreference='Stop'; Import-Module ($PSHOME + '/Modules/Microsoft.PowerShell.Security/Microsoft.PowerShell.Security.psd1') -ErrorAction Stop; $p=$env:DAFEIYU_ACL_TEST_FILE; $a=Get-Acl -LiteralPath $p; $sid=[System.Security.Principal.SecurityIdentifier]::new('S-1-1-0'); $r=[System.Security.AccessControl.FileSystemAccessRule]::new($sid,'Read','Allow'); $a.AddAccessRule($r); Set-Acl -LiteralPath $p -AclObject $a";
    await promisify(execFile)(path.join(process.env.SystemRoot,'System32','WindowsPowerShell','v1.0','powershell.exe'),['-NoProfile','-NonInteractive','-Command',script],{
      timeout:5000,windowsHide:true,env:{...process.env,DAFEIYU_ACL_TEST_FILE:path.join(directory,'qq-worker.json')}});
    await assert.rejects(ensureRuntime({directory,start:false}), error => error.code === 23);
  } finally {
    if(runtime){try{await action(runtime,{action:'shutdown'},expectation(await status(runtime)));}catch{try{process.kill(runtime.pid);}catch{}}}
    await new Promise(resolve=>setTimeout(resolve,500));
    await fs.rm(directory,{recursive:true,force:true});
  }
});
