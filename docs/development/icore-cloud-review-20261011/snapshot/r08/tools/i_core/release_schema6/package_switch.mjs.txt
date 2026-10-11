import { createHash } from 'node:crypto';
import { readFileSync, readdirSync, lstatSync } from 'node:fs';
import path from 'node:path';
import { INVENTORY, PINNED_NODE_SHA256, plainPath, sha256, fail } from './package.mjs';

export const SWITCH_PENDING = 's6-package-switch-pending.json';
// Historical schema6 release inventory is fixed independently of future additions.
export const LEGACY_SWITCH_INVENTORY = Object.freeze([
 'activity_control_plane.mjs','domain_http.mjs','domain_store.mjs','domain_schema.mjs','domain_migrate.mjs','i_core_server.mjs','i_core_store.mjs','personal_data_domains.mjs','inspection_read_only.mjs','shortcut_mail_relay.mjs','send_shortcut_mail.ps1','strict_smtp_tls_validation.ps1',
].map(n=>'tools/i_core/'+n).concat([
 'package.mjs','preflight.mjs','cli.mjs','preflight_schema6.ps1','README.md','recovery_adapter.mjs','readonly_witness.mjs','recovery_witness_worker.mjs','backup_bundle.mjs','backup_bundle_schema6.ps1','automatic_recovery.mjs','raw_state_backup.mjs','backup_key_child.mjs','key_custody.ps1','restore_inspection.mjs','portable_key_custody.mjs','automatic_backup.mjs','portable_backup_schema6.ps1','scheduler_once_schema6.ps1','lifecycle/start_schema6.ps1','lifecycle/owned_job.ps1','lifecycle/job_guardian.ps1','lifecycle/protected_paths.ps1','lifecycle/request_stop.ps1','lifecycle/runtime_child.mjs','lifecycle/common.mjs','lifecycle/configuration.mjs','lifecycle/offline_lease.mjs','lifecycle/probe_offline.ps1','lifecycle/offline_probe_client.mjs','lifecycle/session_window.ps1','lifecycle/login_schema6.ps1','lifecycle/prepare_login_schema6.ps1','lifecycle/mcp_configuration.ps1',
].map(n=>'tools/i_core/release_schema6/'+n),['runtime/node.exe']).sort());
const hex = x=>typeof x==='string'&&/^[a-f0-9]{64}$/.test(x);
const same = (a,b)=>JSON.stringify(a)===JSON.stringify(b);
const quote = s=>'"'+s.replaceAll('"','""')+'"';
const encode = v=>JSON.stringify(v,(_,x)=>typeof x==='bigint'?{integer:String(x)}:typeof x==='number'&&(!Number.isFinite(x)||Object.is(x,-0))?{real:Object.is(x,-0)?'-0':String(x)}:x instanceof Uint8Array?{bytes:Buffer.from(x).toString('base64')}:x);
function inventory(root,relative=''){
 return readdirSync(path.join(root,relative),{withFileTypes:true}).flatMap(e=>{
  const name=relative?relative+'/'+e.name:e.name,filename=plainPath(path.join(root,name));
  if(e.isDirectory())return inventory(root,name);
  if(!e.isFile()||lstatSync(filename).nlink!==1)fail('switch_release_inventory_invalid');
  return [name];
 }).sort();
}
// Read-only verification, never execute code from a supplied manifest. Old and new
// inventories are exact independently reviewed sets, never manifest-selected sets.
export function verifySwitchRelease(release,expected){
 plainPath(release);if(!hex(expected))fail('manifest_anchor_required');
 const bytes=readFileSync(plainPath(path.join(release,'manifest.json')));
 if(sha256(bytes)!==expected)fail('manifest_hash_mismatch');
 const m=JSON.parse(bytes),names=m.files?.map(f=>f.path).sort();
 if(m.format!=='i-core-schema6-preflight-candidate-v1'||m.core_schema_version!==6
  ||m.runtime_profile!=='schema6-owned-lifecycle-v1'||m.activation_supported!==false
  ||!(/^[a-f0-9]{40}$/).test(m.source_commit??'')||m.core_commit!==m.source_commit||m.wrapper_commit!==m.source_commit
  ||m.node_version!=='v24.14.1'||m.pinned_node_sha256!==PINNED_NODE_SHA256
  ||!same(Object.keys(m.policy??{}).sort(),['activity_enabled','companion_reply_jobs','companion_upload_mode','domain_policy'])
  ||m.policy.activity_enabled!==false||m.policy.companion_reply_jobs!==false||m.policy.companion_upload_mode!=='legacy_b3'||m.policy.domain_policy!=='owner_managed'
  ||(!same(names,LEGACY_SWITCH_INVENTORY)&&!same(names,INVENTORY))
  ||!same(inventory(release),[...names,'manifest.json'].sort()))fail('switch_release_inventory_invalid');
 for(const f of m.files){
  const p=plainPath(path.join(release,f.path));
  if(!hex(f.sha256)||!Number.isSafeInteger(f.bytes)||f.bytes<0||lstatSync(p).size!==f.bytes||sha256(readFileSync(p))!==f.sha256)fail('release_file_changed');
 }
 if(m.files.find(f=>f.path==='runtime/node.exe')?.sha256!==PINNED_NODE_SHA256)fail('node_hash_mismatch');
 return {manifestSha256:expected,sourceCommit:m.source_commit};
}
export function readSwitchPlan(filename,expected){
 const raw=readFileSync(plainPath(filename));if(!hex(expected)||raw.length>128*1024||sha256(raw)!==expected)fail('switch_plan_anchor_mismatch');
 const p=JSON.parse(raw);
 if(p.format!=='schema6-package-switch-approved-v1'||p.approved!==true||!(/^[a-zA-Z0-9_-]{8,80}$/).test(p.operationId??'')
  ||!hex(p.expectedHeadSha256)||!hex(p.expectedMarkerSha256)||![null,undefined].includes(p.rollbackOf)&&!hex(p.rollbackOf)
  ||!Array.isArray(p.artifacts)||p.artifacts.length<4)fail('switch_plan_invalid');
 for(const end of [p.from,p.to]){
  if(!end||!hex(end.manifestSha256)||!hex(end.configurationSha256))fail('switch_plan_invalid');
  plainPath(end.releaseDirectory);plainPath(end.configurationPath);
 }
 if(p.from.manifestSha256===p.to.manifestSha256||p.from.releaseDirectory===p.to.releaseDirectory)fail('switch_distinct_packages_required');
 if(!Array.isArray(p.fromArtifacts)||p.fromArtifacts.length!==4)fail('switch_artifacts_required');
 const roles=p.artifacts.map(a=>a.role).sort();
 if(!same(roles,['backup','login','mcp','task']))fail('switch_artifacts_required');
 if(!same(p.fromArtifacts.map(a=>a.role).sort(),['backup','login','mcp','task']))fail('switch_artifacts_required');
 for(const a of [...p.artifacts,...p.fromArtifacts]){if(!hex(a.sha256)||sha256(readFileSync(plainPath(a.path)))!==a.sha256)fail('switch_artifact_changed');}
 return {...p,planSha256:expected};
}
export function verifySwitchConfigurations(plan){
 const values=[];
 for(const end of [plan.from,plan.to]){
  verifySwitchRelease(end.releaseDirectory,end.manifestSha256);
  const raw=readFileSync(plainPath(end.configurationPath));if(sha256(raw)!==end.configurationSha256)fail('switch_configuration_changed');
  const value=JSON.parse(raw);if(value.manifest_sha256!==end.manifestSha256)fail('config_binding_mismatch');
  values.push(value);
 }
 const normalized=values.map(v=>{const c={...v};delete c.manifest_sha256;return c;});
 if(!same(normalized[0],normalized[1]))fail('switch_configuration_scope_changed');
 return values;
}
// Complete content and schema commitment, including unknown tables and internal
// sequence state. No business table or metadata key is exempted. This intentionally
// rejects even maintenance/retention changes. The fixed policy keeps activity dormant.
export function packageBusinessWitness(db){
 const objects=db.prepare("SELECT type,name,tbl_name,sql FROM sqlite_master ORDER BY type,name").all();
 const digest=createHash('sha256').update('schema6-all-business-v1\\0').update(encode(objects));
 const tableInfo=new Map(db.prepare('PRAGMA main.table_list').all().filter(t=>t.schema==='main').map(t=>[t.name,t]));
 let tables=0,rows=0;
 for(const o of objects.filter(o=>o.type==='table')){
  const info=tableInfo.get(o.name);
  if(!info||info.type!=='table'||![0,1].includes(info.wr))fail('switch_business_schema_unverifiable');
  const fields=db.prepare('PRAGMA table_xinfo('+quote(o.name)+')').all();
  if(fields.some(c=>![0,2,3].includes(c.hidden)))fail('switch_business_schema_unverifiable');
  const columns=fields.map(c=>c.name);
  if(!columns.length)fail('switch_business_schema_invalid');
  let selected=columns.map(quote),order=[...selected];
  if(info.wr===0){
   const names=new Set(columns.map(c=>c.toLowerCase()));
   const rowid=['rowid','_rowid_','oid'].find(c=>!names.has(c));
   if(!rowid)fail('switch_business_schema_unverifiable');
   let label='__package_switch_rowid__';while(names.has(label.toLowerCase()))label+='_';
   selected=[quote(rowid)+' AS '+quote(label),...selected];order=[quote(rowid),...order];
   columns.unshift(label);
  }
  const sql='SELECT '+selected.join(',')+' FROM '+quote(o.name)+' ORDER BY '+order.map(c=>c+' COLLATE BINARY').join(',');
  const statement=db.prepare(sql);statement.setReadBigInts(true);
  digest.update(encode({table:o.name,columns}));let count=0;
  for(const row of statement.iterate()){digest.update(encode(row)).update('\\n');count++;}
  digest.update(encode({count}));tables++;rows+=count;
 }
 return {format:'schema6-all-business-v1',sha256:digest.digest('hex'),tables,rows};
}
