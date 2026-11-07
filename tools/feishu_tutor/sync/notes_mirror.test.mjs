import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, mkdir, readFile, writeFile, readdir, rm, access } from 'node:fs/promises';
import path from 'node:path';
import { tmpdir } from 'node:os';
import { spawn } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { buildCommand } from './cli.mjs';
import { folderSlugs } from './notes_mirror.mjs';

const entry = fileURLToPath(new URL('./notes_mirror.mjs', import.meta.url));
// Fake lark-cli: drive files list + docs +fetch over a JSON store. Shapes follow
// the CLI 1.0.98 success envelope and the drive.files.list output schema.
const fakeSource = String.raw`
import fs from 'node:fs';
const args = process.argv.slice(2), store = JSON.parse(fs.readFileSync(process.env.TEST_NOTES_STORE, 'utf8'));
const flag = name => args.includes(name) ? args[args.indexOf(name) + 1] : '';
fs.appendFileSync(process.env.TEST_NOTES_LOG, JSON.stringify({args})+'\n');
let data;
if (args[0] === 'drive' && args[1] === 'files' && args[2] === 'list') {
  const folder = flag('--folder-token'), all = folder ? store.folders[folder] ?? [] : store.root;
  if (store.fail_list === folder) { process.stderr.write('synthetic'); process.exit(1); }
  const size = folder ? store.page_size || 200 : all.length, start = Number(flag('--page-token') || 0);
  const files = all.slice(start, start + size), more = folder && start + size < all.length;
  data = {files, has_more: !!more, ...(more ? {next_page_token: String(start + size)} : {})};
} else if (args[0] === 'docs' && args[1] === '+fetch') {
  const doc = flag('--doc');
  if (store.fail_fetch === doc) { process.stderr.write('synthetic'); process.exit(1); }
  data = {document: {document_id: doc, content: store.docs[doc]}};
} else process.exit(3);
process.stdout.write(JSON.stringify({ok: true, identity: 'user', data}));
`;

const doc = (token, name, modified) => ({token, name, type: 'docx', modified_time: String(modified), url: 'https://example.invalid/docx/' + token});
async function fixture(t) {
  const base = await mkdtemp(path.join(tmpdir(), 'notes-test-'));
  t.after(() => rm(base, {recursive: true, force: true}));
  const tool = path.join(base, 'tool'), study = path.join(base, 'study'), notes = path.join(base, 'notes');
  await mkdir(tool); await mkdir(path.join(study, 'state'), {recursive: true});
  const cli = path.join(tool, 'fake-cli.mjs'), log = path.join(base, 'calls.jsonl'), storeFile = path.join(base, 'store.json');
  await writeFile(cli, fakeSource); await writeFile(log, '');
  const config = {cli: 'lark-cli', notes: {folders: ['日记/日报', '工作']}};
  const configFile = path.join(tool, 'config.json');
  await writeFile(configFile, JSON.stringify(config));
  const store = {
    root: [{token: 'fldDiary', name: '日记/日报', type: 'folder'}, {token: 'fldWork', name: '工作', type: 'folder'},
      {token: 'fldOther', name: '学习', type: 'folder'}, doc('docRoot', '根目录散文档', 1)],
    folders: {
      fldDiary: [doc('docD1', '11-04 日记', 1730700000), {token: 'fldMonth', name: '十一月', type: 'folder'},
        {token: 'shtX', name: '表格', type: 'sheet', modified_time: '1'}],
      fldMonth: [doc('docD2', '11-05 日记', 1730800000)],
      fldWork: [doc('docW1', '周报', 1730750000)],
      fldOther: [doc('docS1', '笔记', 1)],
    },
    docs: {docD1: '今天很累', docD2: '写了周报', docW1: '# 周报\n进度', docS1: 'x', docRoot: 'y'},
  };
  await writeFile(storeFile, JSON.stringify(store));
  const env = {...process.env, FEISHU_TUTOR_CLI: cli, TEST_NOTES_STORE: storeFile, TEST_NOTES_LOG: log};
  return {
    base, tool, study, notes, configFile, config, store,
    async save() { await writeFile(storeFile, JSON.stringify(this.store)); await writeFile(configFile, JSON.stringify(this.config)); },
    async calls() { return (await readFile(log, 'utf8')).trim().split('\n').filter(Boolean).map(l => JSON.parse(l).args); },
    async clearLog() { await writeFile(log, ''); },
    async index() { return JSON.parse(await readFile(path.join(notes, 'index.json'), 'utf8')); },
    async files(dir) { return (await readdir(path.join(notes, dir))).sort(); },
    run(args = ['--config', configFile, '--state', path.join(study, 'state'), '--notes', notes]) {
      return new Promise((resolve, reject) => {
        const child = spawn(process.execPath, [entry, ...args], {env, shell: false});
        let stdout = '', stderr = ''; child.stdout.setEncoding('utf8'); child.stderr.setEncoding('utf8');
        child.stdout.on('data', s => stdout += s); child.stderr.on('data', s => stderr += s);
        child.on('error', reject); child.on('close', exit => resolve({exit, stdout, stderr}));
      });
    },
  };
}
const fetches = calls => calls.filter(a => a[1] === '+fetch').map(a => a[a.indexOf('--doc') + 1]).sort();

test('folder_list is read-only and only paginates inside a folder', () => {
  assert.deepEqual(buildCommand('folder_list', {folder: '', page: ''}), ['drive', 'files', 'list', '--as', 'user', '--format', 'json']);
  assert.deepEqual(buildCommand('folder_list', {folder: 'fldA', page: 'P2'}),
    ['drive', 'files', 'list', '--as', 'user', '--folder-token', 'fldA', '--page-size', '200', '--page-token', 'P2', '--format', 'json']);
  assert.throws(() => buildCommand('folder_list', {folder: '', page: 'P2'}), /command_not_allowed/u);
  assert.throws(() => buildCommand('folder_list', {folder: '--yes', page: ''}), /command_not_allowed/u);
});

test('folder slugs drop path separators and stay unique', () => {
  assert.deepEqual(folderSlugs(['日记/日报', '日记-日报', '工作']), ['日记-日报', '日记-日报-2', '工作']);
});

test('first run mirrors docx from the configured folders and their subfolders only', async t => {
  const f = await fixture(t);
  const result = await f.run();
  assert.equal(result.exit, 0, result.stderr);
  assert.match(result.stdout, /notes_ok fetched=3 unchanged=0 removed=0 failed=0/u);
  assert.deepEqual(await f.files('日记-日报'), ['docD1.md', 'docD2.md']);
  assert.deepEqual(await f.files('工作'), ['docW1.md']);
  const index = await f.index();
  assert.deepEqual(Object.keys(index.docs).sort(), ['docD1', 'docD2', 'docW1']);
  assert.equal(index.docs.docD2.folder, '日记/日报/十一月');
  assert.equal(index.docs.docD2.file, '日记-日报/docD2.md');
  assert.equal(index.last_run.skipped, 1);
  const text = await readFile(path.join(f.notes, '日记-日报', 'docD1.md'), 'utf8');
  assert.match(text, /^---\ntitle: "11-04 日记"\nfolder: "日记\/日报"\nurl: "https:\/\/example.invalid\/docx\/docD1"\nmodified: 2024-11-04T06:00:00.000Z\ntoken: docD1\n---\n\n今天很累\n$/u);
  const calls = await f.calls();
  assert.ok(calls.every(a => (a[0] === 'drive' && a[2] === 'list') || a[1] === '+fetch'));
  assert.deepEqual(fetches(calls), ['docD1', 'docD2', 'docW1']);
});

test('unchanged documents are not fetched again', async t => {
  const f = await fixture(t);
  await f.run(); await f.clearLog();
  const result = await f.run();
  assert.equal(result.exit, 0);
  assert.match(result.stdout, /fetched=0 unchanged=3/u);
  assert.deepEqual(fetches(await f.calls()), []);
});

test('an edited document overwrites its own file instead of adding a copy', async t => {
  const f = await fixture(t);
  await f.run(); await f.clearLog();
  f.store.folders.fldDiary[0] = doc('docD1', '11-04 日记（改）', 1730709999);
  f.store.docs.docD1 = '今天很累，补记：晚上好多了';
  await f.save();
  const result = await f.run();
  assert.match(result.stdout, /fetched=1 unchanged=2/u);
  assert.deepEqual(fetches(await f.calls()), ['docD1']);
  assert.deepEqual(await f.files('日记-日报'), ['docD1.md', 'docD2.md']);
  const text = await readFile(path.join(f.notes, '日记-日报', 'docD1.md'), 'utf8');
  assert.match(text, /title: "11-04 日记（改）"/u);
  assert.match(text, /补记：晚上好多了\n$/u);
  assert.doesNotMatch(text, /今天很累\n/u);
});

test('a document deleted in Feishu is removed locally', async t => {
  const f = await fixture(t);
  await f.run();
  f.store.folders.fldMonth = []; await f.save();
  const result = await f.run();
  assert.match(result.stdout, /removed=1/u);
  assert.deepEqual(await f.files('日记-日报'), ['docD1.md']);
  assert.ok(!('docD2' in (await f.index()).docs));
});

test('an empty listing for a folder that had documents keeps every local copy', async t => {
  const f = await fixture(t);
  await f.run();
  const before = await readFile(path.join(f.notes, 'index.json'), 'utf8');
  f.store.folders.fldWork = []; await f.save();
  const result = await f.run();
  assert.equal(result.exit, 1); assert.match(result.stderr, /notes_listing_empty/u);
  assert.deepEqual(await f.files('工作'), ['docW1.md']);
  assert.equal(await readFile(path.join(f.notes, 'index.json'), 'utf8'), before);
});

test('a failed listing writes nothing', async t => {
  const f = await fixture(t);
  f.store.fail_list = 'fldWork'; await f.save();
  const result = await f.run();
  assert.equal(result.exit, 1); assert.match(result.stderr, /cli_failed/u);
  await assert.rejects(access(path.join(f.notes, 'index.json')));
  assert.deepEqual(fetches(await f.calls()), []);
});

test('a missing folder fails before any fetch', async t => {
  const f = await fixture(t);
  f.config.notes.folders = ['日记/日报', '不存在']; await f.save();
  const result = await f.run();
  assert.equal(result.exit, 1); assert.match(result.stderr, /notes_folder_not_found/u);
  assert.deepEqual(fetches(await f.calls()), []);
});

test('one failed fetch keeps its last good copy and reports partial', async t => {
  const f = await fixture(t);
  await f.run();
  f.store.folders.fldWork[0] = doc('docW1', '周报', 1730759999);
  f.store.fail_fetch = 'docW1'; await f.save();
  const result = await f.run();
  assert.equal(result.exit, 2); assert.match(result.stderr, /notes_partial/u);
  assert.equal(await readFile(path.join(f.notes, '工作', 'docW1.md'), 'utf8').then(t => t.endsWith('# 周报\n进度\n')), true);
  assert.equal((await f.index()).docs.docW1.modified_time, '1730750000');
  delete f.store.fail_fetch; await f.save();
  const retry = await f.run();
  assert.match(retry.stdout, /fetched=1/u);
});

test('folder pagination is followed to the end', async t => {
  const f = await fixture(t);
  f.store.page_size = 1; await f.save();
  const result = await f.run();
  assert.match(result.stdout, /fetched=3/u);
  assert.ok((await f.calls()).some(a => a.includes('--page-token')));
});

test('skips without calling the CLI while feishu_sync holds its lock', async t => {
  const f = await fixture(t);
  await writeFile(path.join(f.study, 'state', '.sync.lock'), JSON.stringify({pid: process.pid}));
  const result = await f.run();
  assert.equal(result.exit, 0); assert.match(result.stdout, /notes_skipped_sync_busy/u);
  assert.equal((await f.calls()).length, 0);
});

test('a stale mirror lock from a crashed run is replaced; a live one blocks', async t => {
  const f = await fixture(t);
  await mkdir(f.notes, {recursive: true});
  await writeFile(path.join(f.notes, '.mirror.lock'), JSON.stringify({pid: 2 ** 22 + 12345}));
  assert.equal((await f.run()).exit, 0);
  await writeFile(path.join(f.notes, '.mirror.lock'), JSON.stringify({pid: process.pid}));
  const blocked = await f.run();
  assert.equal(blocked.exit, 1); assert.match(blocked.stderr, /notes_locked/u);
});

for (const layout of ['inside_study', 'inside_tool', 'contains_tool']) test(`rejects a notes directory overlapping other roots: ${layout}`, async t => {
  const f = await fixture(t);
  const notes = layout === 'inside_study' ? path.join(f.study, 'notes') : layout === 'inside_tool' ? path.join(f.tool, 'notes') : f.base;
  const result = await f.run(['--config', f.configFile, '--state', path.join(f.study, 'state'), '--notes', notes]);
  assert.equal(result.exit, 1); assert.match(result.stderr, /daily_layout_invalid/u);
  assert.equal((await f.calls()).length, 0);
});

test('requires notes folders in config and both directories', async t => {
  const f = await fixture(t);
  assert.match((await f.run(['--config', f.configFile, '--notes', f.notes])).stderr, /usage_invalid/u);
  delete f.config.notes; await f.save();
  assert.match((await f.run()).stderr, /notes_config_invalid/u);
  assert.equal((await f.calls()).length, 0);
});
