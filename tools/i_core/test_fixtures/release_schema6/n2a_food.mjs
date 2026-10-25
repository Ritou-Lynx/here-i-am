import {DatabaseSync} from 'node:sqlite';
import {randomUUID} from 'node:crypto';
import {rmSync} from 'node:fs';
import path from 'node:path';
import {DomainStore} from '../../domain_store.mjs';
import {DOMAIN_SCHEMA_SQL} from '../../domain_schema.mjs';
import {ICoreStore} from '../../i_core_store.mjs';
import {createICoreServer} from '../../i_core_server.mjs';
import {foodTotals, createFoodDomainHooks, FOOD_WRITER_PRINCIPAL_ID} from '../../personal_data_domains.mjs';
import {syntheticRoot} from './synthetic_paths.mjs';

export const foodNow = Date.parse('2026-10-25T00:00:00.000Z');
export function foodData() {
 const items=[{name:'synthetic rice',food_ref:{source:'model',id:null},grams:100,grams_low:80,grams_high:120,
  kcal:100,protein_g:2,fat_g:1,carb_g:20,basis:'model_guess',confidence:'medium'}];
 return {eaten_at:'2026-10-25T08:00:00+08:00',local_date:'2026-10-25',meal:'breakfast',title:'synthetic meal',note:'',
  input_kind:'text',items,totals:foodTotals(items),user_corrected:false,voided:false};
}
export function foodMemory(t, options={}) {
 const db=new DatabaseSync(':memory:');
 db.exec("CREATE TABLE core_metadata(key TEXT PRIMARY KEY,value TEXT);INSERT INTO core_metadata VALUES('schema_version','6'),('node_id','food-synthetic'),('cursor_secret','synthetic-food-secret');");
 db.exec(DOMAIN_SCHEMA_SQL);
 const domains=new DomainStore(db,{nodeId:'food-synthetic',cursorSecret:'synthetic-food-secret',clock:()=>foodNow,
  domainHooks:createFoodDomainHooks({writerPrincipalIds:[FOOD_WRITER_PRINCIPAL_ID]}),...options});
 t.after(()=>db.close());return {db,domains};
}
export function foodOperation(core, kind='create', overrides={}) {
 return {domain_protocol_version:1,core_instance_id:core.store.nodeId,schema_version:1,op_id:randomUUID(),kind,
  id:randomUUID(),base_revision:kind==='create'?0:1,created_at:new Date(foodNow).toISOString(),
  expires_at:new Date(foodNow+86400000).toISOString(),actor:'agent_inferred',
  ...(kind==='create'?{data:foodData(),provenance:{source:'synthetic_food',source_refs:[],import_batch_id:null}}:{}),...overrides};
}
export async function foodHttp(t) {
 const root=syntheticRoot('n2a-food-http-'), databasePath=path.join(root,'core.sqlite');
 let core;
 t.after(async()=>{if(core)await core.close();rmSync(root,{recursive:true,force:true});});
 const initial=new ICoreStore(databasePath,{activityEnabled:false,activityAutoActivate:false});initial.close();
 const db=new DatabaseSync(databasePath);
 try {db.exec("BEGIN IMMEDIATE");db.exec(DOMAIN_SCHEMA_SQL);db.exec("UPDATE core_metadata SET value='6' WHERE key='schema_version';COMMIT");} finally {db.close();}
 let origin;
 async function open(hooks=true) {
  core=createICoreServer({databasePath,clock:()=>foodNow,pairingCode:'synthetic-pairing-code',
   ...(hooks?{domainHooks:createFoodDomainHooks({writerPrincipalIds:[FOOD_WRITER_PRINCIPAL_ID]})}:{})});
  const address=await core.listen({host:'127.0.0.1',port:0});origin='http://127.0.0.1:'+address.port;return core;
 }
 await open();
 return {root,databasePath,get core(){return core;},async close(){await core.close();core=null;},open,
  async send(route, token, body) {
   const response=await fetch(origin+route,{method:body?'POST':'GET',signal:AbortSignal.timeout(5000),headers:{connection:'close',
    'x-i-core-domain-protocol':'1','x-core-protocol':'0.1',...(token?{authorization:'Bearer '+token}:{}),
    ...(body?{'content-type':'application/json'}:{})},...(body?{body:JSON.stringify(body)}:{})});
   return {status:response.status,body:await response.json()};
  }};
}
