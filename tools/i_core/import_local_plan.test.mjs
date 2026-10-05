import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import os from 'node:os';
import { spawnSync } from 'node:child_process';
import { pathToFileURL } from 'node:url';
import { randomUUID } from 'node:crypto';
import { DatabaseSync } from 'node:sqlite';
import { DomainStore } from './domain_store.mjs';
import { DOMAIN_SCHEMA_SQL } from './domain_schema.mjs';
import { createPersonalDataHooks, registerPersonalDataDomains, stableImportId } from './personal_data_domains.mjs';
import { importLocalPlan, readLocalPlan } from './import_local_plan.mjs';
const iso='2026-10-05T00:00:00.000Z';
const item=(overrides={})=>({id:randomUUID(),事项:'合成行动',层级:'行动',主线:'生活',上级:null,前置:[],状态:'想法',替代为:null,
  块型:null,块数:null,定时:null,计划日期:null,截止:null,完成于:null,精力:null,推迟:0,来源:'手打',链接:null,备注:'',...overrides});
function fixture(t){
  const root=fs.mkdtempSync(path.join(os.tmpdir(),'w2-plan-synthetic-')),source=path.join(root,'plan.json');
  const plan={schema_version:1,revision:42,updated_at:iso,items:[item()],processed_receipts:[{name:'synthetic.md',sha256:'a'.repeat(64)}]};
  const save=()=>fs.writeFileSync(source,JSON.stringify(plan));save();
  const db=new DatabaseSync(':memory:');db.exec("CREATE TABLE core_metadata(key TEXT PRIMARY KEY,value TEXT);INSERT INTO core_metadata VALUES('schema_version','6'),('node_id','core-plan-test'),('cursor_secret','synthetic-only');");db.exec(DOMAIN_SCHEMA_SQL);
  const store=new DomainStore(db,{nodeId:'core-plan-test',cursorSecret:'synthetic-only',clock:()=>Date.parse(iso),domainHooks:createPersonalDataHooks({plannerPrincipalIds:['planner']}),
    verifyLegacyAdoption:({authorizationRef,record,adoption})=>authorizationRef==='wi-owner-proof'&&record.origin.principal_id==='owner'&&adoption.sourceKind==='wi_local_plan'});
  registerPersonalDataDomains(store,{mode:'authoritative'});
  const issued=store.configurePrincipal({principal_id:'wi-import',device_id:'import-device',installation_id:'import-install',
    scopes:['plan_items','plan_weeks','plan_days'].flatMap(d=>[d+':adopt',d+':read']),actors:['import'],import_sources:['wi_local_plan']});
  const options={sourcePath:source,sourceId:'wi-copy',batchId:'batch-1',targetInstanceId:store.nodeId,target:store,principal:store.authenticate(issued.token),
    authorizationRef:'wi-owner-proof',originMapping:()=>({principal_id:'owner',device_id:'owner-device'})};
  t.after(()=>{db.close();assert.equal(path.dirname(root),path.resolve(os.tmpdir()));fs.rmSync(root,{recursive:true,force:true});});
  return {root,source,plan,save,db,store,options};
}
test('WI default dry-run preserves source bytes, UUID and all exact field values',t=>{
  const f=fixture(t),before=fs.readFileSync(f.source),result=importLocalPlan(f.options);
  assert.equal(result.phase,'dry_run');assert.equal(result.totals.validated,1);
  assert.equal(result.source_plan_revision,42);assert.equal(result.source_processed_receipt_count,1);
  assert.equal(result.mappings[0].target_id,f.plan.items[0].id);assert.equal(result.mappings[0].target_revision,1);
  assert.equal(f.db.prepare('SELECT COUNT(*) n FROM domain_records').get().n,0);assert.deepEqual(fs.readFileSync(f.source),before);
  assert.deepEqual(result.mapping_required.map(v=>v.kind),['plan_weeks','plan_days']);
});
test('WI actual import is stable, rerun no-op and changed same source identity conflicts',t=>{
  const f=fixture(t);assert.equal(importLocalPlan({...f.options,dryRun:false}).totals.accepted,1);
  const record=f.store.load('production','plan_items',f.plan.items[0].id);assert.equal(record.revision,1);assert.equal(record.data.title,'合成行动');assert.equal(record.data.remind_at,null);
  const count=f.db.prepare('SELECT COUNT(*) n FROM domain_changes').get().n;
  assert.equal(importLocalPlan({...f.options,dryRun:false}).totals.duplicate,1);
  assert.equal(f.db.prepare('SELECT COUNT(*) n FROM domain_changes').get().n,count);
  f.plan.items[0].事项='改过但未获覆盖许可';f.plan.revision++;f.save();
  assert.equal(importLocalPlan({...f.options,dryRun:false}).totals.conflict,1);
  assert.equal(f.store.load('production','plan_items',record.id).data.title,'合成行动');
});
test('dependencies import in explicit safe order; WI global revision never becomes item revision',t=>{
  const f=fixture(t),parent=item({事项:'合成目的',层级:'目的'}),child=item({上级:parent.id,前置:[parent.id]});f.plan.items=[child,parent];f.save();
  const dry=importLocalPlan(f.options);assert.equal(dry.mappings[0].target_id,parent.id);assert.equal(dry.totals.planned,1);
  const applied=importLocalPlan({...f.options,dryRun:false});assert.equal(applied.totals.accepted,2,JSON.stringify(applied));
  const record=f.store.load('production','plan_items',child.id);assert.equal(record.revision,1);assert.deepEqual(record.data.depends_on,[parent.id]);
});
test('malformed dates, status conditions, unknown fields and relation cycles fail before import',t=>{
  const f=fixture(t),original=structuredClone(f.plan.items);
  for(const mutation of [
    i=>i.截止='2026-02-29',i=>i.完成于=iso,i=>i.状态='done',i=>i.块数=-1,i=>i.偷添='x',i=>i.前置=[i.id],
  ]){
    f.plan.items=structuredClone(original);mutation(f.plan.items[0]);f.save();assert.throws(()=>readLocalPlan(f.source),/invalid_wi_item/);
  }
  assert.equal(f.db.prepare('SELECT COUNT(*) n FROM domain_records').get().n,0);
});
test('joint dependency cycle needs explicit atomic mapping even when each WI relation is acyclic',t=>{
  const f=fixture(t),a=item(),b=item();a.上级=b.id;b.前置=[a.id];f.plan.items=[a,b];f.save();
  const result=importLocalPlan({...f.options,dryRun:false});assert.equal(result.totals.mapping_required,2);
  assert.equal(result.mapping_required[0].reason,'combined_reference_order_requires_atomic_mapping');
  assert.equal(f.db.prepare('SELECT COUNT(*) n FROM domain_records').get().n,0);
});
test('Markdown projections explicitly require mapping and unknown capacity is never invented',t=>{
  const f=fixture(t),week=path.join(f.root,'week.md'),day=path.join(f.root,'today.md');
  fs.writeFileSync(week,'# 本周账\n预计容量：未知。');fs.writeFileSync(day,'# 今日单\n待补充。');
  const result=importLocalPlan({...f.options,weekSourcePath:week,daySourcePath:day});
  assert.equal(result.mapping_required.length,2);assert.ok(result.mapping_required.every(v=>v.reason==='markdown_mapping_required'));
  assert.equal(f.db.prepare("SELECT COUNT(*) n FROM domain_records WHERE domain IN ('plan_weeks','plan_days')").get().n,0);
});
test('explicit strict week/day JSON projection preserves nulls, ordered IDs and stable date identity',t=>{
  const f=fixture(t),wpath=path.join(f.root,'week.json'),dpath=path.join(f.root,'day.json'),capacity={deep:null,long:null,voice:null};
  fs.writeFileSync(wpath,JSON.stringify([{week_key:'2026-W41',expected_capacity:capacity,actual_capacity:capacity,daily_capacities:[],area_quotas:[],debt:[]}]));
  fs.writeFileSync(dpath,JSON.stringify([{date:'2026-10-05',display_version:3,generated_at:iso,change_summary:'经确认的合成映射',pending_decisions:[],capacity,
    queues:{fixed:[],deep:[f.plan.items[0].id],long:[],voice:[],extra:[],errands:[]},noted:[],lights_out_at:null}]));
  const args={...f.options,weekSourcePath:wpath,daySourcePath:dpath,dryRun:false};
  const result=importLocalPlan(args);assert.equal(result.totals.accepted,3,JSON.stringify(result));
  assert.equal(result.mapping_required.length,0);
  const dayId=stableImportId('wi-copy','plan_days','2026-10-05'),record=f.store.load('production','plan_days',dayId);
  assert.equal(record.data.display_version,3);assert.equal(record.revision,1);assert.equal(record.data.capacity.deep,null);
  assert.deepEqual(record.data.queues.deep,[f.plan.items[0].id]);
  assert.equal(importLocalPlan(args).totals.duplicate,3);
});
test('source absence is not deletion and origin mapping is required for every record',t=>{
  const f=fixture(t);importLocalPlan({...f.options,dryRun:false});const old=f.plan.items[0].id;
  f.plan.items=[];f.plan.revision++;f.save();assert.equal(importLocalPlan({...f.options,dryRun:false}).totals.accepted,0);
  assert.equal(f.store.load('production','plan_items',old).deleted_at,null);
  f.plan.items=[item()];f.save();assert.equal(importLocalPlan({...f.options,originMapping:{},dryRun:false}).totals.mapping_required,1);
});

test('CLI reports top-level projection mapping gaps with exit 2 even when item mappings are complete',t=>{
  const f=fixture(t),origin=path.join(f.root,'origin.json');
  fs.writeFileSync(origin,JSON.stringify({[f.plan.items[0].id]:{principal_id:'owner',device_id:'owner-device'}}));
  const args=[path.join(import.meta.dirname,'import_local_plan.mjs'),'--source',f.source,'--source-id','wi-copy','--batch-id','batch-1',
    '--target-instance','core-plan-test','--origin-map',origin];
  const dry=spawnSync(process.execPath,args,{encoding:'utf8'});
  assert.equal(dry.status,2);const report=JSON.parse(dry.stdout);
  assert.equal(report.phase,'dry_run');assert.equal(report.completion,'mapping_required');
  assert.equal(report.totals.mapping_required,0);assert.equal(report.mapping_required.length,2);
  const adapter=path.join(f.root,'synthetic-adapter.mjs');
  const moduleURL=name=>JSON.stringify(pathToFileURL(path.join(import.meta.dirname,name)).href);
  fs.writeFileSync(adapter,[
    "import {DatabaseSync} from 'node:sqlite';",
    'import {DomainStore} from '+moduleURL('domain_store.mjs')+';',
    'import {DOMAIN_SCHEMA_SQL} from '+moduleURL('domain_schema.mjs')+';',
    'import {createPersonalDataHooks,registerPersonalDataDomains} from '+moduleURL('personal_data_domains.mjs')+';',
    'export function createImportContext(){',
    "const db=new DatabaseSync(':memory:');",
    `db.exec("CREATE TABLE core_metadata(key TEXT PRIMARY KEY,value TEXT);INSERT INTO core_metadata VALUES('schema_version','6'),('node_id','core-plan-test'),('cursor_secret','synthetic-only');");`,
    'db.exec(DOMAIN_SCHEMA_SQL);',
    "const target=new DomainStore(db,{nodeId:'core-plan-test',cursorSecret:'synthetic-only',domainHooks:createPersonalDataHooks(),verifyLegacyAdoption:({authorizationRef})=>authorizationRef==='synthetic-owner-proof'});",
    "registerPersonalDataDomains(target,{mode:'authoritative'});",
    "const issued=target.configurePrincipal({principal_id:'cli-import',device_id:'cli-device',installation_id:'cli-install',scopes:['plan_items:adopt','plan_items:read'],actors:['import'],import_sources:['wi_local_plan']});",
    "return {target,principal:target.authenticate(issued.token),authorizationRef:'synthetic-owner-proof'};}",
  ].join('\n'));
  const apply=spawnSync(process.execPath,[...args,'--apply','--adapter',adapter],{encoding:'utf8'});
  assert.equal(apply.status,2,apply.stderr);const applied=JSON.parse(apply.stdout);
  assert.equal(applied.phase,'apply');assert.equal(applied.completion,'partial');assert.equal(applied.totals.accepted,1);
  assert.equal(applied.totals.mapping_required,0);assert.equal(applied.mapping_required.length,2);
  assert.ok(!apply.stdout.includes(f.plan.items[0].id));assert.ok(!apply.stdout.includes('合成行动'));
});
