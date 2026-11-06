#!/usr/bin/env node
import fs from 'node:fs/promises';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {spawnSync} from 'node:child_process';

if(process.platform!=='darwin'||!['arm64','x64'].includes(process.arch)) throw new Error('Build the macOS test bundle on its target Mac architecture');
const root=fileURLToPath(new URL('..',import.meta.url)), version='0.3.0-preview.2';
const args=process.argv.slice(2);
if(args.length && (args.length!==2 || args[0]!=='--output')) throw new Error('Usage: build-macos-mcp.mjs [--output dist/macos-mcp-arm64]');
const output=path.resolve(root,args[1]??`dist/macos-mcp-${process.arch}`);
if(!output.startsWith(path.join(root,'dist')+path.sep)) throw new Error('Use a generated directory inside dist/');
const native=path.join(output,'native'), archives=path.join(output,'npm');
const plugin=path.join(output,'dafeiyu-qq-macos-test');
const npm=process.env.npm_execpath;
if(!npm) throw new Error('Run npm run build:macos-mcp');
function run(command,args,options={}) {
  const result=spawnSync(command,args,{cwd:root,stdio:'inherit',...options});
  if(result.error||result.status!==0) throw new Error('macOS bundle step failed');
}
run('python3',['scripts/build-qq.py','--output',path.relative(root,native)]);
run(process.execPath,['scripts/pack-qq.mjs','--runtime',native,'--output',archives]);
await fs.rm(plugin,{recursive:true,force:true});
await fs.cp(path.join(root,'plugins','macos-test'),plugin,{recursive:true});
const runtime=path.join(plugin,'runtime');
const files=(await fs.readdir(archives)).filter(name=>name.endsWith('.tgz')).map(name=>path.join(archives,name));
if(files.length!==4) throw new Error('Expected four QQ artifacts');
run(process.execPath,[npm,'install','--prefix',runtime,'--ignore-scripts','--omit=optional','--no-audit','--no-fund',...files]);
await fs.copyFile(process.execPath,path.join(runtime,'node'));
await fs.chmod(path.join(runtime,'node'),0o755);
// A portable bundle must not retain npm's local tarball paths or the developer's cache paths.
await fs.writeFile(path.join(runtime,'package.json'),JSON.stringify({name:'dafeiyu-macos-test-runtime',version,private:true},null,2));
for(const name of ['package-lock.json','node_modules/.package-lock.json']) await fs.rm(path.join(runtime,name),{force:true});
await fs.rm(path.join(runtime,'node_modules','.bin'),{recursive:true,force:true});
const nodeLicense=path.join(path.dirname(path.dirname(process.execPath)),'LICENSE');
await fs.copyFile(nodeLicense,path.join(runtime,'NODE-LICENSE.txt'));
await fs.copyFile(path.join(root,'LICENSE'),path.join(plugin,'LICENSE'));
await fs.copyFile(path.join(root,'THIRD_PARTY_NOTICES.md'),path.join(plugin,'THIRD_PARTY_NOTICES.md'));
await fs.copyFile(path.join(root,'docs','MACOS_MCP_TEST.md'),path.join(plugin,'README.md'));
for(const name of ['mcp.sh','client.command','http.command']) await fs.chmod(path.join(plugin,'bin',name),0o755);
// The worker and the bundled official Node runtime depend only on Apple system libraries.
const worker=path.join(runtime,'node_modules',`@sakurafan1023/qq-darwin-${process.arch}`,'dafeiyu-qq');
for(const binary of [worker,path.join(runtime,'node')]) {
  const linked=spawnSync('/usr/bin/otool',['-L',binary],{encoding:'utf8'});
  if(linked.status!==0||linked.stdout.split('\n').slice(1).some(line=>line.trim()&&!/^\s+\/(?:usr\/lib|System\/Library)\//.test(line))) {
    throw new Error('The test bundle has a non-system dynamic library dependency');
  }
}
run('python3',['scripts/build-macos-test-client.py',plugin,'--arch',process.arch]);
await fs.writeFile(path.join(plugin,'build.json'),JSON.stringify({version,platform:'darwin',architecture:process.arch,configuration:'release',nodeVersion:process.version},null,2));
const archive=path.join(root,'dist',`dafeiyu-macos-mcp-${process.arch}-${version}.zip`);
await fs.rm(archive,{force:true});
run('/usr/bin/zip',['-q','-r',archive,path.basename(plugin)],{cwd:output});
console.log('macOS test bundle: '+plugin+'\nArchive: '+archive);
