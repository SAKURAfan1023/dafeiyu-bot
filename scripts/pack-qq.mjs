#!/usr/bin/env node
import fs from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { spawnSync } from 'node:child_process';
import { createHash } from 'node:crypto';

const root = fileURLToPath(new URL('..', import.meta.url));
const args = process.argv.slice(2), options = {};
for (let index = 0; index < args.length; index += 2) {
  if (!['--runtime', '--output'].includes(args[index]) || !args[index + 1] || options[args[index]]) throw new Error('Usage: pack-qq.mjs [--runtime dist/qq] [--output dist/npm]');
  options[args[index]] = args[index + 1];
}
const output = path.resolve(root, options['--output'] ?? 'dist/npm');
const runtime = path.resolve(root, options['--runtime'] ?? 'dist/qq');
if (!output.startsWith(path.join(root, 'dist') + path.sep)) throw new Error('Package output must be a generated directory inside dist/');
const plan = JSON.parse(await fs.readFile(path.join(root,'release-plan.json'),'utf8'));
const manifest = JSON.parse(await fs.readFile(path.join(runtime, 'module.json'), 'utf8'));
if (manifest.platform !== process.platform || manifest.architecture !== process.arch) throw new Error('Build the matching native runtime before packing');
if(manifest.version!==plan.version) throw new Error('Runtime and release plan versions differ');
const platformName = `@sakurafan1023/qq-${process.platform}-${process.arch}`;
const targets = ['darwin-arm64','darwin-x64','win32-x64','linux-x64','linux-arm64'];
if (!targets.includes(`${process.platform}-${process.arch}`)) throw new Error('Unsupported binary target');
for (const file of manifest.sourceFiles) {
  if (/Social|WeChatBridge|BotEngine|Views|QQView/.test(file)) throw new Error('QQ artifact contains an unrelated engine');
}
await fs.mkdir(output, { recursive: true });
const platform = path.join(output, `qq-${process.platform}-${process.arch}`);
await fs.rm(platform, { recursive: true, force: true });
await fs.cp(runtime, platform, { recursive: true });
if ((await fs.readdir(path.join(platform, 'Resources'))).some(name => /Social/.test(name))) throw new Error('QQ includes social resources');
await fs.copyFile(path.join(root, 'LICENSE'), path.join(platform, 'LICENSE'));
await fs.copyFile(path.join(root, 'THIRD_PARTY_NOTICES.md'), path.join(platform, 'THIRD_PARTY_NOTICES.md'));
const readme=(await fs.readFile(path.join(root,'docs/NPM_PLATFORM_README.md'),'utf8')).replaceAll('{{PACKAGE_NAME}}',platformName).replaceAll('{{PLATFORM}}',`${process.platform}-${process.arch}`);
await fs.writeFile(path.join(platform,'README.md'),readme);
const hashes = {};
async function hashFiles(directory, prefix = '') {
  for (const item of await fs.readdir(directory, { withFileTypes: true })) {
    const name = path.posix.join(prefix, item.name), file = path.join(directory, item.name);
    if (item.isSymbolicLink()) throw new Error('No symlinks in release artifact');
    if (item.isDirectory()) await hashFiles(file, name);
    else hashes[name] = createHash('sha256').update(await fs.readFile(file)).digest('hex');
  }
}
await hashFiles(platform);
await fs.writeFile(path.join(platform, 'integrity.json'), JSON.stringify(hashes, null, 2));
await fs.writeFile(path.join(platform, 'package.json'), JSON.stringify({ name: platformName, version: manifest.version,
  repository:{type:'git',url:'git+https://github.com/SAKURAfan1023/dafeiyu-bot.git'},
  homepage:'https://github.com/SAKURAfan1023/dafeiyu-bot#readme',bugs:{url:'https://github.com/SAKURAfan1023/dafeiyu-bot/issues'},
  publishConfig:{access:plan.access,tag:plan.tag,registry:plan.registry},
  license: 'MIT', os: [process.platform], cpu: [process.arch], files: [manifest.binary, '*.dll', 'Resources', 'README.md', 'module.json', 'integrity.json', 'licenses', 'LICENSE', 'THIRD_PARTY_NOTICES.md'] }, null, 2));
const folders = [platform];
for (const name of ['qq','cli','mcp']) {
  const destination = path.join(output, name);
  await fs.rm(destination, { recursive: true, force: true });
  await fs.cp(path.join(root, 'packages', name), destination, { recursive: true, filter: file => !/(?:^|[/\\])(?:test|node_modules)(?:[/\\]|$)/.test(file) });
  await fs.copyFile(path.join(root, 'LICENSE'), path.join(destination, 'LICENSE'));
  const pkg = JSON.parse(await fs.readFile(path.join(destination, 'package.json'), 'utf8'));
  if(pkg.version!==plan.version) throw new Error('Package and release plan versions differ');
  if (name === 'qq') pkg.optionalDependencies = Object.fromEntries(plan.platforms.map(target => [`@sakurafan1023/qq-${target}`, manifest.version]));
  await fs.writeFile(path.join(destination, 'package.json'), JSON.stringify(pkg, null, 2));
  folders.push(destination);
}
for (const folder of folders) {
  const npm = process.env.npm_execpath;
  if (!npm) throw new Error('Run via npm run pack:qq');
  const result = spawnSync(process.execPath, [npm, 'pack', '--ignore-scripts', '--json', '--pack-destination', output], { cwd: folder, encoding: 'utf8' });
  if (result.status !== 0) throw new Error('npm pack failed: ' + result.stderr);
  console.log(JSON.parse(result.stdout)[0].filename);
}
