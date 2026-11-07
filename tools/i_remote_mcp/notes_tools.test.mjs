import assert from 'node:assert/strict';
import {mkdirSync, mkdtempSync, rmSync, symlinkSync, writeFileSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {test} from 'node:test';
import {NOTES_TOOLS, NotesInputError, createNotesTools, loadNotesConfig, notesByDate, notesContextLines, notesDayOf} from './notes_tools.mjs';

// Same layout notes_mirror writes: <dir>/<token>.md with front matter, plus index.json (notes-v1).
const NOW = Date.parse('2026-11-07T12:00:00+08:00');
function fixture(t, docs = DOCS) {
  const dir = mkdtempSync(join(tmpdir(), 'notes-tools-'));
  t.after(() => rmSync(dir, {recursive:true, force:true}));
  const index = {format:'notes-v1', folders:[{name:'日记/日报', dir:'日记-日报'}, {name:'工作', dir:'工作'}],
    last_run:{at:'2026-11-07T03:40:00.000Z'}, docs:{}};
  for (const d of docs) {
    const file = `${d.top}/${d.token}.md`;
    mkdirSync(join(dir, d.top), {recursive:true});
    writeFileSync(join(dir, file), ['---', `title: ${JSON.stringify(d.title)}`, `folder: ${JSON.stringify(d.folder)}`, `modified: ${d.modified}`, `token: ${d.token}`, '---', '', d.body].join('\n') + '\n');
    index.docs[d.token] = {title:d.title, folder:d.folder, top:d.top, url:null, modified_time:'1', modified:d.modified, file, chars:d.body.length, synced_at:'2026-11-07T03:40:00.000Z'};
  }
  writeFileSync(join(dir, 'index.json'), JSON.stringify(index));
  return dir;
}
const DOCS = [
  {token:'docD1', title:'11-07 日记', folder:'日记/日报', top:'日记-日报', modified:'2026-11-07T02:00:00.000Z', body:'早上开会。\n下午写周报，有点累。\nTODO 给妈妈打电话'},
  {token:'docD2', title:'11-06 日记', folder:'日记/日报/十一月', top:'日记-日报', modified:'2026-11-06T19:30:00.000Z', body:'凌晨三点半还在写，算 11-06。'},
  {token:'docD3', title:'11-01 日记', folder:'日记/日报', top:'日记-日报', modified:'2026-11-01T04:00:00.000Z', body:'一周前的事'},
  {token:'docW1', title:'Q4 周报', folder:'工作', top:'工作', modified:'2026-11-06T09:00:00.000Z', body:'# 周报\n' + '进度正常。'.repeat(5000)},
];

test('tool list is read-only and matches the handlers', t => {
  const {tools, handlers} = createNotesTools({notesDir:fixture(t), now:() => NOW});
  assert.deepEqual(tools.map(x => x.name), ['notes_recent', 'notes_search', 'notes_read']);
  assert.deepEqual(Object.keys(handlers), tools.map(x => x.name));
  for (const tool of NOTES_TOOLS) { assert.equal(tool.requiredScope, 'i.read'); assert.equal(tool.annotations.readOnlyHint, true); }
});

test('the diary day starts at 04:00 Shanghai time', () => {
  assert.equal(notesDayOf(Date.parse('2026-11-07T03:59:00+08:00')), '2026-11-06');
  assert.equal(notesDayOf(Date.parse('2026-11-07T04:00:00+08:00')), '2026-11-07');
});

test('notes_recent lists the last three diary days newest first, with previews', async t => {
  const {handlers} = createNotesTools({notesDir:fixture(t), now:() => NOW});
  const r = await handlers.notes_recent({});
  assert.equal(r.today, '2026-11-07'); assert.equal(r.from, '2026-11-05');
  assert.deepEqual(r.docs.map(d => d.token), ['docD1', 'docD2', 'docW1']);
  assert.equal(r.docs[1].day, '2026-11-06');
  assert.match(r.docs[0].preview, /^早上开会。 下午写周报/);
  assert.equal(r.docs[0].top, '日记/日报'); assert.equal(r.synced_at, '2026-11-07T03:40:00.000Z');
  assert.deepEqual((await handlers.notes_recent({date:'2026-11-06', folder:'工作'})).docs.map(d => d.token), ['docW1']);
  assert.deepEqual((await handlers.notes_recent({days:7})).docs.map(d => d.token), ['docD1', 'docD2', 'docW1', 'docD3']);
});

test('notes_search matches title or body and returns a snippet', async t => {
  const {handlers} = createNotesTools({notesDir:fixture(t), now:() => NOW});
  const r = await handlers.notes_search({query:'周报'});
  assert.deepEqual(r.hits.map(h => h.token), ['docD1', 'docW1']);
  assert.match(r.hits[0].snippet, /下午写周报，有点累/);
  assert.equal(r.hits[1].in_title, true);
  assert.deepEqual((await handlers.notes_search({query:'todo', folder:'日记/日报'})).hits.map(h => h.token), ['docD1']);
  assert.equal((await handlers.notes_search({query:'不存在的词'})).hits.length, 0);
});

test('notes_read strips front matter and pages long documents', async t => {
  const {handlers} = createNotesTools({notesDir:fixture(t), now:() => NOW});
  const d = await handlers.notes_read({token:'docD1'});
  assert.equal(d.content, '早上开会。\n下午写周报，有点累。\nTODO 给妈妈打电话\n'); assert.equal(d.next_offset, null);
  const w = await handlers.notes_read({token:'docW1'});
  assert.equal([...w.content].length, 20000); assert.equal(w.next_offset, 20000);
  const rest = await handlers.notes_read({token:'docW1', offset:w.next_offset});
  assert.equal(rest.next_offset, null); assert.equal(rest.offset + [...rest.content].length, rest.total_chars);
});

test('notesByDate returns full bodies for one diary day', t => {
  const r = notesByDate(fixture(t), '2026-11-06');
  assert.deepEqual(r.docs.map(d => d.token), ['docD2', 'docW1']);
  assert.equal(r.docs[0].content, '凌晨三点半还在写，算 11-06。\n');
});

test('context lines stay short and list titles only', t => {
  const many = Array.from({length:30}, (_, i) => ({token:'d' + i, title:'很长的日记标题第' + i + '篇', folder:'工作', top:'工作',
    modified:new Date(NOW - i * 60000).toISOString(), body:'正文不进上下文'}));
  const c = notesContextLines(fixture(t, many), NOW);
  assert.ok(c.lines.join('').length <= 260, c.lines.join('').length);
  assert.match(c.lines.at(-1), /^……另有 \d+ 篇$/);
  assert.ok(!c.lines.join('').includes('正文'));
  assert.equal(notesContextLines(join(tmpdir(), 'no-such-notes-dir'), NOW), null);
});

test('rejects bad input, unknown folders and documents outside the index', async t => {
  const dir = fixture(t);
  const {handlers} = createNotesTools({notesDir:dir, now:() => NOW});
  const code = async (p, c) => assert.rejects(p, e => e instanceof NotesInputError && e.message === c);
  await code(handlers.notes_recent({days:3, date:'2026-11-06'}), 'invalid_request');
  await code(handlers.notes_recent({folder:'学习'}), 'notes_folder_not_found');
  await code(handlers.notes_recent({extra:1}), 'invalid_request');
  await code(handlers.notes_read({token:'../index'}), 'invalid_notes_token');
  await code(handlers.notes_read({token:'docNope'}), 'notes_doc_not_found');
  await code(handlers.notes_search({query:' '}), 'invalid_notes_query');
});

test('symlinked documents are refused', {skip:process.platform === 'win32'}, async t => {
  const dir = fixture(t), outside = mkdtempSync(join(tmpdir(), 'notes-outside-'));
  t.after(() => rmSync(outside, {recursive:true, force:true}));
  writeFileSync(join(outside, 'secret.md'), 'secret');
  rmSync(join(dir, '日记-日报', 'docD1.md'));
  symlinkSync(join(outside, 'secret.md'), join(dir, '日记-日报', 'docD1.md'));
  const {handlers} = createNotesTools({notesDir:dir, now:() => NOW});
  await assert.rejects(handlers.notes_read({token:'docD1'}), e => e.message === 'notes_path_forbidden');
  const s = await handlers.notes_search({query:'secret'});
  assert.equal(s.hits.length, 0);
});

test('notes.json config: absent means off, malformed fails closed', t => {
  const state = mkdtempSync(join(tmpdir(), 'notes-state-'));
  t.after(() => rmSync(state, {recursive:true, force:true}));
  assert.equal(loadNotesConfig(state), null);
  writeFileSync(join(state, 'notes.json'), JSON.stringify({format:'notes-config-v1', notes_dir:state}));
  assert.deepEqual(loadNotesConfig(state), {format:'notes-config-v1', notes_dir:state});
  writeFileSync(join(state, 'notes.json'), JSON.stringify({format:'notes-config-v1', notes_dir:'relative'}));
  assert.throws(() => loadNotesConfig(state), /notes_config_invalid/);
});
