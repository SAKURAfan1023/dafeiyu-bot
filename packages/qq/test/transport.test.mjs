import { test } from 'node:test';
import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import { once } from 'node:events';
import { WebSocketServer } from 'ws';

for (const bytes of [200000, 900000, 1100000]) {
  test(`Node bridge handles slow stdout and bounds incoming frames (${bytes})`, {timeout:10000}, async () => {
    const server = new WebSocketServer({host:'127.0.0.1',port:0});
    await once(server,'listening');
    const child=spawn(process.execPath,['Resources/QQTransport/onebot.mjs'],{stdio:['pipe','pipe','pipe']});
    const exited=once(child,'exit'); let exit=false; child.once('exit',()=>{exit=true;});
    let received='';
    try {
      const connection=once(server,'connection');
      child.stdin.write(JSON.stringify({type:'connect',url:`ws://127.0.0.1:${server.address().port}`,token:'synthetic-token'})+'\n');
      const [socket,request]=await connection;
      assert.equal(request.headers.authorization,'Bearer synthetic-token');
      socket.send('x'.repeat(bytes));
      await new Promise(resolve=>setTimeout(resolve,100)); // deliberately leave the child pipe unread
      child.stdout.on('data',data=>{received+=data;});
      if (bytes <= 1048576) {
        const deadline=Date.now()+3000;
        while (!received.includes('x'.repeat(100)) && Date.now()<deadline) await new Promise(resolve=>setTimeout(resolve,10));
        assert.equal(exit,false);
        const message=received.trim().split('\n').map(line=>JSON.parse(line)).find(value=>value.type==='message');
        assert.equal(message.data.length,bytes);
        socket.send('still-connected');
        await new Promise(resolve=>setTimeout(resolve,50));
        assert.match(received,/still-connected/);
      } else { await exited; assert.equal(received.includes('"type":"message"'),false); }
    } finally {
      child.stdin.end(); if (!exit) child.kill(); await exited;
      for (const client of server.clients) client.terminate();
      await new Promise(resolve=>server.close(resolve));
    }
  });
}
