#!/usr/bin/env node
// Assemble tested public QQ packages and the official local Node runtime into desktop installers.
import fs from 'node:fs/promises';
import path from 'node:path';
import {fileURLToPath, pathToFileURL} from 'node:url';
import {spawnSync} from 'node:child_process';
import {createHash} from 'node:crypto';

const root=fileURLToPath(new URL('..',import.meta.url));
if (!['darwin-arm64','win32-x64'].includes(`${process.platform}-${process.arch}`)) throw new Error('Build on Mac arm64 or Windows x64');
const {version:runtimeVersion}=JSON.parse(await fs.readFile(path.join(root,'release-plan.json'),'utf8'));
const desktop=JSON.parse(await fs.readFile(path.join(root,'desktop-release.json'),'utf8'));
const {version}=desktop;
const output=path.join(root,'dist','desktop'),work=path.join(output,process.platform);
const bundle=path.join(work,process.platform==='darwin'?'DaFeiYu.app':'DaFeiYu');
const runtime=process.platform==='darwin'?path.join(bundle,'Contents','Resources','QQRuntime'):path.join(bundle,'runtime');
const documents=process.platform==='darwin'?path.join(bundle,'Contents','Resources'):bundle;
const npm=process.env.npm_execpath;
if (!npm) throw new Error('Run npm run build:desktop');
function run(command,args,options={}) {
  const result=spawnSync(command,args,{cwd:root,stdio:'inherit',...options});
  if (result.error || result.status!==0) throw new Error('Desktop build failed: '+path.basename(command));
  return result;
}
async function bundledAsset(item) {
  const cache=path.join(root,'dist','third-party-napcat',item.filename);
  const matches=bytes=>createHash('sha256').update(bytes).digest('hex')===item.sha256;
  const existing=await fs.readFile(cache).catch(error=>{if(error.code==='ENOENT')return null;throw error;});
  if(existing&&matches(existing)) return cache;
  const response=await fetch(item.url,{signal:AbortSignal.timeout(120000)});
  if(!response.ok) throw new Error('Official NapCat archive download failed');
  let size=0;const parts=[];
  for await(const chunk of response.body){size+=chunk.length;if(size>128*1024*1024)throw new Error('NapCat archive exceeds limit');parts.push(chunk);}
  const bytes=Buffer.concat(parts);if(!matches(bytes))throw new Error('Official NapCat archive SHA-256 differs from pinned release');
  await fs.mkdir(path.dirname(cache),{recursive:true});await fs.writeFile(cache,bytes);return cache;
}
await fs.rm(work,{recursive:true,force:true});await fs.mkdir(runtime,{recursive:true});
if (process.platform==='darwin') {
  run('/bin/bash',['scripts/build.sh']);
  await fs.cp(path.join(root,'dist','WeChat AI Bot.app'),bundle,{recursive:true});
}
await fs.writeFile(path.join(runtime,'package.json'),JSON.stringify({name:'dafeiyu-desktop-runtime',version,private:true},null,2));
run(process.execPath,[npm,'install','--prefix',runtime,'--ignore-scripts','--no-audit','--no-fund','--package-lock=false','--bin-links=false',
  ...['cli','qq','mcp'].map(name=>`@sakurafan1023/${name}@${runtimeVersion}`)]);
const node=path.join(runtime,process.platform==='win32'?'node.exe':'node');
await fs.copyFile(process.execPath,node);await fs.chmod(node,0o755);
let nodeLicense;
for (const candidate of [path.join(path.dirname(process.execPath),'LICENSE'),path.join(path.dirname(process.execPath),'LICENSE.txt'),path.join(path.dirname(process.execPath),'..','LICENSE')]) {
  try { nodeLicense=await fs.readFile(candidate);break; } catch (error) { if(error.code!=='ENOENT') throw error; }
}
if (!nodeLicense) {
  const response=await fetch(`https://raw.githubusercontent.com/nodejs/node/${process.version}/LICENSE`);
  if(!response.ok) throw new Error('Official Node license unavailable');nodeLicense=Buffer.from(await response.arrayBuffer());
}
await fs.writeFile(path.join(runtime,'NODE-LICENSE.txt'),nodeLicense);
await fs.copyFile(path.join(root,'scripts','desktop-launch.mjs'),path.join(runtime,'launch.mjs'));
await fs.copyFile(path.join(root,'scripts','napcat-setup.mjs'),path.join(runtime,'napcat-setup.mjs'));
const napcat=path.join(runtime,'napcat');await fs.mkdir(napcat);
for(const item of [desktop.napcat,...(process.platform==='darwin'?[desktop.macInstaller]:[])]) {
  await fs.copyFile(await bundledAsset(item),path.join(napcat,item.filename));
}
await fs.writeFile(path.join(napcat,'manifest.json'),JSON.stringify({napcat:desktop.napcat,macInstaller:desktop.macInstaller},null,2));
for(const name of await fs.readdir(path.join(root,'docs','licenses','napcat'))) await fs.copyFile(path.join(root,'docs','licenses','napcat',name),path.join(napcat,name));
if(process.platform==='darwin') {
  const tools=path.join(napcat,'mac-tools');await fs.mkdir(tools);
  run('/usr/bin/unzip',['-q',path.join(napcat,desktop.macInstaller.filename),'-d',tools]);
  run('/usr/bin/codesign',['--verify','--deep','--strict',path.join(tools,'NapCatInstaller.app')]);
}
const native=path.join(runtime,'node_modules','@sakurafan1023',`qq-${process.platform}-${process.arch}`);
const qq=await import(pathToFileURL(path.join(runtime,'node_modules','@sakurafan1023','qq','lib','runtime.mjs')).href);
await qq.verifyArtifact(native,process.platform==='win32'?'dafeiyu-qq.exe':'dafeiyu-qq');
if(process.platform==='darwin') {
  // Verify the original npm artifact first, then remove private DWARF paths from the desktop copy.
  const binary=path.join(native,'dafeiyu-qq');
  run('/usr/bin/strip',['-S',binary]);
  run('/usr/bin/codesign',['--force','--sign','-',binary]);
  const integrityFile=path.join(native,'integrity.json');
  const integrity=JSON.parse(await fs.readFile(integrityFile,'utf8'));
  integrity['dafeiyu-qq']=createHash('sha256').update(await fs.readFile(binary)).digest('hex');
  await fs.writeFile(integrityFile,JSON.stringify(integrity,null,2));
  await qq.verifyArtifact(native,'dafeiyu-qq');
}
for (const name of ['cli','qq','mcp',`qq-${process.platform}-${process.arch}`]) {
  const metadata=JSON.parse(await fs.readFile(path.join(runtime,'node_modules','@sakurafan1023',name,'package.json'),'utf8'));
  if(metadata.version!==runtimeVersion) throw new Error('Installed package version mismatch');
}
const readme=await fs.readFile(path.join(root,'docs','DESKTOP_INSTALL.md'),'utf8');
await fs.writeFile(path.join(documents,'README.txt'),'\uFEFF'+readme);
for (const name of ['LICENSE','THIRD_PARTY_NOTICES.md']) await fs.copyFile(path.join(root,name),path.join(documents,name));
const source=spawnSync('git',['rev-parse','HEAD'],{cwd:root,encoding:'utf8'});
if(source.status!==0) throw new Error('Unable to record packaging source');
await fs.writeFile(path.join(documents,'desktop-build.json'),JSON.stringify({version,runtimeVersion,napcatVersion:desktop.napcat.version,platform:process.platform,architecture:process.arch,nodeVersion:process.version,
  packagingCommit:source.stdout.trim(),runtimeSource:'public npm fixed version; native integrity verified',
  macNativeDebugInfoRemoved:process.platform==='darwin',signedByDeveloper:false},null,2)+'\n');
if (process.platform==='darwin') {
  const launcher=path.join(bundle,'Contents','Resources','dafeiyu-mcp.command');
  await fs.writeFile(launcher,'#!/bin/sh\nset -eu\nRUNTIME="$(CDPATH= cd -- "$(dirname -- "$0")/QQRuntime" && pwd)"\nexec "$RUNTIME/node" "$RUNTIME/launch.mjs" mcp\n',{mode:0o755});
  run('/usr/bin/python3',['-c','import plistlib,sys; p=sys.argv[1]; d=plistlib.load(open(p,"rb")); d.update(CFBundleName="DaFeiYu",CFBundleDisplayName="大肥鱼",CFBundleShortVersionString="0.3.0",CFBundleVersion="3003"); plistlib.dump(d,open(p,"wb"))',path.join(bundle,'Contents','Info.plist')]);
  for (const binary of [node,path.join(native,'dafeiyu-qq'),path.join(bundle,'Contents','MacOS','WeChatAIBot')]) {
    const linked=spawnSync('/usr/bin/otool',['-L',binary],{encoding:'utf8'});
    if(linked.status!==0||linked.stdout.split('\n').slice(1).some(line=>line.trim()&&!/^\s+\/(?:usr\/lib|System\/Library)\//.test(line))) throw new Error('Desktop binary has non-system dynamic libraries');
    // The app's Info.plist was updated above; its executable is re-signed with the bundle below.
    if(binary!==path.join(bundle,'Contents','MacOS','WeChatAIBot')) run('/usr/bin/codesign',['--verify','--strict',binary]);
  }
  run('/usr/bin/codesign',['--force','--sign','-','--identifier','org.dafeiyu.bot',bundle]);
  run('/usr/bin/codesign',['--verify','--deep','--strict',bundle]);
  const imageRoot=path.join(work,'image');await fs.mkdir(imageRoot);await fs.rename(bundle,path.join(imageRoot,'DaFeiYu.app'));
  await fs.symlink('/Applications',path.join(imageRoot,'Applications'));await fs.writeFile(path.join(imageRoot,'README.txt'),'\uFEFF'+readme);
  const image=path.join(output,`DaFeiYu-${version}-macos-arm64.dmg`);await fs.rm(image,{force:true});
  run('/usr/bin/hdiutil',['create','-ov','-volname','DaFeiYu','-srcfolder',imageRoot,'-format','UDZO',image]);
  run('/usr/bin/hdiutil',['verify',image]);
  console.log('Desktop installer: '+image);
} else {
  const csc=path.join(process.env.SystemRoot,'Microsoft.NET','Framework64','v4.0.30319','csc.exe');
  run(csc,['/nologo','/codepage:65001','/target:winexe','/reference:System.Windows.Forms.dll',`/out:${path.join(bundle,'DaFeiYu.exe')}`,path.join(root,'scripts','windows-client.cs')]);
  await fs.writeFile(path.join(bundle,'Stop DaFeiYu.cmd'),'@echo off\r\n"%~dp0runtime\\node.exe" "%~dp0runtime\\launch.mjs" disconnect\r\nif errorlevel 1 exit /b 1\r\n"%~dp0runtime\\node.exe" "%~dp0runtime\\launch.mjs" stop\r\n');
  await fs.writeFile(path.join(bundle,'Open NapCat.cmd'),'@echo off\r\n"%~dp0DaFeiYu.exe" --napcat\r\n');
  const compiler=path.join(process.env['ProgramFiles(x86)'],'Inno Setup 6','ISCC.exe');
  run(compiler,[`/DBundleDir=${bundle}`,`/DOutputDir=${output}`,`/DAppVersion=${version}`,path.join(root,'scripts','windows-installer.iss')]);
  const archive=path.join(output,`DaFeiYu-${version}-windows-x64-portable.zip`);await fs.rm(archive,{force:true});
  run('tar.exe',['-a','-cf',path.relative(work,archive),'DaFeiYu'],{cwd:work});
  console.log('Desktop installer and portable ZIP: '+output);
}
