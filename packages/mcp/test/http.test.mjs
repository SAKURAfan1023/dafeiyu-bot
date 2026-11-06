import {test} from 'node:test';
import assert from 'node:assert/strict';
import {randomUUID} from 'node:crypto';
import {Client} from '@modelcontextprotocol/sdk/client/index.js';
import {StreamableHTTPClientTransport} from '@modelcontextprotocol/sdk/client/streamableHttp.js';
import {startHTTP} from '../lib/http.mjs';

test('HTTP MCP uses real SDK transport; bounded loopback discovery and writes',async()=>{
  const calls=[];
  const state={config:{expectedSelfID:'12345'},runtime:{generation:randomUUID()},configurationRevision:randomUUID(),running:false};
  const qq={status:async()=>state,action:async(_,input)=>{calls.push(input);return{running:false};}};
  const endpoint=await startHTTP(qq,{}),url=new URL(endpoint.url);
  const client=new Client({name:'synthetic-chatgpt-http-host',version:'1.0.0'});
  try {
    await client.connect(new StreamableHTTPClientTransport(url));
    assert.equal((await client.listTools()).tools.length,7);
    const read=await client.callTool({name:'qq_status',arguments:{}});
    assert.equal(read.structuredContent.running,false);assert.equal(calls.length,0);
    const paused=await client.callTool({name:'qq_run_control',arguments:{account:'12345',generation:state.runtime.generation,revision:state.configurationRevision,action:'pause'}});
    assert.ok(!paused.isError);assert.equal(calls[0].action,'pause');
    assert.equal((await fetch(url,{method:'POST',headers:{Origin:'https://invalid.example','Content-Type':'application/json'},body:'{}'})).status,403);
    assert.equal((await fetch(url.origin+'/mcp',{method:'POST'})).status,404);
    assert.equal((await fetch(url,{method:'GET'})).status,405);
    assert.equal((await fetch(url,{method:'POST',headers:{'Content-Type':'application/json'},body:'not json'})).status,400);
    assert.equal((await fetch(url,{method:'POST',headers:{'Content-Type':'application/json'},body:'x'.repeat(65537)})).status,413);
  } finally {await client.close();await endpoint.close();}
});
