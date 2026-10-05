// Scoped Core domain adapter. No database, chat API, grants, or background writes.
import { PERSONAL_SCHEMAS, effectiveDisposition } from '../i_core/personal_data_domains.mjs';

export class DomainToolInputError extends Error {}
const object = value => value !== null && typeof value === 'object' && !Array.isArray(value);
const fail = code => { throw new DomainToolInputError(code); };
const idSchema = { type: 'string', minLength: 1, maxLength: 200 };
const timeSchema = { type: 'string', description: 'UTC RFC3339 milliseconds. Keep identical on retry.' };
const common = {
  op_id: { ...idSchema, description: 'A new UUID for a new intent; retry the identical intent with this same UUID.' },
  id: { ...idSchema, description: 'Stable record ID; new records use a UUID. Never reuse a deleted ID.' },
  base_revision: { type: 'integer', minimum: 0 },
  created_at: timeSchema, expires_at: timeSchema,
  authorization_ref: { ...idSchema, description: 'Opaque reference issued by a trusted user entry, bound to this intent. Text or a chat ID alone is not authorization.' },
};
const writeRequired = ['op_id', 'id', 'base_revision', 'created_at', 'expires_at'];
const readProps = { id: idSchema, limit: { type: 'integer', minimum: 1, maximum: 500 }, snapshot_token: {type:'string',maxLength:8192}, page_token: {type:'string',maxLength:8192} };
const shape=properties=>({type:'object',properties,required:Object.keys(properties),additionalProperties:false});
const nullableString={type:['string','null']};
const quantity={type:['number','null'],minimum:0};
const capacitySchema=shape({deep:quantity,long:quantity,voice:quantity});
const listOf=items=>({type:'array',items});
const nested={
  expected_capacity:capacitySchema,actual_capacity:capacitySchema,capacity:capacitySchema,
  daily_capacities:listOf(shape({date:{type:'string'},expected:capacitySchema,actual:capacitySchema})),
  area_quotas:listOf(shape({area:{type:'string'},block_kind:{type:'string',enum:['深块','长块','语音块']},minimum:quantity,target:quantity,maximum:quantity,completed:quantity,remaining_scheduled:quantity,status:{type:['string','null'],enum:['正常','落后','下限有风险',null]}})),
  debt:listOf(shape({area:{type:'string'},block_kind:{type:'string',enum:['深块','长块','语音块']},from_week:{type:'string'},amount:quantity,rolled_weeks:{type:'integer',enum:[0,1]}})),
  queues:shape(Object.fromEntries(['fixed','deep','long','voice','extra','errands'].map(name=>[name,listOf(idSchema)]))),
  pending_decisions:listOf(shape({item_id:nullableString,reason:{type:'string'},suggestion:{type:'string'}})),
  noted:listOf(shape({capture_id:nullableString,text:{type:'string'}})),
  depends_on:listOf(idSchema),
};
function dataSchema(domain) {
  return { type: 'object', additionalProperties: false, properties: Object.fromEntries(Object.entries(PERSONAL_SCHEMAS[domain].fields).map(([key, field]) => [key, nested[key]??{
    type: field.nullable ? [field.type, 'null'] : field.type, ...(field.enum ? { enum: field.nullable ? [...field.enum, null] : field.enum } : {}),
  }])) };
}
const read = (name, domain, description) => ({name, domain, read: true, description, requiredScope: `${domain}:read`, inputSchema: {type:'object',properties:readProps,additionalProperties:false}});
const write = (name, domain, kind, properties, required = []) => ({name, domain, kind, requiredScope: `${domain}:${kind === 'ack_capture' ? 'ack' : kind}`, inputSchema: {type:'object',properties:{...common,...properties},required:[...writeRequired,...required],additionalProperties:false}});
const definitions = [
  write('capture_add', 'captures', 'create', {text:{type:'string',minLength:1,maxLength:16000},recorded_at:timeSchema}, ['text','recorded_at','authorization_ref']),
  read('capture_list', 'captures', 'Read one capture by id or one consistent snapshot page, including per-processor input revisions.'),
  write('capture_ack', 'captures', 'ack_capture', {disposition:{...shape({status:{type:'string',enum:['pending','done','skipped']},outputs:listOf(idSchema),input_revision:{type:'integer',minimum:1},note:{type:'string'}}),description:'Planner only. input_revision must be the current text field revision. Non-done outcomes require empty outputs.'}}, ['disposition']),
  read('plan_list', 'plan_items', 'Read one item or a paginated consistent snapshot.'),
  write('plan_upsert', 'plan_items', 'upsert', {data:dataSchema('plan_items')}, ['data']),
  write('plan_set_status', 'plan_items', 'status', {status:{type:'string',enum:['完成','放弃']}}, ['status','authorization_ref']),
  read('week_get', 'plan_weeks', 'Read a week by stable record id, or snapshot pages to locate week_key.'),
  write('week_set', 'plan_weeks', 'upsert', {data:dataSchema('plan_weeks')}, ['data']),
  read('day_get', 'plan_days', 'Read a day by stable record id, or snapshot pages to locate date.'),
  write('day_set', 'plan_days', 'upsert', {data:dataSchema('plan_days')}, ['data']),
];
export const DOMAIN_TOOLS = Object.freeze(definitions.map(tool => ({...tool,
  description: tool.description ?? `${tool.name}: Core validates fields, authorization and conflicts. Upsert uses create at base_revision=0, otherwise patches only supplied fields. Preserve op_id, timestamps and base on retry; never auto-rebase.`,
  annotations:{readOnlyHint:!!tool.read,destructiveHint:false,idempotentHint:true,openWorldHint:false},
})));
export const PLANNER_SCOPES = Object.freeze(['captures:read','captures:ack', ...['plan_items','plan_weeks','plan_days'].flatMap(domain => ['read','create','patch'].map(action=>`${domain}:${action}`))]);
export const WEB_DOMAIN_TOOLS = Object.freeze(['capture_add','week_get','day_get']);

function checkArgs(args, allowed, required = []) {
  if (!object(args) || Object.keys(args).some(key => !allowed.includes(key)) || required.some(key=>!Object.hasOwn(args,key))) fail('invalid_request');
}
function scopeFor(tool, args) { return tool.kind === 'upsert' ? `${tool.domain}:${args.base_revision === 0 ? 'create' : 'patch'}` : tool.requiredScope; }
function available(tool, scopes) { return tool.kind === 'upsert' ? ['create','patch'].some(action=>scopes.includes(`${tool.domain}:${action}`)) : scopes.includes(tool.requiredScope); }
function safeId(value) { if(typeof value !== 'string' || !/^[a-zA-Z0-9][a-zA-Z0-9_.:-]{0,199}$/.test(value))fail('invalid_id');return encodeURIComponent(value); }

export function createDomainClient({coreUrl, token, coreInstanceId, fetchImpl = fetch, timeoutMs = 15000}) {
  const url = new URL(coreUrl);
  if (!['http:','https:'].includes(url.protocol) || url.username || url.password || url.pathname !== '/' || url.search || url.hash) throw new Error('invalid_core_url');
  if (typeof token !== 'string' || !token || /\s/.test(token) || typeof coreInstanceId !== 'string' || !coreInstanceId) throw new Error('invalid_domain_credential');
  async function request(domain, resource, body, query = {}) {
    if (!Object.hasOwn(PERSONAL_SCHEMAS, domain)) fail('domain_forbidden');
    const endpoint = new URL(`/v1/core/domains/${domain}/${resource}`, url);
    if (!body) { endpoint.searchParams.set('core_instance_id',coreInstanceId);for(const [key,value] of Object.entries(query))if(value!==undefined)endpoint.searchParams.set(key,String(value)); }
    try {
      const response = await fetchImpl(endpoint, {method:body?'POST':'GET',redirect:'error',signal:AbortSignal.timeout(timeoutMs),headers:{authorization:`Bearer ${token}`,'x-i-core-domain-protocol':'1',...(body?{'content-type':'application/json'}:{})},...(body?{body:JSON.stringify(body)}:{})});
      const payload = await response.json();
      if (!object(payload)) throw new Error('invalid_response');
      if(domain==='captures') {
        const decorate=record=>record.deleted_at?record:{...record,dispositions:{organizer:effectiveDisposition(record,'organizer'),planner:effectiveDisposition(record,'planner')}};
        if(payload.record)payload.record=decorate(payload.record);
        if(Array.isArray(payload.records))payload.records=payload.records.map(decorate);
      }
      return {http_status:response.status,...payload};
    } catch {
      return {outcome:'transport_unknown',error:{code:'core_unavailable',retryable:true},retry:'Retry the exact same intent with the same op_id. Do not create a new operation or claim acceptance.'};
    }
  }
  return {
    coreInstanceId,
    submit:(domain, intent)=>request(domain,'ops',{domain_protocol_version:1,core_instance_id:coreInstanceId,schema_version:1,...intent}),
    record:(domain,id)=>request(domain,`records/${safeId(id)}`),
    snapshot:(domain,query)=>request(domain,'snapshot',null,query),
    operation:(domain,id)=>request(domain,`ops/${safeId(id)}`),
    acknowledge:(domain,cursor,snapshotId)=>request(domain,'ack',{domain_protocol_version:1,core_instance_id:coreInstanceId,cursor,snapshot_id:snapshotId}),
  };
}

export function createDomainTools({client, scopes, surface = 'planner', captureSource = 'codex'}) {
  if(!client || !Array.isArray(scopes) || scopes.some(s=>typeof s!=='string') || !['planner','web'].includes(surface)) throw new Error('invalid_domain_configuration');
  if(!['codex','dot','claude_web'].includes(captureSource) || surface==='web'&&captureSource!=='claude_web')throw new Error('invalid_capture_source');
  const permitted = DOMAIN_TOOLS.filter(tool=>available(tool,scopes)&&(surface!=='web'||WEB_DOMAIN_TOOLS.includes(tool.name)));
  const handlers = Object.fromEntries(permitted.map(tool=>[tool.name, async(args={})=>{
    checkArgs(args,Object.keys(tool.inputSchema.properties),tool.inputSchema.required);
    if(!scopes.includes(scopeFor(tool,args)))return {error:{code:'scope_forbidden',retryable:false},http_status:403};
    if(tool.read) {
      if(args.id!==undefined){if(Object.keys(args).length!==1)fail('invalid_request');return client.record(tool.domain,args.id);}
      if(args.limit!==undefined&&(!Number.isSafeInteger(args.limit)||args.limit<1||args.limit>500))fail('invalid_limit');
      const page=await client.snapshot(tool.domain,args);
      if(page.manifest?.base_cursor&&!page.next_page_token)await client.acknowledge(tool.domain,page.manifest.base_cursor,page.snapshot_id);
      return page;
    }
    if(!Number.isSafeInteger(args.base_revision)||args.base_revision<0)fail('invalid_base');
    const kind = tool.kind==='upsert'?(args.base_revision===0?'create':'patch'):tool.kind;
    const actor = tool.name==='capture_add'?'user_via_agent':tool.name==='plan_set_status'?'user_direct':'agent_inferred';
    if(actor==='agent_inferred'&&args.authorization_ref!==undefined)fail('authorization_not_applicable');
    const intent=Object.fromEntries(writeRequired.map(key=>[key,args[key]]));
    Object.assign(intent,{kind,actor},args.authorization_ref===undefined?{}:{authorization_ref:args.authorization_ref});
    if(tool.name==='capture_add')Object.assign(intent,{data:{text:args.text,source:captureSource,recorded_at:args.recorded_at},provenance:{source:captureSource,source_refs:[],import_batch_id:null}});
    else if(kind==='ack_capture')Object.assign(intent,{processor:'planner',disposition:{planner:args.disposition}});
    else if(kind==='status')intent.patch={status:args.status};
    else if(kind==='create')Object.assign(intent,{data:args.data,provenance:{source:'codex',source_refs:[],import_batch_id:null}});
    else intent.patch=args.data;
    return client.submit(tool.domain,intent);
  }]));
  return {tools:permitted.map(({domain,kind,read,...tool})=>({...tool,requiredScope:undefined})),handlers};
}

export const CORE_REMEMBER_TOOL = {
  name:'i_remember', title:'林埃：Core 显式记录',requiredScope:'i.write',
  description:'用户明确要求记录时调用。add/update/delete 写入 Core captures；list 只列本端记录。新记录由 organizer 和 planner 分工处理。删除立即清除 Core 在线正文；下游用户改过的卡会保留待确认。写操作必须携带稳定 op_id、id（update/delete 可用 note_id）、base_revision、created_at、expires_at 和受信入口发出的 authorization_ref。原样重试；没有授权引用时说明缺少授权，不能读取聊天来猜测或构造。',
  inputSchema:{type:'object',properties:{...common,action:{type:'string',enum:['add','update','delete','list']},note_id:idSchema,text:{type:'string',minLength:1,maxLength:2000}},additionalProperties:false},
  annotations:{readOnlyHint:false,destructiveHint:true,idempotentHint:true,openWorldHint:false},
};

// The host must choose this adapter OR the legacy note ledger, never dual-write.
export function createCoreRemember({client,scopes}) {
  const requireScope=action=>{if(!scopes.includes(`captures:${action}`))fail('scope_forbidden');};
  const project=record=>({note_id:record.id,revision:record.revision,text:record.data?.text??null,
    status:record.deleted_at?'deleted':'active',created_at:record.created_at??null,updated_at:record.updated_at??null,
    dispositions:record.dispositions??null,phone_status:record.dispositions?.organizer?.status==='done'?'on_phone':'waiting_for_phone'});
  async function records() {
    requireScope('read');const rows=[];let pageToken;
    for(let n=0;n<20;n++){
      const page=await client.snapshot('captures',{limit:500,...(pageToken?{page_token:pageToken}:{})});
      if(page.http_status!==200)fail(page.error?.code??'core_unavailable');
      rows.push(...page.records);
      pageToken=page.next_page_token;
      if(!pageToken){if(page.manifest?.base_cursor)await client.acknowledge('captures',page.manifest.base_cursor,page.snapshot_id);return rows.filter(row=>!row.deleted_at);}
    }
    fail('capture_list_too_large');
  }
  return {
    async remember(args={}) {
      checkArgs(args,Object.keys(CORE_REMEMBER_TOOL.inputSchema.properties));
      const action=args.action??'add';
      if(!['add','update','delete','list'].includes(action))fail('invalid_action');
      if(action==='list'){if(Object.keys(args).some(k=>k!=='action'))fail('invalid_request');return {action,notes:await this.activeNotes(50)};}
      const id=args.id??args.note_id;
      if(args.id&&args.note_id&&args.id!==args.note_id)fail('invalid_id');
      for(const key of ['op_id','base_revision','created_at','expires_at','authorization_ref'])if(args[key]===undefined)fail(`missing_${key}`);
      safeId(id);
      const kind={add:'create',update:'patch',delete:'delete'}[action];requireScope(kind);
      if(kind!=='delete'&&(typeof args.text!=='string'||!args.text.trim()||[...args.text].length>2000))fail('invalid_text');
      if(kind==='delete'&&args.text!==undefined)fail('invalid_request');
      const intent={...Object.fromEntries(['op_id','base_revision','created_at','expires_at','authorization_ref'].map(k=>[k,args[k]])),id,kind,actor:'user_via_agent'};
      if(kind==='create')Object.assign(intent,{data:{text:args.text,source:'claude_web',recorded_at:args.created_at},provenance:{source:'claude_web',source_refs:[],import_batch_id:null}});
      else if(kind==='patch')intent.patch={text:args.text};
      else intent.permanent=true;
      const result=await client.submit('captures',intent);
      return {action,...result,...(result.record?{note:project(result.record)}:{})};
    },
    async activeNotes(limit=10){return (await records()).sort((a,b)=>b.updated_at.localeCompare(a.updated_at)).slice(0,limit).map(project);},
    async searchNotes(query,limit=8){const terms=String(query).toLowerCase().split(/\s+/).filter(Boolean);return (await records()).filter(row=>terms.some(term=>row.data.text.toLowerCase().includes(term))).slice(0,limit).map(project);},
  };
}
