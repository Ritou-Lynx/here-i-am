#!/usr/bin/env node
import { readFile, writeFile, mkdir, readdir, rename, open, unlink, lstat, access } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { randomUUID } from 'node:crypto';
import { isDeepStrictEqual } from 'node:util';
import { callCli, fail, SyncError } from './cli.mjs';
import { assertSeparateDirectories, resolvedPath } from './layout.mjs';
import { SCHEMA, OPTIONS, object, validDate, validateConfig, validateFields, encodeFields, decodeRow } from './schema.mjs';

export const HELP = `Feishu tutor sync (Node 24)
Usage: node <tool>/sync/feishu_sync.mjs <pull|push|check> --state <study>/state --config <tool>/config.json
       node <tool>/sync/feishu_sync.mjs push --dry-run --state <study>/state --config <tool>/config.json
       node sync/feishu_sync.mjs --help
--state is required. Config defaults to <tool>/config.json, outside the study directory.
Tool and study directories must be separate, without either containing the other.
Only user identity, fixed allowlisted CLI commands, and append-only study docs.
Dry-run validates local outbox only; it makes no CLI calls and moves no files.
`;
async function json(file) {
  try { return JSON.parse(await readFile(file, 'utf8')); } catch { fail('local_json_invalid'); }
}
async function exists(file) { try { await access(file); return true; } catch { return false; } }
async function save(file, data) {
  await mkdir(path.dirname(file), { recursive: true });
  const temp = `${file}.pending-${randomUUID()}`;
  try { await writeFile(temp, `${JSON.stringify(data, null, 2)}\n`, { mode: 0o600 }); await rename(temp, file); }
  finally { if (await exists(temp)) await unlink(temp); }
}
function code(error) { return error instanceof SyncError ? error.code : 'sync_failed'; }
function exactKeys(action, keys) {
  if (!object(action) || Object.keys(action).some(k => !keys.includes(k)) || keys.some(k => !Object.hasOwn(action, k))) fail('outbox_invalid_action');
}
function id(value) {
  if (typeof value !== 'string' || !/^[A-Za-z0-9_-]+$/u.test(value)) fail('outbox_invalid_record_id');
}

export async function readTable(config, table) {
  let offset = 0, rev, context;
  const records = [], ids = new Set();
  for (let page = 0; page < 10000; page++) {
    const { rows, manifest } = await callCli(config, 'record_list', {
      base: config.base_token, table: config.tables[table].name, offset,
    });
    if (page === 0) { rev = manifest.rev; context = manifest.query_context; }
    else if (rev === undefined || manifest.rev !== rev || !isDeepStrictEqual(context, manifest.query_context)) fail('pull_snapshot_changed');
    for (const row of rows) {
      if (ids.has(row.record_id)) fail('pull_duplicate_record');
      ids.add(row.record_id);
      records.push(decodeRow(row, table, config));
    }
    if (!manifest.has_more) return records;
    if (!Number.isSafeInteger(manifest.next_offset) || manifest.next_offset <= offset || !rows.length) fail('pull_pagination_invalid');
    offset = manifest.next_offset;
  }
  fail('pull_pagination_invalid');
}

export async function check(config) {
  await callCli(config, 'whoami');
  for (const [table, schema] of Object.entries(SCHEMA)) {
    const params = { base: config.base_token, table: config.tables[table].name };
    await callCli(config, 'table_get', params);
    const data = await callCli(config, 'field_list', params);
    if (!Array.isArray(data?.fields)) fail('schema_response_invalid');
    for (const [key, type] of Object.entries(schema)) {
      const matches = data.fields.filter(f => f.name === config.tables[table].fields[key]);
      if (matches.length !== 1) fail('schema_field_missing');
      const field = matches[0];
      if (field.type !== type || (type === 'select' && field.multiple !== false)) fail('schema_type_mismatch');
      if (type === 'select') {
        const expected = key === '科目' ? config.subjects : OPTIONS[key];
        if (!Array.isArray(field.options) || expected.some(v => !field.options.some(o => o.name === v))) fail('schema_option_missing');
      }
    }
  }
}

function sourceUrl(value) {
  if (typeof value !== 'string') return false;
  try {
    const url = new URL(value);
    return url.protocol === 'https:' && !url.username && !url.password && /^\/(docx|wiki)\//u.test(url.pathname);
  } catch { return false; }
}

async function pull(config, state) {
  await check(config);
  const records = await readTable(config, 'ledger');
  const practice = await readTable(config, 'practice');
  const inbox = (await readTable(config, 'inbox')).filter(row => row.fields.状态 === '待入账');
  const sources = [];
  if (config.sources !== undefined && !Array.isArray(config.sources)) fail('config_invalid');
  for (const source of config.sources || []) {
    if (!object(source) || typeof source.title !== 'string' || !source.title.trim() || typeof source.doc !== 'string') fail('config_invalid');
    // Optional share link so the tutor can cite a clickable source; same shape
    // the ledger 来源 field accepts.
    if (source.url !== undefined && !sourceUrl(source.url)) fail('config_invalid');
    const data = await callCli(config, 'doc_fetch', { doc: source.doc });
    if (typeof data?.document?.content !== 'string') fail('cli_invalid_response');
    sources.push({ title: source.title, ...(source.url ? { url: source.url } : {}), document: data.document });
  }
  // No valid local snapshot is touched until all remote reads have completed.
  const pulled_at = new Date().toISOString();
  await save(path.join(state, 'sources.json'), { pulled_at, sources });
  await save(path.join(state, 'ledger.json'), { pulled_at, records, practice });
  await save(path.join(state, 'inbox.json'), { pulled_at, records: inbox });
}

export function validateAction(action, config, ledger, inbox, documents) {
  if (!object(action)) fail('outbox_invalid_action');
  switch (action.action) {
    case 'ledger_update': {
      exactKeys(action, ['action', 'record_id', 'expected_fields', 'fields']); id(action.record_id);
      const row = ledger?.records?.find(r => r.record_id === action.record_id);
      if (!row || !object(action.expected_fields) || !isDeepStrictEqual(row.snapshot, action.expected_fields)) fail('outbox_invalid_baseline');
      validateFields(action.fields, 'ledger', config);
      break;
    }
    case 'ledger_create':
    case 'practice_create': {
      exactKeys(action, ['action', 'records']);
      const table = action.action === 'ledger_create' ? 'ledger' : 'practice';
      if (!Array.isArray(action.records) || action.records.length < 1 || action.records.length > (table === 'ledger' ? 30 : 200)) fail('outbox_invalid_batch');
      const required = table === 'ledger' ? ['知识点', '科目', '掌握度', '连对', '错次', '下次复习'] : Object.keys(SCHEMA.practice);
      for (const fields of action.records) validateFields(fields, table, config, required);
      break;
    }
    case 'inbox_mark':
      exactKeys(action, ['action', 'record_id', 'date']); id(action.record_id);
      if (!validDate(action.date)) fail('outbox_invalid_date');
      if (!inbox?.records?.some(r => r.record_id === action.record_id && r.fields.状态 === '待入账')) fail('outbox_invalid_record_id');
      break;
    case 'doc_write':
      exactKeys(action, ['action', 'date', 'content']);
      if (!validDate(action.date)) fail('outbox_invalid_date');
      if (typeof action.content !== 'string' || !action.content.startsWith(`# 学习单 ${action.date}`) || action.content.includes('\0')) fail('outbox_invalid_document');
      if (Object.hasOwn(documents, action.date) &&
          (!object(documents[action.date]) || documents[action.date].created_by !== 'feishu_tutor_sync' ||
           typeof documents[action.date].token !== 'string' ||
           !/^[A-Za-z0-9_-]+$/u.test(documents[action.date].token))) fail('document_not_owned');
      break;
    default: fail('outbox_invalid_action');
  }
}

async function loadBatch(config, state) {
  const outbox = path.join(state, 'outbox');
  await mkdir(outbox, { recursive: true });
  const names = (await readdir(outbox)).filter(n => n.endsWith('.json')).sort();
  const ledger = await exists(path.join(state, 'ledger.json')) ? await json(path.join(state, 'ledger.json')) : null;
  const inbox = await exists(path.join(state, 'inbox.json')) ? await json(path.join(state, 'inbox.json')) : null;
  const docFile = path.join(state, 'sync-owned', 'documents.json');
  const documents = await exists(docFile) ? await json(docFile) : {};
  if (!object(documents)) fail('document_not_owned');
  const batch = [], targets = new Set(); let createCount = 0;
  for (const name of names) {
    const stat = await lstat(path.join(outbox, name));
    if (!stat.isFile() || stat.size > 1024 * 1024) fail('outbox_invalid_file');
    if (await exists(path.join(outbox, 'done', name))) fail('outbox_already_done');
    const action = await json(path.join(outbox, name));
    validateAction(action, config, ledger, inbox, documents);
    const target = action.record_id ? `${action.action}:${action.record_id}` : action.action === 'doc_write' ? `doc:${action.date}` : null;
    if (target && targets.has(target)) fail('outbox_duplicate_target');
    if (target) targets.add(target);
    if (action.action === 'ledger_create') createCount += action.records.length;
    batch.push({ name, action });
  }
  if (createCount > 30) fail('outbox_invalid_batch');
  return { batch, ledger, inbox, documents, docFile };
}

async function perform(config, state, action, context) {
  if (action.action === 'doc_write') {
    const known = context.documents[action.date];
    const data = await callCli(config, known ? 'doc_append' : 'doc_create', known ? { doc: known.token } : {}, action.content);
    if (data?.warnings?.length) fail('write_unconfirmed');
    if (!known) {
      const token = data?.document?.document_id;
      if (typeof token !== 'string' || !/^[A-Za-z0-9_-]+$/u.test(token)) fail('write_unconfirmed');
      context.documents[action.date] = { token, created_by: 'feishu_tutor_sync' };
      await save(context.docFile, context.documents);
    }
    return 'done';
  }
  const table = action.action.startsWith('ledger_') ? 'ledger' : action.action === 'practice_create' ? 'practice' : 'inbox';
  const params = { base: config.base_token, table: config.tables[table].name };
  if (action.action.endsWith('_create')) {
    const data = await callCli(config, 'record_create', params, { create_records: action.records.map(f => encodeFields(f, table, config)) });
    if (!Array.isArray(data?.record_id_list) || data.record_id_list.length !== action.records.length ||
        data.record_id_list.some(v => typeof v !== 'string' || !v) || data.ignored_fields && Object.keys(data.ignored_fields).length) fail('write_unconfirmed');
  } else {
    const current = (await readTable(config, table)).find(r => r.record_id === action.record_id);
    const expected = table === 'ledger' ? action.expected_fields : context.inbox.records.find(r => r.record_id === action.record_id).snapshot;
    if (!current || !isDeepStrictEqual(current.snapshot, expected)) return 'conflict';
    const fields = table === 'ledger' ? action.fields : { 状态: '已入账', 入账日期: action.date };
    const data = await callCli(config, 'record_update', params, { update_records: { [action.record_id]: encodeFields(fields, table, config) } });
    if (data?.ignored_fields && Object.keys(data.ignored_fields).length) fail('write_unconfirmed');
    // CLI update does not check record existence. Confirm the requested values.
    const after = (await readTable(config, table)).find(r => r.record_id === action.record_id);
    if (!after || Object.entries(fields).some(([k, v]) => !isDeepStrictEqual(after.fields[k], v))) fail('write_unconfirmed');
  }
  return 'done';
}

async function push(config, state, dryRun) {
  const report = { started_at: new Date().toISOString(), dry_run: dryRun, status: 'pending', results: [] };
  const reportFile = path.join(state, 'push-report.json');
  try {
    const context = await loadBatch(config, state); // Complete batch validation precedes ALL remote calls.
    const outbox = path.join(state, 'outbox');
    const inflight = path.join(outbox, 'inflight');
    if (await exists(inflight) && (await readdir(inflight)).length) fail('push_reconciliation_required');
    if (dryRun) {
      report.status = 'dry_run';
      report.results = context.batch.map(({ name }) => ({ file: name, status: 'validated' }));
    } else if (!context.batch.length) report.status = 'done';
    else {
      await check(config);
      await mkdir(inflight, { recursive: true }); await mkdir(path.join(outbox, 'done'), { recursive: true });
      // Intake acknowledgement follows the writes it acknowledges, regardless
      // of filenames. A ledger conflict must never consume its source receipt.
      const order = { ledger_update: 0, ledger_create: 1, practice_create: 2, doc_write: 3, inbox_mark: 4 };
      const ordered = [...context.batch].sort((a, b) => order[a.action.action] - order[b.action.action]);
      for (const { name, action } of ordered) {
        if (action.action === 'inbox_mark' && report.results.some(r => r.status === 'conflict')) {
          report.results.push({ file: name, status: 'conflict', error: 'record_conflict' });
          continue;
        }
        // Retain ambiguous writes outside the automatic retry queue, even after a crash.
        await rename(path.join(outbox, name), path.join(inflight, name));
        let status;
        try { status = await perform(config, state, action, context); }
        catch (error) {
          report.results.push({ file: name, status: 'uncertain', error: code(error) });
          throw error;
        }
        if (status === 'conflict') {
          await rename(path.join(inflight, name), path.join(outbox, name));
          report.results.push({ file: name, status: 'conflict', error: 'record_conflict' });
        } else {
          await rename(path.join(inflight, name), path.join(outbox, 'done', name));
          report.results.push({ file: name, status: 'done' });
        }
        await save(reportFile, report);
      }
      report.status = report.results.some(r => r.status === 'conflict') ? 'conflict' : 'done';
    }
    await save(reportFile, report);
    return report.status === 'conflict' ? 2 : 0;
  } catch (error) {
    report.status = 'failed'; report.error = code(error);
    await save(reportFile, report);
    throw error;
  }
}

export async function run(argv, output = console.log) {
  if (argv.length === 1 && ['--help', '-h'].includes(argv[0])) { output(HELP); return 0; }
  const [command, ...rest] = argv;
  if (!['pull', 'push', 'check'].includes(command)) fail('usage_invalid');
  const toolDirectory = fileURLToPath(new URL('../', import.meta.url));
  let configFile = path.join(toolDirectory, 'config.json'), state, dryRun = false, suppliedConfig = false;
  for (let i = 0; i < rest.length; i++) {
    if (rest[i] === '--dry-run' && command === 'push' && !dryRun) dryRun = true;
    else if (rest[i] === '--config' && rest[i + 1] && !suppliedConfig) { configFile = path.resolve(rest[++i]); suppliedConfig = true; }
    else if (rest[i] === '--state' && rest[i + 1] && !state) state = path.resolve(rest[++i]);
    else fail('usage_invalid');
  }
  if (!state) fail('usage_invalid');
  const tools = [toolDirectory, path.dirname(configFile), path.dirname(await resolvedPath(configFile))];
  await assertSeparateDirectories(path.dirname(state), tools);
  await assertSeparateDirectories(state, tools);
  const config = await json(configFile); validateConfig(config);
  await mkdir(state, { recursive: true });
  let lock;
  try { lock = await open(path.join(state, '.sync.lock'), 'wx'); }
  catch (error) {
    if (error.code !== 'EEXIST') throw error;
    let owner;
    try { owner = JSON.parse(await readFile(path.join(state, '.sync.lock'), 'utf8')); } catch { fail('sync_locked'); }
    if (Number.isSafeInteger(owner?.pid) && owner.pid > 0) {
      try { process.kill(owner.pid, 0); }
      catch (probe) { if (probe.code === 'ESRCH') fail('sync_lock_stale'); }
    }
    fail('sync_locked');
  }
  try {
    await lock.writeFile(`${JSON.stringify({ pid: process.pid, started_at: new Date().toISOString() })}\n`);
    if (command === 'push') return await push(config, state, dryRun);
    if (command === 'pull') await pull(config, state);
    else await check(config);
    output(`${command}_ok`);
    return 0;
  } finally { await lock.close(); await unlink(path.join(state, '.sync.lock')); }
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  try { process.exitCode = await run(process.argv.slice(2)); }
  catch (error) { console.error(code(error)); process.exitCode = 1; }
}
