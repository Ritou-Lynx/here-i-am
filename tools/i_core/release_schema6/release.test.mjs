import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { copyFileSync, mkdirSync, mkdtempSync, readFileSync, readdirSync, rmSync, unlinkSync, writeFileSync } from 'node:fs';
import { realpathSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { syntheticRoot, syntheticFixedNode } from '../test_fixtures/release_schema6/synthetic_paths.mjs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { DatabaseSync } from 'node:sqlite';
import test, { before, after } from 'node:test';
import { ICoreStore } from '../i_core_store.mjs';
import { DOMAIN_SCHEMA_SQL, assertDomainSchemaReady } from '../domain_schema.mjs';
import { cleanEnvironment, prepareRelease, readCommittedSources, verifyInventory, verifyRelease, sha256, INVENTORY } from './package.mjs';
import { digest, inspectInputs, preflight } from './preflight.mjs';

const here = path.dirname(fileURLToPath(import.meta.url));
const repository = path.resolve(here, '../../..');
let node;
const gitExecPath = spawnSync('git', ['--exec-path'], { encoding: 'utf8', windowsHide: true }).stdout?.trim();
const git = process.platform === 'win32' ? path.resolve(gitExecPath, '../../../bin/git.exe') : '/usr/bin/git';
let root, release, manifestHash, sourceRepository, sourceCommit, inventoryRelease, inventoryHash;
function removeOwned(directory) {
  assert.ok(path.resolve(directory).startsWith(path.resolve(root) + path.sep));
  rmSync(directory, { recursive: true, force: true });
}
function runGit(args) {
  const result = spawnSync(git, args, { windowsHide: true, encoding: 'utf8', env: cleanEnvironment() });
  assert.equal(result.status, 0, result.stderr);
  return result.stdout.trim();
}
before(() => {
  root = syntheticRoot('schema6-release-synthetic-');
  node = syntheticFixedNode(root);
  sourceRepository = path.join(root, 'fresh-git'); mkdirSync(sourceRepository);
  runGit(['init', '-q', sourceRepository]);
  for (const name of INVENTORY.filter(name => name !== 'runtime/node.exe')) {
    const target = path.join(sourceRepository, name); mkdirSync(path.dirname(target), { recursive: true });
    copyFileSync(path.join(repository, name), target);
  }
  runGit(['-C', sourceRepository, '-c', 'core.autocrlf=false', 'add', '.']);
  runGit(['-C', sourceRepository, '-c', 'user.name=Synthetic', '-c', 'user.email=synthetic@example.invalid', '-c', 'commit.gpgsign=false', 'commit', '-qm', 'synthetic release sources']);
  sourceCommit = runGit(['-C', sourceRepository, 'rev-parse', 'HEAD']);
  // Portable inventory test fixture; intentionally not a runnable release.
  inventoryRelease = path.join(root, 'inventory'); mkdirSync(inventoryRelease);
  const records = INVENTORY.map(name => {
    const content = Buffer.from('synthetic inventory ' + name);
    mkdirSync(path.dirname(path.join(inventoryRelease, name)), { recursive: true });
    writeFileSync(path.join(inventoryRelease, name), content);
    return { path: name, bytes: content.length, sha256: sha256(content) };
  });
  const manifest = Buffer.from(JSON.stringify({ format: 'i-core-schema6-preflight-candidate-v1',
    source_commit: sourceCommit, core_commit: sourceCommit, wrapper_commit: sourceCommit,
    core_schema_version: 6, runtime_profile: 'schema6-owned-lifecycle-v1', activation_supported: false,
    policy: { companion_upload_mode: 'legacy_b3', companion_reply_jobs: false, activity_enabled: false, domain_policy: 'owner_managed' }, files: records }));
  writeFileSync(path.join(inventoryRelease, 'manifest.json'), manifest); inventoryHash = sha256(manifest);
  if (process.platform === 'win32') {
    release = path.join(root, 'release');
    manifestHash = prepareRelease({ repository: sourceRepository, output: release, nodePath: node, gitPath: git }).manifest_sha256;
  }
});
after(() => {
  assert.equal(path.dirname(root), realpathSync.native(tmpdir()));
  assert.ok(path.basename(root).startsWith('schema6-release-synthetic-'));
  rmSync(root, { recursive: true, force: true });
});
function fixture(t, version = 6) {
  const directory = mkdtempSync(path.join(root, 'state-'));
  t.after(() => removeOwned(directory));
  const database = path.join(directory, 'i-core.sqlite');
  const approvals = path.join(directory, 'historical-replay-approvals.json');
  const grants = path.join(directory, 'local-transcript-grants.json');
  const store = new ICoreStore(database, { companionReplyJobsEnabled: false, companionUploadMode: 'legacy_b3' });
  const token = store.pairDevice({ device_id: 'phone-one', display_name: 'Synthetic', platform: 'android', client_version: 'test', capabilities: [] }, 'synthetic-code').device_token;
  const records = [];
  const old = Array.from({ length: 72 }, (_, index) => {
    const incoming = { sync_id: `synthetic-${index}`, origin_device_id: 'phone-one', origin_sequence: index,
      character_id: 'i', sender: 'user', content: `synthetic body ${index}`, created_at_ms: 1700000000000 + index,
      message_type: 'chat', asset_refs: [], addenda: [] };
    const existing = { ...incoming, origin_device_id: 'v3-history-0123456789abcdef0123', origin_sequence: index + 1,
      created_at_ms: incoming.created_at_ms + 123, addenda: [{ kind: 'historical_import', source: 'hereiam_v3' }] };
    records.push({ sync_id: incoming.sync_id, device_id: incoming.origin_device_id, origin_sequence: incoming.origin_sequence,
      incoming_digest: digest(incoming), existing_digest: digest(existing) });
    return existing;
  });
  store.importMessages('v3-history-0123456789abcdef0123', old);
  const approvalDocument = { version: 1, approved_replays: records };
  store.db.prepare('INSERT INTO core_metadata(key,value) VALUES(?,?)').run('historical_replay_approvals_v1', JSON.stringify(approvalDocument));
  if (version === 6) {
    store.db.exec(DOMAIN_SCHEMA_SQL);
    store.db.prepare("UPDATE core_metadata SET value='6' WHERE key='schema_version'").run();
  }
  store.close();
  const db = new DatabaseSync(database);
  db.exec('PRAGMA wal_checkpoint(TRUNCATE); PRAGMA journal_mode=DELETE'); db.close();
  writeFileSync(approvals, JSON.stringify(approvalDocument));
  writeFileSync(grants, JSON.stringify({ version: 1, grants: [{ device_id: 'phone-one', character_id: 'i', credential_sha256: sha256(token), from_created_at_ms: 1700000000000 }] }));
  const config = { format: 'schema6-preflight-v1', mode: 'legacy_b3', companion_reply_jobs: false, activity_enabled: false,
    domain_policy: 'owner_managed', database_path: database, approvals_path: approvals, grants_path: grants };
  return { directory, database, approvals, grants, records, token, config,
    mutate(sql, ...params) { const db = new DatabaseSync(database); try { db.prepare(sql).run(...params); } finally { db.close(); } },
    capture() { return inspectInputs({ config, capture: true, assertDomainReady: assertDomainSchemaReady }); },
    async anchored() {
      const baseline = await this.capture();
      return { ...config, ...Object.fromEntries(Object.entries(baseline).filter(([key]) => key.startsWith('expected_'))) };
    },
  };
}
async function check(f, config) { return inspectInputs({ config: config ?? await f.anchored(), assertDomainReady: assertDomainSchemaReady }); }
const rejects = (promise, code) => assert.rejects(promise, error => error.code === code);

for (const version of [5, 6]) test(`schema${version} exact72 preflight preserves all input bytes and never deploys`, async t => {
  const f = fixture(t, version);
  const before = [f.database, f.approvals, f.grants].map(p => sha256(readFileSync(p)));
  const filenames = readdirSync(f.directory).sort();
  const report = await check(f);
  assert.equal(report.preflight_passed, true);
  assert.equal(report.exact_bindings, 72);
  assert.equal(report.grants, 1);
  assert.equal(report.input_unchanged, true);
  assert.equal(report.deployed, false);
  assert.equal(report.deployment_ready, false);
  assert.equal(report.activation_supported, false);
  assert.equal(report.recovery_floor_verified, false);
  assert.equal(report.services_started, 0);
  assert.deepEqual([f.database, f.approvals, f.grants].map(p => sha256(readFileSync(p))), before);
  assert.deepEqual(readdirSync(f.directory).sort(), filenames);
  const text = JSON.stringify(report);
  for (const secret of [f.token, f.directory, 'phone-one', 'synthetic body', 'cursor_secret']) assert.equal(text.includes(secret), false);
});

test('same72 count but different file binding rejects', async t => {
  const f = fixture(t); const config = await f.anchored();
  const changed = f.records.map((row, i) => i ? row : { ...row, incoming_digest: 'f'.repeat(64) });
  writeFileSync(f.approvals, JSON.stringify({ version: 1, approved_replays: changed }));
  await rejects(check(f, config), 'approval_ledger_set_mismatch');
});

test('same changed72 in both sources cannot replace the independently retained anchor', async t => {
  const f = fixture(t); const config = await f.anchored();
  const document = JSON.stringify({ version: 1, approved_replays: f.records.map((row, i) => i ? row : { ...row, incoming_digest: 'f'.repeat(64) }) });
  writeFileSync(f.approvals, document);
  f.mutate('UPDATE core_metadata SET value=? WHERE key=?', document, 'historical_replay_approvals_v1');
  await rejects(check(f, config), 'trusted_anchor_mismatch');
});

for (const absent of ['file', 'ledger', 'both', 'grant']) test(`missing ${absent} rejects without repairing input`, async t => {
  const f = fixture(t); const config = await f.anchored();
  if (['file', 'both'].includes(absent)) unlinkSync(f.approvals);
  if (['ledger', 'both'].includes(absent)) f.mutate('DELETE FROM core_metadata WHERE key=?', 'historical_replay_approvals_v1');
  if (absent === 'grant') unlinkSync(f.grants);
  const before = sha256(readFileSync(f.database));
  await assert.rejects(check(f, config));
  assert.equal(sha256(readFileSync(f.database)), before);
});

test('empty and duplicate72 binding sets reject', async t => {
  const f = fixture(t);
  writeFileSync(f.approvals, JSON.stringify({ version: 1, approved_replays: [] }));
  await rejects(f.capture(), 'exact_72_bindings_required');
  writeFileSync(f.approvals, JSON.stringify({ version: 1, approved_replays: Array(72).fill(f.records[0]) }));
  await rejects(f.capture(), 'approval_duplicate_identity');
});

for (const change of ['content', 'canonical_digest', 'origin_sequence', 'server_sequence', 'missing']) test(`historical ${change} corruption rejects`, async t => {
  const f = fixture(t); const config = await f.anchored();
  if (change === 'missing') f.mutate('DELETE FROM chat_messages WHERE sync_id=?', 'synthetic-0');
  else if (change === 'server_sequence') f.mutate("UPDATE change_events SET entity_id='wrong-identity' WHERE server_sequence=1");
  else f.mutate(`UPDATE chat_messages SET ${change}=? WHERE sync_id=?`, change === 'content' ? 'changed body' : change === 'canonical_digest' ? '0'.repeat(64) : 999, 'synthetic-0');
  await assert.rejects(check(f, config));
});

for (const change of ['token', 'platform', 'identity', 'grants', 'domain']) test(`${change} change rejects`, async t => {
  const f = fixture(t); const config = await f.anchored();
  if (change === 'token') f.mutate("UPDATE devices SET token_hash=? WHERE device_id='phone-one'", 'a'.repeat(64));
  if (change === 'platform') f.mutate("UPDATE devices SET platform='external-frontend' WHERE device_id='phone-one'");
  if (change === 'identity') f.mutate("UPDATE core_metadata SET value='replaced' WHERE key='cursor_secret'");
  if (change === 'grants') writeFileSync(f.grants, readFileSync(f.grants, 'utf8') + '\n');
  if (change === 'domain') f.mutate("INSERT INTO domain_registry VALUES('unapproved','active',NULL,'{}','v1')");
  await assert.rejects(check(f, config));
});

test('wholeCore backup_read_only and live runtime claim remain blocked', async t => {
  const f = fixture(t); const config = await f.anchored();
  f.mutate("UPDATE activity_metadata SET value='backup_read_only' WHERE key='database_role'");
  await rejects(check(f, config), 'backup_activation_unsupported');
  f.mutate("UPDATE activity_metadata SET value='live' WHERE key='database_role'");
  f.mutate("UPDATE activity_runtime_claim SET runtime_id='still-running',lease_expires_at_ms=1 WHERE singleton=1");
  await rejects(check(f, config), 'activity_recovery_required');
});

test('sidecar refuses before open', async t => {
  const f = fixture(t); const config = await f.anchored();
  writeFileSync(f.database + '-wal', 'synthetic marker');
  const before = sha256(readFileSync(f.database));
  await rejects(check(f, config), 'quiescent_checkpointed_copy_required');
  assert.equal(sha256(readFileSync(f.database)), before);
});

test('illegal mode, enabled jobs/activity, widened domain config and missing anchors reject', async t => {
  const f = fixture(t); const config = await f.anchored();
  for (const patch of [{ mode: 'pr10' }, { mode: 'disabled' }, { mode: 'unknown' }, { companion_reply_jobs: true },
    { activity_enabled: true }, { domain_policy: 'all_on' }, { unexpected: true }]) {
    await rejects(check(f, { ...config, ...patch }), 'explicit_safe_config_required');
  }
  await rejects(check(f, f.config), 'explicit_safe_config_required');
});

test('portable inventory detects manifest, source, Node-byte mutations and extra file', () => {
  const release = inventoryRelease, manifestHash = inventoryHash;
  for (const relative of ['manifest.json', 'tools/i_core/i_core_store.mjs', 'runtime/node.exe']) {
    const filename = path.join(release, relative), before = readFileSync(filename);
    try { writeFileSync(filename, Buffer.concat([before, Buffer.from('\n')])); assert.throws(() => verifyInventory(release, manifestHash)); }
    finally { writeFileSync(filename, before); }
  }
  const extra = path.join(release, 'unlisted.mjs');
  try { writeFileSync(extra, ''); assert.throws(() => verifyInventory(release, manifestHash), { code: 'manifest_contract_mismatch' }); }
  finally { unlinkSync(extra); }
});

test('environment allowlist removes case-insensitive injection and runtime flags', () => {
  assert.deepEqual(cleanEnvironment({ SystemRoot: 'C:\\Windows', TEMP: 'C:\\Temp', I_CORE_COMPANION_UPLOAD_MODE: 'pr10',
    i_core_activity_admin_secret: 'secret', NODE_OPTIONS: '--require evil.js', node_path: 'evil', HTTPS_PROXY: 'evil',
    PSModulePath: 'evil', OLLAMA_HOST: 'evil', PATHEXT: '.CMD;.BAT', RANDOM_OTHER_SETTING: 'evil' }), { SystemRoot: 'C:\\Windows', TEMP: 'C:\\Temp', ...(process.platform === 'win32' ? { PATHEXT: '.EXE' } : {}) });
});

test('actual PowerShell wrapper clears inherited Node injection and is preflight-only', { skip: process.platform !== 'win32' && 'Windows PowerShell integration only' }, async t => {
  const f = fixture(t); const config = await f.anchored();
  const configPath = path.join(f.directory, 'config.json'); writeFileSync(configPath, JSON.stringify(config));
  const powershell = path.join(process.env.SystemRoot, 'System32/WindowsPowerShell/v1.0/powershell.exe');
  const args = ['-NoProfile', '-NonInteractive', '-File', path.join(release, 'tools/i_core/release_schema6/preflight_schema6.ps1'),
    '-ReleaseDirectory', release, '-ManifestSha256', manifestHash, '-ConfigurationPath', configPath, '-CompanionUploadMode', 'legacy_b3'];
  const result = spawnSync(powershell, args, { windowsHide: true, encoding: 'utf8', env: { ...process.env,
    NODE_OPTIONS: '--require this-file-must-never-load.cjs', I_CORE_COMPANION_REPLY_JOBS: '1', I_CORE_COMPANION_UPLOAD_MODE: 'pr10',
    I_CORE_ACTIVITY_ADMIN_SECRET: 'inherited-secret' } });
  assert.equal(result.status, 0, result.stderr);
  const report = JSON.parse(result.stdout.trim());
  assert.equal(report.preflight_passed, true); assert.equal(report.deployed, false); assert.equal(report.services_started, 0);
  const forbidden = spawnSync(powershell, [...args, '-Start'], { windowsHide: true, encoding: 'utf8' });
  assert.notEqual(forbidden.status, 0);
});

test('reserved origin sequence collision is rejected before anchor comparison', async t => {
  const f = fixture(t); const config = await f.anchored();
  f.mutate("INSERT INTO change_events(server_sequence,event_id,kind,entity_id,occurred_at_ms,payload_json) VALUES(999,'synthetic-collision','chat.message.upsert','other-id',1700000000000,'{}')");
  f.mutate(`INSERT INTO chat_messages
    SELECT 'other-id','phone-one',0,character_id,sender,content,created_at_ms,message_type,
      asset_refs_json,addenda_json,canonical_digest,999 FROM chat_messages WHERE sync_id='synthetic-0'`);
  await rejects(check(f, config), 'reserved_sequence_collision');
});

test('pending phone-character Core job blocks legacy transcript candidate', async t => {
  const f = fixture(t); const config = await f.anchored();
  f.mutate(`INSERT INTO companion_reply_jobs
    (job_id,trigger_sync_id,reply_sync_id,character_id,trigger_server_sequence,status,created_at_ms,updated_at_ms)
    VALUES('synthetic-job','synthetic-0','synthetic-reply','i',1,'pending',1700000000000,1700000000000)`);
  await rejects(check(f, config), 'companion_jobs_conflict');
});


test('fresh independent Git history supplies committed Core and wrappers without worker commit', () => {
  const absent = spawnSync(git, ['-C', sourceRepository, 'cat-file', '-e', '736875630f4ac682571c28adc4e0d6397bec917e^{commit}'], { windowsHide: true });
  assert.notEqual(absent.status, 0);
  const first = readCommittedSources({ repository: sourceRepository, gitPath: git });
  assert.equal(first.resolvedCommit, sourceCommit);
  const wrapper = 'tools/i_core/release_schema6/cli.mjs';
  writeFileSync(path.join(sourceRepository, wrapper), 'uncommitted source must not enter candidate');
  const second = readCommittedSources({ repository: sourceRepository, gitPath: git, sourceCommit });
  assert.deepEqual(second.content.get(wrapper), first.content.get(wrapper));
  assert.throws(() => readCommittedSources({ repository: sourceRepository, gitPath: git, sourceCommit: 'main' }), { code: 'source_commit_required' });
});

test('generic inventory cannot pass the production pinned Node release gate', () => {
  assert.equal(verifyInventory(inventoryRelease, inventoryHash).manifest.files.length, INVENTORY.length);
  assert.throws(() => verifyRelease(inventoryRelease, inventoryHash), { code: 'node_hash_mismatch' });
});

test('Windows pinned candidate from fresh history passes production preflight', { skip: process.platform !== 'win32' && 'Windows fixed executable integration only' }, async t => {
  const f = fixture(t); const config = await f.anchored();
  const report = await preflight({ release, manifestHash, config });
  assert.equal(report.preflight_passed, true); assert.equal(report.source_commit, sourceCommit);
  assert.equal(report.deployed, false);
});


test('re-anchored unsafe policy and missing owned lifecycle profile reject inventory', () => {
  const filename = path.join(inventoryRelease, 'manifest.json'), original = readFileSync(filename);
  try {
    for (const patch of [ { runtime_profile: 'unsupervised' }, { core_schema_version: 5 }, { activation_supported: true },
      { policy: { companion_upload_mode: 'pr10', companion_reply_jobs: false, activity_enabled: false, domain_policy: 'owner_managed' } },
      { policy: { companion_upload_mode: 'legacy_b3', companion_reply_jobs: true, activity_enabled: false, domain_policy: 'owner_managed' } },
      { policy: { companion_upload_mode: 'legacy_b3', companion_reply_jobs: false, activity_enabled: true, domain_policy: 'owner_managed' } },
      { policy: { companion_upload_mode: 'legacy_b3', companion_reply_jobs: false, activity_enabled: false, domain_policy: 'owner_managed', extra: true } } ]) {
      const bytes = Buffer.from(JSON.stringify({ ...JSON.parse(original), ...patch })); writeFileSync(filename, bytes);
      assert.throws(() => verifyInventory(inventoryRelease, sha256(bytes)), { code: 'manifest_contract_mismatch' });
    }
  } finally { writeFileSync(filename, original); }
});

test('committed unlisted wrapper dependency rejects a fresh source package', t => {
  const directory = path.join(root, 'unlisted-wrapper-git');
  t.after(() => removeOwned(directory));
  runGit(['clone', '-q', '--no-hardlinks', sourceRepository, directory]);
  const wrapper = path.join(directory, 'tools/i_core/release_schema6/cli.mjs');
  writeFileSync(wrapper, readFileSync(wrapper, 'utf8') + "\nimport './not-in-fixed-inventory.mjs';\n");
  runGit(['-C', directory, '-c', 'core.autocrlf=false', 'add', 'tools/i_core/release_schema6/cli.mjs']);
  runGit(['-C', directory, '-c', 'user.name=Synthetic', '-c', 'user.email=synthetic@example.invalid', '-c', 'commit.gpgsign=false', 'commit', '-qm', 'synthetic unlisted dependency']);
  assert.throws(() => readCommittedSources({ repository: directory, gitPath: git }), { code: 'unlisted_runtime_dependency' });
});
