import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, mkdir, readFile, writeFile, readdir, rm, access, symlink } from 'node:fs/promises';
import path from 'node:path';
import { tmpdir } from 'node:os';
import { spawn } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { COMMANDS, buildCommand, callCli, resolveCli } from './cli.mjs';
import { assertSeparateDirectories } from './layout.mjs';
import { SCHEMA, OPTIONS, decodeRow } from './schema.mjs';

const entry = fileURLToPath(new URL('./feishu_sync.mjs', import.meta.url));
const fakeSource = String.raw`
import fs from 'node:fs';
import path from 'node:path';
const args = process.argv.slice(2), store = JSON.parse(fs.readFileSync(process.env.TEST_FEISHU_STORE, 'utf8'));
const flag = name => args[args.indexOf(name) + 1];
const files = args.filter(v => v.startsWith('@')).map(arg => ({arg, bytes:fs.readFileSync(arg.slice(1)).toString('base64')}));
const lock = process.env.TEST_FEISHU_LOCK && fs.existsSync(process.env.TEST_FEISHU_LOCK) ? JSON.parse(fs.readFileSync(process.env.TEST_FEISHU_LOCK,'utf8')) : null;
fs.appendFileSync(process.env.TEST_FEISHU_LOG, JSON.stringify({args,files,lock,cwd:process.cwd(),no_proxy:process.env.LARK_CLI_NO_PROXY})+'\n');
const command = args[0] === 'whoami' ? 'whoami' : args[1];
const table = flag('--table-id');
let data = {};
if (store.fail === command) { process.stderr.write('synthetic upstream failure'); process.exit(1); }
if (command === '+table-get') data = {table:{name:table}};
if (command === '+field-list') data = {fields:store.fields[table]};
if (command === '+record-list') {
  const offset = Number(flag('--offset')), all = store.rows[table], count = store.page_size || 2000;
  const rows = all.slice(offset, offset+count), more = offset+rows.length < all.length;
  fs.writeFileSync(flag('--output'), rows.map(r=>JSON.stringify(r)+'\n').join(''));
  fs.writeFileSync(path.basename(flag('--output'),'.ndjson')+'.manifest.json',JSON.stringify({
    records_count:store.bad_count ? rows.length+1 : rows.length,has_more:more,
    next_offset:store.bad_offset ? offset : offset+rows.length,rev:store.changed_rev && offset ? 2 : 1,
    query_context:{table_id:table}
  }));
}
if (command === '+record-batch-create') {
  const payload = JSON.parse(fs.readFileSync(flag('--json').slice(1),'utf8'));
  const ids = payload.create_records.map((fields,i)=>{
    const record_id = 'recCreated'+store.counter++;
    store.rows[table].push({record_id,...fields});return record_id;
  });
  data = {record_id_list:ids};
}
if (command === '+record-batch-update') {
  const payload = JSON.parse(fs.readFileSync(flag('--json').slice(1),'utf8'));
  if (!store.ignore_update) for (const [id,fields] of Object.entries(payload.update_records)) {
    const row = store.rows[table].find(r=>r.record_id===id);if(row) Object.assign(row,fields);
  }
  data = store.ignore_update ? {ignored_fields:['synthetic']} : {};
}
if (command === '+fetch') data = {document:{document_id:'TEST_SOURCE',content:'# 语法\n原始资料'}};
if (command === '+create' || command === '+update') data = {document:{document_id:'TEST_CREATED_DOC'},warnings:[]};
fs.writeFileSync(process.env.TEST_FEISHU_STORE, JSON.stringify(store));
process.stdout.write(JSON.stringify({ok:!store.bad_ok,identity:store.bot?'bot':'user',data}));
`;
const ledgerFields = { 知识点: 'て形', 科目: '日语', 来源: '[语法](https://example.invalid/docx/note)',
  掌握度: '未学', 最近结果: '不会', 连对: 0, 错次: 1, 上次练习: '2026-10-23', 下次复习: '2026-10-24', 备注: '待复习' };
const practiceFields = { 时间: '2026-10-24T06:30:00+08:00', 知识点: 'て形', 科目: '日语', 结果: '错',
  纠正: '言う → 言って → 特例', 渠道: 'dot', 学习单日期: '2026-10-24' };
const sourceRow = { record_id: 'recLedger', ...ledgerFields, 科目: ['日语'], 掌握度: ['未学'], 最近结果: ['不会'] };
const inboxRow = { record_id: 'recInbox', 内容: '语音错点', 渠道: ['手动'], 状态: ['待入账'], 入账日期: null };

async function fixture(t) {
  const base = await mkdtemp(path.join(tmpdir(), 'feishu-test-'));
  t.after(async () => { assert.equal(path.dirname(base), path.resolve(tmpdir())); await rm(base, { recursive: true, force: true }); });
  const root = path.join(base, 'study'), tool = path.join(base, 'tool');
  await mkdir(tool); await mkdir(path.join(root, 'state', 'outbox'), { recursive: true });
  const cli = path.join(tool, 'fake-cli.mjs'), log = path.join(base, 'calls.jsonl'), storeFile = path.join(base, 'store.json');
  await writeFile(cli, fakeSource); await writeFile(log, '');
  const config = { cli: 'lark-cli', base_token: 'TEST_BASE', model: 'TEST_MODEL', subjects: ['日语'],
    sources: [{title:'语法',doc:'TEST_SOURCE'}], tables: {} };
  const fields = {};
  for (const [table, schema] of Object.entries(SCHEMA)) {
    config.tables[table] = { name: table, fields: Object.fromEntries(Object.keys(schema).map(k=>[k,k])) };
    fields[table] = Object.entries(schema).map(([name,type])=>({name,type,...(type==='select'?{
      multiple:false,options:(name==='科目'?config.subjects:OPTIONS[name]).map(name=>({name}))}: {})}));
  }
  const store = { fields, rows: { ledger: [structuredClone(sourceRow)], practice: [], inbox: [structuredClone(inboxRow)] }, counter: 0 };
  const configFile = path.join(tool, 'config.json');
  await writeFile(configFile, JSON.stringify(config)); await writeFile(storeFile, JSON.stringify(store));
  const env = {...process.env,TEST_FEISHU_STORE:storeFile,TEST_FEISHU_LOG:log};
  env.FEISHU_TUTOR_CLI = cli;
  env.TEST_FEISHU_LOCK = path.join(root,'state','.sync.lock');
  const f = {
    root, tool, configFile, config, store, env,
    async storeSave() { await writeFile(storeFile,JSON.stringify(store)); },
    async savedStore() { return JSON.parse(await readFile(storeFile,'utf8')); },
    async put(name, action) { await writeFile(path.join(root,'state','outbox',name),JSON.stringify(action)); },
    async calls() { return (await readFile(log,'utf8')).trim().split('\n').filter(Boolean).map(l=>JSON.parse(l)); },
    async clearLog() { await writeFile(log,''); },
    async report() { return JSON.parse(await readFile(path.join(root,'state','push-report.json'),'utf8')); },
    async run(...args) {
      return this.invoke([...args,'--config',configFile,'--state',path.join(root,'state')]);
    },
    async invoke(args) {
      return new Promise((resolve,reject)=>{
        const child = spawn(process.execPath,[entry,...args],{env,shell:false});
        let stdout='',stderr='';child.stdout.setEncoding('utf8');child.stderr.setEncoding('utf8');
        child.stdout.on('data',s=>stdout+=s);child.stderr.on('data',s=>stderr+=s);
        child.on('error',reject);child.on('close',exit=>resolve({exit,stdout,stderr}));
      });
    },
    update(fields={连对:1}) { return {action:'ledger_update',record_id:'recLedger',expected_fields:decodeRow(sourceRow,'ledger',config).snapshot,fields}; },
  };
  return f;
}
const writes = calls => calls.filter(c=>['+record-batch-create','+record-batch-update','+create','+update'].includes(c.args[1]));
const create = () => ({action:'ledger_create',records:[structuredClone(ledgerFields)]});

test('sync requires --state before reading config or calling CLI', async t => {
  const f=await fixture(t);
  const result=await f.invoke(['check','--config',f.configFile]);
  assert.equal(result.exit,1);assert.match(result.stderr,/usage_invalid/u);
  assert.equal((await f.calls()).length,0);
});

for (const layout of ['same','tool_inside_study','study_inside_tool']) test(`Node sync rejects overlapping directories: ${layout}`,async t=>{
  const f=await fixture(t);
  const study=layout==='same'?f.tool:layout==='tool_inside_study'?path.dirname(f.tool):path.join(f.tool,'nested-study');
  const result=await f.invoke(['pull','--config',f.configFile,'--state',path.join(study,'state')]);
  assert.equal(result.exit,1);assert.match(result.stderr,/daily_layout_invalid/u);
  assert.equal((await f.calls()).length,0);
});

test('Node layout resolves junctions and missing state ancestors',async t=>{
  const f=await fixture(t), alias=path.join(path.dirname(f.root),'alias');
  await symlink(f.tool,alias,process.platform==='win32'?'junction':'dir');
  await assert.rejects(assertSeparateDirectories(path.join(alias,'missing'),[f.tool]),/daily_layout_invalid/u);
  await assertSeparateDirectories(f.root,[f.tool]);
});

test('state alias into tools is rejected before remote calls',async t=>{
  const f=await fixture(t), alias=path.join(f.root,'aliased-state');
  await symlink(f.tool,alias,process.platform==='win32'?'junction':'dir');
  const result=await f.invoke(['check','--config',f.configFile,'--state',alias]);
  assert.equal(result.exit,1);assert.match(result.stderr,/daily_layout_invalid/u);
  assert.equal((await f.calls()).length,0);
});

test('config alias placed in the writable study directory is rejected',async t=>{
  const f=await fixture(t), alias=path.join(f.root,'tool-alias');
  await symlink(f.tool,alias,process.platform==='win32'?'junction':'dir');
  const result=await f.invoke(['check','--config',path.join(alias,'config.json'),'--state',path.join(f.root,'state')]);
  assert.equal(result.exit,1);assert.match(result.stderr,/daily_layout_invalid/u);
  assert.equal((await f.calls()).length,0);
});

test('script CLI paths are only accepted from the test environment override',async()=>{
  const previous=process.env.FEISHU_TUTOR_CLI;
  try {
    delete process.env.FEISHU_TUTOR_CLI;
    for(const extension of ['mjs','js','cjs','JS']) await assert.rejects(resolveCli({cli:`fake.${extension}`}),/cli_invalid/u);
    process.env.FEISHU_TUTOR_CLI='fake.mjs';
    assert.deepEqual(await resolveCli({cli:'lark-cli'}),{cli:process.execPath,prefix:[path.resolve('fake.mjs')]});
    await assert.rejects(resolveCli({cli:'config-script.mjs'}),/cli_invalid/u);
  } finally { if(previous===undefined)delete process.env.FEISHU_TUTOR_CLI;else process.env.FEISHU_TUTOR_CLI=previous; }
});

test('ledger create permits omitted source and wiki sources',async t=>{
  const f=await fixture(t), withoutSource={...ledgerFields};delete withoutSource.来源;
  await f.put('a.json',{action:'ledger_create',records:[withoutSource,{...ledgerFields,来源:'[知识库](https://example.invalid/wiki/note)'}]});
  const result=await f.run('push');assert.equal(result.exit,0,result.stderr);
  const records=(await f.savedStore()).rows.ledger;
  assert.equal(Object.hasOwn(records[1],'来源'),false);
  assert.equal(records[2].来源,'[知识库](https://example.invalid/wiki/note)');
});

test('sync lock records owner pid and timestamp and releases after success',async t=>{
  const f=await fixture(t);assert.equal((await f.run('check')).exit,0);
  const lock=(await f.calls())[0].lock;
  assert.ok(Number.isSafeInteger(lock.pid)&&lock.pid>0);
  assert.ok(Number.isFinite(Date.parse(lock.started_at)));
  await assert.rejects(access(path.join(f.root,'state','.sync.lock')));
});

for(const kind of ['live','stale','malformed']) test(`existing ${kind} sync lock is retained without CLI calls`,async t=>{
  const f=await fixture(t);let pid=process.pid;
  if(kind==='stale') pid=await new Promise((resolve,reject)=>{
    const child=spawn(process.execPath,['-e',''],{shell:false});
    child.once('error',reject);child.once('close',()=>resolve(child.pid));
  });
  const lockFile=path.join(f.root,'state','.sync.lock');
  const contents=kind==='malformed'?'{':JSON.stringify({pid,started_at:new Date().toISOString()});
  await writeFile(lockFile,contents);
  await mkdir(path.join(f.root,'state','outbox','inflight'));
  await writeFile(path.join(f.root,'state','outbox','inflight','uncertain.json'),'{}');
  const result=await f.run('check');assert.equal(result.exit,1);
  assert.match(result.stderr,kind==='stale'?/sync_lock_stale/u:/sync_locked/u);
  assert.equal(await readFile(lockFile,'utf8'),contents);
  assert.deepEqual(await readdir(path.join(f.root,'state','outbox','inflight')),['uncertain.json']);
  assert.equal((await f.calls()).length,0);
});

test('closed command builder enumerates every allowed operation', () => {
  const cases = {
    whoami:[{},['whoami']],record_list:[{base:'TEST_BASE',table:'ledger',offset:0},['base','+record-list']],
    table_get:[{base:'TEST_BASE',table:'ledger'},['base','+table-get']],field_list:[{base:'TEST_BASE',table:'ledger'},['base','+field-list']],
    record_create:[{base:'TEST_BASE',table:'ledger',file:'payload.json'},['base','+record-batch-create']],
    record_update:[{base:'TEST_BASE',table:'ledger',file:'payload.json'},['base','+record-batch-update']],
    doc_fetch:[{doc:'TEST_DOC'},['docs','+fetch']],doc_create:[{file:'content.md'},['docs','+create']],
    doc_append:[{doc:'TEST_DOC',file:'content.md'},['docs','+update']],
  };
  assert.ok(Object.isFrozen(COMMANDS));
  assert.deepEqual([...COMMANDS].sort(),Object.keys(cases).sort());
  for (const [op,[params,prefix]] of Object.entries(cases)) {
    const args=buildCommand(op,params);assert.deepEqual(args.slice(0,prefix.length),prefix);
    assert.ok(!args.some(v=>/^(?:\+)?(?:delete|remove|clear|config|auth|role|permission|member)(?:-|$)/u.test(v)));
    assert.deepEqual(args.slice(prefix.length,prefix.length+2),['--as','user']);
    if(op==='doc_append') assert.equal(args[args.indexOf('--command')+1],'append');
    for(const badKey of ['command','args','flags','shell','auth','config']) assert.throws(()=>buildCommand(op,{...params,[badKey]:'delete'}),/command_not_allowed/u);
  }
  for(const word of ['delete','remove','clear','config','auth','permissions','members']) {
    for(const prefix of ['', '+', 'base ', 'docs ', 'base +', 'docs +', 'ledger_', 'doc_']) {
      assert.throws(()=>buildCommand(prefix+word,{}),/command_not_allowed/u);
    }
    for(const op of COMMANDS) for(const suffix of ['_'+word,' '+word,'\n'+word]) assert.throws(()=>buildCommand(op+suffix),/command_not_allowed/u);
  }
  for(const invalid of ['--config','@file','line\nbreak','x\0x']) assert.throws(()=>buildCommand('doc_fetch',{doc:invalid}),/command_not_allowed/u);
  assert.throws(()=>buildCommand('record_list',{base:'B',table:'T',offset:-1}),/command_not_allowed/u);
  assert.throws(()=>buildCommand('record_create',{base:'B',table:'T',file:'../outside'}),/command_not_allowed/u);
});

test('pull reads all three tables and sources; paginates and filters inbox', async t => {
  const f=await fixture(t);f.store.page_size=1;
  f.store.rows.ledger.push({...sourceRow,record_id:'recTwo'});
  f.store.rows.inbox.push({...inboxRow,record_id:'recDone',状态:['已入账']});await f.storeSave();
  assert.equal((await f.run('pull')).exit,0);
  const ledger=JSON.parse(await readFile(path.join(f.root,'state','ledger.json'),'utf8'));
  const inbox=JSON.parse(await readFile(path.join(f.root,'state','inbox.json'),'utf8'));
  assert.equal(ledger.records.length,2);assert.deepEqual(ledger.practice,[]);
  assert.equal(inbox.records.length,1);assert.equal(inbox.pulled_at,ledger.pulled_at);
  assert.deepEqual(ledger.records[0].snapshot,decodeRow(sourceRow,'ledger',f.config).snapshot);
  assert.ok((await f.calls()).some(c=>c.args[1]==='+fetch'));
  assert.equal(writes(await f.calls()).length,0);
});

test('all five actions succeed; exact UTF-8 @file bytes and done archives survive', async t => {
  const f=await fixture(t);assert.equal((await f.run('pull')).exit,0);await f.clearLog();
  const text='# 学习单 2026-10-24 日语\r\n中文「引号」 "quote" $HOME `literal`\n下一行';
  const note='中文\n"引号" $HOME `literal`';
  await f.put('01.json',create());await f.put('02.json',f.update({备注:note}));
  await f.put('03.json',{action:'practice_create',records:[practiceFields]});
  await f.put('04.json',{action:'inbox_mark',record_id:'recInbox',date:'2026-10-24'});
  await f.put('05.json',{action:'doc_write',date:'2026-10-24',content:text});
  const result=await f.run('push');assert.equal(result.exit,0,result.stderr);
  assert.equal((await f.report()).status,'done');
  assert.deepEqual((await readdir(path.join(f.root,'state','outbox','done'))).sort(),['01.json','02.json','03.json','04.json','05.json']);
  const calls=await f.calls();assert.equal(writes(calls).length,5);
  const doc=writes(calls).find(c=>c.args[1]==='+create');
  assert.deepEqual(Buffer.from(doc.files[0].bytes,'base64'),Buffer.from(text,'utf8'));
  const update=writes(calls).find(c=>c.args[1]==='+record-batch-update');
  assert.deepEqual(Buffer.from(update.files[0].bytes,'base64'),Buffer.from(JSON.stringify({update_records:{recLedger:{备注:note}}}),'utf8'));
  for(const call of calls) { assert.equal(call.no_proxy,'1');await assert.rejects(access(call.cwd)); }
  const stored=await f.savedStore();assert.deepEqual(stored.rows.inbox[0].状态,['已入账']);
  await f.put('06.json',{action:'doc_write',date:'2026-10-24',content:text});
  assert.equal((await f.run('push')).exit,0);
  const append=writes(await f.calls()).find(c=>c.args[1]==='+update');
  assert.equal(append.args[append.args.indexOf('--command')+1],'append');
  assert.equal(append.args[append.args.indexOf('--doc')+1],'TEST_CREATED_DOC');
});

const invalidCases = [
  ['unknown_action',{action:'delete'}],
  ['field',f=>f.update({非法:'x'})], ['number_negative',f=>f.update({连对:-1})],
  ['number_float',f=>f.update({错次:1.5})],['number_string',f=>f.update({连对:'1'})],
  ['number_null',f=>f.update({错次:null})],['number_unsafe',f=>f.update({错次:1e20})],
  ['mastery',f=>f.update({掌握度:'精通'})],['result',f=>f.update({最近结果:'正确'})],
  ['subject',f=>f.update({科目:'unknown'})],['select_array',f=>f.update({掌握度:['未学']})],
  ['date_format',f=>f.update({下次复习:'tomorrow'})],['date_leap',f=>f.update({下次复习:'2026-02-29'})],
  ['date_rollover',f=>f.update({上次练习:'2026-04-31'})],['date_null',f=>f.update({上次练习:null})],
  ['text_type',f=>f.update({备注:12})],['text_empty',f=>f.update({备注:''})],['text_null',f=>f.update({备注:null})],
  ['source',f=>f.update({来源:'https://example.invalid/docx/note'})],
  ['id',f=>({...f.update(),record_id:'--config'})],['baseline',f=>({...f.update(),expected_fields:{}})],
  ['extra_key',f=>({...f.update(),command:'remove'})],['batch_empty',{action:'ledger_create',records:[]}],
  ['batch_limit',{action:'ledger_create',records:Array.from({length:31},()=>ledgerFields)}],
  ['missing_field',{action:'ledger_create',records:[{知识点:'x'}]}],
  ['practice_result',{action:'practice_create',records:[{...practiceFields,结果:'好'}]}],
  ['practice_channel',{action:'practice_create',records:[{...practiceFields,渠道:'other'}]}],
  ['practice_time',{action:'practice_create',records:[{...practiceFields,时间:'2026-10-24T25:00:00Z'}]}],
  ['practice_bad_date',{action:'practice_create',records:[{...practiceFields,时间:'2026-02-30T00:00:00Z'}]}],
  ['inbox_missing',{action:'inbox_mark',record_id:'unknown',date:'2026-10-24'}],
  ['inbox_field',{action:'inbox_mark',record_id:'recInbox',date:'2026-10-24',内容:'overwrite'}],
  ['inbox_date',{action:'inbox_mark',record_id:'recInbox',date:'2026-13-01'}],
  ['doc_token',{action:'doc_write',date:'2026-10-24',content:'# 学习单 2026-10-24',token:'ARBITRARY'}],
  ['doc_header',{action:'doc_write',date:'2026-10-24',content:'# 无关文档'}],
  ['doc_date',{action:'doc_write',date:'2026-02-30',content:'# 学习单 2026-02-30'}],
];
for(const [name,value] of invalidCases) test(`whole batch rejected without any CLI call: ${name}`,async t=>{
  const f=await fixture(t);assert.equal((await f.run('pull')).exit,0);await f.clearLog();
  await f.put('01-valid.json',create());await f.put('02-invalid.json',typeof value==='function'?value(f):value);
  assert.equal((await f.run('push')).exit,1);assert.equal((await f.report()).status,'failed');
  assert.equal((await f.calls()).length,0);assert.ok((await readdir(path.join(f.root,'state','outbox'))).includes('01-valid.json'));
});

test('malformed JSON rejects entire batch before any remote call',async t=>{
  const f=await fixture(t);await f.put('01.json',create());await writeFile(path.join(f.root,'state','outbox','02.json'),'{');
  assert.equal((await f.run('push')).exit,1);assert.equal((await f.report()).error,'local_json_invalid');assert.equal((await f.calls()).length,0);
});
test('combined ledger-create limit applies across files',async t=>{
  const f=await fixture(t);for(const name of ['a.json','b.json']) await f.put(name,{action:'ledger_create',records:Array.from({length:16},()=>ledgerFields)});
  assert.equal((await f.run('push')).exit,1);assert.equal((await f.report()).error,'outbox_invalid_batch');assert.equal((await f.calls()).length,0);
});
test('phone change causes conflict, skips update, and still handles other files',async t=>{
  const f=await fixture(t);assert.equal((await f.run('pull')).exit,0);await f.clearLog();
  f.store.rows.ledger[0].备注='手机改动';await f.storeSave();
  await f.put('01.json',f.update());await f.put('02.json',create());
  assert.equal((await f.run('push')).exit,2);const report=await f.report();
  assert.equal(report.status,'conflict');assert.equal(report.results[0].error,'record_conflict');
  assert.equal(writes(await f.calls()).filter(c=>c.args[1]==='+record-batch-update').length,0);
  assert.ok((await readdir(path.join(f.root,'state','outbox'))).includes('01.json'));
  assert.deepEqual(await readdir(path.join(f.root,'state','outbox','done')),['02.json']);
});
test('inbox phone change is also preserved',async t=>{
  const f=await fixture(t);await f.run('pull');await f.clearLog();f.store.rows.inbox[0].内容='新内容';await f.storeSave();
  await f.put('a.json',{action:'inbox_mark',record_id:'recInbox',date:'2026-10-24'});
  assert.equal((await f.run('push')).exit,2);assert.equal(writes(await f.calls()).length,0);
});
test('ledger conflict cannot acknowledge an intake receipt even when its filename sorts first',async t=>{
  const f=await fixture(t);await f.run('pull');await f.clearLog();f.store.rows.ledger[0].备注='手机改动';await f.storeSave();
  await f.put('a-inbox.json',{action:'inbox_mark',record_id:'recInbox',date:'2026-10-24'});
  await f.put('z-ledger.json',f.update());
  assert.equal((await f.run('push')).exit,2);assert.equal(writes(await f.calls()).length,0);
  assert.equal((await f.report()).results.filter(r=>r.status==='conflict').length,2);
});
test('dry-run makes zero CLI calls and leaves outbox untouched',async t=>{
  const f=await fixture(t);await f.put('a.json',create());const before=await readFile(path.join(f.root,'state','outbox','a.json'));
  assert.equal((await f.run('push','--dry-run')).exit,0);assert.equal((await f.report()).status,'dry_run');
  assert.equal((await f.calls()).length,0);assert.deepEqual(await readFile(path.join(f.root,'state','outbox','a.json')),before);
});
test('duplicate record targets reject all writes',async t=>{
  const f=await fixture(t);await f.run('pull');await f.clearLog();await f.put('a.json',f.update());await f.put('b.json',f.update());
  assert.equal((await f.run('push')).exit,1);assert.equal((await f.report()).error,'outbox_duplicate_target');assert.equal((await f.calls()).length,0);
});
test('uncertain write is retained and cannot automatically replay',async t=>{
  const f=await fixture(t);f.store.fail='+record-batch-create';await f.storeSave();await f.put('a.json',create());
  assert.equal((await f.run('push')).exit,1);assert.deepEqual(await readdir(path.join(f.root,'state','outbox','inflight')),['a.json']);
  await f.clearLog();assert.equal((await f.run('push')).exit,1);assert.equal((await f.report()).error,'push_reconciliation_required');assert.equal((await f.calls()).length,0);
});
for(const mode of ['bad_offset','changed_rev','bad_count']) test(`pull rejects incomplete/unstable pages: ${mode}`,async t=>{
  const f=await fixture(t);await f.run('pull');const before=await readFile(path.join(f.root,'state','ledger.json'));
  f.store.page_size=1;f.store.rows.ledger.push({...sourceRow,record_id:'recTwo'});f.store[mode]=true;await f.storeSave();
  assert.equal((await f.run('pull')).exit,1);assert.deepEqual(await readFile(path.join(f.root,'state','ledger.json')),before);
});
for(const change of ['bot','bad_ok','field_type','option','missing_field','multiselect']) test(`check fails closed: ${change}`,async t=>{
  const f=await fixture(t);
  if(['bot','bad_ok'].includes(change))f.store[change]=true;
  if(change==='field_type')f.store.fields.ledger[0].type='number';
  if(change==='option')f.store.fields.ledger.find(v=>v.name==='掌握度').options=[];
  if(change==='missing_field')f.store.fields.practice.pop();
  if(change==='multiselect')f.store.fields.inbox.find(v=>v.name==='状态').multiple=true;
  await f.storeSave();assert.equal((await f.run('check')).exit,1);assert.equal(writes(await f.calls()).length,0);
});
test('ignored fields do not archive a write as successful',async t=>{
  const f=await fixture(t);await f.run('pull');f.store.ignore_update=true;await f.storeSave();await f.put('a.json',f.update());
  assert.equal((await f.run('push')).exit,1);assert.equal((await f.report()).error,'write_unconfirmed');
  assert.deepEqual(await readdir(path.join(f.root,'state','outbox','done')),[]);
});
test('transport finally removes temporary files on subprocess failure',async t=>{
  const f=await fixture(t);f.store.fail='+create';await f.storeSave();
  const oldStore=process.env.TEST_FEISHU_STORE,oldLog=process.env.TEST_FEISHU_LOG,oldCli=process.env.FEISHU_TUTOR_CLI;
  process.env.TEST_FEISHU_STORE=f.env.TEST_FEISHU_STORE;process.env.TEST_FEISHU_LOG=f.env.TEST_FEISHU_LOG;process.env.FEISHU_TUTOR_CLI=f.env.FEISHU_TUTOR_CLI;
  try { await assert.rejects(callCli({cli:'unused'},'doc_create',{},'中文\n$ "x"'),/cli_failed/u); }
  finally { for(const [k,v] of Object.entries({TEST_FEISHU_STORE:oldStore,TEST_FEISHU_LOG:oldLog,FEISHU_TUTOR_CLI:oldCli})) {if(v===undefined)delete process.env[k];else process.env[k]=v;} }
  const calls=await f.calls();assert.equal(calls.length,1);await assert.rejects(access(calls[0].cwd));
});
