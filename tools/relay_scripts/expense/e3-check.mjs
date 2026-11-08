// E3 round 5: read-only check of the new MCP after the switch (cloud clients report Bad Gateway).
// Task states, MCP listener, local OAuth metadata (expect 200), unauthenticated POST /mcp (expect 401),
// Funnel target for 443, newest session receipts' names. Prints status codes and names only.
// Usage: e3-check.ps1 (Windows PowerShell 5.1, -File) runs this with --git <git.exe>.
import {existsSync,readdirSync,statSync} from 'node:fs';
import http from 'node:http';
import path from 'node:path';
import {P2,emit,need,plain,short,run,tasks,loginOf,mcpOf,portFree,LISTEN_PORT} from './e3-common.mjs';

function req(port,method,p,body){return new Promise(resolve=>{
 const r=http.request({host:'127.0.0.1',port,method,path:p,timeout:8000,headers:body?{'content-type':'application/json',accept:'application/json, text/event-stream'}:{}},res=>{let n=0;res.on('data',d=>n+=d.length);res.on('end',()=>resolve({status:res.statusCode,bytes:n}));});
 r.on('timeout',()=>{r.destroy();resolve({status:0,error:'timeout'});});r.on('error',e=>resolve({status:0,error:String(e.code??'error')}));
 if(body)r.write(body);r.end();});}

async function main(){
 const a=process.argv.slice(2);need(a.length===2&&a[0]==='--git','args','usage: --git <git.exe>');
 need(process.platform==='win32'&&plain(process.execPath),'args','windows_required');
 const list=tasks('step0');
 emit('step0',true,{tasks:list.filter(t=>t.state!=='Disabled').map(t=>t.name+':'+t.state)});
 const cur=list.find(t=>t.name===P2);need(cur,'step0','new_task_missing');
 const l=loginOf(cur,'step0'),mcp=mcpOf(l,'step0'),port=mcp.listen_port;
 emit('step1',true,{mcp_port:port,listening:!(await portFree(port)),heart_rate_listening:!(await portFree(LISTEN_PORT)),
  server:short(mcp.source_files.find(f=>f.path==='i_remote_mcp/server.mjs')?.sha256),public_url_set:typeof mcp.environment?.I_REMOTE_MCP_PUBLIC_URL==='string'});
 const meta=await req(port,'GET','/.well-known/oauth-protected-resource');
 const init=JSON.stringify({jsonrpc:'2.0',id:1,method:'initialize',params:{protocolVersion:'2025-06-18',capabilities:{},clientInfo:{name:'e3-check',version:'1'}}});
 const post=await req(port,'POST','/mcp',init);
 emit('step2',meta.status===200&&post.status===401,{oauth_metadata:meta,unauthenticated_mcp:post});
 const ts=run('where.exe',['tailscale.exe'],{step:'step3'});
 const exe=ts.code===0?ts.stdout.split(/\r?\n/).map(s=>s.trim()).find(s=>s&&existsSync(s)):path.join(process.env.ProgramFiles??'','Tailscale','tailscale.exe');
 if(exe&&existsSync(exe)){
  const r=run(exe,['funnel','status','--json'],{step:'step3'});let j={};try{j=JSON.parse(r.stdout.trim()||'{}');}catch{}
  const proxies=Object.entries(j?.Web??{}).flatMap(([host,v])=>Object.entries(v?.Handlers??{}).map(([p,h])=>({port:host.split(':').pop(),path:p,target:String(h?.Proxy??'').replace(/^http:\/\/(127\.0\.0\.1|localhost)/,'local')})));
  emit('step3',proxies.some(x=>x.port==='443'&&x.target==='local:'+port),{funnel_on:Object.keys(j?.AllowFunnel??{}).map(k=>k.split(':').pop()),proxies});
 }else emit('step3',false,'tailscale_not_found');
 const sessions=path.join(l.login.control_root);
 const dirs=readdirSync(sessions,{withFileTypes:true}).filter(e=>e.isDirectory()).map(e=>path.join(sessions,e.name)).sort((x,y)=>statSync(y).mtimeMs-statSync(x).mtimeMs).slice(0,1);
 for(const d of dirs)emit('step4',true,{newest_control_files:readdirSync(d).filter(n=>!/token|secret|key/i.test(n)).slice(0,40),age_min:Math.round((Date.now()-statSync(d).mtimeMs)/60000)});
 emit('done',true,'read_only');
}
main().catch(e=>{emit(e.step??'unexpected',false,e.detail??String(e.message).slice(0,300));process.exitCode=1;});
