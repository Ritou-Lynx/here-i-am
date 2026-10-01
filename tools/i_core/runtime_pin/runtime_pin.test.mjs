import assert from 'node:assert/strict';
import { spawn, spawnSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import { existsSync, mkdirSync, mkdtempSync, readdirSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { createServer } from 'node:net';
import { tmpdir } from 'node:os';
import path from 'node:path';
import test from 'node:test';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { BASELINE, NODE_SHA256, prepareRuntimePin, SOURCE_FILES } from './prepare_runtime_pin.mjs';

const here = path.dirname(fileURLToPath(import.meta.url));
const repository = path.resolve(here, '..', '..', '..');
const nodePath = 'D:\\Nodejs\\node.exe';
const powershell = path.join(process.env.SystemRoot ?? 'C:\\Windows', 'System32', 'WindowsPowerShell', 'v1.0', 'powershell.exe');
const sha256 = bytes => createHash('sha256').update(bytes).digest('hex');

function onlyWindows(t) {
  if (process.platform !== 'win32') {
    t.skip('runtime pin is a Windows-only release boundary');
    return false;
  }
  return true;
}

function sandbox(t) {
  const root = mkdtempSync(path.join(tmpdir(), 'i-core-runtime-pin-'));
  t.after(() => rmSync(root, { recursive: true, force: true }));
  return root;
}

function environment(overrides = {}) {
  return Object.fromEntries([
    ...Object.entries(process.env).filter(([name]) => !name.toUpperCase().startsWith('I_CORE_') && !['NODE_OPTIONS', 'NODE_PATH'].includes(name.toUpperCase())),
    ...Object.entries(overrides),
  ]);
}

function powerShell(args, options = {}) {
  return spawnSync(powershell, ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', ...args], {
    encoding: 'utf8',
    timeout: 20_000,
    windowsHide: true,
    ...options,
  });
}

function verifyOnly(release, manifestSha256, stateDirectory = '') {
  return powerShell([path.join(release, 'start_pinned_i_core.ps1'), '-ManifestSha256', manifestSha256, ...(stateDirectory ? ['-StateDirectory', stateDirectory] : [])]);
}

function prepare(t) {
  const root = sandbox(t);
  const release = path.join(root, 'release');
  const result = prepareRuntimePin({ repository, output: release, nodePath });
  return { root, release, ...result };
}

function seedV4(release, stateDirectory) {
  const seedPath = path.join(stateDirectory, 'seed-v4.mjs');
  const storeUrl = pathToFileURL(path.join(release, 'tools', 'i_core', 'i_core_store.mjs')).href;
  writeFileSync(seedPath, `import { ICoreStore } from ${JSON.stringify(storeUrl)};\nconst store = new ICoreStore(process.argv[2]);\nstore.close();\n`, 'utf8');
  const seeded = spawnSync(path.join(release, 'runtime', 'node.exe'), [seedPath, path.join(stateDirectory, 'i-core.sqlite')], {
    encoding: 'utf8', timeout: 20_000, windowsHide: true, env: environment(),
  });
  assert.equal(seeded.status, 0, `schema-v4 seed failed: ${seeded.stderr || seeded.stdout}`);
}

function setSchemaVersion(release, stateDirectory, version) {
  const editPath = path.join(stateDirectory, 'set-schema.mjs');
  writeFileSync(editPath, `import { DatabaseSync } from 'node:sqlite';\nconst db = new DatabaseSync(process.argv[2]);\ndb.prepare(\"UPDATE core_metadata SET value=? WHERE key='schema_version'\").run(process.argv[3]);\ndb.close();\n`, 'utf8');
  const changed = spawnSync(path.join(release, 'runtime', 'node.exe'), [editPath, path.join(stateDirectory, 'i-core.sqlite'), String(version)], {
    encoding: 'utf8', timeout: 20_000, windowsHide: true, env: environment(),
  });
  assert.equal(changed.status, 0, `schema mutation fixture failed: ${changed.stderr || changed.stdout}`);
}

function stateBytes(stateDirectory) {
  return ['', '-wal', '-shm', '-journal'].map(suffix => {
    const target = path.join(stateDirectory, `i-core.sqlite${suffix}`);
    return existsSync(target) ? readFileSync(target) : null;
  });
}

function assertNoPreflightCopies(stateDirectory) {
  assert.equal(readdirSync(stateDirectory).filter(name => name.startsWith('.runtime-preflight-')).length, 0);
}

function runGuard(release, stateDirectory) {
  return spawnSync(path.join(release, 'runtime', 'node.exe'), [path.join(release, 'verify_v4_state.mjs'), path.join(stateDirectory, 'i-core.sqlite')], {
    encoding: 'utf8', timeout: 20_000, windowsHide: true, env: environment(), cwd: path.dirname(stateDirectory),
  });
}

async function waitForWriter(child) {
  let output = '';
  await Promise.race([
    new Promise((resolve, reject) => {
      child.stdout.on('data', (chunk) => {
        output += chunk;
        if (output.includes('writer-ready')) resolve();
      });
      child.once('error', reject);
      child.once('exit', code => reject(new Error(`WAL fixture writer exited before ready: ${code}`)));
    }),
    new Promise((_, reject) => setTimeout(() => reject(new Error('WAL fixture writer timed out before ready')), 5_000)),
  ]);
}

async function freePort() {
  const server = createServer();
  await new Promise((resolve, reject) => server.once('error', reject).listen(0, '127.0.0.1', resolve));
  const { port } = server.address();
  await new Promise((resolve, reject) => server.close(error => error ? reject(error) : resolve()));
  return port;
}

async function waitForHealth(port) {
  let lastError;
  for (let attempt = 0; attempt < 50; attempt += 1) {
    try {
      const response = await fetch(`http://127.0.0.1:${port}/v1/core/health`, { signal: AbortSignal.timeout(1_000) });
      if (response.ok) return response.json();
    } catch (error) { lastError = error; }
    await new Promise(resolve => setTimeout(resolve, 100));
  }
  throw new Error(`pinned service did not become healthy: ${lastError?.message ?? 'no response'}`);
}

async function assertPortReleased(port) {
  await assert.rejects(fetch(`http://127.0.0.1:${port}/v1/core/health`, { signal: AbortSignal.timeout(1_000) }));
}

async function terminateOwnedProcess(child) {
  if (child.exitCode !== null || child.pid == null) return;
  // This is intentionally non-graceful teardown of this test's own PowerShell PID tree.
  const result = spawnSync('taskkill.exe', ['/pid', String(child.pid), '/t', '/f'], { encoding: 'utf8', timeout: 20_000, windowsHide: true });
  assert.equal(result.status, 0, `owned child tree cleanup failed: ${result.stderr || result.stdout}`);
  if (child.exitCode === null) await new Promise(resolve => child.once('exit', resolve));
}

test('runtime pin freezes every packaged source blob at bbb8025d', (t) => {
  if (!onlyWindows(t)) return;
  const { release, manifest_sha256: manifestSha256 } = prepare(t);
  const manifest = JSON.parse(readFileSync(path.join(release, 'manifest.json'), 'utf8'));
  assert.equal(manifest.source_commit, BASELINE);
  assert.equal(manifest.core_schema_version, 4);
  assert.equal(sha256(readFileSync(nodePath)), NODE_SHA256);
  const wrapper = readFileSync(path.join(release, 'start_pinned_i_core.ps1'), 'utf8');
  assert.match(wrapper, /Get-ChildItem Env: \| Where-Object \{ \$_.Name -like 'I_CORE_\*' \}/);
  assert.match(wrapper, /Remove-Item Env:NODE_OPTIONS/);
  for (const source of SOURCE_FILES) {
    const entry = manifest.files.find(file => file.path === source);
    assert.ok(entry, `manifest must include ${source}`);
    const baseline = spawnSync('git', ['-C', repository, 'show', `${BASELINE}:${source}`], { encoding: null, windowsHide: true });
    const blob = spawnSync('git', ['-C', repository, 'rev-parse', `${BASELINE}:${source}`], { encoding: 'utf8', windowsHide: true });
    assert.equal(baseline.status, 0);
    assert.equal(blob.status, 0);
    assert.equal(entry.source_blob, blob.stdout.trim());
    assert.equal(entry.sha256, sha256(baseline.stdout));
    assert.deepEqual(readFileSync(path.join(release, source)), baseline.stdout);
  }
  assert.equal(verifyOnly(release, manifestSha256).status, 0);
});

test('verify-only, content tamper, and manifest mismatch never open or create external state', (t) => {
  if (!onlyWindows(t)) return;
  const { root, release, manifest_sha256: manifestSha256 } = prepare(t);
  const absentState = path.join(root, 'absent-state');
  const verified = verifyOnly(release, manifestSha256, absentState);
  assert.equal(verified.status, 0, verified.stderr);
  assert.equal(existsSync(absentState), false);

  writeFileSync(path.join(release, 'manifest.json'), '\n', { flag: 'a' });
  const manifestMismatch = verifyOnly(release, manifestSha256, absentState);
  assert.notEqual(manifestMismatch.status, 0);
  assert.match(manifestMismatch.stderr, /manifest hash mismatch/i);
  assert.equal(existsSync(absentState), false);

  const content = prepare(t);
  writeFileSync(path.join(content.release, 'tools', 'i_core', 'i_core_server.mjs'), '// synthetic tamper\n', { flag: 'a' });
  const rejected = verifyOnly(content.release, content.manifest_sha256, absentState);
  assert.notEqual(rejected.status, 0);
  assert.match(rejected.stderr, /Release content mismatch|manifest hash mismatch/i);
  assert.equal(existsSync(absentState), false);
});

test('schema-v4 guard rejects missing and schema-v5 state without modifying either', (t) => {
  if (!onlyWindows(t)) return;
  const { root, release, manifest_sha256: manifestSha256 } = prepare(t);
  const missing = path.join(root, 'missing-state');
  mkdirSync(missing);
  const missingResult = powerShell([path.join(release, 'start_pinned_i_core.ps1'), '-ManifestSha256', manifestSha256, '-Start', '-StateDirectory', missing, '-CorePort', '48137']);
  assert.notEqual(missingResult.status, 0);
  assert.equal(existsSync(path.join(missing, 'i-core.sqlite')), false);

  const state = path.join(root, 'schema-five');
  mkdirSync(state);
  seedV4(release, state);
  setSchemaVersion(release, state, 5);
  const database = path.join(state, 'i-core.sqlite');
  const before = readFileSync(database);
  const rejected = powerShell([path.join(release, 'start_pinned_i_core.ps1'), '-ManifestSha256', manifestSha256, '-Start', '-StateDirectory', state, '-CorePort', '48138']);
  assert.notEqual(rejected.status, 0);
  assert.match(`${rejected.stderr}${rejected.stdout}`, /Schema preflight rejected|schema 4/i);
  assert.deepEqual(readFileSync(database), before);
});

test('guard rejects a schema-v5 write still resident in WAL and leaves all source bytes untouched', async (t) => {
  if (!onlyWindows(t)) return;
  const { root, release } = prepare(t);
  const state = path.join(root, 'wal-schema-five');
  mkdirSync(state);
  seedV4(release, state);
  const writerPath = path.join(state, 'hold-schema-five-in-wal.mjs');
  writeFileSync(writerPath, [
    "import { DatabaseSync } from 'node:sqlite';",
    "const db = new DatabaseSync(process.argv[2]);",
    "db.exec('PRAGMA journal_mode=WAL');",
    "db.prepare(\"UPDATE core_metadata SET value='5' WHERE key='schema_version'\").run();",
    "console.log('writer-ready');",
    'setInterval(() => {}, 1_000);',
  ].join('\n'), 'utf8');
  const writer = spawn(path.join(release, 'runtime', 'node.exe'), [writerPath, path.join(state, 'i-core.sqlite')], {
    env: environment(), cwd: root, windowsHide: true, stdio: ['ignore', 'pipe', 'pipe'],
  });
  try {
    await waitForWriter(writer);
    const before = stateBytes(state);
    assert.notEqual(before[1], null, 'fixture must retain a WAL file while its writer is open');
    const rejected = runGuard(release, state);
    assert.notEqual(rejected.status, 0);
    assert.match(`${rejected.stderr}${rejected.stdout}`, /schema 4|schema-v4/i);
    assert.deepEqual(stateBytes(state), before);
    assertNoPreflightCopies(state);
  } finally {
    await terminateOwnedProcess(writer);
  }
});

test('guard rejects a schema-4 database whose table columns were changed', (t) => {
  if (!onlyWindows(t)) return;
  const { root, release } = prepare(t);
  const state = path.join(root, 'column-tamper');
  mkdirSync(state);
  seedV4(release, state);
  const alterPath = path.join(state, 'alter-devices.mjs');
  writeFileSync(alterPath, "import { DatabaseSync } from 'node:sqlite';\nconst db = new DatabaseSync(process.argv[2]);\ndb.exec('ALTER TABLE devices ADD COLUMN synthetic_tamper TEXT');\ndb.close();\n", 'utf8');
  const altered = spawnSync(path.join(release, 'runtime', 'node.exe'), [alterPath, path.join(state, 'i-core.sqlite')], {
    encoding: 'utf8', timeout: 20_000, windowsHide: true, env: environment(), cwd: root,
  });
  assert.equal(altered.status, 0, altered.stderr);
  const before = stateBytes(state);
  const rejected = runGuard(release, state);
  assert.notEqual(rejected.status, 0);
  assert.match(`${rejected.stderr}${rejected.stdout}`, /table columns|schema 4/i);
  assert.deepEqual(stateBytes(state), before);
  assertNoPreflightCopies(state);
});

test('pinned v4 start clears inherited enablement and holds its external runtime lock', async (t) => {
  if (!onlyWindows(t)) return;
  const { root, release, manifest_sha256: manifestSha256 } = prepare(t);
  const state = path.join(root, 'state');
  mkdirSync(state);
  seedV4(release, state);
  writeFileSync(path.join(state, 'shortcut-mail-relay.enabled'), 'synthetic enable marker\n');
  writeFileSync(path.join(state, 'shortcut-mail-relay.json'), JSON.stringify({
    workflow: 'ios_shortcut_test_v0', token_hash: 'a'.repeat(64), token_expires_at_ms: 4102444800000,
    receiver_hint: 'test@example.invalid', smtp: { use_ssl: true },
  }));
  const port = await freePort();
  const child = spawn(powershell, ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', path.join(release, 'start_pinned_i_core.ps1'), '-ManifestSha256', manifestSha256, '-Start', '-StateDirectory', state, '-CorePort', String(port)], {
    env: environment({
      I_CORE_PAIRING_CODE: 'synthetic-pairing-code', I_CORE_WORKER_SECRET: 'synthetic-worker-secret',
      I_CORE_ACTIVITY_ADMIN_SECRET: 'synthetic-owner-secret', NODE_OPTIONS: '--require C:\\does-not-exist.js',
    }),
    cwd: root, windowsHide: true, stdio: ['ignore', 'pipe', 'pipe'],
  });
  try {
    const health = await waitForHealth(port);
    assert.equal(health.protocol_version, '0.1');
    assert.equal(health.schema_version, 4);
    assert.equal(health.features.includes('worker_leases'), false);
    const pairing = await fetch(`http://127.0.0.1:${port}/v1/core/devices/pair`, { method: 'POST', headers: { 'x-core-protocol': '0.1' } });
    assert.equal(pairing.status, 403);
    const worker = await fetch(`http://127.0.0.1:${port}/v1/core/workers/leases`, { headers: { 'x-core-protocol': '0.1', authorization: 'Bearer synthetic-worker-secret' } });
    assert.equal(worker.status, 401);
    const receipt = await fetch(`http://127.0.0.1:${port}/v1/core/actions/shortcut-email/manual-test/receipts/synthetic`, { headers: { 'x-core-protocol': '0.1' } });
    assert.equal(receipt.status, 401);
    assert.equal(existsSync(path.join(state, 'shortcut-mail-journal.sqlite')), true);
    const second = powerShell([path.join(release, 'start_pinned_i_core.ps1'), '-ManifestSha256', manifestSha256, '-Start', '-StateDirectory', state, '-CorePort', String(await freePort())], { env: environment(), cwd: root });
    assert.notEqual(second.status, 0);
    assert.match(`${second.stderr}${second.stdout}`, /runtime is active|being rotated/i);
    assert.equal((await fetch(`http://127.0.0.1:${port}/v1/core/health`, { signal: AbortSignal.timeout(1_000) })).status, 200);
  } finally {
    await terminateOwnedProcess(child);
    await assertPortReleased(port);
  }

  const lockedState = path.join(root, 'relay-configuring');
  mkdirSync(lockedState);
  seedV4(release, lockedState);
  writeFileSync(path.join(lockedState, 'shortcut-mail-relay.enabled'), 'synthetic enable marker\n');
  writeFileSync(path.join(lockedState, 'shortcut-mail-relay.configure.lock'), 'synthetic configuration lock\n');
  writeFileSync(path.join(lockedState, 'shortcut-mail-relay.json'), JSON.stringify({
    workflow: 'ios_shortcut_test_v0', token_hash: 'b'.repeat(64), token_expires_at_ms: 4102444800000,
    receiver_hint: 'test@example.invalid', smtp: { use_ssl: true },
  }));
  const lockedPort = await freePort();
  const lockedChild = spawn(powershell, ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', path.join(release, 'start_pinned_i_core.ps1'), '-ManifestSha256', manifestSha256, '-Start', '-StateDirectory', lockedState, '-CorePort', String(lockedPort)], {
    env: environment(), cwd: root, windowsHide: true, stdio: ['ignore', 'pipe', 'pipe'],
  });
  try {
    await waitForHealth(lockedPort);
    const lockedReceipt = await fetch(`http://127.0.0.1:${lockedPort}/v1/core/actions/shortcut-email/manual-test/receipts/synthetic`, { headers: { 'x-core-protocol': '0.1' } });
    assert.equal(lockedReceipt.status, 503);
    assert.equal(existsSync(path.join(lockedState, 'shortcut-mail-journal.sqlite')), false);
  } finally {
    await terminateOwnedProcess(lockedChild);
    await assertPortReleased(lockedPort);
  }
});
