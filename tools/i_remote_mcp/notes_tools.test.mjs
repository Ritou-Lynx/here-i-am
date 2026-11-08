import assert from 'node:assert/strict';
import {randomUUID} from 'node:crypto';
import {mkdirSync, mkdtempSync, readFileSync, rmSync, symlinkSync, writeFileSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {pathToFileURL} from 'node:url';
import {after, before, test} from 'node:test';
import {buildChatgptCandidate} from './chatgpt_candidate.mjs';
import {createFakeReadModel, PASSPHRASE, PUBLIC_URL, pkcePair, registerClient, submitPassphrase, authorizeParams, postToken, initSession, mcpPost} from './fixtures.mjs';
import {listenForFetch} from './fetch_test_listener.mjs';
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

test('a root spelled through another path (like a Windows 8.3 name) still works', {skip:process.platform === 'win32'}, async t => {
  const dir = fixture(t), alias = mkdtempSync(join(tmpdir(), 'notes-alias-'));
  t.after(() => rmSync(alias, {recursive:true, force:true}));
  symlinkSync(join(dir, '..'), join(alias, 'parent'));
  const {handlers} = createNotesTools({notesDir:join(alias, 'parent', dir.split(/[\\/]/).pop()), now:() => NOW});
  assert.equal((await handlers.notes_read({token:'docD1'})).token, 'docD1');
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

// ---------- N2: the legacy candidate inlines this module and lists the tools for four frontends ----------
let built, candidate, candidateOauth;
before(async () => {
  built = buildChatgptCandidate({outputDirectory: join('build', 'notes-candidate-' + randomUUID())});
  const load = name => import(pathToFileURL(join(built.root, 'i_remote_mcp', name + '.mjs')));
  [candidate, candidateOauth] = await Promise.all([load('server'), load('oauth')]);
});
after(() => { if (built) rmSync(built.outputRoot, {recursive: true, force: true}); });

function mcpState(t, notesDir) {
  const path = mkdtempSync(join(tmpdir(), 'notes-mcp-state-'));
  t.after(() => rmSync(path, {recursive: true, force: true}));
  if (notesDir !== undefined) writeFileSync(join(path, 'notes.json'), JSON.stringify(typeof notesDir === 'string' ? {format: 'notes-config-v1', notes_dir: notesDir} : notesDir));
  return path;
}
const callbacks = {claude_web: 'https://claude.ai/api/mcp/auth_callback', chatgpt_web: 'https://chatgpt.com/connector_platform_oauth_redirect',
  antigravity: 'http://127.0.0.1:32014/oauth/callback', gemini_web: 'https://oauth-redirect.googleusercontent.com/r/user_bound_custom-mcp-synthetic-notes',
  sesame: 'https://sesameai.app/api/oauth/external-mcp/callback'};
async function start(t, state, frontend) {
  candidateOauth.setPassphrase(state, PASSPHRASE);
  const app = candidate.createApp({stateDir: state, publicUrl: PUBLIC_URL, getReadModel: async () => createFakeReadModel(), now: () => NOW,
    chatgptEnabled: true, geminiEnabled: true, antigravityEnabled: true, sesameEnabled: true});
  await listenForFetch(app.server);
  t.after(() => new Promise(resolve => app.server.close(resolve)));
  const base = 'http://127.0.0.1:' + app.server.address().port, redirectUri = callbacks[frontend];
  const registered = await registerClient(base, [redirectUri]); assert.equal(registered.status, 201);
  const {verifier, challenge} = pkcePair();
  const auth = await submitPassphrase(base, {...Object.fromEntries(authorizeParams({clientId: registered.body.client_id, challenge})), redirect_uri: redirectUri, scope: 'i.read i.write'});
  assert.equal(auth.status, 302);
  const token = await postToken(base, {grant_type: 'authorization_code', code: new URL(auth.headers.get('location')).searchParams.get('code'),
    client_id: registered.body.client_id, redirect_uri: redirectUri, code_verifier: verifier, resource: PUBLIC_URL + '/mcp'});
  assert.equal(token.status, 200);
  const {init, sessionId} = await initSession(base, token.body.access_token); assert.equal(init.status, 200);
  let id = 2;
  const rpc = async (method, params) => {
    const response = await mcpPost(base, token.body.access_token, {jsonrpc: '2.0', id: id++, method, params}, {sessionId});
    assert.equal(response.status, 200); return response.body;
  };
  return {rpc, call: async (name, args) => (await rpc('tools/call', {name, arguments: args})).result};
}

test('N2 candidate inlines notes_tools.mjs verbatim with node-only imports', () => {
  const server = readFileSync(join(built.root, 'i_remote_mcp', 'server.mjs'), 'utf8').replaceAll('\r\n', '\n');
  const source = readFileSync(new URL('./notes_tools.mjs', import.meta.url), 'utf8').replaceAll('\r\n', '\n');
  assert.equal(server.split(source.trimEnd()).length, 2, 'notes_tools.mjs must appear exactly once, byte for byte');
  assert.deepEqual(candidate.NOTES_TOOLS, NOTES_TOOLS);
  const imports = [...source.matchAll(/(?:from\s*|import\s*\()(['"])([^'"]+)\1/g)].map(match => match[2]);
  assert.deepEqual(imports, ['node:fs', 'node:path']);
});

test('N2 four frontends list and call the notes tools; Sesame gets none', {timeout: 90000}, async t => {
  const state = mcpState(t, fixture(t));
  for (const frontend of ['claude_web', 'chatgpt_web', 'gemini_web', 'antigravity']) {
    const app = await start(t, state, frontend);
    const listed = (await app.rpc('tools/list')).result.tools;
    for (const tool of NOTES_TOOLS) {
      const actual = listed.find(item => item.name === tool.name);
      assert.ok(actual, frontend + ' lists ' + tool.name);
      assert.equal(actual.description, tool.description); assert.deepEqual(actual.inputSchema, tool.inputSchema);
    }
    const recent = await app.call('notes_recent', {});
    assert.equal(recent.isError, false, JSON.stringify(recent.structuredContent));
    assert.deepEqual(recent.structuredContent.docs.map(d => d.token), ['docD1', 'docD2', 'docW1']);
    const read = await app.call('notes_read', {token: 'docD1'});
    assert.match(read.structuredContent.content, /给妈妈打电话/);
    const missing = await app.call('notes_read', {token: 'docNope'});
    assert.equal(missing.isError, true); assert.equal(missing.structuredContent.error.code, 'notes_doc_not_found');
  }
  const sesame = await start(t, state, 'sesame');
  assert.equal((await sesame.rpc('tools/list')).result.tools.some(tool => tool.name.startsWith('notes_')), false);
});

test('N2 tools are off without notes.json and a malformed notes.json fails startup', {timeout: 60000}, async t => {
  const app = await start(t, mcpState(t), 'claude_web');
  assert.equal((await app.rpc('tools/list')).result.tools.some(tool => tool.name.startsWith('notes_')), false);
  for (const value of [{format: 'notes-config-v2', notes_dir: tmpdir()}, {format: 'notes-config-v1', notes_dir: 'relative'}, []]) {
    assert.throws(() => candidate.createApp({stateDir: mcpState(t, value), publicUrl: PUBLIC_URL, getReadModel: async () => ({})}), /^Error: notes_config_invalid$/);
  }
});
