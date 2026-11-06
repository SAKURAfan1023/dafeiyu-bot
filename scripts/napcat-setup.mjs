// Prepare the unmodified bundled NapCat offline. It never starts QQ or changes its application entry.
import fs from 'node:fs/promises';
import path from 'node:path';
import os from 'node:os';
import {fileURLToPath} from 'node:url';
import {execFile,spawn} from 'node:child_process';
import {promisify} from 'node:util';
import {createHash} from 'node:crypto';

const run=promisify(execFile),root=path.dirname(fileURLToPath(import.meta.url));
const manifest=JSON.parse(await fs.readFile(path.join(root,'napcat','manifest.json'),'utf8'));
const destination=process.env.DAFEIYU_NAPCAT_DIR ?? (process.platform==='darwin'
  ?path.join(os.homedir(),'Library','Containers','com.tencent.qq','Data','Documents','napcat')
  :path.join(process.env.LOCALAPPDATA,'DaFeiYu','NapCat'));
const prepareOnly=process.argv[2]==='--prepare-only';
if(process.argv.length>(prepareOnly?3:2)) throw new Error('Usage: napcat-setup.mjs [--prepare-only]');
for(const item of [manifest.napcat,...(process.platform==='darwin'?[manifest.macInstaller]:[])]) {
  const archive=path.join(root,'napcat',item.filename);
  if(createHash('sha256').update(await fs.readFile(archive)).digest('hex')!==item.sha256) throw new Error('Bundled NapCat integrity check failed');
}
await fs.mkdir(path.dirname(destination),{recursive:true,mode:0o700});
let staging,reused=false;
try {
  const existing=await fs.lstat(destination).catch(error=>{if(error.code==='ENOENT')return null;throw error;});
  if(existing) {
    if(!existing.isDirectory()||existing.isSymbolicLink()) throw new Error('NapCat directory is unsafe');
    await fs.access(path.join(destination,'napcat.mjs'));
    reused=true;
  } else {
    staging=await fs.mkdtemp(path.join(path.dirname(destination),'.napcat-prepare-'));
    if(process.platform==='win32') {
      await run(path.join(process.env.SystemRoot,'System32','WindowsPowerShell','v1.0','powershell.exe'),['-NoProfile','-NonInteractive','-Command',
        'Add-Type -AssemblyName System.IO.Compression.FileSystem; [System.IO.Compression.ZipFile]::ExtractToDirectory($env:DAFEIYU_NAPCAT_ARCHIVE,$env:DAFEIYU_NAPCAT_STAGE)'],
        {env:{...process.env,DAFEIYU_NAPCAT_ARCHIVE:path.join(root,'napcat',manifest.napcat.filename),DAFEIYU_NAPCAT_STAGE:staging},timeout:120000});
    } else {
      await run('/usr/bin/unzip',['-q',path.join(root,'napcat',manifest.napcat.filename),'-d',staging],{timeout:120000});
    }
    await fs.access(path.join(staging,'napcat.mjs'));
    // As in the upstream Mac installer, record the release version in the private installed copy.
    // The bundled upstream archive remains byte-for-byte unchanged.
    const packageFile=path.join(staging,'package.json');
    const metadata=JSON.parse(await fs.readFile(packageFile,'utf8'));
    metadata.version=manifest.napcat.version;await fs.writeFile(packageFile,JSON.stringify(metadata,null,2));
    await fs.copyFile(path.join(root,'napcat','NapCat-LICENSE.txt'),path.join(staging,'NapCat-LICENSE.txt'));
    await fs.rename(staging,destination);staging=undefined;
  }
  if(process.platform==='darwin') {
    const tools=path.join(root,'napcat','mac-tools');
    // The installer is supplied unmodified; it is used to switch QQ's entry only after a user click.
    await fs.access(path.join(tools,'NapCatInstaller.app'));
    if(!prepareOnly) await run('/usr/bin/open',[path.join(tools,'NapCatInstaller.app')]);
  } else if(!prepareOnly) {
    const child=spawn(path.join(process.env.SystemRoot,'explorer.exe'),[destination],{detached:true,stdio:'ignore'});
    await new Promise((resolve,reject)=>{child.once('spawn',resolve);child.once('error',reject);});child.unref();
  }
  console.log(JSON.stringify({prepared:true,directory:destination,bundledVersion:manifest.napcat.version,reusedExisting:reused,
    next:process.platform==='darwin'?'在配置工具中切换 NapCat 入口，再启动；不必点击下载/更新。':'双击 launcher-user.bat（Windows 10 可用 launcher-win10-user.bat），按提示扫码。'}));
} finally { if(staging) await fs.rm(staging,{recursive:true,force:true}); }
