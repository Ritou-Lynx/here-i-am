import test from 'node:test';
import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import { createHash, randomUUID } from 'node:crypto';
import { createServer } from 'node:http';
import { DatabaseSync } from 'node:sqlite';
import { EventEmitter } from 'node:events';
import { mkdtemp, readFile, readdir, rm, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { setTimeout as delay } from 'node:timers/promises';
import { fileURLToPath } from 'node:url';
import { CaptureMonitor, acquireInstanceLock, defaultCodexRunner, isQuietTime, terminateWindowsTree } from './capture_sync.mjs';
import { DomainStore, DOMAIN_POLICY } from '../i_core/domain_store.mjs';
import { DOMAIN_SCHEMA_SQL } from '../i_core/domain_schema.mjs';
import { createDomainRequestHandler } from '../i_core/domain_http.mjs';
import { createPersonalDataHooks, personalDedupHooks, registerPersonalDataDomains } from '../i_core/personal_data_domains.mjs';

const canonicalJSON = value => JSON.stringify(sort(value));
const sort = value => Array.isArray(value) ? value.map(sort) : value && typeof value === 'object' ?
  Object.fromEntries(Object.keys(value).sort().map(key => [key, sort(value[key])])) : value;
const digest = value => createHash('sha256').update(canonicalJSON(value)).digest('hex');
const runProcess = (executable, args, options = {}) => new Promise((resolveRun, rejectRun) => {
  const child = spawn(executable, args, {shell:false,windowsHide:true,...options});
  const stdout = [], stderr = [];
  child.stdout?.on('data', chunk => stdout.push(chunk)); child.stderr?.on('data', chunk => stderr.push(chunk));
  child.once('error', rejectRun);
  child.once('exit', (code, signal) => resolveRun({code,signal,stdout:Buffer.concat(stdout).toString(),stderr:Buffer.concat(stderr).toString()}));
});

async function fixture(t, {failFirst = false, hang = false, verifyStatus = 200, corruptPageDigest = false, mixedSnapshot = false,
  resyncAfterBootstrap = false, omitOnResync = false, rebindOnResync = false} = {}) {
  const root = await mkdtemp(join(tmpdir(), 'hia-capture-sync-'));
  const record = {
    id: 'capture-1', revision: 1, deleted_at: null, field_meta: {text: {rev: 1}},
    provenance: {source: 'phone_quick'}, data: {text: 'PRIVATE TEST CAPTURE'},
  };
  let ackCount = 0, snapshotCalls = 0;
  const server = createServer(async (request, response) => {
    const url = new URL(request.url, 'http://127.0.0.1');
    const send = (status, body) => { response.writeHead(status, {'content-type': 'application/json'}); response.end(JSON.stringify(body)); };
    if (request.headers.authorization !== 'Bearer fake-token') return send(401, {error: {code: 'unauthenticated'}});
    if (request.method === 'GET' && url.pathname.endsWith('/snapshot')) {
      snapshotCalls++;
      const other = {...structuredClone(record),id:'capture-2',data:{...structuredClone(record.data),text:'SECOND SYNTHETIC CAPTURE'}};
      const resyncSnapshot = resyncAfterBootstrap && snapshotCalls > 1;
      const collection = omitOnResync && resyncSnapshot ? [] : mixedSnapshot ? [structuredClone(record),other] : [structuredClone(record)];
      const records = omitOnResync && resyncSnapshot ? [] : mixedSnapshot && snapshotCalls > 1 ? [other] : [structuredClone(record)];
      const hasMore = mixedSnapshot && snapshotCalls === 1;
      const snapshotId = mixedSnapshot && snapshotCalls > 1 ? 'snapshot-mixed' : resyncSnapshot ? 'snapshot-resync' : 'snapshot-1';
      return send(200, {
        snapshot_id: snapshotId, snapshot_token: snapshotCalls > 1 ? 'snapshot-token-next' : 'snapshot-token', records,
        page_digest: corruptPageDigest ? '0'.repeat(64) : digest(records), next_page_token: hasMore ? 'next-page-token' : null, has_more: hasMore,
        manifest: {core_instance_id:'fake-core',domain:'captures',principal_id:rebindOnResync && resyncSnapshot ? 'planner-rebound' : 'planner',credential_generation:1,installation_id:'install-planner',
          view_policy_version:'domain-policy-v1',namespace:'production',snapshot_id:snapshotId,schema_version:1,policy_version:'domain-policy-v1',
          created_at:'2026-10-07T00:00:00.000Z',expires_at:'2026-10-07T00:15:00.000Z',cut_sequence:collection.length,collection_digest:digest(collection),
          base_watermark:0,base_cursor:hasMore ? null : 'cursor-1',manifest_auth:'a'.repeat(64)},
      });
    }
    if (request.method === 'GET' && url.pathname.endsWith('/changes')) {
      if (resyncAfterBootstrap && snapshotCalls === 1) return send(409, {error:{code:'resync_required'}});
      return send(200, {
      records: [], next_cursor: url.searchParams.get('cursor'), has_more: false, retained_watermark: 0, policy_version: 'domain-policy-v1',
      });
    }
    if (request.method === 'GET' && url.pathname.endsWith(`/records/${record.id}`)) {
      if (verifyStatus === 410) return send(410, {error:{code:'deleted_target'},tombstone:{domain:'captures',id:record.id,revision:record.revision,deleted_at:'2026-10-07T00:04:00.000Z',merged_into:null,body_state:'purged',policy_version:'domain-policy-v1',core_instance_id:'fake-core'}});
      if (verifyStatus !== 200) return send(verifyStatus, {error:{code:verifyStatus === 404 ? 'not_found' : 'scope_forbidden'}});
      return send(200, {record, policy_version:'domain-policy-v1'});
    }
    if (request.method === 'POST' && url.pathname.endsWith('/ack')) { ackCount++; return send(200, {advanced: true}); }
    if (request.method === 'POST' && url.pathname === '/test/mark-done') {
      record.revision = 2;
      record.data.planner = {status: 'done', outputs: ['plan-1'], input_revision: 1, note: ''};
      return send(200, {ok: true});
    }
    send(404, {error: {code: 'not_found'}});
  });
  await new Promise(resolveListen => server.listen(0, '127.0.0.1', resolveListen));
  const address = server.address();
  const coreUrl = `http://127.0.0.1:${address.port}/`;
  const marker = join(root, 'codex-runs.txt');
  const fakeCodex = join(root, 'fake-codex.mjs');
  await writeFile(fakeCodex, `
    import { appendFile, readFile } from 'node:fs/promises';
    import { spawn } from 'node:child_process';
    const [base, marker, failFirst, hang] = process.argv.slice(2);
    let prior = ''; try { prior = await readFile(marker, 'utf8'); } catch {}
    await appendFile(marker, 'run\\n');
    if (hang === 'true') {
      await appendFile(marker + '.pid', String(process.pid));
      if (process.platform === 'win32') {
        const descendant = spawn(process.execPath, ['-e', 'setInterval(() => {}, 1000)'], {shell:false,windowsHide:true,stdio:'ignore'});
        await appendFile(marker + '.childpid', String(descendant.pid));
      }
      setInterval(() => {}, 1000); await new Promise(() => {});
    }
    if (failFirst === 'true' && prior === '') process.exit(7);
    const response = await fetch(new URL('/test/mark-done', base), {method:'POST',headers:{authorization:'Bearer fake-token'}});
    process.exit(response.ok ? 0 : 8);
  `, 'utf8');
  const config = {
    core_url: coreUrl,
    core_instance_id: 'fake-core',
    token_env: 'FAKE_CAPTURE_TOKEN',
    token: 'fake-token',
    plan_dir: root,
    state_file: 'state.json',
    log_file: 'logs.jsonl',
    poll_ms: 1,
    batch_ms: 180_000,
    min_interval_ms: 600_000,
    retry_base_ms: 2_000,
    retry_cap_ms: 300_000,
    request_timeout_ms: 2_000,
    quiet_start: '23:30',
    quiet_end: '07:00',
    codex_timeout_ms: hang ? 100 : 5_000,
    codex_kill_grace_ms: hang ? 2_000 : 100,
    codex: {executable: process.execPath, model: 'synthetic-test-model',
      args: [fakeCodex, coreUrl, marker, String(failFirst), String(hang), '--model', 'synthetic-test-model']},
  };
  t.after(async () => {
    await new Promise(resolveClose => server.close(resolveClose));
    await rm(root, {recursive: true, force: true});
  });
  return {config, root, marker, getAckCount: () => ackCount};
}

async function realDomainFixture(t) {
  const root = await mkdtemp(join(tmpdir(), 'hia-capture-real-'));
  const now = Date.parse('2026-10-07T00:00:00.000Z');
  const iso = new Date(now).toISOString();
  const db = new DatabaseSync(':memory:');
  db.exec("CREATE TABLE core_metadata(key TEXT PRIMARY KEY,value TEXT);INSERT INTO core_metadata VALUES('schema_version','6'),('node_id','real-core'),('cursor_secret','real-synthetic-secret');");
  db.exec(DOMAIN_SCHEMA_SQL);
  const hooks = createPersonalDataHooks({
    captureSourcesByPrincipal: {author: ['phone_quick']},
    plannerPrincipalIds: ['planner'],
    processorPrincipals: {planner: 'planner'},
  });
  const store = new DomainStore(db, {
    nodeId: 'real-core', cursorSecret: 'real-synthetic-secret', clock: () => now,
    domainHooks: hooks, dedupHooks: personalDedupHooks(), verifyAuthorization: () => true,
  });
  registerPersonalDataDomains(store, {mode: 'authoritative'});
  const authorIssued = store.configurePrincipal({principal_id:'author',device_id:'device-author',installation_id:'install-author',
    scopes:['captures:read','captures:create'],actors:['user_direct'],trusted_interactive:true,origin_device_only:true});
  const plannerIssued = store.configurePrincipal({principal_id:'planner',device_id:'device-planner',installation_id:'install-planner',
    scopes:['captures:read','captures:ack'],actors:['agent_inferred'],trusted_interactive:false,processor:'planner'});
  const author = store.authenticate(authorIssued.token);
  const captureId = randomUUID();
  const created = store.submit(author, 'captures', {
    domain_protocol_version:1,core_instance_id:'real-core',op_id:randomUUID(),schema_version:1,kind:'create',id:captureId,base_revision:0,
    created_at:iso,expires_at:new Date(now + DOMAIN_POLICY.intentTtl).toISOString(),actor:'user_direct',authorization_ref:'synthetic-authorized',
    data:{text:'REAL DOMAINSTORE SYNTHETIC CAPTURE',source:'phone_quick',recorded_at:iso},
    provenance:{source:'phone_quick',source_refs:[],import_batch_id:null},
  });
  assert.equal(created.status, 201, JSON.stringify(created));

  const handler = createDomainRequestHandler({getStore: () => store});
  const server = createServer(async (request, response) => {
    if (!await handler(request, response)) { response.writeHead(404, {'content-type':'application/json'}); response.end('{"error":{"code":"not_found"}}'); }
  });
  await new Promise(resolveListen => server.listen(0, '127.0.0.1', resolveListen));
  const coreUrl = `http://127.0.0.1:${server.address().port}/`;
  t.after(async () => {
    await new Promise(resolveClose => { server.close(resolveClose); server.closeAllConnections(); });
    db.close();
    await rm(root, {recursive:true,force:true});
  });
  const runCodex = async () => {
    const current = store.getRecord(store.authenticate(plannerIssued.token), 'captures', captureId, 'real-core').body.record;
    const response = await fetch(new URL('/v1/core/domains/captures/ops', coreUrl), {
      method:'POST',headers:{authorization:`Bearer ${plannerIssued.token}`,'content-type':'application/json'},
      body:JSON.stringify({domain_protocol_version:1,core_instance_id:'real-core',op_id:randomUUID(),schema_version:1,kind:'ack_capture',
        id:captureId,base_revision:current.revision,created_at:iso,expires_at:new Date(now + DOMAIN_POLICY.intentTtl).toISOString(),actor:'agent_inferred',
        processor:'planner',disposition:{planner:{status:'skipped',outputs:[],input_revision:current.field_meta.text.rev,note:'synthetic integration'}}}),
    });
    assert.equal(response.status, 201, await response.text());
    return {code:0,signal:null};
  };
  const config = {core_url:coreUrl,core_instance_id:'real-core',token_env:'REAL_SYNTHETIC_TOKEN',token:plannerIssued.token,plan_dir:root,
    poll_ms:1,batch_ms:1,min_interval_ms:1,request_timeout_ms:2_000,retry_base_ms:1,retry_cap_ms:10,codex_timeout_ms:2_000,codex_kill_grace_ms:100,
    quiet_start:'23:30',quiet_end:'07:00',
    codex:{executable:process.execPath,model:'synthetic-test-model',args:['--model','synthetic-test-model']}};
  return {root, db, store, plannerIssued, captureId, config, runCodex, now};
}

test('batches a pending capture, runs a fake Codex process, verifies disposition, and persists cursor', async t => {
  const f = await fixture(t);
  const monitor = new CaptureMonitor(f.config, {random: () => 0.5});
  const start = Date.parse('2026-10-07T00:00:00.000Z');
  assert.deepEqual(await monitor.tick(start), {status: 'batching', count: 1});
  assert.equal(f.getAckCount(), 0);
  assert.deepEqual(await monitor.tick(start + 180_000), {status: 'committed', count: 1});
  assert.equal(f.getAckCount(), 1);
  assert.equal((await readFile(f.marker, 'utf8')).trim(), 'run');
  const state = JSON.parse(await readFile(join(f.root, 'state.json'), 'utf8'));
  assert.equal(state.committed_cursor, 'cursor-1');
  assert.deepEqual(state.pending_ids, []);
  const log = await readFile(join(f.root, 'logs.jsonl'), 'utf8');
  assert.doesNotMatch(log, /PRIVATE TEST CAPTURE/);
});

test('persists a failed fake Codex retry across monitor restart', async t => {
  const f = await fixture(t, {failFirst: true});
  const start = Date.parse('2026-10-07T01:00:00.000Z');
  const first = new CaptureMonitor(f.config, {random: () => 0.5});
  assert.equal((await first.tick(start)).status, 'batching');
  const failed = await first.tick(start + 180_000);
  assert.equal(failed.status, 'retry');
  assert.equal(failed.delay_ms, 2_000);

  const restarted = new CaptureMonitor(f.config, {random: () => 0.5});
  assert.equal((await restarted.tick(start + 181_999)).status, 'backoff');
  assert.equal((await restarted.tick(start + 182_000)).status, 'committed');
  assert.equal((await readFile(f.marker, 'utf8')).trim().split(/\r?\n/).length, 2);
  assert.equal(f.getAckCount(), 1);
});

test('keeps an invisible 404 capture pending instead of treating it as deleted', async t => {
  const f = await fixture(t, {verifyStatus: 404});
  const monitor = new CaptureMonitor(f.config, {random: () => 0.5});
  const start = Date.parse('2026-10-07T00:00:00.000Z');
  assert.equal((await monitor.tick(start)).status, 'batching');
  const result = await monitor.tick(start + 180_000);
  assert.equal(result.status, 'retry');
  assert.equal(result.phase, 'verify');
  assert.equal(f.getAckCount(), 0);
  assert.deepEqual(monitor.state.pending_ids, ['capture-1']);
});

test('accepts only an explicit valid 410 capture tombstone as terminal', async t => {
  const f = await fixture(t, {verifyStatus: 410});
  const monitor = new CaptureMonitor(f.config, {random: () => 0.5});
  const start = Date.parse('2026-10-07T00:00:00.000Z');
  assert.equal((await monitor.tick(start)).status, 'batching');
  assert.equal((await monitor.tick(start + 180_000)).status, 'committed');
  assert.equal(f.getAckCount(), 1);
});

test('rejects a snapshot page digest mismatch before launching Codex', async t => {
  const f = await fixture(t, {corruptPageDigest: true});
  const monitor = new CaptureMonitor(f.config, {random: () => 0.5});
  const result = await monitor.tick(Date.parse('2026-10-07T00:00:00.000Z'));
  assert.equal(result.status, 'retry');
  assert.equal(result.phase, 'core');
  await assert.rejects(readFile(f.marker, 'utf8'), {code: 'ENOENT'});
  assert.equal(f.getAckCount(), 0);
});

test('rejects snapshot pagination that switches snapshot identity or binding', async t => {
  const f = await fixture(t, {mixedSnapshot:true});
  const monitor = new CaptureMonitor(f.config, {random:() => 0.5});
  const result = await monitor.tick(Date.parse('2026-10-07T00:00:00.000Z'));
  assert.equal(result.status, 'retry');
  assert.equal(result.phase, 'core');
  assert.equal(f.getAckCount(), 0);
});

test('serializes concurrent ticks in one monitor and launches one Codex process', async t => {
  const f = await fixture(t);
  const monitor = new CaptureMonitor(f.config, {random: () => 0.5});
  const start = Date.parse('2026-10-07T00:00:00.000Z');
  assert.equal((await monitor.tick(start)).status, 'batching');
  const results = await Promise.all([monitor.tick(start + 180_000), monitor.tick(start + 180_000)]);
  assert.ok(results.some(result => result.status === 'committed'));
  assert.equal((await readFile(f.marker, 'utf8')).trim().split(/\r?\n/).length, 1);
});

test('times out and reaps a hung fake Codex child', async t => {
  const f = await fixture(t, {hang: true});
  const normalized = new CaptureMonitor(f.config).config;
  const lock = await acquireInstanceLock(normalized);
  const monitor = new CaptureMonitor(f.config, {random: () => 0.5, instanceLock: lock});
  const start = Date.parse('2026-10-07T00:00:00.000Z');
  assert.equal((await monitor.tick(start)).status, 'batching');
  const running = monitor.tick(start + 180_000);
  let pid;
  for (let attempt = 0; attempt < 20; attempt++) {
    try { pid = Number(await readFile(`${f.marker}.pid`, 'utf8')); break; }
    catch (error) { if (error?.code !== 'ENOENT') throw error; await delay(10); }
  }
  assert.ok(Number.isSafeInteger(pid));
  const activeLock = JSON.parse(await readFile(normalized.lock_path, 'utf8'));
  assert.equal(activeLock.child_pid, pid);
  const result = await running;
  assert.equal(result.status, 'retry');
  assert.equal(result.phase, 'codex');
  assert.throws(() => process.kill(pid, 0), error => error?.code === 'ESRCH');
  if (process.platform === 'win32') {
    const descendantPid = Number(await readFile(`${f.marker}.childpid`, 'utf8'));
    assert.ok(Number.isSafeInteger(descendantPid));
    assert.throws(() => process.kill(descendantPid, 0), error => error?.code === 'ESRCH');
  }
  assert.equal(JSON.parse(await readFile(normalized.lock_path, 'utf8')).child_pid, null);
  assert.equal(await lock.release(), true);
  assert.equal(f.getAckCount(), 0);
});

test('does not return from a lock-registration failure until the spawned process has exited', async t => {
  const f = await fixture(t, {hang:true});
  let spawnedPid = null;
  const instanceLock = {setChildPid(pid) {
    if (pid !== null) spawnedPid = pid;
    throw Object.assign(new Error('private lock failure'), {code:'capture_sync_lock_lost'});
  }};
  const monitor = new CaptureMonitor(f.config, {random:() => 0.5,instanceLock});
  const start = Date.parse('2026-10-07T00:00:00.000Z');
  assert.equal((await monitor.tick(start)).status, 'batching');
  const result = await monitor.tick(start + 180_000);
  assert.equal(result.status, 'retry');
  assert.equal(result.phase, 'codex');
  assert.ok(Number.isSafeInteger(spawnedPid));
  assert.throws(() => process.kill(spawnedPid, 0), error => error?.code === 'ESRCH');
  assert.equal(f.getAckCount(), 0);
});

test('exclusive lock rejects a live owner and archives a valid stale owner before recovery', async t => {
  const f = await fixture(t);
  const monitor = new CaptureMonitor(f.config);
  const first = await acquireInstanceLock(monitor.config);
  await assert.rejects(acquireInstanceLock(monitor.config), error => error?.code === 'capture_sync_already_running');
  assert.equal(await first.release(), true);
  await writeFile(monitor.config.lock_path, `${JSON.stringify({version:1,pid:99999999,child_pid:null,nonce:'stale-lock',started_at:'2026-10-07T00:00:00.000Z'})}\n`, 'utf8');
  const recovered = await acquireInstanceLock(monitor.config);
  assert.equal((await readdir(f.root)).some(name => name.startsWith('.capture-sync.lock.stale-')), true);
  assert.equal(await recovered.release(), true);
});

test('refuses stale-lock recovery while the recorded Codex child is still alive', async t => {
  const f = await fixture(t);
  const monitor = new CaptureMonitor(f.config);
  await writeFile(monitor.config.lock_path, `${JSON.stringify({version:1,pid:99999999,child_pid:process.pid,nonce:'orphan-lock',started_at:'2026-10-07T00:00:00.000Z'})}\n`, 'utf8');
  await assert.rejects(acquireInstanceLock(monitor.config), error => error?.code === 'capture_sync_orphan_child_running');
});

test('serializes concurrent stale-lock recovery so a recovered live lock is never archived', async t => {
  const f = await fixture(t);
  const monitor = new CaptureMonitor(f.config);
  await writeFile(monitor.config.lock_path, `${JSON.stringify({version:1,pid:99999999,child_pid:null,nonce:'stale-race',started_at:'2026-10-07T00:00:00.000Z'})}\n`, 'utf8');
  const contenders = await Promise.allSettled([acquireInstanceLock(monitor.config), acquireInstanceLock(monitor.config)]);
  const winners = contenders.filter(result => result.status === 'fulfilled');
  assert.equal(winners.length, 1);
  const loser = contenders.find(result => result.status === 'rejected');
  assert.ok(['capture_sync_lock_recovery_busy','capture_sync_already_running'].includes(loser.reason?.code));
  const active = JSON.parse(await readFile(monitor.config.lock_path, 'utf8'));
  assert.equal(active.pid, process.pid);
  assert.equal(await winners[0].value.release(), true);
});

test('a dead recorded child still requires proof of descendant cleanup before recovery', async t => {
  const f = await fixture(t);
  const monitor = new CaptureMonitor(f.config);
  const stale = {version:1,pid:99999999,child_pid:99999998,nonce:'dead-child-unconfirmed',started_at:'2026-10-07T00:00:00.000Z'};
  await writeFile(monitor.config.lock_path, JSON.stringify(stale), 'utf8');
  await assert.rejects(acquireInstanceLock(monitor.config), error => error?.code === 'codex_tree_reap_unverified');
  assert.deepEqual(JSON.parse(await readFile(monitor.config.lock_path, 'utf8')), stale);
  assert.equal((await readdir(f.root)).some(name => name.startsWith('.capture-sync.lock.stale-')), false);
});

test('requires an absolute Codex executable and an explicit matching model argument', async t => {
  const f = await fixture(t);
  assert.throws(() => new CaptureMonitor({...f.config, codex:undefined}), /invalid_codex_command/);
  assert.throws(() => new CaptureMonitor({...f.config, codex:{...f.config.codex,model:'different-model'}}), /codex_model_not_explicit/);
  assert.throws(() => new CaptureMonitor({...f.config,codex:{...f.config.codex,
    args:['exec','--model','synthetic-test-model','--model','other-model']}}), /codex_model_not_explicit/);
  assert.throws(() => new CaptureMonitor({...f.config,codex:{...f.config.codex,
    args:['exec','--','--model','synthetic-test-model']}}), /codex_model_not_explicit/);
  assert.throws(() => new CaptureMonitor({...f.config,codex:{...f.config.codex,
    args:['exec','-msynthetic-test-model']}}), /codex_model_not_explicit/);
  assert.throws(() => new CaptureMonitor({...f.config,codex:{...f.config.codex,
    args:['exec','-m=synthetic-test-model']}}), /codex_model_not_explicit/);
  if (process.platform === 'win32') {
    assert.throws(() => new CaptureMonitor({...f.config,codex:{...f.config.codex,executable:'C:\\tools\\codex.cmd'}}), /invalid_codex_command/);
  }
});

test('Windows tree termination trusts only taskkill exit zero', async () => {
  const attempt = event => {
    const child = {pid:4242,kills:0,kill(){ this.kills++; }};
    const spawnImpl = () => {
      const killer = new EventEmitter();
      killer.kill = () => {};
      if (event) queueMicrotask(() => killer.emit(event.name, ...event.args));
      return killer;
    };
    return {child,result:terminateWindowsTree(child, 5, spawnImpl)};
  };
  const success = attempt({name:'exit',args:[0,null]});
  assert.equal(await success.result, true);
  assert.equal(success.child.kills, 0);
  const nonzero = attempt({name:'exit',args:[5,null]});
  assert.equal(await nonzero.result, false);
  assert.equal(nonzero.child.kills, 1);
  const errored = attempt({name:'error',args:[Object.assign(new Error('synthetic'),{code:'ENOENT'})]});
  assert.equal(await errored.result, false);
  assert.equal(errored.child.kills, 1);
  const timedOut = attempt(null);
  assert.equal(await timedOut.result, false);
  assert.equal(timedOut.child.kills, 1);
});

test('unverified tree reap rejects the runner without clearing its child registration', async () => {
  let registeredPid = null, exitCalls = 0;
  await assert.rejects(defaultCodexRunner({executable:process.execPath,args:['-e','setInterval(()=>{},1000)']}, {
    timeoutMs:20,killGraceMs:20,
    onSpawn:pid => { registeredPid = pid; },
    onExit:() => { exitCalls++; },
    terminateTree:async child => { child.kill('SIGKILL'); return false; },
  }), error => error?.code === 'codex_tree_reap_unverified');
  assert.ok(Number.isSafeInteger(registeredPid));
  assert.equal(exitCalls, 0);
});

test('unverified tree reap persistently blocks the monitor and lock from takeover', async t => {
  const f = await fixture(t);
  const normalized = new CaptureMonitor(f.config).config;
  const lock = await acquireInstanceLock(normalized);
  let runs = 0;
  const runCodex = async () => { runs++; throw Object.assign(new Error('synthetic reap failure'),{code:'codex_tree_reap_unverified'}); };
  const monitor = new CaptureMonitor(f.config, {runCodex,random:() => 0.5,instanceLock:lock});
  const start = Date.parse('2026-10-07T00:00:00.000Z');
  assert.equal((await monitor.tick(start)).status, 'batching');
  assert.equal((await monitor.tick(start + 180_000)).status, 'reap_required');
  assert.equal((await monitor.tick(start + 180_001)).status, 'reap_required');
  assert.equal(runs, 1);
  const persisted = JSON.parse(await readFile(normalized.state_path, 'utf8'));
  assert.equal(persisted.blocked_reason, 'codex_tree_reap_unverified');
  const lockState = JSON.parse(await readFile(normalized.lock_path, 'utf8'));
  assert.equal(lockState.reap_unverified, true);
  assert.equal(await lock.release(), false);
  await assert.rejects(acquireInstanceLock(normalized), error => error?.code === 'codex_tree_reap_unverified');
  const restarted = new CaptureMonitor(f.config, {runCodex});
  assert.equal((await restarted.tick(start + 180_002)).status, 'reap_required');
  assert.equal(runs, 1);
});

test('logs only allowlisted error codes', async t => {
  const f = await fixture(t);
  const monitor = new CaptureMonitor(f.config);
  await monitor.log('retry_scheduled', {code:'TOKEN_SHAPED_PRIVATE_VALUE'});
  const entry = JSON.parse((await readFile(join(f.root, 'logs.jsonl'), 'utf8')).trim());
  assert.equal(entry.code, 'unspecified_error');
  assert.doesNotMatch(JSON.stringify(entry), /TOKEN_SHAPED_PRIVATE_VALUE/);
});

test('resync preserves an old pending id that disappears from the new snapshot', async t => {
  const f = await fixture(t, {resyncAfterBootstrap:true,omitOnResync:true,verifyStatus:404});
  const monitor = new CaptureMonitor(f.config, {random:() => 0.5});
  const start = Date.parse('2026-10-07T00:00:00.000Z');
  assert.equal((await monitor.tick(start)).status, 'batching');
  const result = await monitor.tick(start + 180_000);
  assert.equal(result.status, 'retry');
  assert.equal(result.phase, 'verify');
  assert.deepEqual(monitor.state.pending_ids, ['capture-1']);
  assert.equal(f.getAckCount(), 0);
});

test('resync blocks for explicit rebinding when the authority binding changes', async t => {
  const f = await fixture(t, {resyncAfterBootstrap:true,rebindOnResync:true});
  const monitor = new CaptureMonitor(f.config, {random:() => 0.5});
  const start = Date.parse('2026-10-07T00:00:00.000Z');
  assert.equal((await monitor.tick(start)).status, 'batching');
  assert.equal((await monitor.tick(start + 180_000)).status, 'rebind_required');
  assert.equal((await monitor.tick(start + 180_001)).status, 'rebind_required');
  assert.deepEqual(monitor.state.pending_ids, ['capture-1']);
  await assert.rejects(readFile(f.marker, 'utf8'), {code:'ENOENT'});
  assert.equal(f.getAckCount(), 0);
});

test('real DomainStore plus domain_http validates snapshot binding/digests, capture disposition, cursor, and ack', async t => {
  const f = await realDomainFixture(t);
  const monitor = new CaptureMonitor(f.config, {runCodex:f.runCodex,random:() => 0.5});
  assert.equal((await monitor.tick(f.now)).status, 'batching');
  assert.equal((await monitor.tick(f.now + 1)).status, 'committed');
  assert.equal((await monitor.tick(f.now + 2)).status, 'idle');
  const principal = f.store.authenticate(f.plannerIssued.token);
  const record = f.store.getRecord(principal, 'captures', f.captureId, 'real-core').body.record;
  assert.equal(record.data.planner.status, 'skipped');
  assert.equal(record.data.planner.input_revision, record.field_meta.text.rev);
  const ack = f.db.prepare("SELECT cursor_sequence FROM domain_consumer_acks WHERE domain='captures' AND principal_id='planner'").get();
  assert.equal(ack.cursor_sequence, 2);
  const state = JSON.parse(await readFile(join(f.root, '.capture-sync-state.json'), 'utf8'));
  assert.equal(state.policy_version, 'domain-policy-v1');
  assert.equal(typeof state.committed_cursor, 'string');
});

test('--once exits nonzero for a persisted retry and fatal output does not echo parser details', async t => {
  const f = await fixture(t, {corruptPageDigest:true});
  const script = fileURLToPath(new URL('./capture_sync.mjs', import.meta.url));
  const configPath = join(f.root, 'once-config.json');
  await writeFile(configPath, `${JSON.stringify({enabled:true,core_url:f.config.core_url,core_instance_id:'fake-core',token_env:'FAKE_CAPTURE_TOKEN',
    plan_dir:f.root,poll_ms:1,batch_ms:1,min_interval_ms:1,request_timeout_ms:2_000,retry_base_ms:1,retry_cap_ms:10,
    codex_timeout_ms:2_000,codex_kill_grace_ms:100,quiet_start:'23:30',quiet_end:'07:00',
    codex:{executable:process.execPath,model:'synthetic-test-model',args:['--model','synthetic-test-model']}})}\n`, 'utf8');
  const retry = await runProcess(process.execPath, [script, '--config', configPath, '--once'], {
    env:{...process.env,FAKE_CAPTURE_TOKEN:'fake-token'},stdio:['ignore','pipe','pipe'],
  });
  assert.equal(retry.code, 2, retry.stderr);
  assert.equal(retry.stderr, '');
  await writeFile(configPath, '{"PRIVATE_PATH_C:\\\\secret":', 'utf8');
  const fatal = await runProcess(process.execPath, [script, '--config', configPath, '--once'], {
    env:{...process.env,FAKE_CAPTURE_TOKEN:'fake-token'},stdio:['ignore','pipe','pipe'],
  });
  assert.equal(fatal.code, 1);
  assert.equal(fatal.stderr, 'capture_sync failed.\n');
  assert.doesNotMatch(fatal.stderr, /PRIVATE_PATH|secret|position/i);
});

test('keeps a complete batch quiet overnight and runs it at the quiet-window boundary', async t => {
  const f = await fixture(t);
  const monitor = new CaptureMonitor(f.config, {random: () => 0.5});
  const start = Date.parse('2026-10-07T15:27:00.000Z');
  assert.equal((await monitor.tick(start)).status, 'batching');
  assert.equal((await monitor.tick(start + 180_000)).status, 'quiet');
  await assert.rejects(readFile(f.marker, 'utf8'), {code: 'ENOENT'});
  const morning = Date.parse('2026-10-07T23:00:00.000Z');
  assert.equal((await monitor.tick(morning)).status, 'committed');
});

test('does not start a second successful run inside the ten-minute interval', async t => {
  const f = await fixture(t);
  const monitor = new CaptureMonitor(f.config, {random: () => 0.5});
  const start = Date.parse('2026-10-07T00:00:00.000Z');
  assert.equal((await monitor.tick(start)).status, 'batching');
  monitor.state.last_success_at = '2026-10-06T23:55:00.000Z';
  await monitor.save();
  assert.equal((await monitor.tick(start + 180_000)).status, 'rate_limited');
  assert.equal((await monitor.tick(Date.parse('2026-10-07T00:05:00.000Z'))).status, 'committed');
  assert.equal((await readFile(f.marker, 'utf8')).trim(), 'run');
});

test('quiet hours cross midnight and end at 07:00', () => {
  assert.equal(isQuietTime(new Date('2026-10-07T15:30:00.000Z')), true);
  assert.equal(isQuietTime(new Date('2026-10-07T22:59:00.000Z')), true);
  assert.equal(isQuietTime(new Date('2026-10-07T23:00:00.000Z')), false);
  assert.equal(isQuietTime(new Date('2026-10-08T04:00:00.000Z')), false);
});
