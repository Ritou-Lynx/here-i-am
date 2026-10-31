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
  read('day_get', 'plan_days', 'Read a day by stable record id, or snapshot pages to locate date. Returns current referenced item titles with item revisions when plan_items:read is granted; queues retain stable IDs. Title lookup is bounded and is not an atomic cross-domain snapshot.'),
  write('day_set', 'plan_days', 'upsert', {data:dataSchema('plan_days')}, ['data']),
];
export const DOMAIN_TOOLS = Object.freeze(definitions.map(tool => ({...tool,
  description: tool.description ?? `${tool.name}: Core validates fields, authorization and conflicts. Upsert uses create at base_revision=0, otherwise patches only supplied fields. Preserve op_id, timestamps and base on retry; never auto-rebase.`,
  annotations:{readOnlyHint:!!tool.read,destructiveHint:false,idempotentHint:true,openWorldHint:false},
})));
export const PLANNER_SCOPES = Object.freeze(['captures:read','captures:ack', ...['plan_items','plan_weeks','plan_days'].flatMap(domain => ['read','create','patch'].map(action=>`${domain}:${action}`))]);
export const WEB_DOMAIN_TOOLS = Object.freeze(['capture_add','week_get','day_get','food_log','food_day']);

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
    if (!Object.hasOwn(PERSONAL_SCHEMAS, domain) && domain !== 'food_entries') fail('domain_forbidden');
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

// Resolve only the display fields allowed by the separately scoped plan reader.
// Keep canonical day records and their queue identities unchanged.
async function withDayItemTitles(result, client, scopes) {
  const days = result.record ? [result.record] : Array.isArray(result.records) ? result.records : [];
  if (!days.length || result.http_status !== 200) return result;
  const ids = [...new Set(days.filter(day => !day.deleted_at).flatMap(day =>
    Object.values(day.data?.queues ?? {}).flat()).filter(id => typeof id === 'string'))];
  const item_titles = {}, item_title_issues = [];
  if (!scopes.includes('plan_items:read')) {
    for (const id of ids) item_title_issues.push({id, reason:'scope_forbidden'});
    return {...result, item_titles, item_title_issues};
  }
  const bounded = ids.slice(0, 500);
  for (const id of ids.slice(500)) item_title_issues.push({id, reason:'lookup_limit'});
  let index = 0;
  await Promise.all(Array.from({length:Math.min(4, bounded.length)}, async () => {
    while (index < bounded.length) {
      const id = bounded[index++];
      let response;
      try { response = await client.record('plan_items', id); }
      catch { response = null; }
      const item = response?.record;
      if (response?.http_status === 200 && item && !item.deleted_at && typeof item.data?.title === 'string') {
        item_titles[id] = {title:item.data.title, revision:item.revision};
      } else {
        item_title_issues.push({id, reason:response?.http_status === 403 ? 'scope_forbidden' :
          response?.http_status === 404 || item?.deleted_at ? 'not_found' : 'unavailable'});
      }
    }
  }));
  return {...result, item_titles, item_title_issues};
}

export function createDomainTools({client, scopes, surface = 'planner', captureSource = 'codex'}) {
  if(!client || !Array.isArray(scopes) || scopes.some(s=>typeof s!=='string') || !['planner','web'].includes(surface)) throw new Error('invalid_domain_configuration');
  if(!['codex','dot','claude_web'].includes(captureSource) || surface==='web'&&captureSource!=='claude_web')throw new Error('invalid_capture_source');
  const permitted = DOMAIN_TOOLS.filter(tool=>available(tool,scopes)&&(surface!=='web'||WEB_DOMAIN_TOOLS.includes(tool.name)));
  const handlers = Object.fromEntries(permitted.map(tool=>[tool.name, async(args={})=>{
    checkArgs(args,Object.keys(tool.inputSchema.properties),tool.inputSchema.required);
    if(!scopes.includes(scopeFor(tool,args)))return {error:{code:'scope_forbidden',retryable:false},http_status:403};
    if(tool.read) {
      if(args.id!==undefined){if(Object.keys(args).length!==1)fail('invalid_request');const result=await client.record(tool.domain,args.id);return tool.name==='day_get'?withDayItemTitles(result,client,scopes):result;}
      if(args.limit!==undefined&&(!Number.isSafeInteger(args.limit)||args.limit<1||args.limit>500))fail('invalid_limit');
      const page=await client.snapshot(tool.domain,args);
      if(page.manifest?.base_cursor&&!page.next_page_token)await client.acknowledge(tool.domain,page.manifest.base_cursor,page.snapshot_id);
      return tool.name==='day_get'?withDayItemTitles(page,client,scopes):page;
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
  return {tools:permitted.map(({domain,kind,read,...tool})=>({...tool,requiredScope:surface==='web'?(read?'i.read':'i.write'):undefined})),handlers};
}

// Food is opt-in and uses a separate Core credential. No photos enter this adapter.
const foodKeys = ['kcal','kcal_low','kcal_high','protein_g','fat_g','carb_g'];
const roundFood = value => Math.round(value*10)/10;
function foodSum(items) {
  return Object.fromEntries(foodKeys.map(key=>[key,roundFood(items.reduce((sum,item)=>sum+
    (key==='kcal_low'?item.kcal*item.grams_low/item.grams:key==='kcal_high'?item.kcal*item.grams_high/item.grams:item[key]),0))]));
}
const foodInstructions = '照片由你自己看，不要尝试上传。逐项列食物，中式炒菜把“烹调油”单列一项。给克数范围，参照物写进 note。不确定标 low，不编数；food_ref.source 用 model，拍到营养标签时用 label、basis:"label"。写入后把结果和今日累计告诉用户并请对方纠正。用户说记错了、不要这条时用 void。';
const foodNumber = {type:'number',minimum:0,maximum:10000};
const foodItemSchema = shape({
  name:{type:'string',minLength:1,maxLength:100},
  food_ref:shape({source:{type:'string',enum:['model','label','personal','usda']},id:{type:['string','null']}}),
  grams:{type:'number',exclusiveMinimum:0,maximum:5000},grams_low:{type:'number',exclusiveMinimum:0,maximum:5000},grams_high:{type:'number',exclusiveMinimum:0,maximum:5000},
  kcal:foodNumber,protein_g:foodNumber,fat_g:foodNumber,carb_g:foodNumber,
  basis:{type:'string',enum:['weighed','label','photo','described','model_guess']},confidence:{type:'string',enum:['high','medium','low']},
});
const foodEntrySchema = {...shape({eaten_at:{type:'string'},meal:{type:'string',enum:['breakfast','lunch','dinner','snack','drink']},title:{type:'string',minLength:1,maxLength:200},
  note:{type:'string',maxLength:2000},input_kind:{type:'string',enum:['photo','text','mixed','app']},items:{type:'array',minItems:1,maxItems:40,items:foodItemSchema}}),required:['eaten_at','meal','title','input_kind','items']};
export const FOOD_TOOLS = Object.freeze([
  {name:'food_log',requiredScope:'i.write',description:foodInstructions+' action 为 add/update/void。新意图用新 UUID op_id，重试保留原参数。update/void 必须提供 base_revision；void 仅撤销该条。',inputSchema:{type:'object',properties:{
    action:{type:'string',enum:['add','update','void']},op_id:idSchema,id:idSchema,base_revision:{type:'integer',minimum:1},entry:foodEntrySchema},required:['action','op_id','id'],additionalProperties:false},
    annotations:{readOnlyHint:false,destructiveHint:false,idempotentHint:true,openWorldHint:false}},
  {name:'food_day',requiredScope:'i.read',description:'读取指定日或按配置时区本地 04:00 日界的今天，返回未撤销条目及累计。'+foodInstructions,inputSchema:{type:'object',properties:{date:{type:'string',pattern:'^\\d{4}-\\d{2}-\\d{2}$'}},additionalProperties:false},
    annotations:{readOnlyHint:true,destructiveHint:false,idempotentHint:true,openWorldHint:false}},
]);
const foodUuid = value => typeof value==='string' && /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(value);
const foodDate = value => typeof value==='string' && /^\d{4}-\d{2}-\d{2}$/.test(value) && Number.isFinite(Date.parse(value+'T00:00:00Z')) && new Date(value+'T00:00:00Z').toISOString().slice(0,10)===value;
function foodTime(value) {
  if(typeof value!=='string'||!foodDate(value.slice(0,10)))return false;
  const m=value.match(/^\d{4}-\d{2}-\d{2}T(\d{2}):(\d{2}):(\d{2})(?:\.\d{3})?(Z|[+-](\d{2}):(\d{2}))$/);
  return !!m && +m[1]<24 && +m[2]<60 && +m[3]<60 && (m[4]==='Z'||+m[5]<=14&&+m[6]<60&&(+m[5]!==14||+m[6]===0)) && Number.isFinite(Date.parse(value));
}
function foodShape(value,keys,optional=[]) {
  return object(value)&&keys.every(key=>Object.hasOwn(value,key))&&Object.keys(value).every(key=>keys.includes(key)||optional.includes(key));
}
function checkFoodEntry(entry) {
  if(!object(entry))fail('invalid_food_entry');
  if(Object.keys(entry).some(key=>!Object.hasOwn(foodEntrySchema.properties,key)))fail('food_field_not_allowed');
  if(!foodShape(entry,foodEntrySchema.required,['note'])||!foodTime(entry.eaten_at)
    ||!foodEntrySchema.properties.meal.enum.includes(entry.meal)||!foodEntrySchema.properties.input_kind.enum.includes(entry.input_kind)
    ||typeof entry.title!=='string'||!entry.title.trim()||[...entry.title].length>200
    ||entry.note!==undefined&&(typeof entry.note!=='string'||[...entry.note].length>2000)
    ||!Array.isArray(entry.items)||entry.items.length<1||entry.items.length>40)fail('invalid_food_entry');
  for(const item of entry.items) {
    if(!foodShape(item,Object.keys(foodItemSchema.properties))||typeof item.name!=='string'||!item.name.trim()||[...item.name].length>100
      ||!foodShape(item.food_ref,['source','id'])||!['model','label','personal','usda'].includes(item.food_ref.source)
      ||!(item.food_ref.id===null||typeof item.food_ref.id==='string')
      ||!['weighed','label','photo','described','model_guess'].includes(item.basis)||!['high','medium','low'].includes(item.confidence)
      ||!['grams','grams_low','grams_high','kcal','protein_g','fat_g','carb_g'].every(key=>typeof item[key]==='number'&&Number.isFinite(item[key]))
      ||!(0<item.grams_low&&item.grams_low<=item.grams&&item.grams<=item.grams_high&&item.grams_high<=5000)
      ||!['kcal','protein_g','fat_g','carb_g'].every(key=>item[key]>=0&&item[key]<=10000))fail('invalid_food_item');
  }
}

export function createFoodTools({client,scopes,timeZone='Asia/Shanghai',now=()=>Date.now()}) {
  if(!client||!Array.isArray(scopes)||scopes.some(scope=>!['food_entries:read','food_entries:create','food_entries:patch'].includes(scope)))throw new Error('invalid_food_configuration');
  const formatter=new Intl.DateTimeFormat('en-CA',{timeZone,year:'numeric',month:'2-digit',day:'2-digit',hour:'2-digit',hourCycle:'h23'});
  function localDate(time) {
    const parts=Object.fromEntries(formatter.formatToParts(new Date(time)).map(part=>[part.type,part.value]));
    const date=new Date(`${parts.year}-${parts.month}-${parts.day}T00:00:00Z`);
    if(Number(parts.hour)<4)date.setUTCDate(date.getUTCDate()-1);
    return date.toISOString().slice(0,10);
  }
  const has=kind=>scopes.includes('food_entries:'+kind);
  const tools=FOOD_TOOLS.filter(tool=>has('read')&&(tool.name==='food_day'||has('create')||has('patch')));
  // Keep generated timestamps identical on retries. On restart/eviction, an existing
  // Core op is fail-closed rather than reconstructing a different intent.
  const intents=new Map();
  async function day(date) {
    const rows=[];let pageToken;
    for(let n=0;n<200;n++) {
      const page=await client.snapshot('food_entries',{limit:100,...(pageToken?{page_token:pageToken}:{})});
      if(page.http_status!==200||!Array.isArray(page.records))fail(page.error?.code??'core_unavailable');
      rows.push(...page.records.filter(row=>!row.deleted_at&&row.data?.voided!==true&&row.data?.local_date===date));
      pageToken=page.next_page_token;
      if(!pageToken) {
        if(page.manifest?.base_cursor)await client.acknowledge('food_entries',page.manifest.base_cursor,page.snapshot_id);
        rows.sort((a,b)=>Date.parse(a.data.eaten_at)-Date.parse(b.data.eaten_at)||a.id.localeCompare(b.id));
        return {date,entries:rows,day_totals:Object.fromEntries(foodKeys.map(key=>[key,roundFood(rows.reduce((sum,row)=>sum+row.data.totals[key],0))]))};
      }
    }
    fail('food_day_too_large');
  }
  const handlers={
    async food_day(args={}) {
      checkArgs(args,['date']);if(args.date!==undefined&&!foodDate(args.date))fail('invalid_food_date');
      return day(args.date??localDate(now()));
    },
    async food_log(args={}) {
      if(object(args)&&Object.keys(args).some(key=>!Object.hasOwn(FOOD_TOOLS[0].inputSchema.properties,key)))fail('food_field_not_allowed');
      checkArgs(args,Object.keys(FOOD_TOOLS[0].inputSchema.properties),['action','op_id','id']);
      if(!['add','update','void'].includes(args.action))fail('invalid_action');
      if(!foodUuid(args.op_id)||!foodUuid(args.id)||args.op_id===args.id)fail('invalid_id');
      const kind=args.action==='add'?'create':'patch';
      if(!has(kind)||!has('read'))return {error:{code:'scope_forbidden',retryable:false},http_status:403};
      if(args.action==='add'&&args.base_revision!==undefined||args.action!=='add'&&(!Number.isSafeInteger(args.base_revision)||args.base_revision<1))fail('invalid_base');
      if(args.action==='void'&&args.entry!==undefined)fail('invalid_request');
      if(args.action!=='void')checkFoodEntry(args.entry);
      const data=args.action==='void'?{voided:true}:{...structuredClone(args.entry),note:args.entry.note??'',local_date:localDate(args.entry.eaten_at),totals:foodSum(args.entry.items),user_corrected:false,voided:false};
      const intent={op_id:args.op_id,id:args.id,base_revision:args.action==='add'?0:args.base_revision,kind,actor:'agent_inferred',...(kind==='create'?{data,provenance:{source:'food_log',source_refs:[],import_batch_id:null}}:{patch:data})};
      const fingerprint=JSON.stringify(intent);let cached=intents.get(args.op_id);
      if(cached&&cached.fingerprint!==fingerprint)fail('idempotency_conflict');
      if(!cached) {
        if(client.operation) {
          const prior=await client.operation('food_entries',args.op_id);
          if(prior.http_status===200)fail('food_retry_state_unavailable');
          if(prior.http_status!==404)fail(prior.error?.code??'core_unavailable');
        }
        const stamp=now();cached={fingerprint,created_at:new Date(stamp).toISOString(),expires_at:new Date(stamp+60*86400000).toISOString()};
        if(intents.size>=1024)intents.delete(intents.keys().next().value);
        intents.set(args.op_id,cached);
      }
      const result=await client.submit('food_entries',{...intent,created_at:cached.created_at,expires_at:cached.expires_at});
      if(!['accepted','duplicate'].includes(result.outcome))return result;
      const record=result.record??(await client.record('food_entries',args.id)).record;
      if(!record?.data)fail('food_record_unavailable');
      const snapshot=await day(record.data.local_date);
      return {id:record.id,revision:record.revision,local_date:record.data.local_date,totals:record.data.totals,day_totals:snapshot.day_totals};
    },
  };
  return {tools,handlers:Object.fromEntries(tools.map(tool=>[tool.name,handlers[tool.name]]))};
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
