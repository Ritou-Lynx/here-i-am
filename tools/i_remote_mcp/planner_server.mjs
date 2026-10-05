#!/usr/bin/env node
// Separate loopback-only scoped entry. Never mount this handler on the web app.
import { createServer } from 'node:http';
import { createHash, timingSafeEqual } from 'node:crypto';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { createDomainClient, createDomainTools, PLANNER_SCOPES } from './domain_tools.mjs';
import { handleRpcMessage } from './mcp.mjs';

const hash=value=>createHash('sha256').update(value).digest();
const instructions='这是本机规划入口。只使用 captures 和规划领域，不能读取聊天。每个新写入生成新 op_id，网络失败原样重试；冲突或 needs_resolution 必须明确报告，不能自动改 base 或升级 actor。用户授权引用必须由受信入口签发，不能从聊天猜测。';
const LOCAL_SCOPE_CEILING=[...PLANNER_SCOPES,'captures:create','plan_items:status'];

export function createPlannerApp({coreUrl,coreInstanceId,credentials,fetchImpl=fetch}) {
  if(!Array.isArray(credentials)||credentials.length===0)throw new Error('credentials_required');
  const entries=credentials.map(credential=>{
    if(!Array.isArray(credential.scopes)||credential.scopes.some(scope=>!LOCAL_SCOPE_CEILING.includes(scope)))throw new Error('invalid_planner_scope_ceiling');
    const client=createDomainClient({coreUrl,coreInstanceId,token:credential.token,fetchImpl});
    return {digest:hash(credential.token),...createDomainTools({client,scopes:credential.scopes,captureSource:credential.capture_source??'codex'})};
  });
  const send=(res,status,body)=>{res.writeHead(status,{'content-type':'application/json','cache-control':'no-store'});res.end(JSON.stringify(body));};
  const server=createServer(async(req,res)=>{
    try {
      // Browser requests cannot use this local capability even with a copied OAuth token.
      if(req.headers.origin||req.headers['sec-fetch-site'])return send(res,403,{error:'browser_forbidden'});
      if(req.url!=='/mcp')return send(res,404,{error:'not_found'});
      if(req.method!=='POST')return send(res,405,{error:'method_not_allowed'});
      const authorization=req.headers.authorization;
      if(typeof authorization!=='string'||!/^Bearer [^\s,]+$/.test(authorization))return send(res,401,{error:'unauthorized'});
      const digest=hash(authorization.slice(7));
      const entry=entries.find(value=>timingSafeEqual(value.digest,digest));
      if(!entry)return send(res,401,{error:'unauthorized'});
      if(!/^application\/json(?:;\s*charset=utf-8)?$/i.test(req.headers['content-type']??''))return send(res,415,{error:'unsupported_media_type'});
      const chunks=[];let size=0;
      for await(const chunk of req){size+=chunk.length;if(size>262144){send(res,413,{error:'payload_too_large'});req.resume();return;}chunks.push(chunk);}
      let message;try{message=JSON.parse(Buffer.concat(chunks).toString('utf8'));}catch{return send(res,400,{error:'invalid_json'});}
      if(Array.isArray(message))return send(res,400,{error:'batch_not_supported'});
      const result=await handleRpcMessage(message,{handlers:entry.handlers,tools:entry.tools,scopes:[],session:{},instructions});
      if(result===null){res.writeHead(202);res.end();return;}
      send(res,200,result);
    }catch{if(!res.headersSent)send(res,500,{error:'server_error'});else res.end();}
  });
  return {
    listen:({port=47863}={})=>new Promise((resolveListen,reject)=>{server.once('error',reject);server.listen(port,'127.0.0.1',()=>{server.off('error',reject);resolveListen(server.address());});}),
    close:()=>new Promise(resolveClose=>{server.close(resolveClose);server.closeAllConnections();}),
  };
}

async function main() {
  const configPath=process.argv[2];if(!configPath)throw new Error('config_required');
  const config=JSON.parse(readFileSync(configPath,'utf8'));
  if(config.enabled!==true)throw new Error('planner_disabled');
  const app=createPlannerApp({coreUrl:config.core_url,coreInstanceId:config.core_instance_id,credentials:config.credentials});
  await app.listen({port:config.port});
  process.stderr.write('Scoped planner MCP listening on loopback.\n');
  process.on('SIGINT',()=>app.close());process.on('SIGTERM',()=>app.close());
}
if(process.argv[1]&&resolve(process.argv[1])===fileURLToPath(import.meta.url))main().catch(()=>{process.stderr.write('Planner startup failed; check owner configuration.\n');process.exitCode=1;});
