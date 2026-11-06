import { createServer as createHTTPServer } from 'node:http';
import { randomBytes } from 'node:crypto';
import { StreamableHTTPServerTransport } from '@modelcontextprotocol/sdk/server/streamableHttp.js';
import { createServer } from './server.mjs';

// A local test endpoint for ChatGPT/tunnel acceptance. The capability path is private;
// production remote deployments need their own authenticated connection boundary.
export async function startHTTP(qq, runtime, {port=0}={}) {
  if (!Number.isInteger(port) || port < 0 || port > 65535) throw new Error('Invalid MCP port');
  const endpoint='/mcp/'+randomBytes(32).toString('hex');
  let active=0;
  const sessions=new Set();
  const listener=createHTTPServer({maxHeaderSize:8192},async (request,response)=>{
    const host=`127.0.0.1:${listener.address()?.port}`;
    const reject=code=>{response.writeHead(code,{'Content-Type':'text/plain','Cache-Control':'no-store'});response.end();};
    if(request.headers.host!==host || (request.headers.origin && request.headers.origin!==`http://${host}`)) return reject(403);
    if(request.url!==endpoint) return reject(404);
    if(request.method!=='POST'){response.setHeader('Allow','POST');return reject(405);}
    if(!request.headers['content-type']?.toLowerCase().startsWith('application/json')) return reject(415);
    if(active>=16) return reject(503);
    active++;
    const server=createServer(qq,runtime);
    const transport=new StreamableHTTPServerTransport({sessionIdGenerator:undefined,enableJsonResponse:true});
    sessions.add(server);
    try {
      let size=0;const parts=[];
      for await(const part of request){size+=part.length;if(size>65536){reject(413);return;}parts.push(part);}
      let body;
      try{body=JSON.parse(Buffer.concat(parts).toString('utf8'));}catch{return reject(400);}
      await server.connect(transport);
      await transport.handleRequest(request,response,body);
    } catch {
      if(!response.headersSent) reject(500); else response.end();
    } finally {
      active--;sessions.delete(server);await server.close();
    }
  });
  listener.requestTimeout=15000;listener.headersTimeout=10000;listener.timeout=20000;
  await new Promise((resolve,reject)=>{listener.once('error',reject);listener.listen(port,'127.0.0.1',()=>{listener.off('error',reject);resolve();});});
  return {url:`http://127.0.0.1:${listener.address().port}${endpoint}`, async close(){
    const stopped=new Promise((resolve,reject)=>listener.close(error=>error?reject(error):resolve()));
    listener.closeAllConnections();await Promise.all([...sessions].map(server=>server.close()));await stopped;
  }};
}
