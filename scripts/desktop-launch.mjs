// Fixed entrypoints for the installed desktop bundle; do not inherit source-build overrides.
import path from 'node:path';
import {fileURLToPath, pathToFileURL} from 'node:url';

const runtime = path.dirname(fileURLToPath(import.meta.url));
const verb = process.argv[2] ?? 'client';
if (process.argv.length > 3 || !['client','mcp','status','pause','disconnect','stop'].includes(verb)) {
  console.error('Usage: desktop-launch.mjs client|mcp|status|pause|disconnect|stop');
  process.exit(1);
}
for (const key of ['DAFEIYU_QQ_ROOT','DAFEIYU_RESOURCES','DAFEIYU_NODE_DEPENDENCIES','DAFEIYU_ONEBOT_TOKEN','DAFEIYU_MODEL_KEY']) delete process.env[key];
process.env.DAFEIYU_MODULES_DIR = runtime;
const entry = path.join(runtime,'node_modules','@sakurafan1023',verb === 'mcp' ? 'mcp/bin/mcp.mjs' : 'qq/bin/qq.mjs');
process.argv = [process.execPath,entry,...(verb === 'mcp' ? ['--modules','qq'] : [verb === 'client' ? 'panel' : verb])];
await import(pathToFileURL(entry).href);
