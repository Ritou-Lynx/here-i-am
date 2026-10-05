// Explicit synthetic interoperability harness. Never opens an App or live Core database.
import http from 'node:http';
import path from 'node:path';
import { pathToFileURL } from 'node:url';
import { DatabaseSync } from 'node:sqlite';
import { randomUUID } from 'node:crypto';
const repository = process.argv[2];
if (!repository) throw new Error('explicit_core_repository_required');
const { DOMAIN_SCHEMA_SQL } = await import(pathToFileURL(path.join(repository, 'tools/i_core/domain_schema.mjs')));
const { DomainStore } = await import(pathToFileURL(path.join(repository, 'tools/i_core/domain_store.mjs')));
const { createDomainRequestHandler } = await import(pathToFileURL(path.join(repository, 'tools/i_core/domain_http.mjs')));
const db = new DatabaseSync(':memory:');
db.exec('CREATE TABLE core_metadata(key TEXT PRIMARY KEY,value TEXT NOT NULL);');
for (const [key,value] of Object.entries({schema_version:'6',node_id:'core-client-interop',cursor_secret:'s'.repeat(43)})) db.prepare('INSERT INTO core_metadata VALUES(?,?)').run(key,value);
db.exec(DOMAIN_SCHEMA_SQL);
const store = new DomainStore(db,{nodeId:'core-client-interop',cursorSecret:'s'.repeat(43),verifyAuthorization:()=>true});
store.registerDomain('example',{version:1,fields:{title:{type:'string',required:true},amount:{type:'number'},nested:{type:'object'}}},{mode:'authoritative'});
const credential=store.configurePrincipal({principal_id:'interop-phone',device_id:'interop-device',installation_id:'interop-install',scopes:['read','create','patch','delete','purge','restore','merge'].map(a=>'example:'+a),actors:['agent_inferred','user_direct'],trusted_interactive:true},{token:'synthetic-interop-token-never-valid-on-live-core'});
const principal=store.authenticate(credential.token);
for(let n=0;n<103;n++){
 const now=new Date().toISOString();
 const result=store.submit(principal,'example',{domain_protocol_version:1,core_instance_id:'core-client-interop',schema_version:1,op_id:randomUUID(),id:randomUUID(),base_revision:0,kind:'create',actor:'agent_inferred',created_at:now,expires_at:new Date(Date.parse(now)+60*86400000).toISOString(),data:{title:`合成分页 ${n} 🌧️`,amount:n===0?1e-7:n===1?1e20:n===2?1e21:n===3?1e-6:n+0.5,nested:{z:[null,true,'中文'],a:{value:1}}},provenance:{source:'fixture',source_refs:[],import_batch_id:null}});
 if(result.status!==201)throw new Error('synthetic_seed_failed');
}
const handler=createDomainRequestHandler({getStore:()=>store,authenticateDevice:()=>null});
const dropAt=process.argv[3]==='drop-first'?1:process.argv[3]==='drop-merge'?3:0;
let operationCount=0;
const server=http.createServer(async(req,res)=>{
 if(req.method==='POST'&&req.url==='/v1/core/domains/example/ops'&&++operationCount===dropAt){res.end=()=>res.destroy();}
 if(!await handler(req,res)){res.writeHead(404);res.end('{}');}
});
await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));
process.stdout.write(JSON.stringify({url:`http://127.0.0.1:${server.address().port}`,principal_id:credential.principal_id,generation:credential.generation})+'\n');
let closing=false;
function close(){if(closing)return;closing=true;server.close(()=>{db.close();process.exit(0);});server.closeAllConnections();}
process.stdin.setEncoding('utf8');process.stdin.on('data',data=>{if(data.trim()==='close')close();});process.stdin.on('end',close);
process.on('SIGTERM',close);
