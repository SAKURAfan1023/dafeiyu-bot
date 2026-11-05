#!/usr/bin/env node
import { createRequire } from 'node:module';
import { pathToFileURL } from 'node:url';
import path from 'node:path';
import os from 'node:os';
import { StdioServerTransport } from '@modelcontextprotocol/sdk/server/stdio.js';
import { createServer } from '../lib/server.mjs';
import { startHTTP } from '../lib/http.mjs';

try {
  const args = process.argv.slice(2);
  let http=false,port=0;
  for(let i=0;i<args.length;i++) {
    if(args[i]==='--modules' && args[i+1]==='qq') i++;
    else if(args[i]==='--http') http=true;
    else if(args[i]==='--port' && /^\d{1,5}$/.test(args[i+1]??'')) port=Number(args[++i]);
    else throw new Error('Usage: dafeiyu-mcp [--modules qq] [--http --port 0]');
  }
  if(port>65535 || (!http && port!==0)) throw new Error('Invalid MCP HTTP port');
  if(http && !process.env.DAFEIYU_DATA_DIR) throw new Error('HTTP testing requires an explicit isolated DAFEIYU_DATA_DIR');
  const prefix = process.env.DAFEIYU_MODULES_DIR ?? path.join(os.homedir(), '.local', 'share', 'dafeiyu', 'modules');
  let qq;
  try { qq = await import(pathToFileURL(createRequire(path.join(prefix, 'package.json')).resolve('@sakurafan1023/qq')).href); }
  catch { qq = await import('@sakurafan1023/qq'); }
  if(http && path.resolve(process.env.DAFEIYU_DATA_DIR)===qq.dataDirectory({})) throw new Error('Use an isolated test data directory');
  const runtime = await qq.ensureRuntime();
  if(http) {
    const endpoint=await startHTTP(qq,runtime,{port});
    console.error('DAFEIYU_MCP_HTTP_URL='+endpoint.url);
    const stop=()=>{endpoint.close().then(()=>process.exit(0),()=>process.exit(1));};
    process.once('SIGTERM',stop);process.once('SIGINT',stop);
  } else {
    const server = createServer(qq, runtime);
    await server.connect(new StdioServerTransport());
  }
  // The runtime is shared with the client: closing this Host does not kill it or an external NapCat.
} catch { console.error('大肥鱼 MCP 启动失败：请先安装匹配版本的 QQ 模块并检查本机后台。'); process.exitCode = 1; }
