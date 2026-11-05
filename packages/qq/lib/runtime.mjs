import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { createRequire } from 'node:module';
import { execFile, spawn } from 'node:child_process';
import { promisify } from 'node:util';
import { createHash } from 'node:crypto';

export const version = '0.3.0-preview.2';
const require = createRequire(import.meta.url);
const packageRoot = fileURLToPath(new URL('..', import.meta.url));
const sleep = ms => new Promise(resolve => setTimeout(resolve, ms));

export function dataDirectory(env = process.env, platform = process.platform) {
  if (env.DAFEIYU_DATA_DIR) return path.resolve(env.DAFEIYU_DATA_DIR);
  if (platform === 'win32') {
    if (!env.LOCALAPPDATA) throw new Error('LOCALAPPDATA is unavailable');
    return path.join(env.LOCALAPPDATA, 'DaFeiYu');
  }
  return platform === 'darwin' ? path.join(os.homedir(), 'Library', 'Application Support', 'WeChatAIBot')
    : path.join(os.homedir(), '.local', 'share', 'dafeiyu');
}

export function parseRecord(record) {
  if (record?.schema !== 1 || record.module !== 'qq' || record.version !== version ||
      !Number.isSafeInteger(record.pid) || record.pid <= 0 || !/^[\da-f-]{36}$/i.test(record.generation ?? '')) {
    throw new Error('QQ runtime record is incompatible');
  }
  const url = new URL(record.controlURL);
  if (url.protocol !== 'http:' || url.hostname !== '127.0.0.1' || !url.port || url.username || url.password || url.search || url.pathname !== '/' ||
      !/^[\da-f-]{72}$/i.test(url.hash.slice(1))) throw new Error('Invalid local QQ endpoint');
  return { ...record, origin: url.origin, token: url.hash.slice(1) };
}

async function readRecord(directory) {
  const file = path.join(directory, 'qq-worker.json');
  const stat = await fs.lstat(file);
  if (!stat.isFile() || stat.isSymbolicLink() || stat.size > 4096 || (process.platform !== 'win32' && (stat.mode & 0o077))) {
    throw new Error('QQ runtime record permissions are unsafe');
  }
  if (process.platform === 'win32') {
    // Get-Acl is read-only. Paths travel in the environment, never interpolated as PowerShell code.
    const script = "$ErrorActionPreference='Stop'; try { $sid=[System.Security.Principal.WindowsIdentity]::GetCurrent().User.Value; foreach($p in @($env:DAFEIYU_ACL_DIRECTORY,$env:DAFEIYU_ACL_FILE)) { $a=Get-Acl -LiteralPath $p; $owner=$a.GetOwner([System.Security.Principal.SecurityIdentifier]).Value; if(-not $a.AreAccessRulesProtected){exit 21}; if($owner -ne $sid -and $owner -ne 'S-1-5-32-544'){exit 22}; foreach($r in $a.GetAccessRules($true,$true,[System.Security.Principal.SecurityIdentifier])) { if($r.AccessControlType -eq 'Allow' -and $r.IdentityReference.Value -ne $sid){exit 23} } } } catch { [Console]::Error.WriteLine($_.FullyQualifiedErrorId); exit 24 }";
    await promisify(execFile)(path.join(process.env.SystemRoot, 'System32', 'WindowsPowerShell', 'v1.0', 'powershell.exe'),
      ['-NoProfile','-NonInteractive','-Command',script], { windowsHide: true, timeout: 5000,
        env: { ...process.env, DAFEIYU_ACL_DIRECTORY: directory, DAFEIYU_ACL_FILE: file } });
  }
  return parseRecord(JSON.parse(await fs.readFile(file, 'utf8')));
}

async function jsonRequest(runtime, route, body, timeout = 20000) {
  const response = await fetch(runtime.origin + route, {
    method: body === undefined ? 'GET' : 'POST', redirect: 'error', signal: AbortSignal.timeout(timeout),
    headers: { 'X-QQ-Control': runtime.token, Origin: runtime.origin, ...(body === undefined ? {} : { 'Content-Type': 'application/json' }) },
    ...(body === undefined ? {} : { body: JSON.stringify(body) })
  });
  if (!response.ok) throw new Error(`QQ request rejected (${response.status})`);
  const reader = response.body.getReader(); let size = 0; const parts = [];
  try {
    while (true) {
      const { done, value } = await reader.read(); if (done) break;
      size += value.length;
      if (size > 4200000) throw new Error('QQ response exceeded the limit');
      parts.push(value);
    }
  } finally { await reader.cancel(); }
  const result = JSON.parse(Buffer.concat(parts).toString('utf8'));
  if (result.runtime?.generation !== runtime.generation || result.runtime?.pid !== runtime.pid ||
      result.runtime?.module !== 'qq' || result.runtime?.version !== version) throw new Error('QQ runtime identity changed');
  return result;
}

export async function locateRuntimeRoot() {
  if (process.env.DAFEIYU_QQ_ROOT) return path.resolve(process.env.DAFEIYU_QQ_ROOT);
  try { return path.dirname(require.resolve(`@sakurafan1023/qq-${process.platform}-${process.arch}/module.json`)); }
  catch { throw new Error('QQ platform binary is not installed. Build with python3 scripts/build-qq.py or install the matching platform package.'); }
}

export async function verifyArtifact(root, binary) {
  const hashes = JSON.parse(await fs.readFile(path.join(root, 'integrity.json'), 'utf8'));
  if (!hashes[binary] || !hashes['module.json'] || !hashes['Resources/QQControl/app.js']) throw new Error('Incomplete QQ artifact');
  for (const [name, digest] of Object.entries(hashes)) {
    if (!name || name.includes('\\') || name.split('/').some(part => !part || part === '.' || part === '..') || !/^[a-f0-9]{64}$/.test(digest)) {
      throw new Error('Invalid QQ artifact integrity manifest');
    }
    const file = path.join(root, ...name.split('/'));
    const stat = await fs.lstat(file);
    if (!stat.isFile() || stat.isSymbolicLink() || createHash('sha256').update(await fs.readFile(file)).digest('hex') !== digest) {
      throw new Error('QQ artifact integrity check failed; reinstall the platform package.');
    }
  }
}

export async function ensureRuntime({ directory = dataDirectory(), start = true } = {}) {
  directory = path.resolve(directory);
  await fs.mkdir(directory, { recursive: true, mode: 0o700 });
  const stat = await fs.lstat(directory);
  if (!stat.isDirectory() || stat.isSymbolicLink() || (process.platform !== 'win32' && (stat.mode & 0o077))) {
    throw new Error('QQ data directory must be private');
  }
  let previous;
  try {
    previous = await readRecord(directory);
    await jsonRequest(previous, '/api/status', undefined, 3000);
    return previous;
  } catch (error) {
    if (previous) {
      try { process.kill(previous.pid, 0); throw new Error('Existing QQ runtime is unresponsive; do not start another engine.'); }
      catch (probe) { if (probe.code !== 'ESRCH') throw probe; }
    } else if (error.code !== 'ENOENT') throw error;
  }
  if (!start) throw new Error('QQ runtime is not running');
  const root = await locateRuntimeRoot();
  const manifest = JSON.parse(await fs.readFile(path.join(root, 'module.json'), 'utf8'));
  const binary = process.platform === 'win32' ? 'dafeiyu-qq.exe' : 'dafeiyu-qq';
  if (manifest.id !== 'qq' || manifest.version !== version || manifest.protocol !== 1 || manifest.binary !== binary || manifest.resources !== 'Resources') {
    throw new Error('QQ platform manifest is incompatible');
  }
  // Local source builds use an explicit override. Installed native packages must be complete.
  if (!process.env.DAFEIYU_QQ_ROOT) await verifyArtifact(root, binary);
  const child = spawn(path.join(root, binary), ['--quiet'], {
    cwd: directory, windowsHide: true, detached: true, stdio: 'ignore',
    env: { ...process.env, DAFEIYU_DATA_DIR: directory, DAFEIYU_RESOURCES: path.join(root, 'Resources'),
      DAFEIYU_NODE: process.execPath, DAFEIYU_NODE_DEPENDENCIES: packageRoot }
  });
  let spawnError, discoveryCode = 'pending';
  child.on('error', error => { spawnError = error; }); child.unref();
  // Concurrent launchers race only for the Swift OS lease. The loser attaches to the winner.
  for (let i = 0; i < 100; i++) {
    if (spawnError) throw new Error('QQ worker could not start');
    try {
      const runtime = await readRecord(directory);
      await jsonRequest(runtime, '/api/status', undefined, 1000);
      return runtime;
    } catch (error) {
      // Only non-sensitive status codes reach launcher errors; never paths, tokens or response bodies.
      discoveryCode = Number.isInteger(error.code) || (typeof error.code === 'string' && /^[A-Z0-9_]{1,40}$/.test(error.code)) ? String(error.code) : 'validation';
      if (error.code === 24 && typeof error.stderr === 'string' && /^[A-Za-z0-9_.,-]{1,160}$/.test(error.stderr.trim())) discoveryCode += '/' + error.stderr.trim();
      await sleep(100);
    }
  }
  // The child has never been connected or started automatically; terminate only our failed launch.
  if (child.exitCode === null) child.kill();
  throw new Error(`QQ worker startup timed out (exit=${child.exitCode ?? 'running'}, discovery=${discoveryCode}); check dependencies, version, permissions and runtime lock.`);
}

export async function status(runtime, { includeMemory = false } = {}) {
  const state = await jsonRequest(runtime, '/api/status');
  if (!includeMemory) delete state.memories;
  return state;
}

const actions = new Set(['saveConnection', 'connect', 'disconnect', 'pause', 'clear', 'start', 'add', 'remove', 'shutdown',
  'setPersona', 'save', 'takeOver', 'clearMemory', 'saveArtwork', 'addArtworkArtist', 'removeArtworkArtist',
  'saveVisualTools', 'saveImageGeneration', 'importSticker']);
export async function action(runtime, input, expected) {
  if (!actions.has(input?.action)) throw new Error('Unsupported QQ action');
  const before = await status(runtime);
  if (!expected || before.runtime.generation !== expected.generation || before.configurationRevision !== expected.revision ||
      before.config.expectedSelfID !== expected.account) {
    throw Object.assign(new Error('QQ account, generation or configuration changed; reload status.'), {code:'QQ_STATE_CHANGED'});
  }
  // No retries: a timeout after POST means the action may already have been applied.
  const result = await jsonRequest(runtime, input.action === 'importSticker' ? '/api/import-sticker' : '/api/action',
    { ...input, configurationRevision: expected.revision });
  if (result.error) throw new Error('QQ action did not complete; inspect status for the current error.');
  delete result.memories;
  return result;
}

export function expectation(state) {
  return { account: state.config.expectedSelfID, generation: state.runtime.generation, revision: state.configurationRevision };
}

export function panelURL(runtime) { return runtime.origin + '/#' + runtime.token; }
export async function openPanel(runtime) {
  const url = panelURL(runtime);
  const [command, args] = process.platform === 'win32' ? ['rundll32.exe', ['url.dll,FileProtocolHandler', url]]
    : process.platform === 'darwin' ? ['/usr/bin/open', [url]] : ['xdg-open', [url]];
  await new Promise((resolve, reject) => {
    const child = spawn(command, args, { stdio: 'ignore', windowsHide: true });
    child.once('error', reject); child.once('exit', code => code === 0 ? resolve() : reject(new Error('Could not open the local QQ panel')));
  });
}
