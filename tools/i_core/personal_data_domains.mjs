// W2 personal domains. Explicit host registration only; no runtime activation or scheduling.
import { createHash } from 'node:crypto';

export const PERSONAL_HOOK_VERSION = 'personal-data-v1';
export const PERSONAL_DOMAINS = ['captures', 'plan_items', 'plan_weeks', 'plan_days'];
export const PLAN_STATUSES = ['想法', '待办', '进行中', '等待', '完成', '放弃', '被替代'];
export const BLOCK_KINDS = ['深块', '长块', '语音块', '零碎'];
export const CAPTURE_SOURCES = ['phone_quick', 'claude_web', 'dot', 'codex'];
export const WI_FIELD_MAP = Object.freeze({
  事项:'title', 层级:'level', 主线:'area', 上级:'parent_id', 前置:'depends_on',
  状态:'status', 替代为:'replaced_by', 块型:'block_kind', 块数:'blocks',
  定时:'scheduled_at', 计划日期:'planned_date', 截止:'due_date', 完成于:'completed_at',
  精力:'energy', 推迟:'defer_count', 来源:'source', 链接:'source_url', 备注:'note',
});
const field = (type, nullable=false, values) => ({type, required:true, ...(nullable?{nullable:true}:{}), ...(values?{enum:values}:{})});
const str = () => field('string');
export const PERSONAL_SCHEMAS = {
  captures: {version:1, fields:{
    text:str(), source:field('string',false,CAPTURE_SOURCES), recorded_at:str(),
    organizer:{type:'object'}, planner:{type:'object'},
  }, processors:{organizer:['organizer'],planner:['planner']}, immediateDeleteSources:['claude_web','i_remember']},
  plan_items: {version:1, fields:{
    title:str(), level:field('string',false,['主线','目的','行动']), area:str(),
    parent_id:field('string',true), depends_on:field('array'),
    status:field('string',false,PLAN_STATUSES), replaced_by:field('string',true),
    block_kind:field('string',true,BLOCK_KINDS), blocks:field('number',true),
    scheduled_at:field('string',true), planned_date:field('string',true), due_date:field('string',true),
    completed_at:field('string',true), energy:field('string',true,['高','低']),
    defer_count:field('integer'), source:field('string',false,['语音','手打','邮件','复盘','拆分']),
    source_url:field('string',true), note:str(), remind_at:field('string',true),
  }, groups:{effort:['block_kind','blocks']}, statusFields:['status'],
     referenceFields:['parent_id','depends_on','replaced_by']},
  plan_weeks: {version:1, fields:{
    week_key:str(), expected_capacity:field('object'), actual_capacity:field('object'),
    daily_capacities:field('array'), area_quotas:field('array'), debt:field('array'),
  }},
  plan_days: {version:1, fields:{
    date:str(), display_version:field('integer'), generated_at:str(), change_summary:str(),
    pending_decisions:field('array'), capacity:field('object'), queues:field('object'),
    noted:field('array'), lights_out_at:field('string',true),
  }, groups:{edition:['display_version','generated_at','change_summary','pending_decisions','capacity','queues','noted','lights_out_at']}},
};
export const QUEUES = ['fixed','deep','long','voice','extra','errands'];
const plain = v => v !== null && typeof v === 'object' && !Array.isArray(v) && Object.getPrototypeOf(v) === Object.prototype;
const exact = (v, keys, optional=[]) => plain(v) && keys.every(k=>Object.hasOwn(v,k)) && Object.keys(v).every(k=>keys.includes(k)||optional.includes(k));
const nonempty = v => typeof v === 'string' && v.trim().length>0;
const id = v => typeof v === 'string' && /^[a-zA-Z0-9][a-zA-Z0-9_.:-]{0,199}$/.test(v);
const uniqueIds = v => Array.isArray(v) && v.length<=5000 && v.every(id) && new Set(v).size===v.length;
const integer = v => Number.isSafeInteger(v) && v>=0;
const quantity = v => v===null || typeof v==='number' && Number.isFinite(v) && v>=0;
export function validBusinessDate(v) {
  return typeof v==='string' && /^\d{4}-\d{2}-\d{2}$/.test(v)
    && Number.isFinite(Date.parse(v+'T00:00:00Z')) && new Date(v+'T00:00:00Z').toISOString().slice(0,10)===v;
}
export function validBusinessTime(v) {
  if(typeof v!=='string' || !/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{3})?(?:Z|[+-]\d{2}:\d{2})$/.test(v) || !validBusinessDate(v.slice(0,10)))return false;
  const match=v.match(/T(\d{2}):(\d{2}):(\d{2})(?:\.\d{3})?(Z|[+-](\d{2}):(\d{2}))$/);
  return Number(match[1])<24 && Number(match[2])<60 && Number(match[3])<60 &&
    (match[4]==='Z'||Number(match[5])<=14&&Number(match[6])<60&&(Number(match[5])!==14||Number(match[6])===0)) && Number.isFinite(Date.parse(v));
}
export function validWeekKey(v) {
  if(typeof v!=='string'||!/^\d{4}-W\d{2}$/.test(v))return false;
  const year=Number(v.slice(0,4)),week=Number(v.slice(-2));
  if(week<1||week>53)return false;
  const jan4=new Date(v.slice(0,4)+'-01-04T00:00:00Z');
  jan4.setUTCDate(jan4.getUTCDate()-((jan4.getUTCDay()+6)%7)+(week-1)*7+3);
  return jan4.getUTCFullYear()===year;
}
function capacity(v) {return exact(v,['deep','long','voice'])&&Object.values(v).every(quantity);}
function disposition(v,processor) {
  return exact(v,processor==='planner'?['status','outputs','input_revision','note']:['status','outputs','input_revision'])
    && ['pending','done','skipped'].includes(v.status) && uniqueIds(v.outputs)
    && Number.isSafeInteger(v.input_revision)&&v.input_revision>=1
    && (processor!=='planner'||typeof v.note==='string')
    && (v.status==='done'||v.outputs.length===0);
}
function captureData(data) {
  return exact(data,['text','source','recorded_at'],['organizer','planner']) && nonempty(data.text) && data.text.length<=16000
    && CAPTURE_SOURCES.includes(data.source) && validBusinessTime(data.recorded_at)
    && ['organizer','planner'].every(p=>!Object.hasOwn(data,p)||disposition(data[p],p));
}
function itemData(data) {
  if(!exact(data,Object.keys(PERSONAL_SCHEMAS.plan_items.fields)))return false;
  return nonempty(data.title)&&nonempty(data.area)&&['主线','目的','行动'].includes(data.level)
    && PLAN_STATUSES.includes(data.status)&&[data.parent_id,data.replaced_by].every(v=>v===null||id(v))
    && uniqueIds(data.depends_on)&&(data.block_kind===null||BLOCK_KINDS.includes(data.block_kind))
    && (data.blocks===null||typeof data.blocks==='number'&&Number.isFinite(data.blocks)&&data.blocks>0)
    && [data.scheduled_at,data.completed_at,data.remind_at].every(v=>v===null||validBusinessTime(v))
    && [data.planned_date,data.due_date].every(v=>v===null||validBusinessDate(v))
    && (data.status==='完成')===(data.completed_at!==null)
    && (data.status==='被替代')===(data.replaced_by!==null)
    && (data.energy===null||['高','低'].includes(data.energy))&&integer(data.defer_count)
    && ['语音','手打','邮件','复盘','拆分'].includes(data.source)
    && (data.source_url===null||nonempty(data.source_url))&&typeof data.note==='string';
}
function weekData(data) {
  if(!exact(data,Object.keys(PERSONAL_SCHEMAS.plan_weeks.fields))||!validWeekKey(data.week_key)
    ||!capacity(data.expected_capacity)||!capacity(data.actual_capacity))return false;
  if(!Array.isArray(data.daily_capacities)||data.daily_capacities.length>7)return false;
  const dates=new Set();
  for(const row of data.daily_capacities){
    if(!exact(row,['date','expected','actual'])||!validBusinessDate(row.date)||dates.has(row.date)||!capacity(row.expected)||!capacity(row.actual))return false;
    dates.add(row.date);
    const date=new Date(row.date+'T00:00:00Z');date.setUTCDate(date.getUTCDate()+3-((date.getUTCDay()+6)%7));
    const first=new Date(date.getUTCFullYear()+'-01-04T00:00:00Z');first.setUTCDate(first.getUTCDate()+3-((first.getUTCDay()+6)%7));
    if(date.getUTCFullYear()+'-W'+String(1+Math.round((date-first)/604800000)).padStart(2,'0')!==data.week_key)return false;
  }
  if(!Array.isArray(data.area_quotas)||!Array.isArray(data.debt)||data.area_quotas.length>500||data.debt.length>500)return false;
  const areas=new Set();
  for(const row of data.area_quotas){
    if(!exact(row,['area','block_kind','minimum','target','maximum','completed','remaining_scheduled','status'])
      ||!nonempty(row.area)||!BLOCK_KINDS.slice(0,3).includes(row.block_kind)
      ||!['minimum','target','maximum','completed','remaining_scheduled'].every(k=>quantity(row[k]))
      ||!(row.status===null||['正常','落后','下限有风险'].includes(row.status)))return false;
    const key=JSON.stringify([row.area,row.block_kind]);if(areas.has(key))return false;areas.add(key);
    if(row.minimum!==null&&row.target!==null&&row.minimum>row.target||row.target!==null&&row.maximum!==null&&row.target>row.maximum)return false;
  }
  return data.debt.every(row=>exact(row,['area','block_kind','from_week','amount','rolled_weeks'])&&nonempty(row.area)
    && BLOCK_KINDS.slice(0,3).includes(row.block_kind)&&validWeekKey(row.from_week)&&row.from_week<data.week_key
    && quantity(row.amount)&&[0,1].includes(row.rolled_weeks));
}
function dayData(data) {
  if(!exact(data,Object.keys(PERSONAL_SCHEMAS.plan_days.fields))||!validBusinessDate(data.date)
    ||!Number.isSafeInteger(data.display_version)||data.display_version<1||!validBusinessTime(data.generated_at)
    ||typeof data.change_summary!=='string'||!capacity(data.capacity)
    ||!(data.lights_out_at===null||validBusinessTime(data.lights_out_at))
    ||!exact(data.queues,QUEUES)||!QUEUES.every(k=>uniqueIds(data.queues[k])))return false;
  const queued=QUEUES.flatMap(k=>data.queues[k]);if(new Set(queued).size!==queued.length)return false;
  return Array.isArray(data.pending_decisions)&&data.pending_decisions.length<=500&&data.pending_decisions.every(row=>
    exact(row,['item_id','reason','suggestion'])&&(row.item_id===null||id(row.item_id))&&nonempty(row.reason)&&typeof row.suggestion==='string')
    && Array.isArray(data.noted)&&data.noted.length<=500&&data.noted.every(row=>exact(row,['capture_id','text'])&&(row.capture_id===null||id(row.capture_id))&&nonempty(row.text));
}
function referencesValid(record,lookupRecord) {
  const root=record.id, domain=record.domain;
  const get=(targetDomain,targetId)=>targetDomain===domain&&targetId===root?record:lookupRecord?.(targetDomain,targetId);
  if(domain==='plan_items') {
    for(const relation of ['parent_id','depends_on','replaced_by']) {
      const visiting=new Set(),visited=new Set();
      function visit(nodeId){
        if(visiting.has(nodeId)||visited.size>5000)return false;
        if(visited.has(nodeId))return true;
        const node=get(domain,nodeId);if(!node||node.deleted_at||!itemData(node.data))return false;
        visiting.add(nodeId);
        const raw=node.data[relation], refs=Array.isArray(raw)?raw:raw===null?[]:[raw];
        for(const ref of refs)if(ref===nodeId||!visit(ref))return false;
        visiting.delete(nodeId);visited.add(nodeId);return true;
      }
      if(!visit(root))return false;
    }
  }
  if(domain==='plan_days') {
    const ids=[...QUEUES.flatMap(k=>record.data.queues[k]),...record.data.pending_decisions.map(v=>v.item_id).filter(Boolean)];
    for(const ref of ids){const item=get('plan_items',ref);if(!item||item.deleted_at)return false;}
    // A capture reference is a provenance link, not a grant to read capture text.
    for(const row of record.data.noted)if(row.capture_id){const capture=get('captures',row.capture_id);if(!capture||capture.deleted_at)return false;}
  }
  return true;
}
export function validatePersonalRecord(domain,record,{lookupRecord}={}) {
  if(!PERSONAL_DOMAINS.includes(domain)||!plain(record)||!id(record.id))return false;
  if(record.deleted_at)return !Object.hasOwn(record,'data')||record.body_state==='recoverable';
  const valid=domain==='captures'?captureData(record.data):domain==='plan_items'?itemData(record.data):domain==='plan_weeks'?weekData(record.data):dayData(record.data);
  return valid&&referencesValid({...record,domain},lookupRecord);
}
export function effectiveDisposition(record,processor) {
  if(!['organizer','planner'].includes(processor)||record.deleted_at)return null;
  const revision=record.field_meta?.text?.rev??record.revision;
  if(processor==='planner'&&record.provenance?.source==='i_remember')return {status:'skipped',outputs:[],input_revision:revision,note:'legacy_i_remember'};
  const stored=record.data?.[processor];
  if(stored?.input_revision===revision)return structuredClone(stored);
  return {status:'pending',outputs:[],input_revision:revision,...(processor==='planner'?{note:''}:{})};
}
export function normalizedPlanTitle(title) {return title.normalize('NFKC').trim().replace(/\s+/gu,' ').toLocaleLowerCase('en-US');}
export function planDedupHook({data,candidates}) {
  if(!data.due_date&&!data.scheduled_at)return null;
  return candidates.find(r=>normalizedPlanTitle(r.data.title)===normalizedPlanTitle(data.title)
    && (data.due_date!==null&&data.due_date===r.data.due_date||data.scheduled_at!==null&&r.data.scheduled_at!==null
      && Date.parse(data.scheduled_at)===Date.parse(r.data.scheduled_at)))?.id??null;
}
export function personalDedupHooks(){return {plan_items:planDedupHook};}

/** Trusted host policy: never inferred from request.actor, source text or a role name in JSON. */
export function createPersonalDataHooks({captureSourcesByPrincipal={},plannerPrincipalIds=[],processorPrincipals={},resolveDerivedReferences=null,
  webPrincipalIds=[],verifyWebAuthorization=null}={}) {
  const hooks={};
  for(const domain of PERSONAL_DOMAINS)hooks[domain]={
    version:PERSONAL_HOOK_VERSION,
    usesActorResolution:({principal,request})=>domain==='captures'&&webPrincipalIds.includes(principal.principal_id)
      &&['user_via_agent','agent_inferred'].includes(request.actor)&&['create','patch','delete'].includes(request.kind),
    resolveActor(ctx) {
      if(ctx.request.actor==='agent_inferred')return 'agent_inferred';
      return typeof verifyWebAuthorization==='function'&&verifyWebAuthorization({...ctx,authorizationRef:ctx.request.authorization_ref})===true
        ?'user_via_agent':'agent_inferred';
    },
    allowInferredDelete:domain==='captures'&&webPrincipalIds.length>0,
    authorizeOperation(ctx) {
      const {principal:p,request:r,current,operationOrigin}=ctx;
      const web=domain==='captures'&&webPrincipalIds.includes(p.principal_id);
      if(ctx.phase==='lookup') {
        const op=ctx.operation;
        if(op.kind==='legacy_adopt')return op.actor==='import';
        if(domain==='captures') {
          if(op.kind==='ack_capture')return processorPrincipals[p.principal_id]===op.processor && op.fields.every(f=>f===op.processor);
          if(!(web?['user_via_agent','agent_inferred']:['user_direct','user_via_agent']).includes(op.actor)||!(captureSourcesByPrincipal[p.principal_id]?.length))return false;
          if(op.kind==='create')return captureSourcesByPrincipal[p.principal_id].some(source=>ctx.matchesOperationValue('source',source));
          return ['delete','restore','purge'].includes(op.kind)||op.kind==='patch'&&op.fields.every(f=>f==='text');
        }
        if(op.kind==='status')return domain==='plan_items'&&op.actor==='user_direct'&&op.fields.every(f=>f==='status')
          && ['完成','放弃'].some(value=>ctx.matchesOperationValue('status',value));
        return plannerPrincipalIds.includes(p.principal_id);
      }
      if(operationOrigin==='local_adoption')return r.actor==='import';
      if(domain==='captures'){
        if(r.kind==='ack_capture')return processorPrincipals[p.principal_id]===r.processor;
        if(!(captureSourcesByPrincipal[p.principal_id]?.length))return false;
        if(!(web?['create','patch','delete']:['create','patch','delete','restore','purge']).includes(r.kind)
          ||!(web?['user_via_agent','agent_inferred']:['user_direct','user_via_agent']).includes(r.actor))return false;
        if(r.kind==='create')return (captureSourcesByPrincipal[p.principal_id]??[]).includes(r.data.source)
          && r.provenance.source===r.data.source&&!('organizer'in r.data)&&!('planner'in r.data);
        if(ctx.phase!=='preflight'&&(!current||current.origin?.principal_id!==p.principal_id&&current.origin?.device_id!==p.device_id))return false;
        // A user edit after creation protects the capture from Web deletion.
        // Processor acknowledgements do not constitute a user text edit.
        if(web&&ctx.phase!=='preflight'&&r.kind==='delete') {
          if(current.data?.source!=='claude_web')return false;
          if(Object.values(current.field_meta??{}).some(m=>m.rev>1&&['user_direct','user_via_agent'].includes(m.actor)))return false;
        }
        return r.kind!=='patch'||Object.keys(r.patch).every(k=>k==='text');
      }
      if(r.kind==='status')return domain==='plan_items'&&r.actor==='user_direct'
        && Object.keys(r.patch).length===1&&['完成','放弃'].includes(r.patch.status)&&(ctx.phase==='preflight'||current?.data?.replaced_by===null);
      return plannerPrincipalIds.includes(p.principal_id)&&['create','patch','merge','delete','restore','purge'].includes(r.kind);
    },
    deriveFields({request,current}) {
      if(domain!=='plan_items')return {};
      return {completed_at:request.patch.status==='完成'?(current.data.status==='完成'?current.data.completed_at:request.created_at):null};
    },
    validateTransition(ctx) {
      const {request:r,current,next,lookupRecord,operationOrigin}=ctx;
      if(next.deleted_at)return true; // Engine owns tombstone scrub and minimal cascade registration.
      if(!validatePersonalRecord(domain,next,{lookupRecord}))return false;
      if(domain==='captures') {
        if(next.provenance?.source==='i_remember'&&(!next.data.planner||next.data.planner.status!=='skipped'||next.data.planner.outputs.length!==0))return false;
        if(next.provenance?.source!==next.data.source && !(next.provenance?.source==='i_remember'&&next.data.source==='claude_web'))return false;
        if(r.kind==='ack_capture') {
          const d=next.data[r.processor],inputRevision=current.field_meta?.text?.rev??current.revision;
          if(d.input_revision!==inputRevision)return {valid:false,code:'stale_base'};
          if(!d.outputs.length)return true;
          if(typeof resolveDerivedReferences!=='function')return false;
          const refs=resolveDerivedReferences({processor:r.processor,outputs:structuredClone(d.outputs),principal:structuredClone(ctx.principal),captureId:current.id});
          if(!Array.isArray(refs)||refs.length!==d.outputs.length||refs.some((ref,i)=>!exact(ref,['domain','id'])||!id(ref.domain)||ref.id!==d.outputs[i]))return false;
          if(r.processor==='planner'&&refs.some(ref=>!['plan_items','plan_weeks','plan_days'].includes(ref.domain)))return false;
          return {valid:true,derived_refs:refs};
        }
      }
      if(domain==='plan_days'&&current&&!current.deleted_at&&JSON.stringify(current.data)!==JSON.stringify(next.data)
        && next.data.display_version!==current.data.display_version+1)return false;
      return true;
    },
  };
  return hooks;
}
export function registerPersonalDataDomains(store,{mode='off'}={}) {
  for(const domain of PERSONAL_DOMAINS)store.registerDomain(domain,structuredClone(PERSONAL_SCHEMAS[domain]),{mode,requiredHooksVersion:PERSONAL_HOOK_VERSION,...(domain==='plan_items'?{serverDerivedFields:['completed_at']}:{})});
}
/** Deterministic identity for source records lacking an ID; never derived from their text. */
export function stableImportId(sourceIdentity,domain,key) {
  if(!nonempty(sourceIdentity)||!PERSONAL_DOMAINS.includes(domain)||!nonempty(key))throw new Error('invalid_import_identity');
  const bytes=createHash('sha1').update(Buffer.from('d777a124551c48b7a67dcc2ed6839d78','hex')).update(JSON.stringify([sourceIdentity,domain,key])).digest().subarray(0,16);
  bytes[6]=(bytes[6]&15)|80;bytes[8]=(bytes[8]&63)|128;
  const hex=bytes.toString('hex');return [hex.slice(0,8),hex.slice(8,12),hex.slice(12,16),hex.slice(16,20),hex.slice(20)].join('-');
}
