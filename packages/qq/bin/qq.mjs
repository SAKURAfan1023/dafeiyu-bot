#!/usr/bin/env node
import { ensureRuntime, status, action, expectation, openPanel } from '../lib/runtime.mjs';
try {
  const command = process.argv[2] ?? 'panel';
  if (!['panel','status','connect','pause','disconnect','stop'].includes(command)) throw new Error('Usage: dafeiyu-qq panel|status|connect|pause|disconnect|stop');
  const runtime = await ensureRuntime({ start: command !== 'stop' });
  if (command === 'panel') await openPanel(runtime);
  else {
    const state = await status(runtime);
    const input = command === 'connect' ? { action: 'connect', token: process.env.DAFEIYU_ONEBOT_TOKEN ?? '', key: process.env.DAFEIYU_MODEL_KEY ?? '' } : { action: command === 'stop' ? 'shutdown' : command };
    const result = command === 'status' ? state : await action(runtime, input, expectation(state));
    console.log(JSON.stringify(result, null, 2));
  }
} catch (error) { console.error(error.message); process.exitCode = 1; }
