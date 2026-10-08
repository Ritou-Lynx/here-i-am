// Manual backup preparation only: no scheduler integration, process changes, keys or DB reads.
// Prepare immediately before an authorized capture, call assertUnchanged before AND after it,
// and reject (but retain) the captured artifact if either check fails. A stable custody vector
// is not MAC authentication, writer authority, cross-component atomicity or activation proof.
// Existing release/configuration inventory is preserved, not regenerated or declared complete.
// Online SQLite capture still has its own snapshot time and capture-window provenance; these
// source-authority history files do not turn an inspection copy into activation authority.
// External rawManifest/plan/release references are checked as hashes only, not captured here.
// CLI: prepare --spec FILE --custody-directory DIR --expected-head-sha256 HASH --output NEW_FILE
//      check --prepared FILE --prepared-sha256 HASH (before and after manual full capture)
import { createHash } from 'node:crypto';
import { execFileSync } from 'node:child_process';
import { lstatSync, readdirSync, writeFileSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { backupFilePrimitives as f, BACKUP_LIMITS } from '../release_schema6/backup_bundle.mjs';
import { cleanEnvironment, plainPath } from '../release_schema6/package.mjs';

const HASH=/^[a-f0-9]{64}$/, HISTORY=/^([a-f0-9]{64})\.(head|floor|recovery|package-switch)\.json$/;
const FORMAT='schema6-manual-custody-backup-inventory-v1', VECTOR='schema6-custody-source-vector-v1';
const flags={approved:false,deploymentReady:false,authorityVerified:false,macAuthenticated:false,crossComponentAtomic:false};
const fail=code=>{throw Object.assign(new Error(code),{code});};
const sha=b=>createHash('sha256').update(b).digest('hex');
const same=(a,b)=>JSON.stringify(a)===JSON.stringify(b);
const eq=(a,b)=>process.platform==='win32'?a.toLowerCase()===b.toLowerCase():a===b;
const parentIs=(p,d)=>eq(path.dirname(p),d);
const digest=x=>{if(!HASH.test(x??''))fail('custody_inventory_hash_required');return x;};
const object=v=>v&&typeof v==='object'&&!Array.isArray(v);
// Match recovery_adapter's 4 MiB floor ceiling; the inspection context stays at 1 MiB.
const metadataLimit=name=>Math.min(BACKUP_LIMITS.file,name==='current-head.json'||name.endsWith('.head.json')?16384:name.endsWith('.floor.json')?4*1024*1024:BACKUP_LIMITS.custody);

// Reuse the production ACL contract in one read-only batch; never print identities.
function assertAcls(items){
 for(const {target,root=false} of items)f.safe(target,root);
 if(process.platform!=='win32'){
  for(const {target} of items){const s=lstatSync(target);if(s.uid!==process.getuid()||(s.mode&0o077)!==0)fail('custody_inventory_private_path_required');}
  return;
 }
 const script=fileURLToPath(new URL('../release_schema6/lifecycle/protected_paths.ps1',import.meta.url));
 const quote=s=>"'"+s.replaceAll("'","''")+"'";
 const command="$ErrorActionPreference='Stop'; . "+quote(script)+"; $items=([Console]::In.ReadToEnd()|ConvertFrom-Json); foreach($item in $items){ if($item.root){Assert-ProtectedPath -Target $item.target -Root}else{Assert-ProtectedPath -Target $item.target} }";
 try{execFileSync(path.join(process.env.SystemRoot,'System32/WindowsPowerShell/v1.0/powershell.exe'),['-NoProfile','-NonInteractive','-Command',command],{input:JSON.stringify(items),env:cleanEnvironment(),windowsHide:true,timeout:30000,stdio:['pipe','pipe','pipe'],maxBuffer:65536});}
 catch{fail('custody_inventory_acl_rejected');}
}
function directoryIdentity(directory){f.safe(directory,true);const s=lstatSync(directory,{bigint:true});return `${s.dev}:${s.ino}`;}
function names(directory){
 const found=[];
 for(const e of readdirSync(directory,{withFileTypes:true})){
  const full=path.join(directory,e.name);
  if(e.name==='custody.lock'){
   // A lock may appear/disappear while reading. Its contents and changes are not custody history.
   if(!e.isFile())fail('custody_inventory_lock_path_rejected');
   try{f.safe(full);}catch(error){if(error.code!=='ENOENT')throw error;}
   continue;
  }
  if(!e.isFile()||!(e.name==='current-head.json'||HISTORY.test(e.name)))fail('custody_inventory_unknown_entry');
  f.safe(full);found.push(e.name);
  if(found.length>BACKUP_LIMITS.files)fail('inventory_limit_exceeded');
 }
 return found.sort();
}
function readMetadata(sourcePath,limit=BACKUP_LIMITS.custody){
 const chunks=[];let observation;
 try{
  observation=f.readStable(sourcePath,c=>chunks.push(Buffer.from(c)),limit);
  const bytes=Buffer.concat(chunks);let value;
  try{value=JSON.parse(bytes.toString('utf8'));}catch{fail('custody_inventory_json_invalid');}finally{bytes.fill(0);}
  if(!object(value))fail('custody_inventory_json_invalid');
  return {value,observation:{sourcePath,...observation}};
 }finally{for(const c of chunks)c.fill(0);}
}
function validateChain(records,expectedHeadSha256,nodeId,databasePath){
 const get=(hash,kind)=>{const r=records.get(digest(hash)+'.'+kind+'.json');if(!r)fail('custody_inventory_reference_missing');return r.value;};
 const current=records.get('current-head.json');
 if(!current||current.observation.sha256!==expectedHeadSha256)fail('custody_inventory_head_anchor_mismatch');
 if(!same(current.value,get(expectedHeadSha256,'head')))fail('custody_inventory_head_copy_mismatch');
 const validateHead=h=>{
  if(!Number.isSafeInteger(h.generation)||h.generation<1)fail('custody_inventory_generation_invalid');
  const floor=get(h.custodySha256,'floor');
  if(typeof h.receiptId!=='string'||!h.receiptId||floor.cleanCloseReceiptId!==h.receiptId)fail('custody_inventory_receipt_mismatch');
  if(h.generation===1){if(h.previousHeadSha256!==null)fail('custody_inventory_generation_invalid');}
  else if(get(h.previousHeadSha256,'head').generation!==h.generation-1)fail('custody_inventory_generation_invalid');
 };
 const reachableHeads=new Set();let cursor=expectedHeadSha256;
 while(cursor){
  if(reachableHeads.has(cursor))fail('custody_inventory_head_cycle');
  reachableHeads.add(cursor);const h=get(cursor,'head');
  validateHead(h);cursor=h.previousHeadSha256;
 }
 let unanchoredHeadCount=0;
 for(const [name,{value:v}] of records){
  const kind=name==='current-head.json'?'head':HISTORY.exec(name)[2];
  const format={head:'i-core-custody-head-v1',floor:'i-core-floor-custody-v1',recovery:'i-core-recovery-event-v1','package-switch':'i-core-package-switch-event-v1'}[kind];
  if(v.format!==format||v.nodeId!==nodeId||v.databasePath!==databasePath||!HASH.test(v.authentication??''))fail('custody_inventory_binding_mismatch');
  if(kind==='head'){
   // writeHead archives before publishing current-head. Preserve such history without promoting it.
   if(name!=='current-head.json'&&!reachableHeads.has(name.slice(0,64)))unanchoredHeadCount++;
   validateHead(v);
  }else if(kind==='floor'){
   if(![5,6].includes(v.schemaVersion)||!HASH.test(v.databaseSha256??''))fail('custody_inventory_floor_invalid');
   if(v.recoveryEventSha256!==undefined)get(v.recoveryEventSha256,'recovery');
   if(v.packageSwitchEventSha256!==undefined)get(v.packageSwitchEventSha256,'package-switch');
  }else{
   if(v.previousHeadSha256!==null)get(v.previousHeadSha256,'head');
   if(kind==='recovery')digest(v.rawManifestSha256);
   else{
    digest(v.planSha256);digest(v.databaseSha256);
    const prior=get(v.previousHeadSha256,'head');
    if(!object(v.sourceMarker)||v.sourceMarker.node_id!==nodeId||v.sourceMarker.custody_sha256!==prior.custodySha256)fail('custody_inventory_switch_binding_mismatch');
    for(const endpoint of [v.from,v.to]){if(!object(endpoint))fail('custody_inventory_switch_binding_mismatch');digest(endpoint.manifestSha256);digest(endpoint.configurationSha256);}
    if(v.rollbackOf!==null&&v.rollbackOf!==undefined)get(v.rollbackOf,'package-switch');
    if(v.sourceMarker.package_switch_event_sha256!==undefined)get(v.sourceMarker.package_switch_event_sha256,'package-switch');
   }
  }
 }
 return {unanchoredHeadCount};
}
function snapshot({custodyDirectory,expectedHeadSha256,nodeId,databasePath,contextPath}){
 digest(expectedHeadSha256);
 const before=directoryIdentity(custodyDirectory),initialNames=names(custodyDirectory);
 if(!initialNames.includes('current-head.json'))fail('custody_inventory_head_required');
 const paths=initialNames.map(name=>({target:path.join(custodyDirectory,name)}));
 assertAcls([{target:custodyDirectory,root:true},{target:path.dirname(contextPath),root:true},{target:contextPath},...paths]);
 const records=new Map();let total=0;
 for(const name of initialNames){
  const record=readMetadata(path.join(custodyDirectory,name),metadataLimit(name));
  if(!record.observation.bytes||(total+=record.observation.bytes)>BACKUP_LIMITS.total)fail('input_size_exceeded');
  if(name!=='current-head.json'&&record.observation.sha256!==name.slice(0,64))fail('custody_inventory_filename_hash_mismatch');
  records.set(name,record);
 }
 const {unanchoredHeadCount}=validateChain(records,expectedHeadSha256,nodeId,databasePath);
 const context=readMetadata(contextPath);
 if(context.value.format!=='i-core-recovery-custody-v1'||context.value.node_id!==nodeId||context.value.database_path!==databasePath)fail('custody_inventory_context_binding_mismatch');
 for(const {observation} of [...records.values(),context])if(!same(f.readStable(observation.sourcePath,undefined,observation===context.observation?BACKUP_LIMITS.custody:metadataLimit(path.basename(observation.sourcePath))),{bytes:observation.bytes,sha256:observation.sha256,identity:observation.identity}))fail('custody_inventory_source_changed');
 assertAcls([{target:custodyDirectory,root:true},{target:contextPath},...paths]);
 if(before!==directoryIdentity(custodyDirectory)||!same(initialNames,names(custodyDirectory)))fail('custody_inventory_directory_changed');
 return {format:VECTOR,custodyDirectory,expectedHeadSha256,nodeId,databasePath,contextPath,directoryIdentity:before,unanchoredHeadCount,files:initialNames.map(name=>({name,...records.get(name).observation})),context:context.observation};
}

export function prepareCustodyBackupInventory({specTemplate,custodyDirectory,expectedHeadSha256}){
 const spec=f.validate(JSON.parse(JSON.stringify(specTemplate)));
 f.safe(custodyDirectory,true);digest(expectedHeadSha256);
 const anchors=spec.entries.filter(e=>e.role==='recovery_custody'&&parentIs(e.source_path,custodyDirectory)&&path.basename(e.source_path)==='current-head.json');
 if(anchors.length!==1)fail('custody_inventory_unique_head_anchor_required');
 const contexts=spec.entries.filter(e=>e.role==='recovery_custody'&&e.custody_context===true);
 if(contexts.length!==1||parentIs(contexts[0].source_path,custodyDirectory))fail('custody_inventory_external_context_required');
 for(const e of spec.entries)if(parentIs(e.source_path,custodyDirectory)&&e.role!=='recovery_custody')fail('custody_inventory_role_scope_mismatch');
 const sourceVector=snapshot({custodyDirectory,expectedHeadSha256,nodeId:spec.node_id,databasePath:spec.canonical_database_path,contextPath:contexts[0].source_path});
 if(sourceVector.context.sha256!==contexts[0].sha256)fail('custody_inventory_context_hash_mismatch');
 const prefix=path.posix.dirname(anchors[0].name);
 const custodyEntries=sourceVector.files.map(file=>({role:'recovery_custody',name:file.name==='current-head.json'?anchors[0].name:(prefix==='.'?'':prefix+'/')+file.name,source_path:file.sourcePath,sha256:file.sha256}));
 spec.entries=spec.entries.filter(e=>!parentIs(e.source_path,custodyDirectory)).concat(custodyEntries);
 f.validate(spec);
 // Metadata-only size/plain/single-link checks for other roles; never open credential/DB content.
 let total=0;for(const e of spec.entries){f.safe(e.source_path);const size=lstatSync(e.source_path).size;if((!size&&e.role!=='release')||size>BACKUP_LIMITS.file||(total+=size)>BACKUP_LIMITS.total)fail('input_size_exceeded');}
 assertAcls(spec.entries.map(e=>({target:e.source_path})));
 if(Buffer.byteLength(JSON.stringify(spec))>BACKUP_LIMITS.manifest)fail('manifest_size_exceeded');
 assertUnchanged(sourceVector);
 return {format:FORMAT,prepared:true,...flags,scope:'manual_inventory_preparation_only',externalReferenceContentsVerified:false,spec,sourceVector};
}
export function assertUnchanged(sourceVector){
 if(!object(sourceVector)||sourceVector.format!==VECTOR||!Array.isArray(sourceVector.files)||sourceVector.files.length>BACKUP_LIMITS.files)fail('custody_inventory_vector_invalid');
 const current=snapshot(sourceVector);
 if(!same(current,sourceVector))fail('custody_inventory_source_changed');
 return {unchanged:true,...flags};
}
function readInput(filename,limit){assertAcls([{target:path.dirname(filename),root:true},{target:filename}]);return readMetadata(filename,limit);}
function cli(argv){
 const action=argv.shift(),args=new Map();
 while(argv.length){const k=argv.shift(),v=argv.shift();if(!k?.startsWith('--')||!v||args.has(k))fail('custody_inventory_usage');args.set(k,v);}
 if(action==='prepare'&&same([...args.keys()].sort(),['--custody-directory','--expected-head-sha256','--output','--spec'])){
  const spec=readInput(path.resolve(args.get('--spec')),BACKUP_LIMITS.manifest).value;
  const result=prepareCustodyBackupInventory({specTemplate:spec,custodyDirectory:path.resolve(args.get('--custody-directory')),expectedHeadSha256:args.get('--expected-head-sha256')});
  const output=plainPath(path.resolve(args.get('--output')),{missing:true});
  if(parentIs(output,result.sourceVector.custodyDirectory))fail('custody_inventory_output_scope_rejected');
  assertAcls([{target:path.dirname(output),root:true}]);
  const bytes=Buffer.from(JSON.stringify(result,null,2)+'\n');
  if(bytes.length>BACKUP_LIMITS.manifest)fail('manifest_size_exceeded');
  writeFileSync(output,bytes,{flag:'wx',mode:0o600,flush:true});
  return {prepared:true,...flags,files:result.sourceVector.files.length,unanchoredHeads:result.sourceVector.unanchoredHeadCount,preparedSha256:sha(bytes)};
 }
 if(action==='check'&&same([...args.keys()].sort(),['--prepared','--prepared-sha256'])){
  const input=readInput(path.resolve(args.get('--prepared')),BACKUP_LIMITS.manifest);
  if(input.observation.sha256!==digest(args.get('--prepared-sha256'))||input.value.format!==FORMAT)fail('custody_inventory_prepared_anchor_mismatch');
  const checked=assertUnchanged(input.value.sourceVector);
  return {...checked,preparedSha256:input.observation.sha256,files:input.value.sourceVector.files.length,unanchoredHeads:input.value.sourceVector.unanchoredHeadCount};
 }
 fail('custody_inventory_usage');
}
if(process.argv[1]&&import.meta.url===pathToFileURL(path.resolve(process.argv[1])).href){
 try{process.stdout.write(JSON.stringify(cli(process.argv.slice(2)))+'\n');}
 catch{process.stdout.write(JSON.stringify({prepared:false,...flags,code:'custody_inventory_rejected'})+'\n');process.exitCode=2;}
}