#!/usr/bin/env node
import path from 'node:path';
import os from 'node:os';
import fs from 'node:fs/promises';
import { spawn } from 'node:child_process';
import { createRequire } from 'node:module';
import { pathToFileURL } from 'node:url';

const metadata = JSON.parse(await fs.readFile(new URL('../package.json', import.meta.url), 'utf8'));
const version = metadata.version;
const prefix = process.env.DAFEIYU_MODULES_DIR ?? path.join(os.homedir(), '.local', 'share', 'dafeiyu', 'modules');
async function qqModule() {
  try { return await import(pathToFileURL(createRequire(path.join(prefix, 'package.json')).resolve('@sakurafan1023/qq')).href); }
  catch { return import('@sakurafan1023/qq'); }
}
try {
  const [command, module] = process.argv.slice(2);
  if (command === 'setup' && module === 'qq') {
    if (!metadata.dafeiyu?.publishedPlatforms?.includes(`${process.platform}-${process.arch}`)) {
      throw new Error('本次 npm 预览提供 macOS Apple Silicon（arm64）与 Windows x64；其他平台请使用源码构建。');
    }
    await fs.mkdir(prefix, { recursive: true, mode: 0o700 });
    const npm = process.env.npm_execpath;
    if (!npm || !npm.endsWith('.js')) throw new Error('请通过 npm exec / npx 运行安装向导，或自行安装 @sakurafan1023/qq。');
    await new Promise((resolve, reject) => {
      const child = spawn(process.execPath, [npm, 'install', '--prefix', prefix, '--ignore-scripts', '--no-audit', '--no-fund', `@sakurafan1023/qq@${version}`], { stdio: 'inherit', shell: false });
      child.once('error', reject); child.once('exit', code => code === 0 ? resolve() : reject(new Error('QQ 模块安装未完成。')));
    });
    console.log('QQ 模块已安装。运行 dafeiyu qq panel 打开本机面板；QQ / NapCat 由你单独准备，安装不会连接账号或开始回复。');
  } else if (command === 'qq' && ['panel','status','pause','disconnect','stop'].includes(module ?? 'panel')) {
    const verb = module ?? 'panel';
    const qq = await qqModule(); const runtime = await qq.ensureRuntime({ start: verb !== 'stop' });
    if (verb === 'panel') await qq.openPanel(runtime);
    else {
      const state = await qq.status(runtime);
      console.log(JSON.stringify(verb === 'status' ? state : await qq.action(runtime, { action: verb === 'stop' ? 'shutdown' : verb }, qq.expectation(state)), null, 2));
    }
  } else console.log('用法：dafeiyu setup qq | dafeiyu qq panel|status|pause|disconnect|stop。此预览仅提供 QQ；其他模块不会被下载。');
} catch (error) { console.error(error.message); process.exitCode = 1; }
