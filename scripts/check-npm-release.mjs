#!/usr/bin/env node
// Inspect real tarballs and run anonymous publish --dry-run; never upload or change registry state.
import fs from 'node:fs/promises';
import path from 'node:path';
import os from 'node:os';
import {fileURLToPath} from 'node:url';
import {spawnSync} from 'node:child_process';
import {createHash} from 'node:crypto';

const root=fileURLToPath(new URL('..',import.meta.url));
const directory=path.resolve(root,process.argv[2]??'dist/npm-release');
if(!directory.startsWith(path.join(root,'dist')+path.sep)) throw new Error('Inspect generated packages inside dist/');
const plan=JSON.parse(await fs.readFile(path.join(root,'release-plan.json'),'utf8'));
const temporary=await fs.mkdtemp(path.join(os.tmpdir(),'dafeiyu-npm-audit-'));
const env={...process.env};
for(const key of Object.keys(env)) if(/(?:npm|node).*?(?:auth|token|password)/i.test(key)) delete env[key];
const npm=process.env.npm_execpath;
if(!npm) throw new Error('Run npm run check:npm-release');
const report={version:plan.version,tag:plan.tag,registry:plan.registry,platforms:plan.platforms,packages:[],authenticationVerified:false,published:false};
const run=(command,args,options={})=>{
  const result=spawnSync(command,args,{encoding:'utf8',maxBuffer:12000000,...options});
  if(result.status!==0) throw new Error(`Check failed: ${path.basename(command)} (${result.status})`);
  return result.stdout;
};
const read=(archive,file)=>run('tar',['-xOf',archive,'package/'+file]);
try {
  const userconfig=path.join(temporary,'user.npmrc'),globalconfig=path.join(temporary,'global.npmrc');
  await fs.writeFile(userconfig,'registry='+plan.registry+'\n',{mode:0o600});
  await fs.writeFile(globalconfig,'',{mode:0o600});
  const files=(await fs.readdir(directory)).filter(name=>name.endsWith('.tgz'));
  if(files.length!==plan.packages.length) throw new Error('Unexpected release tarballs');
  const seen=new Set();
  for(const filename of files) {
    const archive=path.join(directory,filename),entries=run('tar',['-tzf',archive]).trim().split('\n');
    if(entries.some(name=>!name.startsWith('package/')||name.split('/').includes('..')||/(?:^|\/)(?:node_modules|test|tests|\.env|qq-state\.json|qq-worker\.json|state\.json)(?:$|[/.])/.test(name)||/\.(?:log|jsonl|db|sqlite|pem|key)$/.test(name))) throw new Error('Runtime/private files in release archive');
    const metadata=JSON.parse(read(archive,'package.json'));
    if(!plan.packages.includes(metadata.name)||seen.has(metadata.name)||metadata.version!==plan.version||metadata.private) throw new Error('Unexpected release identity');
    seen.add(metadata.name);
    if(metadata.publishConfig?.access!==plan.access||metadata.publishConfig?.tag!==plan.tag||metadata.publishConfig?.registry!==plan.registry||!metadata.repository?.url) throw new Error('Incomplete publish metadata');
    if(Object.keys(metadata.scripts??{}).length) throw new Error('Review lifecycle scripts before release');
    const readme=read(archive,'README.md');
    if(readme.length<200||!entries.includes('package/LICENSE')) throw new Error('Missing package documentation/license');
    if(metadata.name==='@sakurafan1023/qq') {
      const expected=Object.fromEntries(plan.platforms.map(target=>['@sakurafan1023/qq-'+target,plan.version]));
      if(JSON.stringify(metadata.optionalDependencies)!==JSON.stringify(expected)) throw new Error('QQ advertises unpublished platforms');
    }
    if(metadata.name.startsWith('@sakurafan1023/qq-')) {
      const module=JSON.parse(read(archive,'module.json'));
      if(module.version!==plan.version||module.configuration!=='release'||!plan.platforms.includes(module.platform+'-'+module.architecture)) throw new Error('Unverified/debug native release');
      if(entries.some(name=>/SocialBrowser|SocialControl|WeChatBridge/.test(name))) throw new Error('Non-QQ code in native package');
      const file=path.join(temporary,module.binary);
      const binary=spawnSync('tar',['-xOf',archive,'package/'+module.binary],{maxBuffer:20000000});
      if(binary.status!==0) throw new Error('Missing native binary');
      await fs.writeFile(file,binary.stdout);
      if(/\/(?:Users|home)\/[A-Za-z0-9_.-]+\//.test(run('strings',['-a',file]))) throw new Error('Private build paths in native release');
    }
    for(const name of entries.filter(name=>/\.(?:json|mjs|js|md|txt|py|sh)$/.test(name)&&!name.includes('/licenses/'))) {
      const text=read(archive,name.slice('package/'.length));
      if(/\/(?:Users|home)\/[A-Za-z0-9_.-]+\/|\b(?:sk-[A-Za-z0-9_-]{24,}|npm_[A-Za-z0-9]{30,})\b/.test(text)) throw new Error('Sensitive text in release archive');
    }
    const output=run(process.execPath,[npm,'publish',archive,'--dry-run','--json','--ignore-scripts','--access',plan.access,'--tag',plan.tag,
      '--registry',plan.registry,'--userconfig',userconfig,'--globalconfig',globalconfig,'--fetch-retries=0','--fetch-timeout=15000'],{cwd:temporary,env});
    const dry=JSON.parse(output),item=Array.isArray(dry)?dry[0]:(dry.name?dry:dry[metadata.name]);
    if(item.name!==metadata.name||item.version!==plan.version) throw new Error('Dry-run package identity changed');
    const bytes=await fs.readFile(archive);
    report.packages.push({name:metadata.name,version:metadata.version,archive:filename,files:entries.length,bytes:bytes.length,sha256:createHash('sha256').update(bytes).digest('hex'),dryRun:'passed'});
  }
  report.authentication='Not checked by anonymous dry-run; verify npm whoami, scope rights and 2FA separately';
  await fs.writeFile(path.join(directory,'verification.json'),JSON.stringify(report,null,2)+'\n');
  console.log(JSON.stringify(report,null,2));
} finally {await fs.rm(temporary,{recursive:true,force:true});}
