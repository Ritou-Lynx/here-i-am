import { existsSync, readFileSync, readdirSync, statSync } from 'node:fs';
import path from 'node:path';
import { DatabaseSync } from 'node:sqlite';
import { pathToFileURL } from 'node:url';
import { plainPath, sha256, fail, PINNED_NODE_SHA256 } from '../package.mjs';
export const MARKER = 's6-lifecycle.json';
export const LOCK = 'shortcut-mail-relay.runtime.lock';
export function assertNode() {
 if (process.version !== 'v24.14.1' || sha256(readFileSync(process.execPath)) !== PINNED_NODE_SHA256 || process.execArgv.length) fail('node_runtime_unbound');
}
export function separatePaths(...paths) {
 for (let i=0;i<paths.length;i++) for(let j=i+1;j<paths.length;j++) {
  const a=paths[i].toLowerCase(), b=paths[j].toLowerCase();
  if(a===b || a.startsWith(b+path.sep) || b.startsWith(a+path.sep)) fail('paths_must_be_separate');
 }
}
export function stateDigest(root) {
 plainPath(root);
 const walk = (directory, prefix='') => readdirSync(directory,{withFileTypes:true}).sort((a,b)=>a.name<b.name?-1:1).flatMap(e=>{
  const relative=prefix+e.name;
  if(!prefix && [MARKER,LOCK].includes(e.name)) return [];
  const filename=plainPath(path.join(directory,e.name));
  if(e.isDirectory()) return [[relative+'/',null],...walk(filename,relative+'/')];
  if(!e.isFile()) fail('state_inventory_invalid');
  return [[relative,sha256(readFileSync(filename))]];
 });
 return sha256(JSON.stringify(walk(root)));
}
export function inspectExisting(filename, versions=['6']) {
 plainPath(filename);
 for(const suffix of ['-wal','-shm','-journal']) if(existsSync(filename+suffix)) fail('state_sidecars_require_review');
 const before=sha256(readFileSync(filename));
 const db=new DatabaseSync(pathToFileURL(filename).href+'?mode=ro&immutable=1',{readOnly:true});
 try {
  const meta=new Map(db.prepare('SELECT key,value FROM core_metadata').all().map(r=>[r.key,r.value]));
  const version=meta.get('schema_version');
  if(!versions.includes(version) || !meta.get('node_id') || !meta.get('cursor_secret')) fail('existing_core_identity_or_schema_required');
  if(meta.get('domain_backup_role')) fail('backup_activation_unsupported');
  if(db.prepare('PRAGMA quick_check').get().quick_check!=='ok') fail('integrity_check_failed');
  if(version!=='4') {
   if(db.prepare("SELECT value FROM activity_metadata WHERE key='database_role'").get()?.value!=='live') fail('backup_activation_unsupported');
   const claim=db.prepare('SELECT runtime_id,lease_expires_at_ms FROM activity_runtime_claim WHERE singleton=1').get();
   if(!claim || claim.runtime_id!=='' || claim.lease_expires_at_ms!==0) fail('activity_recovery_required');
  }
  return {version,nodeId:meta.get('node_id'),database_sha256:before};
 } finally { db.close(); if(sha256(readFileSync(filename))!==before) fail('state_changed_during_preflight'); }
}
export function validatePrevious(marker, config, before, configurationHash) {
 if(!marker || marker.format!=='schema6-lifecycle-v1' || marker.phase!=='clean_closed'
  || marker.database_path!==path.join(config.state,'i-core.sqlite')
  || marker.database_sha256!==before.database_sha256 || marker.node_id!==before.nodeId
  || marker.manifest_sha256!==config.manifest_sha256 || marker.configuration_sha256!==configurationHash
  || marker.state_tree_sha256!==stateDigest(config.state)
  || !/^[a-f0-9]{64}$/.test(marker.custody_sha256??'')
  || marker.supervisor?.job_empty_confirmed!==true || marker.supervisor?.child_exit_code!==0
  || marker.supervisor?.guardian_exit_code!==0 || marker.supervisor?.termination_requested!==false)
   fail('recovery_required');
 return marker;
}
