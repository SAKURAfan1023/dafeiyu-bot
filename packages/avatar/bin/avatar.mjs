#!/usr/bin/env node
import { StdioServerTransport } from '@modelcontextprotocol/sdk/server/stdio.js';
import { AvatarRuntime } from '../lib/runtime.mjs';
import { PreviewBridge } from '../lib/bridge.mjs';
import { createAvatarServer } from '../lib/mcp.mjs';

let runtime;
try {
  const args = process.argv.slice(2), mode = ['preview', 'connect-preview'].includes(args[0]) ? args.shift() : 'mcp';
  const options = {};
  for (let i = 0; i < args.length; i += 2) {
    const key = args[i], value = args[i + 1];
    if (!value || options[key] || !['--port', '--voice-config', '--url'].includes(key)) throw Error('Usage: dafeiyu-avatar [preview] [--port 0] [--voice-config FILE] | connect-preview --url URL');
    options[key] = value;
  }
  if (mode === 'connect-preview') {
    if (Object.keys(options).length !== 1 || !options['--url']) throw Error('connect-preview requires only --url');
    runtime = await PreviewBridge.connect(options['--url']);
    console.error('DaFeiYu MCP connected to the explicitly selected preview');
  } else {
    if (options['--url'] || (options['--port'] && (!/^\d{1,5}$/.test(options['--port']) || Number(options['--port']) > 65535))) throw Error('Invalid port or preview option');
    runtime = await AvatarRuntime.start({ port: Number(options['--port'] ?? 0), voiceConfig: options['--voice-config'] });
    console.error('DaFeiYu avatar preview: ' + runtime.url);
  }
  const stop = async () => { await runtime.close(); process.exit(0); };
  process.once('SIGTERM', stop); process.once('SIGINT', stop);
  if (mode !== 'preview') {
    const server = createAvatarServer(runtime);
    server.server.onclose = () => { runtime.close().finally(() => process.exit(0)); };
    await server.connect(new StdioServerTransport());
  }
} catch (error) { console.error('Avatar startup failed: ' + error.message); await runtime?.close(); process.exitCode = 1; }
