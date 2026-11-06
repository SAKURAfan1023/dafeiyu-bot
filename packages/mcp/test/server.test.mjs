import { test } from 'node:test';
import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import { Client } from '@modelcontextprotocol/sdk/client/index.js';
import { InMemoryTransport } from '@modelcontextprotocol/sdk/inMemory.js';
import { createServer } from '../lib/server.mjs';

test('MCP initializes through SDK transport; safe reads and fixed commands only', async () => {
  const calls=[];
  const state={config:{expectedSelfID:'12345',targets:[]},runtime:{generation:randomUUID()},configurationRevision:randomUUID(),connected:false,contacts:[]};
  const qq={status:async()=>state, expectation:s=>({account:s.config.expectedSelfID,generation:s.runtime.generation,revision:s.configurationRevision}),
    action:async(runtime,input,expected)=>{if(input.action==='saveConnection')throw Object.assign(new Error('synthetic-private-detail'),{code:'QQ_STATE_CHANGED'});calls.push({input,expected});return {ok:true};}};
  const server=createServer(qq,{}), client=new Client({name:'synthetic-host',version:'1.0.0'});
  const [a,b]=InMemoryTransport.createLinkedPair();
  await Promise.all([server.connect(a),client.connect(b)]);
  try {
    const tools=await client.listTools();
    assert.equal(tools.tools.length,7);
    assert.equal(tools.tools.some(t=>/shell|javascript|onebot_action|send_message/.test(t.name)),false);
    const read=await client.callTool({name:'qq_status',arguments:{}});
    assert.equal(read.structuredContent.config.expectedSelfID,'12345');assert.equal(calls.length,0);
    const expected=qq.expectation(state);
    const paused=await client.callTool({name:'qq_run_control',arguments:{...expected,action:'pause'}});
    assert.equal(paused.isError,undefined);assert.equal(calls[0].input.action,'pause');
    const rejected=await client.callTool({name:'qq_settings',arguments:{...expected,action:'save',settings:{token:'synthetic-do-not-persist'}}});
    assert.equal(rejected.isError,true);assert.equal(calls.length,1);
    const stale=await client.callTool({name:'qq_save_connection',arguments:{...expected,endpoint:'ws://127.0.0.1:30123',expectedSelfID:'12345'}});
    assert.equal(stale.isError,true);assert.deepEqual(stale.structuredContent,{code:'QQ_STATE_CHANGED',submitted:false});
    assert.match(stale.content[0].text,/未提交/);assert.doesNotMatch(stale.content[0].text,/synthetic-private-detail/);

  } finally { await client.close(); await server.close(); }
});
