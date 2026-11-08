// E1 expense tools (记账). Self-contained (node: imports only) so the legacy candidate can inline this file verbatim.
// Writes go to the Core expense_entries domain with the food writer credential (core-food.json); the phone
// reads the same domain and projects it into the shared ledger. Enabled only when <stateDir>/expense.json exists.
import * as expenseFs from 'node:fs';
import * as expensePath from 'node:path';

export class ExpenseInputError extends Error {}
const expenseFail = code => { throw new ExpenseInputError(code); };
const expenseObject = value => value !== null && typeof value === 'object' && !Array.isArray(value);
export const EXPENSE_DOMAIN_NAME = 'expense_entries';
export const EXPENSE_TOOL_FRONTENDS = Object.freeze(['claude_web', 'chatgpt_web', 'gemini_web', 'antigravity']);
export const EXPENSE_CATEGORY_NAMES = Object.freeze(['food', 'transport', 'shopping', 'daily', 'entertainment', 'housing', 'health', 'learning', 'social', 'other']);
const EXPENSE_ID_SCHEMA = {type: 'string', minLength: 1, maxLength: 200};
const EXPENSE_HINT = '分类：food 吃喝、transport 交通、shopping 购物、daily 日用、entertainment 娱乐、housing 住房水电、health 医疗健康、learning 学习、social 社交人情、other 其他。';
const expenseEntrySchema = {
  type: 'object',
  properties: {
    amount_cny: {type: 'number', exclusiveMinimum: 0, maximum: 1000000, description: '这笔花了多少元（人民币），最多两位小数。'},
    ai_amount_cny: {type: 'number', minimum: 0, maximum: 1000000, description: '其中由林埃的份额出的钱；用户没说就不传（按 0）。不能超过 amount_cny。'},
    item: {type: 'string', minLength: 1, maxLength: 200, description: '买了什么，简短写清楚，如“午饭 黄焖鸡”。'},
    category: {type: 'string', enum: [...EXPENSE_CATEGORY_NAMES]},
    spent_at: {type: 'string', description: '花钱的时间，带时区的 ISO 8601，如 2026-11-07T12:30:00+08:00。不知道具体时间可不传：add 按现在算，update 保留原时间。'},
    note: {type: 'string', maxLength: 2000},
  },
  required: ['amount_cny', 'item', 'category'],
  additionalProperties: false,
};
export const EXPENSE_TOOLS = Object.freeze([
  {name: 'expense_log', requiredScope: 'i.write',
    description: '记一笔花销到 Here I Am 的共同账本（手机 App 同步后显示在账本里）。用户说“帮我记一下今天花了多少钱买了什么”时用这个工具，不要用 i_remember。只记支出；收入、转账、借还款请让用户在 App 里记。'
      + ' action 为 add/update/void：add 新记一笔；update 改一笔（带完整 entry）；void 撤销记错的一笔。新意图用新的 UUID op_id，add 时 id 也用新 UUID；重试时保留原参数和原 op_id。update/void 必须带 base_revision（上次返回的 revision）。'
      + ' 写入后把金额、分类和当天合计告诉用户。' + EXPENSE_HINT,
    inputSchema: {type: 'object', properties: {
      action: {type: 'string', enum: ['add', 'update', 'void']}, op_id: EXPENSE_ID_SCHEMA, id: EXPENSE_ID_SCHEMA,
      base_revision: {type: 'integer', minimum: 1}, entry: expenseEntrySchema,
    }, required: ['action', 'op_id', 'id'], additionalProperties: false},
    annotations: {readOnlyHint: false, destructiveHint: false, idempotentHint: true, openWorldHint: false}},
  {name: 'expense_day', requiredScope: 'i.read',
    description: '读取某一天（默认今天，北京时间自然日）经 expense_log 记下的未撤销花销和合计。只含 AI 端记的账，App 里手记的不在这里。',
    inputSchema: {type: 'object', properties: {date: {type: 'string', format: 'date', description: 'YYYY-MM-DD，不传为今天。'}}, additionalProperties: false},
    annotations: {readOnlyHint: true, destructiveHint: false, idempotentHint: true, openWorldHint: false}},
]);
export const EXPENSE_TOOL_NAMES = Object.freeze(EXPENSE_TOOLS.map(tool => tool.name));

export function loadExpenseConfig(stateDir) {
  let text;
  try { text = expenseFs.readFileSync(expensePath.resolve(stateDir, 'expense.json'), 'utf8'); }
  catch (error) { if (error.code === 'ENOENT') return null; throw new Error('expense_config_invalid'); }
  try {
    const value = JSON.parse(text.replace(/^﻿/, ''));
    if (!expenseObject(value) || Object.keys(value).length !== 1 || value.format !== 'expense-v1') throw new Error();
    return {format: value.format};
  } catch { throw new Error('expense_config_invalid'); }
}

export function createExpenseClient({coreUrl, token, coreInstanceId, fetchImpl = fetch, timeoutMs = 15000}) {
  const url = new URL(coreUrl);
  if (!['http:', 'https:'].includes(url.protocol) || url.username || url.password || url.pathname !== '/' || url.search || url.hash) throw new Error('invalid_core_url');
  if (typeof token !== 'string' || !token || /\s/.test(token) || typeof coreInstanceId !== 'string' || !coreInstanceId) throw new Error('invalid_domain_credential');
  async function request(resource, body, query = {}) {
    const endpoint = new URL(`/v1/core/domains/${EXPENSE_DOMAIN_NAME}/${resource}`, url);
    if (!body) {
      endpoint.searchParams.set('core_instance_id', coreInstanceId);
      for (const [key, value] of Object.entries(query)) if (value !== undefined) endpoint.searchParams.set(key, String(value));
    }
    try {
      const response = await fetchImpl(endpoint, {method: body ? 'POST' : 'GET', redirect: 'error', signal: AbortSignal.timeout(timeoutMs),
        headers: {authorization: `Bearer ${token}`, 'x-i-core-domain-protocol': '1', ...(body ? {'content-type': 'application/json'} : {})},
        ...(body ? {body: JSON.stringify(body)} : {})});
      const payload = await response.json();
      if (!expenseObject(payload)) throw new Error('invalid_response');
      return {http_status: response.status, ...payload};
    } catch {
      return {outcome: 'transport_unknown', error: {code: 'core_unavailable', retryable: true},
        retry: 'Retry the exact same intent with the same op_id. Do not create a new operation or claim acceptance.'};
    }
  }
  const expenseRecordId = value => {
    if (typeof value !== 'string' || !/^[a-zA-Z0-9][a-zA-Z0-9_.:-]{0,199}$/.test(value)) expenseFail('invalid_id');
    return encodeURIComponent(value);
  };
  return {
    coreInstanceId,
    submit: intent => request('ops', {domain_protocol_version: 1, core_instance_id: coreInstanceId, schema_version: 1, ...intent}),
    record: id => request(`records/${expenseRecordId(id)}`),
    snapshot: query => request('snapshot', null, query),
    operation: id => request(`ops/${expenseRecordId(id)}`),
    acknowledge: (cursor, snapshotId) => request('ack', {domain_protocol_version: 1, core_instance_id: coreInstanceId, cursor, snapshot_id: snapshotId}),
  };
}

const expenseUuid = value => typeof value === 'string' && /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(value);
const expenseDate = value => typeof value === 'string' && /^\d{4}-\d{2}-\d{2}$/.test(value)
  && Number.isFinite(Date.parse(value + 'T00:00:00Z')) && new Date(value + 'T00:00:00Z').toISOString().slice(0, 10) === value;
function expenseTime(value) {
  if (typeof value !== 'string' || !expenseDate(value.slice(0, 10))) return false;
  const m = value.match(/^\d{4}-\d{2}-\d{2}T(\d{2}):(\d{2}):(\d{2})(?:\.\d{3})?(Z|[+-](\d{2}):(\d{2}))$/);
  return !!m && +m[1] < 24 && +m[2] < 60 && +m[3] < 60 && (m[4] === 'Z' || +m[5] <= 14 && +m[6] < 60 && (+m[5] !== 14 || +m[6] === 0)) && Number.isFinite(Date.parse(value));
}
const expenseCents = value => Math.round(value * 100) / 100;
const expenseLength = value => [...value].length;

function checkExpenseEntry(entry) {
  if (!expenseObject(entry)) expenseFail('invalid_expense_entry');
  if (Object.keys(entry).some(key => !Object.hasOwn(expenseEntrySchema.properties, key))) expenseFail('expense_field_not_allowed');
  if (!expenseEntrySchema.required.every(key => Object.hasOwn(entry, key))) expenseFail('invalid_expense_entry');
  if (typeof entry.amount_cny !== 'number' || !Number.isFinite(entry.amount_cny)) expenseFail('invalid_expense_amount');
  const amount = expenseCents(entry.amount_cny);
  if (!(amount > 0 && amount <= 1000000)) expenseFail('invalid_expense_amount');
  if (entry.ai_amount_cny !== undefined && (typeof entry.ai_amount_cny !== 'number' || !Number.isFinite(entry.ai_amount_cny))) expenseFail('invalid_expense_ai_amount');
  const aiAmount = entry.ai_amount_cny === undefined ? 0 : expenseCents(entry.ai_amount_cny);
  if (!(aiAmount >= 0 && aiAmount <= amount)) expenseFail('invalid_expense_ai_amount');
  if (typeof entry.item !== 'string' || !entry.item.trim() || expenseLength(entry.item.trim()) > 200) expenseFail('invalid_expense_item');
  if (!EXPENSE_CATEGORY_NAMES.includes(entry.category)) expenseFail('invalid_expense_category');
  if (entry.spent_at !== undefined && !expenseTime(entry.spent_at)) expenseFail('invalid_expense_time');
  if (entry.note !== undefined && (typeof entry.note !== 'string' || expenseLength(entry.note) > 2000)) expenseFail('invalid_expense_note');
  return {amount_cny: amount, ai_amount_cny: aiAmount, item: entry.item.trim(), category: entry.category,
    ...(entry.spent_at !== undefined ? {spent_at: entry.spent_at} : {}), note: entry.note ?? ''};
}

export function createExpenseTools({client, frontend, timeZone = 'Asia/Shanghai', now = () => Date.now()}) {
  if (!client || !EXPENSE_TOOL_FRONTENDS.includes(frontend)) throw new Error('invalid_expense_configuration');
  const formatter = new Intl.DateTimeFormat('en-CA', {timeZone, year: 'numeric', month: '2-digit', day: '2-digit',
    hour: '2-digit', minute: '2-digit', second: '2-digit', hourCycle: 'h23'});
  const parts = time => Object.fromEntries(formatter.formatToParts(new Date(time)).map(part => [part.type, part.value]));
  const localDate = time => { const p = parts(time); return `${p.year}-${p.month}-${p.day}`; };
  function localStamp(time) {
    const whole = Math.floor(time / 1000) * 1000, p = parts(whole);
    const offset = Math.round((Date.UTC(+p.year, +p.month - 1, +p.day, +p.hour, +p.minute, +p.second) - whole) / 60000);
    const sign = offset < 0 ? '-' : '+', abs = Math.abs(offset);
    return `${p.year}-${p.month}-${p.day}T${p.hour}:${p.minute}:${p.second}${sign}${String(Math.floor(abs / 60)).padStart(2, '0')}:${String(abs % 60).padStart(2, '0')}`;
  }
  // Keep generated timestamps identical on retries. After a restart an op the Core already has fails closed.
  const intents = new Map();
  async function day(date) {
    const rows = [];
    let pageToken;
    for (let n = 0; n < 200; n++) {
      const page = await client.snapshot({limit: 100, ...(pageToken ? {page_token: pageToken} : {})});
      if (page.http_status !== 200 || !Array.isArray(page.records)) expenseFail(page.error?.code ?? 'core_unavailable');
      rows.push(...page.records.filter(row => !row.deleted_at && row.data?.voided !== true && row.data?.local_date === date));
      pageToken = page.next_page_token;
      if (!pageToken) {
        if (page.manifest?.base_cursor) await client.acknowledge(page.manifest.base_cursor, page.snapshot_id);
        rows.sort((a, b) => Date.parse(a.data.spent_at) - Date.parse(b.data.spent_at) || a.id.localeCompare(b.id));
        const entries = rows.map(row => ({id: row.id, revision: row.revision, spent_at: row.data.spent_at, amount_cny: row.data.amount_cny,
          ai_amount_cny: row.data.ai_amount_cny, item: row.data.item, category: row.data.category, note: row.data.note, source_frontend: row.data.source_frontend}));
        return {date, entries, count: entries.length,
          total_cny: expenseCents(entries.reduce((sum, row) => sum + row.amount_cny, 0)),
          ai_total_cny: expenseCents(entries.reduce((sum, row) => sum + row.ai_amount_cny, 0))};
      }
    }
    expenseFail('expense_day_too_large');
  }
  const properties = EXPENSE_TOOLS[0].inputSchema.properties;
  const handlers = {
    async expense_day(args = {}) {
      if (!expenseObject(args) || Object.keys(args).some(key => key !== 'date')) expenseFail('invalid_request');
      if (args.date !== undefined && !expenseDate(args.date)) expenseFail('invalid_expense_date');
      return day(args.date ?? localDate(now()));
    },
    async expense_log(args = {}) {
      if (!expenseObject(args)) expenseFail('invalid_request');
      if (Object.keys(args).some(key => !Object.hasOwn(properties, key))) expenseFail('expense_field_not_allowed');
      if (!['action', 'op_id', 'id'].every(key => Object.hasOwn(args, key))) expenseFail('invalid_request');
      if (!['add', 'update', 'void'].includes(args.action)) expenseFail('invalid_action');
      if (!expenseUuid(args.op_id) || !expenseUuid(args.id) || args.op_id === args.id) expenseFail('invalid_id');
      if (args.action === 'add' ? args.base_revision !== undefined : !Number.isSafeInteger(args.base_revision) || args.base_revision < 1) expenseFail('invalid_base');
      if (args.action === 'void' ? args.entry !== undefined : args.entry === undefined) expenseFail('invalid_request');
      const entry = args.action === 'void' ? null : checkExpenseEntry(args.entry);
      const kind = args.action === 'add' ? 'create' : 'patch';
      const fingerprint = JSON.stringify([args.action, args.id, args.base_revision ?? 0, entry]);
      let cached = intents.get(args.op_id);
      if (cached && cached.fingerprint !== fingerprint) expenseFail('idempotency_conflict');
      if (!cached) {
        const prior = await client.operation(args.op_id);
        if (prior.http_status === 200) expenseFail('expense_retry_state_unavailable');
        if (prior.http_status !== 404) expenseFail(prior.error?.code ?? 'core_unavailable');
        const stamp = now();
        cached = {fingerprint, stamp, created_at: new Date(stamp).toISOString(), expires_at: new Date(stamp + 60 * 86400000).toISOString()};
        if (intents.size >= 1024) intents.delete(intents.keys().next().value);
        intents.set(args.op_id, cached);
      }
      let data;
      if (!entry) data = {voided: true};
      else {
        const timed = entry.spent_at ?? (kind === 'create' ? localStamp(cached.stamp) : undefined);
        data = {amount_cny: entry.amount_cny, ai_amount_cny: entry.ai_amount_cny, item: entry.item, category: entry.category, note: entry.note,
          ...(timed ? {spent_at: timed, local_date: localDate(Date.parse(timed))} : {}), voided: false,
          ...(kind === 'create' ? {source_frontend: frontend} : {})};
      }
      const intent = {op_id: args.op_id, id: args.id, base_revision: kind === 'create' ? 0 : args.base_revision, kind, actor: 'agent_inferred',
        created_at: cached.created_at, expires_at: cached.expires_at,
        ...(kind === 'create' ? {data, provenance: {source: 'expense_log', source_refs: [], import_batch_id: null}} : {patch: data})};
      const result = await client.submit(intent);
      if (!['accepted', 'duplicate'].includes(result.outcome)) return result;
      const record = result.record ?? (await client.record(args.id)).record;
      if (!record?.data) expenseFail('expense_record_unavailable');
      const snapshot = await day(record.data.local_date);
      return {id: record.id, revision: record.revision, local_date: record.data.local_date, amount_cny: record.data.amount_cny,
        ai_amount_cny: record.data.ai_amount_cny, item: record.data.item, category: record.data.category, voided: record.data.voided,
        day_total_cny: snapshot.total_cny, day_count: snapshot.count};
    },
  };
  return {tools: EXPENSE_TOOLS, handlers};
}
