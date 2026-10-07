// WI source adapter. Does not schedule, modify source files, or initialize a Core.
import fs from 'node:fs';
import path from 'node:path';
import { pathToFileURL } from 'node:url';
import { WI_FIELD_MAP, validatePersonalRecord, validBusinessTime, stableImportId } from './personal_data_domains.mjs';
import { safeSourceFile, mappedOrigin, applyImportRecords, importCli, PersonalImportError } from './import_personal_notes.mjs';

const fail=code=>{throw new PersonalImportError(code);};
const plain=v=>v!==null&&typeof v==='object'&&!Array.isArray(v);
const exact=(v,keys)=>plain(v)&&Object.keys(v).length===keys.length&&keys.every(k=>Object.hasOwn(v,k));
const uuid=v=>typeof v==='string'&&/^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(v);
export function readLocalPlan(sourcePath) {
  const file=safeSourceFile(sourcePath,{maxBytes:16777216});
  const plan=JSON.parse(fs.readFileSync(file,'utf8').replace(/^\uFEFF/,''));
  if(!exact(plan,['schema_version','revision','updated_at','items','processed_receipts'])||plan.schema_version!==1
    ||!Number.isSafeInteger(plan.revision)||plan.revision<0||!validBusinessTime(plan.updated_at)
    ||!Array.isArray(plan.items)||plan.items.length>5000||!Array.isArray(plan.processed_receipts))fail('invalid_wi_plan');
  const records=[],ids=new Set();
  for(const item of plan.items){
    if(!exact(item,['id',...Object.keys(WI_FIELD_MAP)])||!uuid(item.id)||ids.has(item.id))fail('invalid_wi_item');
    ids.add(item.id);
    const data=Object.fromEntries(Object.entries(WI_FIELD_MAP).map(([from,to])=>[to,item[from]]));
    data.remind_at=null;
    records.push({domain:'plan_items',id:item.id,revision:1,deleted_at:null,data});
  }
  const byId=new Map(records.map(r=>[r.id,r]));
  for(const record of records)if(!validatePersonalRecord('plan_items',record,{lookupRecord:(domain,id)=>domain==='plan_items'?byId.get(id):null}))fail('invalid_wi_item');
  const receipts=new Set();
  for(const receipt of plan.processed_receipts){
    if(!exact(receipt,['name','sha256'])||typeof receipt.name!=='string'||!/^[^<>:"/\\|?*\x00-\x1f]+\.md$/i.test(receipt.name)
      ||!/[0-9a-f]{64}/.test(receipt.sha256)||receipt.sha256.length!==64||receipts.has(receipt.name))fail('invalid_wi_receipt');
    receipts.add(receipt.name);
  }
  return {plan,records};
}
function ordered(records) {
  const left=new Map(records.map(r=>[r.id,r])),result=[],done=new Set();
  while(left.size) {
    const ready=[...left.values()].filter(r=>[r.data.parent_id,r.data.replaced_by,...r.data.depends_on].filter(Boolean).every(id=>done.has(id)));
    if(!ready.length)return null; // Separate relation DAGs may still have a combined dependency cycle.
    for(const record of ready){result.push(record);done.add(record.id);left.delete(record.id);}
  }
  return result;
}
/** Optional strict structured projection supplied explicitly by a reviewed mapper, never inferred from Markdown. */
export function readPlanProjection(sourcePath,domain,lookupRecord) {
  if(!['plan_weeks','plan_days'].includes(domain))fail('invalid_projection_domain');
  const file=safeSourceFile(sourcePath,{maxBytes:16777216});
  const parsed=JSON.parse(fs.readFileSync(file,'utf8').replace(/^\uFEFF/,''));
  if(!Array.isArray(parsed)||parsed.length>500)fail('invalid_plan_projection');
  for(const data of parsed)if(!validatePersonalRecord(domain,{domain,id:'projection-check',data},{lookupRecord}))fail('invalid_plan_projection');
  return parsed;
}
export function importLocalPlan({sourcePath,originMapping,weekSourcePath,daySourcePath,...options}={}) {
  const {plan,records}=readLocalPlan(sourcePath);
  const order=ordered(records);
  if(!order)return {phase:options.dryRun===false?'apply':'dry_run',totals:{mapping_required:records.length,conflict:0,accepted:0,duplicate:0,planned:0,validated:0},mappings:[],
    mapping_required:[{kind:'plan_items',reason:'combined_reference_order_requires_atomic_mapping'}]};
  const entries=order.map(({domain:ignoredDomain,...record})=>({domain:'plan_items',deferDryRun:[record.data.parent_id,record.data.replaced_by,...record.data.depends_on].some(Boolean),record:{
    ...record,origin:mappedOrigin(originMapping,record.id),
    provenance:{source:'wi_local_plan',source_refs:[],import_batch_id:options.batchId},
  }}));
  const mappingRequired=[];
  const byId=new Map(records.map(r=>[r.id,r]));
  const lookup=(domain,id)=>domain==='plan_items'?byId.get(id):null;
  for(const [domain,file] of [['plan_weeks',weekSourcePath],['plan_days',daySourcePath]]) {
    if(!file){mappingRequired.push({kind:domain,reason:'explicit_structured_mapping_required'});continue;}
    if(path.extname(file).toLowerCase()!=='.json'){
      safeSourceFile(file);mappingRequired.push({kind:domain,reason:'markdown_mapping_required'});continue;
    }
    const projected=readPlanProjection(file,domain,lookup);
    const keys=new Set();
    for(const data of projected){
      const key=domain==='plan_weeks'?data.week_key:data.date;
      if(keys.has(key))fail('duplicate_projection_key');keys.add(key);
      const recordId=stableImportId(options.sourceId,domain,key);
      entries.push({domain,deferDryRun:domain==='plan_days',record:{id:recordId,revision:1,deleted_at:null,data,
        origin:mappedOrigin(originMapping,recordId),provenance:{source:'wi_local_plan',source_refs:[],import_batch_id:options.batchId}}});
    }
  }
  const result=applyImportRecords(entries,{...options,sourceKind:'wi_local_plan'});
  // WI revision is a source snapshot version, not a per-item Core revision. Receipt contents remain local source state.
  return {...result,completion:mappingRequired.length?(result.totals.accepted?'partial':'mapping_required'):(result.totals.conflict||result.totals.mapping_required||result.totals.not_attempted?'needs_resolution':result.totals.shadow_staged?'shadow_staged':options.dryRun===false?'complete':'dry_run'),source_plan_revision:plan.revision,source_processed_receipt_count:plan.processed_receipts.length,mapping_required:mappingRequired};
}
if(process.argv[1]&&pathToFileURL(path.resolve(process.argv[1])).href===import.meta.url)await importCli(importLocalPlan,process.argv.slice(2));
