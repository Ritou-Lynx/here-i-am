import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import { DomainStore, DOMAIN_POLICY } from '../../../domain_store.mjs';

// Real DomainStore operations over a caller-owned synthetic database only.
export function domainFlow(mutate,{mode='authoritative'}={}){
 let now=Date.now(),token,nodeId,initialized=false;
 const id=randomUUID();
 function use(work){return mutate(db=>{
  nodeId=db.prepare("SELECT value FROM core_metadata WHERE key='node_id'").get().value;
  const cursorSecret=db.prepare("SELECT value FROM core_metadata WHERE key='cursor_secret'").get().value;
  const store=new DomainStore(db,{nodeId,cursorSecret,clock:()=>now,verifyAuthorization:({authorizationRef,request})=>authorizationRef==='bound:'+request.op_id});
  if(!initialized){
   store.registerDomain('example',{version:1,fields:{title:{type:'string',required:true}}},{mode});
   token=store.configurePrincipal({principal_id:'synthetic-'+mode,device_id:'synthetic-device',installation_id:'synthetic-install',actors:['user_direct'],trusted_interactive:true,
    scopes:mode==='shadow'?['example:shadow_read','example:shadow_write']:['read','create','patch','delete','restore','purge'].map(x=>'example:'+x)}).token;
   initialized=true;
  }
  return work(store,store.authenticate(token));
 });}
 function submit(kind,revision=0){return use((store,p)=>{
  const op_id=randomUUID(),request={domain_protocol_version:1,core_instance_id:nodeId,op_id,schema_version:1,kind,id,base_revision:revision,
   created_at:new Date(now).toISOString(),expires_at:new Date(now+DOMAIN_POLICY.intentTtl).toISOString(),actor:'user_direct',authorization_ref:'bound:'+op_id,
   ...(kind==='create'?{data:{title:'synthetic'},provenance:{source:'fixture',source_refs:[],import_batch_id:null}}:{}),...(kind==='patch'?{patch:{title:'edited'}}:{})};
  const result=store.submit(p,'example',request);assert.equal(result.status,mode==='shadow'?202:201,JSON.stringify(result));return result;
 });}
 return {id,submit,retention(){now+=31*86400000;return use(store=>{const result=store.runRetention();assert.equal(result.status,200,JSON.stringify(result));assert.equal(result.body.purged,1);return result;});}};
}
