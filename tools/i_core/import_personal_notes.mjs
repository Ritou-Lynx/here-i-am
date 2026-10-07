// Explicit, read-only legacy notes input. Apply requires a prepared trusted host adapter.
import fs from 'node:fs';
import path from 'node:path';
import { pathToFileURL } from 'node:url';
import { DatabaseSync } from 'node:sqlite';
import { stableImportId } from './personal_data_domains.mjs';

export class PersonalImportError extends Error {constructor(code){super(code);this.code=code;}}
const fail=code=>{throw new PersonalImportError(code);};
export function safeSourceFile(input,{maxBytes=67108864}={}) {
  if(typeof input!=='string'||!path.isAbsolute(input))fail('explicit_absolute_source_required');
  const resolved=path.resolve(input);
  let current=resolved;
  while(true){
    const stat=fs.lstatSync(current);
    if(stat.isSymbolicLink()||(current===resolved?(!stat.isFile()||stat.nlink!==1):!stat.isDirectory()))fail('unsafe_source_path');
    const parent=path.dirname(current);if(parent===current)break;current=parent;
  }
  if(fs.statSync(resolved).size>maxBytes)fail('source_too_large');
  return resolved;
}
function offlineDatabase(file) {
  for(const suffix of ['-wal','-journal','-shm'])if(fs.existsSync(file+suffix))fail('source_must_be_closed_copy');
}
const validId=v=>typeof v==='string'&&/^[a-zA-Z0-9][a-zA-Z0-9_.:-]{0,199}$/.test(v);
const epoch=v=>Number.isSafeInteger(v)&&v>=0&&Number.isFinite(new Date(v).getTime());
const iso=v=>new Date(v).toISOString();
export function readPersonalNotes(sourcePath) {
  const file=safeSourceFile(sourcePath);offlineDatabase(file);
  const db=new DatabaseSync(file,{readOnly:true});
  try{
    db.exec('PRAGMA query_only=ON; BEGIN');
    if(!db.prepare("SELECT 1 FROM sqlite_master WHERE type='table' AND name='notes'").get())fail('notes_table_required');
    const count=Number(db.prepare('SELECT COUNT(*) n FROM notes').get().n);if(count>5000)fail('source_too_many_records');
    const rows=db.prepare('SELECT note_id,revision,text,status,created_at_ms,updated_at_ms,delivered_revision,phone_card_id FROM notes ORDER BY note_id').all();
    const ids=new Set();
    for(const row of rows){
      if(!/^note_[A-Za-z0-9_-]{8,48}$/.test(row.note_id)||ids.has(row.note_id)||!Number.isSafeInteger(row.revision)||row.revision<1
        ||!['active','deleted'].includes(row.status)||!epoch(row.created_at_ms)||!epoch(row.updated_at_ms)||row.updated_at_ms<row.created_at_ms
        ||!Number.isSafeInteger(row.delivered_revision)||row.delivered_revision<0||row.delivered_revision>row.revision
        ||!(row.phone_card_id===null||validId(row.phone_card_id))
        ||row.status==='active'&&(typeof row.text!=='string'||!row.text.trim()||row.text.length>16000))fail('invalid_notes_record');
      ids.add(row.note_id);
      // Even an inconsistent legacy tombstone must never carry old text into the import pipeline.
      if(row.status==='deleted')row.text=null;
    }
    db.exec('ROLLBACK');return rows;
  } finally{db.close();}
}
export function validateImportOptions({sourceId,batchId,mappingVersion='personal-import-v1',targetInstanceId}) {
  if(![sourceId,batchId,mappingVersion,targetInstanceId].every(validId))fail('explicit_import_context_required');
}
export function mappedOrigin(mapping,sourceId) {
  const value=typeof mapping==='function'?mapping(sourceId):mapping?.[sourceId];
  if(!value||Object.keys(value).some(k=>!['principal_id','device_id'].includes(k))||!validId(value.principal_id)||!validId(value.device_id))return null;
  return {...value};
}
export function applyImportRecords(records,{target,principal,targetInstanceId,dryRun=true,authorizationRef,sourceId,batchId,mappingVersion='personal-import-v1',sourceKind}={}) {
  validateImportOptions({sourceId,batchId,mappingVersion,targetInstanceId});
  if(typeof dryRun!=='boolean')fail('invalid_apply_mode');
  if(target&&(target.nodeId!==targetInstanceId||typeof target.adoptLegacyRecord!=='function'))fail('target_instance_mismatch');
  if(!dryRun&&(!target||!principal||!authorizationRef))fail('trusted_host_adapter_required');
  const missing=records.some(entry=>!entry.record.origin);
  const mappings=[];let stopped=false;
  for(const entry of records){
    const mapping={domain:entry.domain,source_id:entry.record.id,source_revision:entry.record.revision,target_id:entry.record.id,target_revision:entry.record.revision};
    if(!entry.record.origin){mappings.push({...mapping,decision:'mapping_required'});continue;}
    if(stopped||!dryRun&&missing){mappings.push({...mapping,decision:'not_attempted'});continue;}
    if(!target||dryRun&&entry.deferDryRun){mappings.push({...mapping,decision:'planned',...(entry.deferDryRun?{reason_code:'dependency_requires_apply_order'}:{})});continue;}
    const result=target.adoptLegacyRecord(principal,entry.domain,entry.record,{
      dryRun,authorizationRef,sourceKind,sourceRecordId:entry.record.id,sourceRevision:entry.record.revision,batchId,mappingVersion,
      opId:stableImportId(sourceId,entry.domain,JSON.stringify([entry.record.id,entry.record.revision,batchId,mappingVersion])),
    });
    const success=result.status>=200&&result.status<300;
    mapping.decision=success?(dryRun?'validated':result.body?.transport_state==='shadow_staged'?'shadow_staged':result.body?.outcome==='duplicate'?'duplicate':'accepted'):'conflict';
    mapping.reason_code=result.body?.reason??result.body?.error?.code??null;
    if(!dryRun&&result.body?.receipt)mapping.receipt=result.body.receipt;
    mappings.push(mapping);
    if(!success&&!dryRun)stopped=true; // Per-record atomicity only; report exact partial progress.
  }
  return {phase:dryRun?'dry_run':'apply',source_kind:sourceKind,batch_id:batchId,mapping_version:mappingVersion,
    totals:Object.fromEntries(['planned','validated','accepted','duplicate','shadow_staged','conflict','mapping_required','not_attempted'].map(d=>[d,mappings.filter(m=>m.decision===d).length])),mappings};
}
export function importPersonalNotes({sourcePath,originMapping,...options}={}) {
  const rows=readPersonalNotes(sourcePath);
  const records=rows.map(row=>{
    const deleted=row.status==='deleted';
    return {domain:'captures',record:{
      id:row.note_id,revision:row.revision,deleted_at:deleted?iso(row.updated_at_ms):null,origin:mappedOrigin(originMapping,row.note_id),
      provenance:{source:'i_remember',source_refs:[],import_batch_id:options.batchId},
      ...(!deleted?{data:{text:row.text,source:'claude_web',recorded_at:iso(row.created_at_ms),
        // Legacy transport acknowledgement does not prove organizer processing. Retain no false done claim.
        planner:{status:'skipped',outputs:[],input_revision:row.revision,note:'legacy_i_remember'},
      }}:{}),
    }};
  });
  return applyImportRecords(records,{...options,sourceKind:'i_remember'});
}
export function parseImportArgs(argv) {
  const out={};
  for(let i=0;i<argv.length;i++){
    const arg=argv[i];
    if(arg==='--apply'){if(out.apply)fail('invalid_arguments');out.apply=true;continue;}
    if(!['--source','--source-id','--batch-id','--target-instance','--adapter','--origin-map','--mapping-version','--week-source','--day-source'].includes(arg)||out[arg]!==undefined||!argv[i+1]||argv[i+1].startsWith('--'))fail('invalid_arguments');
    out[arg]=argv[++i];
  }
  return out;
}
export async function importCli(run,argv) {
  try{
    const args=parseImportArgs(argv);
    let context={};
    if(args['--adapter']){
      const adapter=safeSourceFile(args['--adapter'],{maxBytes:1048576});
      // This is explicit trusted-host code supplied by the operator, never a source-data module.
      const module=await import(pathToFileURL(adapter).href);
      if(typeof module.createImportContext!=='function')fail('trusted_host_adapter_required');
      context=await module.createImportContext({targetInstanceId:args['--target-instance'],dryRun:!args.apply});
    }
    if(args.apply&&!args['--adapter'])fail('trusted_host_adapter_required');
    const originMapping=args['--origin-map']?JSON.parse(fs.readFileSync(safeSourceFile(args['--origin-map'],{maxBytes:1048576}),'utf8')):context.originMapping;
    const result=run({...context,sourcePath:args['--source'],sourceId:args['--source-id'],batchId:args['--batch-id'],
      weekSourcePath:args['--week-source'],daySourcePath:args['--day-source'],targetInstanceId:args['--target-instance'],mappingVersion:args['--mapping-version']??'personal-import-v1',originMapping,dryRun:!args.apply});
    // CLI output is aggregate only; private mapping receipts remain with the explicit host caller.
    process.stdout.write(JSON.stringify({phase:result.phase,completion:result.completion??(result.totals.conflict||result.totals.mapping_required||result.totals.not_attempted?'needs_resolution':result.totals.shadow_staged?'shadow_staged':result.phase==='dry_run'?'dry_run':'complete'),totals:result.totals,mapping_required:result.mapping_required??[]})+'\n');
    if(result.totals.conflict||result.totals.mapping_required||result.totals.not_attempted||result.mapping_required?.length)process.exitCode=2;
  }catch(error){process.stderr.write(JSON.stringify({error:error instanceof PersonalImportError?error.code:'import_failed'})+'\n');process.exitCode=1;}
}
if(process.argv[1]&&pathToFileURL(path.resolve(process.argv[1])).href===import.meta.url)await importCli(importPersonalNotes,process.argv.slice(2));
