import test from 'node:test';
import assert from 'node:assert/strict';
import http from 'node:http';
import {randomUUID} from 'node:crypto';
import {DatabaseSync} from 'node:sqlite';
import {createDomainRequestHandler} from './domain_http.mjs';
import {DOMAIN_SCHEMA_SQL} from './domain_schema.mjs';

const base = '/v1/core/domains/example';
const now = '2026-10-05T00:00:00.000Z';
function intent(overrides = {}) {
  return {domain_protocol_version: 1, core_instance_id: 'core-fixture', op_id: randomUUID(), schema_version: 1, kind: 'create', id: randomUUID(), base_revision: 0, created_at: now, expires_at: '2026-12-04T00:00:00.000Z', actor: 'agent_inferred', data: {title: 'synthetic only'}, provenance: {source: 'fixture', source_refs: [], import_batch_id: null}, ...overrides};
}
async function fixture(t, store, options = {}) {
  const calls = [];
  const fake = {authenticate(token) { calls.push(['authenticate', token]); return token === 'domain-token' ? {principal_id: 'fixture'} : null; }};
  for (const name of ['submit', 'getOperation', 'getRecord', 'changes', 'snapshot', 'acknowledge']) fake[name] = (...args) => { calls.push([name, ...args]); return {status: 200, body: {route: name}}; };
  const handler = createDomainRequestHandler({getStore: () => options.schema5 ? null : store ?? fake, authenticateDevice: token => token === 'chat-token' ? {device_id: 'legacy'} : null});
  let dropped = false;
  const server = http.createServer(async (req, res) => {
    if (options.dropFirstOpsResponse && !dropped && req.url === base + '/ops') { dropped = true; res.end = () => res.destroy(); }
    if (!await handler(req, res)) { res.writeHead(404); res.end('{"fallback":true}'); } });
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  t.after(() => new Promise(resolve => {server.close(resolve); server.closeAllConnections();}));
  const send = (path, opts = {}) => new Promise((resolve, reject) => {
    const data = opts.raw ?? (opts.body === undefined ? undefined : JSON.stringify(opts.body));
    const headers = {authorization: `Bearer ${opts.token ?? 'domain-token'}`, 'x-i-core-domain-protocol': '1', ...opts.headers};
    if (data !== undefined && !Object.hasOwn(headers, 'content-type')) headers['content-type'] = 'application/json';
    const req = http.request({host: '127.0.0.1', port: server.address().port, path, method: opts.method ?? (data === undefined ? 'GET' : 'POST'), headers, agent: false}, res => {
      const chunks = [];
      res.on('data', c => chunks.push(c));
      res.on('end', () => { try {resolve({status: res.statusCode, headers: res.headers, body: JSON.parse(Buffer.concat(chunks).toString())});} catch (error) { reject(error); } });
    });
    req.on('error', reject);
    if (opts.chunked && data !== undefined) { for (let i = 0; i < data.length; i += 8192) req.write(data.slice(i, i + 8192)); req.end(); }
    else req.end(data);
  });
  return {send, calls, fake, server};
}
const core = '?core_instance_id=core-fixture';

test('all six routes delegate only the authenticated principal and bounded arguments', async t => {
  const {send, calls} = await fixture(t);
  const op = intent();
  for (const [path, options, method] of [
    [`${base}/ops`, {body: op}, 'submit'],
    [`${base}/ops/${op.op_id}${core}`, {}, 'getOperation'],
    [`${base}/records/${op.id}${core}`, {}, 'getRecord'],
    [`${base}/changes${core}&cursor=opaque`, {}, 'changes'],
    [`${base}/snapshot${core}&limit=2&snapshot_token=s&page_token=p`, {}, 'snapshot'],
    [`${base}/ack`, {body: {domain_protocol_version: 1, core_instance_id: 'core-fixture', cursor: 'opaque'}}, 'acknowledge'],
  ]) {
    const response = await send(path, options);
    assert.equal(response.status, 200);
    assert.equal(response.body.route, method);
    assert.equal(response.headers['cache-control'], 'no-store');
    assert.equal(calls.at(-1)[1].principal_id, 'fixture');
    assert.equal(calls.at(-1)[2], 'example');
  }
  assert.equal(calls.find(c => c[0] === 'changes')[3].limit, 100);
  assert.equal(calls.find(c => c[0] === 'snapshot')[3].limit, 2);
});

test('unrelated legacy route falls through; bad domain routes never fall through', async t => {
  const {send, calls} = await fixture(t);
  assert.equal((await send('/v1/core/chat/messages')).body.fallback, true);
  for (const suffix of ['/example/unknown', '/example/records/a/b', '/example/records/%2F', '/example/records/%252f', '/example/records/%00', '/example/records/%5c', '/example/records/%', '/example/records/..', '/example/records/', '/example//changes']) {
    const response = await send(`/v1/core/domains${suffix}${core}`);
    assert.ok([400, 404].includes(response.status), suffix);
    assert.equal(response.body.fallback, undefined);
  }
  assert.equal(calls.length, 0);
});

test('known routes reject method changes with Allow and without touching engine', async t => {
  const {send, calls} = await fixture(t);
  for (const [route, method, expected] of [['ops', 'GET', 'POST'], ['records/id', 'POST', 'GET'], ['snapshot', 'DELETE', 'GET'], ['ack', 'PUT', 'POST']]) {
    const response = await send(`${base}/${route}`, {method});
    assert.equal(response.status, 405);
    assert.equal(response.headers.allow, expected);
    assert.equal(response.body.error.code, 'method_not_allowed');
  }
  assert.equal(calls.length, 0);
});

test('schema5 reports schema_not_ready without creating or upgrading a store', async t => {
  const {send, calls} = await fixture(t, null, {schema5: true});
  assert.equal((await send(`${base}/snapshot${core}`)).body.error.code, 'schema_not_ready');
  assert.equal(calls.length, 0);
});

test('legacy chat, worker, activity and forged credentials cannot enter any new domain route', async t => {
  const {send, calls} = await fixture(t);
  for (const token of ['chat-token', 'worker-token', 'activity-token', 'wrong-token']) {
    for (const path of [`ops/id${core}`, `records/id${core}`, `changes${core}`, `snapshot${core}`, 'ops', 'ack']) {
      const response = await send(`${base}/${path}`, {token, ...(path === 'ops' ? {body: intent()} : path === 'ack' ? {body: {domain_protocol_version: 1, core_instance_id: 'core-fixture', cursor: 'x'}} : {})});
      assert.equal(response.status, token === 'chat-token' ? 403 : 401);
    }
  }
  assert.ok(calls.every(c => c[0] === 'authenticate'));
});

test('GET protocol, unknown/repeated queries and malformed limits fail before lookup', async t => {
  const {send, calls} = await fixture(t);
  for (const query of ['?core_instance_id=x&core_instance_id=y', `${core}&unknown=x`, `${core}&limit=501`, `${core}&limit=0`, `${core}&limit=1.5`, `${core}&limit=NaN`, `${core}&limit=Infinity`, `${core}&limit=-1`, `${core}&limit=1e2`, `${core}&limit=`, `${core}&cursor=%`, `${core}&cursor=%ff`, '']) {
    assert.equal((await send(`${base}/changes${query}`)).status, 400, query);
  }
  assert.equal((await send(`${base}/snapshot${core}`, {headers: {'x-i-core-domain-protocol': '2'}})).body.error.code, 'protocol_mismatch');
  assert.ok(calls.every(c => c[0] === 'authenticate'));
});

test('JSON media, syntax, batch, protocol and unknown write fields fail before submit', async t => {
  const {send, calls} = await fixture(t);
  const cases = [
    [{raw: '{'}, 400, 'invalid_request'], [{body: []}, 413, 'batch_not_supported'], [{body: {ops: []}}, 413, 'batch_not_supported'],
    [{body: intent(), headers: {'content-type': 'text/plain'}}, 415, 'unsupported_media_type'],
    [{body: intent(), headers: {'content-encoding': 'gzip'}}, 415, 'unsupported_media_type'],
    [{body: intent({domain_protocol_version: 2})}, 400, 'protocol_mismatch'],
    [{body: intent({revision: 10})}, 400, 'invalid_request'],
    [{body: intent({patch: {title: 'not create'}})}, 400, 'invalid_request'],
    [{body: intent({epoch: 1})}, 400, 'unsupported_authority_feature'],
    [{body: intent({fencing_token: 'invented'})}, 400, 'unsupported_authority_feature'],
  ];
  for (const [options, status, code] of cases) {
    const response = await send(`${base}/ops`, options);
    assert.equal(response.status, status);
    assert.equal(response.body.error.code, code);
  }
  assert.equal((await send(`${base}/ack`, {body: {domain_protocol_version: 1, core_instance_id: 'core-fixture', cursor: 'opaque', actor: 'user_direct'}})).status, 400);
  assert.ok(calls.every(c => c[0] === 'authenticate'));
});

test('oversized UTF-8 and chunked bodies return 413 without a persisted operation', async t => {
  const {send, calls} = await fixture(t);
  for (const chunked of [false, true]) {
    const response = await send(`${base}/ops`, {body: intent({data: {title: '合'.repeat(100000)}}), chunked});
    assert.equal(response.status, 413);
    assert.equal(response.body.error.code, 'payload_too_large');
  }
  assert.ok(calls.every(c => c[0] === 'authenticate'));
});

test('engine exceptions expose a fixed error code, never sensitive message/details/stack', async t => {
  const {send, fake} = await fixture(t);
  fake.getRecord = () => {throw Object.assign(new Error('PRIVATE_SECRET'), {code: 'scope_forbidden', status: 403, details: {record: 'PRIVATE_SECRET'}});};
  let response = await send(`${base}/records/id${core}`);
  assert.equal(response.status, 403);
  assert.equal(JSON.stringify(response.body).includes('PRIVATE_SECRET'), false);
  fake.getRecord = () => {throw Object.assign(new Error('PRIVATE_SECRET'), {code: 'PRIVATE_SECRET', status: 500});};
  response = await send(`${base}/records/id${core}`);
  assert.equal(response.status, 500);
  assert.equal(response.body.error.code, 'internal_error');
  assert.equal(JSON.stringify(response.body).includes('PRIVATE_SECRET'), false);
});

test('duplicate JSON object members including escaped spellings and nested data are ambiguous and rejected', async t => {
  const {send, calls} = await fixture(t);
  const raw = JSON.stringify(intent());
  for (const malformed of [raw.replace('"domain_protocol_version":1', '"domain_protocol_version":1,"domain_protocol_version":1'), raw.replace('"title":"synthetic only"', '"title":"first","title":"second"'), raw.replace('"title":"synthetic only"', '"title":"first","t\\u0069tle":"second"')]) {
    assert.equal((await send(`${base}/ops`, {raw: malformed})).status, 400);
  }
  assert.ok(calls.every(c => c[0] === 'authenticate'));
});

async function realFixture(t, options = {}) {
  const {DomainStore} = await import('./domain_store.mjs');
  const db = new DatabaseSync(':memory:');
  db.exec("CREATE TABLE core_metadata (key TEXT PRIMARY KEY,value TEXT NOT NULL); INSERT INTO core_metadata VALUES ('schema_version','6'),('node_id','core-fixture'),('cursor_secret','synthetic-domain-hmac-secret-only');");
  db.exec(DOMAIN_SCHEMA_SQL);
  t.after(() => db.close());
  const authorizations = new Map();
  const store = new DomainStore(db, {nodeId: 'core-fixture', cursorSecret: 'synthetic-domain-hmac-secret-only', clock: () => Date.parse(now), verifyAuthorization: ({principal, request, targets, authorizationRef}) => {
    const expected = authorizations.get(authorizationRef);
    return !!expected && expected.principal === principal.principal_id && expected.op === request.op_id && JSON.stringify(expected.targets) === JSON.stringify(targets);
  }});
  store.registerDomain('example', {version: 1, fields: {title: {type: 'string', required: true}, status: {type: 'string'}}, statusFields: ['status']}, {mode: 'authoritative'});
  const config = {principal_id: 'fixture', device_id: 'device-fixture', installation_id: 'installation-fixture', scopes: ['read', 'create', 'patch', 'delete', 'restore', 'purge', 'status'].map(action => `example:${action}`), actors: ['agent_inferred', 'user_direct'], trusted_interactive: true};
  const {token} = store.configurePrincipal(config);
  const net = await fixture(t, store, options);
  const send = (path, opts = {}) => net.send(path, {token, ...opts});
  const operation = (kind, id, revision, fields = {}, user = false) => {
    const raw = intent({kind, id, base_revision: revision, ...fields});
    if (kind !== 'create') {delete raw.data; delete raw.provenance;}
    if (user) {
      raw.actor = 'user_direct'; raw.authorization_ref = randomUUID();
      authorizations.set(raw.authorization_ref, {principal: 'fixture', op: raw.op_id, targets: [{id, fields: Object.keys(raw.patch ?? raw.data ?? {})}]});
    }
    return raw;
  };
  return {...net, send, db, store, config, token, operation};
}
const errorCode = response => response.body.error?.code ?? response.body.error ?? response.body.problem?.code;

test('real schema6 HTTP create, patch, user conflict, duplicate, permanent delete and sanitized read/feed/op', async t => {
  const {send, db, operation} = await realFixture(t);
  const empty = await send(`${base}/snapshot${core}`);
  assert.equal(empty.status, 200);
  const start = empty.body.manifest.base_cursor;
  const create = intent();
  const created = await send(`${base}/ops`, {body: create});
  assert.equal(created.status, 201, JSON.stringify(created.body));
  assert.equal(created.body.record.revision, 1);
  const replay = await send(`${base}/ops`, {body: create});
  assert.equal(replay.status, 200);
  assert.equal(replay.body.outcome, 'duplicate');
  assert.equal(replay.body.receipt.receipt_id, created.body.receipt.receipt_id);
  const patch = operation('patch', create.id, 1, {patch: {title: 'user correction'}}, true);
  assert.equal((await send(`${base}/ops`, {body: patch})).status, 201);
  const conflict = await send(`${base}/ops`, {body: operation('patch', create.id, 1, {patch: {title: 'concurrent user'}}, true)});
  assert.equal(conflict.status, 409);
  assert.equal(errorCode(conflict), 'user_conflict');
  assert.equal(conflict.body.receipt, null);
  const record = await send(`${base}/records/${create.id}${core}`);
  assert.equal(record.body.record.data.title, 'user correction');
  assert.equal(record.body.record.revision, 2);
  const deleted = await send(`${base}/ops`, {body: operation('delete', create.id, 2, {permanent: true}, true)});
  assert.equal(deleted.status, 201, JSON.stringify(deleted.body));
  const readDeleted = await send(`${base}/records/${create.id}${core}`);
  assert.equal(readDeleted.status, 410);
  assert.equal(readDeleted.body.tombstone.body_state, 'purged');
  assert.equal(readDeleted.body.tombstone.data, undefined);
  const old = await send(`${base}/ops/${create.op_id}${core}`);
  assert.equal(old.status, 200);
  assert.equal(old.body.target_state, 'deleted');
  assert.equal(old.body.result.record, undefined);
  assert.equal((await send(`${base}/ops`, {body: create})).status, 410);
  const changes = await send(`${base}/changes${core}&cursor=${encodeURIComponent(start)}`);
  assert.equal(changes.status, 200);
  assert.equal(changes.body.records.length, 1);
  assert.equal(changes.body.records[0].revision, 3);
  assert.equal(changes.body.records[0].data, undefined);
  assert.equal(JSON.stringify([old.body, readDeleted.body, changes.body]).includes('user correction'), false);
  const ack = await send(`${base}/ack`, {body: {domain_protocol_version: 1, core_instance_id: 'core-fixture', cursor: changes.body.next_cursor}});
  assert.equal(ack.status, 200);
  assert.equal(db.prepare('SELECT COUNT(*) n FROM domain_receipts').get().n, 3);
});

test('real HTTP snapshot pages hold one read cut; complete snapshot ack and following changes recover concurrent writes', async t => {
  const {send, operation} = await realFixture(t);
  const records = [intent({data: {title: 'first'}}), intent({data: {title: 'second'}})];
  for (const raw of records) assert.equal((await send(`${base}/ops`, {body: raw})).status, 201);
  const first = await send(`${base}/snapshot${core}&limit=1`);
  assert.equal(first.status, 200);
  assert.equal(first.body.has_more, true);
  assert.equal(first.body.manifest.base_cursor, null);
  assert.equal((await send(`${base}/ops`, {body: operation('patch', records[0].id, 1, {patch: {title: 'later revision'}})})).status, 201);
  const second = await send(`${base}/snapshot${core}&limit=1&snapshot_token=${encodeURIComponent(first.body.snapshot_token)}&page_token=${encodeURIComponent(first.body.next_page_token)}`);
  assert.equal(second.status, 200, JSON.stringify(second.body));
  assert.equal(second.body.snapshot_id, first.body.snapshot_id);
  assert.equal(second.body.has_more, false);
  assert.equal(second.body.manifest.collection_digest, first.body.manifest.collection_digest);
  assert.equal([...first.body.records, ...second.body.records].every(r => r.revision === 1), true);
  const ackBody = {domain_protocol_version: 1, core_instance_id: 'core-fixture', cursor: second.body.manifest.base_cursor, snapshot_id: second.body.snapshot_id};
  assert.equal((await send(`${base}/ack`, {body: ackBody})).status, 200);
  const repeatAck = await send(`${base}/ack`, {body: ackBody});
  assert.equal(repeatAck.status, 200);
  assert.equal(repeatAck.body.advanced, false);
  const delta = await send(`${base}/changes${core}&cursor=${encodeURIComponent(second.body.manifest.base_cursor)}`);
  assert.equal(delta.status, 200);
  assert.equal(delta.body.records.length, 1);
  assert.equal(delta.body.records[0].data.title, 'later revision');
  assert.equal((await send(`${base}/ack`, {body: {...ackBody, cursor: 'forged'}})).status, 409);
});

test('real HTTP deletion invalidates old snapshot pages and rotated credentials before any result lookup', async t => {
  const {send, store, config, operation, token} = await realFixture(t);
  const a = intent(), b = intent();
  for (const raw of [a, b]) assert.equal((await send(`${base}/ops`, {body: raw})).status, 201);
  const first = await send(`${base}/snapshot${core}&limit=1`);
  assert.equal((await send(`${base}/ops`, {body: operation('delete', a.id, 1, {}, true)})).status, 201);
  assert.equal((await send(`${base}/snapshot${core}&page_token=${encodeURIComponent(first.body.next_page_token)}`)).status, 409);
  const {token: rotated} = store.configurePrincipal(config);
  let lookups = 0;
  const lookup = store.getOperation.bind(store);
  store.getOperation = (...args) => {lookups++; return lookup(...args);};
  assert.equal((await send(`${base}/ops/${a.op_id}${core}`, {token})).status, 401);
  assert.equal(lookups, 0);
  assert.equal((await send(`${base}/ops/${a.op_id}${core}`, {token: rotated})).status, 200);
  assert.equal(lookups, 1);
  assert.equal((await send(`${base}/snapshot${core}&page_token=${encodeURIComponent(first.body.next_page_token)}`, {token: rotated})).status, 409);
});

test('real HTTP scope and object boundaries deny secret lookup and actor spoofing', async t => {
  const {send, store, config, operation} = await realFixture(t);
  const created = intent();
  assert.equal((await send(`${base}/ops`, {body: created})).status, 201);
  const {token: limited} = store.configurePrincipal({...config, principal_id: 'limited', scopes: ['example:status'], actors: ['agent_inferred'], trusted_interactive: false});
  for (const path of [`records/${created.id}${core}`, `changes${core}`, `snapshot${core}`]) {
    const response = await send(`${base}/${path}`, {token: limited});
    assert.equal(response.status, 403);
    assert.equal(errorCode(response), 'scope_forbidden');
    assert.equal(JSON.stringify(response.body).includes(created.id), false);
  }
  const {token: other} = store.configurePrincipal({...config, principal_id: 'other', record_ids: []});
  assert.equal((await send(`${base}/records/${created.id}${core}`, {token: other})).status, 404);
  assert.equal((await send(`${base}/ops/${created.op_id}${core}`, {token: other})).status, 404);
  const forged = operation('patch', created.id, 1, {patch: {title: 'forged'}, actor: 'user_direct', authorization_ref: 'some-chat-sync-id'});
  assert.equal((await send(`${base}/ops`, {body: forged})).status, 403);
  assert.equal((await send(`${base}/records/${created.id}${core}`)).body.record.data.title, 'synthetic only');
  assert.equal((await send(`${base}/records/${created.id}?core_instance_id=wrong-core`)).status, 409);
  assert.equal((await send('/v1/core/domains/cycle/snapshot' + core)).status, 404);
});


test('real Core commit followed by lost HTTP response recovers one result by original op id', async t => {
  const {send, db} = await realFixture(t, {dropFirstOpsResponse: true});
  const raw = intent();
  await assert.rejects(send(`${base}/ops`, {body: raw}), error => error.code === 'ECONNRESET');
  const queried = await send(`${base}/ops/${raw.op_id}${core}`);
  assert.equal(queried.status, 200, JSON.stringify(queried.body));
  assert.equal(queried.body.result.outcome, 'accepted');
  const receipt = queried.body.result.receipt.receipt_id;
  const retried = await send(`${base}/ops`, {body: raw});
  assert.equal(retried.status, 200);
  assert.equal(retried.body.outcome, 'duplicate');
  assert.equal(retried.body.receipt.receipt_id, receipt);
  assert.equal(db.prepare('SELECT COUNT(*) n FROM domain_receipts').get().n, 1);
  assert.equal(db.prepare('SELECT COUNT(*) n FROM domain_changes').get().n, 1);
  assert.equal(db.prepare('SELECT revision FROM domain_records').get().revision, 1);
});

test('returned engine errors strip private details but retain minimum tombstone and resync instructions', async t => {
  const {send, fake} = await fixture(t);
  fake.getRecord = () => ({status: 410, body: {error: {code: 'deleted_target', message: 'PRIVATE_SECRET'}, message: 'PRIVATE_SECRET', details: {secret: 'PRIVATE_SECRET'}, tombstone: {id: 'synthetic', revision: 3, body_state: 'purged', data: {title: 'PRIVATE_SECRET'}}}});
  const deleted = await send(`${base}/records/id${core}`);
  assert.equal(deleted.status, 410);
  assert.equal(deleted.body.tombstone.revision, 3);
  assert.equal(JSON.stringify(deleted.body).includes('PRIVATE_SECRET'), false);
  fake.changes = () => ({status: 409, body: {error: 'resync_required', reason: 'retention_gap', domain: 'example', core_instance_id: 'core-fixture', retained_watermark: 4, snapshot: `${base}/snapshot`, details: 'PRIVATE_SECRET'}});
  const resync = await send(`${base}/changes${core}`);
  assert.equal(resync.status, 409);
  assert.equal(resync.body.retained_watermark, 4);
  assert.equal(resync.body.snapshot, `${base}/snapshot`);
  assert.equal(JSON.stringify(resync.body).includes('PRIVATE_SECRET'), false);
});

test('exact request byte limit is accepted, one extra byte rejected, and quoted JSON strings retain content', async t => {
  const {send, calls} = await fixture(t);
  const raw = JSON.stringify(intent({data: {title: 'quote " backslash \\ newline\n 合成'}}));
  const exact = raw + ' '.repeat(262144 - Buffer.byteLength(raw));
  assert.equal((await send(`${base}/ops`, {raw: exact})).status, 200);
  assert.equal(calls.at(-1)[3].data.title, 'quote " backslash \\ newline\n 合成');
  const submissions = calls.filter(c => c[0] === 'submit').length;
  assert.equal((await send(`${base}/ops`, {raw: exact + ' '})).status, 413);
  assert.equal(calls.filter(c => c[0] === 'submit').length, submissions);
});

test('real createICoreServer keeps schema5 chat live, opens explicit synthetic schema6, and separates chat/domain credentials', async t => {
  const {mkdtempSync, rmSync} = await import('node:fs');
  const {tmpdir} = await import('node:os');
  const path = await import('node:path');
  const {createICoreServer} = await import('./i_core_server.mjs');
  const directory = mkdtempSync(path.join(tmpdir(), 'domain-http-synthetic-'));
  const databasePath = path.join(directory, 'core.sqlite');
  let running;
  t.after(async () => {
    if (running) await running.close();
    assert.equal(path.dirname(path.resolve(directory)), path.resolve(tmpdir()));
    assert.equal(path.basename(directory).startsWith('domain-http-synthetic-'), true);
    rmSync(directory, {recursive: true, force: true});
  });
  let origin;
  const request = async (route, {token, body, method = body === undefined ? 'GET' : 'POST', protocol = 'domain'} = {}) => {
    const result = await fetch(origin + route, {method, headers: {connection: 'close', ...(token ? {authorization: `Bearer ${token}`} : {}), ...(body ? {'content-type': 'application/json'} : {}), ...(protocol === 'domain' ? {'x-i-core-domain-protocol': '1'} : {'x-core-protocol': '0.1'})}, ...(body ? {body: JSON.stringify(body)} : {})});
    return {status: result.status, body: await result.json()};
  };
  running = createICoreServer({databasePath, pairingCode: 'synthetic-pairing-code', clock: () => Date.parse(now)});
  let address = await running.listen({port: 0});
  origin = `http://127.0.0.1:${address.port}`;
  assert.equal(running.store.domains, null);
  assert.equal(running.store.db.prepare("SELECT value FROM core_metadata WHERE key='schema_version'").get().value, '5');
  const paired = await request('/v1/core/devices/pair', {protocol: 'chat', body: {device_id: 'synthetic-phone', display_name: 'synthetic phone', platform: 'test', client_version: '0.1', capabilities: ['chat'], pairing_code: 'synthetic-pairing-code'}});
  assert.equal(paired.status, 200);
  const chatToken = paired.body.device_token;
  const nodeId = running.store.nodeId;
  const query = '?core_instance_id=' + encodeURIComponent(nodeId);
  assert.equal(errorCode(await request(base + '/snapshot' + query, {token: chatToken})), 'schema_not_ready');
  assert.equal(running.store.db.prepare("SELECT value FROM core_metadata WHERE key='schema_version'").get().value, '5');
  assert.equal((await request('/v1/core/health')).status, 200);
  assert.equal((await request('/v1/core/changes?cursor=' + encodeURIComponent(paired.body.initial_cursor), {token: chatToken, protocol: 'chat'})).status, 200);
  await running.close(); running = null;
  // Test-only DDL fixture construction, explicitly not evidence of production migration.
  const db = new DatabaseSync(databasePath);
  try { db.exec('BEGIN IMMEDIATE'); db.exec(DOMAIN_SCHEMA_SQL); db.exec("UPDATE core_metadata SET value='6' WHERE key='schema_version'; COMMIT;"); } finally {db.close();}
  running = createICoreServer({databasePath, clock: () => Date.parse(now), domainDedupHooks: {example: ({data, candidates}) => {
    if (data.title === 'synthetic dedup failure') throw new Error('PRIVATE_HOOK_ERROR');
    return candidates.find(record => record.data.title === data.title)?.id ?? null;
  }}});
  address = await running.listen({port: 0}); origin = `http://127.0.0.1:${address.port}`;
  assert.equal(running.store.nodeId, nodeId);
  assert.ok(running.store.domains);
  running.store.domains.registerDomain('example', {version: 1, fields: {title: {type: 'string', required: true}}}, {mode: 'authoritative'});
  const {token} = running.store.domains.configurePrincipal({principal_id: 'synthetic-domain', device_id: 'synthetic-device', installation_id: 'synthetic-install', scopes: ['example:create', 'example:read'], actors: ['agent_inferred']});
  const created = intent({core_instance_id: nodeId});
  assert.equal((await request(base + '/ops', {token, body: created})).status, 201);
  const duplicate = await request(base + '/ops', {token, body: intent({core_instance_id: nodeId})});
  assert.equal(duplicate.status, 200);
  assert.equal(duplicate.body.outcome, 'duplicate');
  assert.equal(duplicate.body.duplicate_of, created.id);
  const before = ['domain_records', 'domain_ops', 'domain_receipts', 'domain_changes'].map(table => running.store.db.prepare(`SELECT COUNT(*) n FROM ${table}`).get().n);
  const unavailable = await request(base + '/ops', {token, body: intent({core_instance_id: nodeId, data: {title: 'synthetic dedup failure'}})});
  assert.equal(unavailable.status, 503);
  assert.equal(errorCode(unavailable), 'dedup_unavailable');
  assert.equal(unavailable.body.error.retryable, true);
  assert.equal(JSON.stringify(unavailable.body).includes('PRIVATE_HOOK_ERROR'), false);
  assert.deepEqual(['domain_records', 'domain_ops', 'domain_receipts', 'domain_changes'].map(table => running.store.db.prepare(`SELECT COUNT(*) n FROM ${table}`).get().n), before);
  assert.equal((await request(`${base}/records/${created.id}${query}`, {token})).status, 200);
  for (const route of [`ops/${created.op_id}`, `records/${created.id}`, 'changes', 'snapshot']) {
    const forbidden = await request(`${base}/${route}${query}`, {token: chatToken});
    assert.equal(forbidden.status, 403);
    assert.equal(errorCode(forbidden), 'scope_forbidden');
  }
  assert.equal((await request('/v1/core/changes?cursor=' + encodeURIComponent(paired.body.initial_cursor), {token, protocol: 'chat'})).status, 401);
  assert.equal((await request('/v1/core/changes?cursor=' + encodeURIComponent(paired.body.initial_cursor), {token: chatToken, protocol: 'chat'})).status, 200);
});




test('real DomainStore schema integrity latch stays retryable 503 at HTTP authentication', async t => {
  const {send, db} = await realFixture(t);
  db.exec('DROP INDEX domain_changes_feed');
  const first = await send(`${base}/snapshot${core}`);
  assert.equal(first.status, 503);
  assert.equal(errorCode(first), 'schema_not_ready');
  const latched = await send(`${base}/snapshot${core}`);
  assert.equal(latched.status, 503);
  assert.equal(errorCode(latched), 'core_not_ready');
  assert.equal(latched.body.error.retryable, true);
});

test('real DomainStore backup activation denial stays 503 through the HTTP boundary', async t => {
  const {send, db} = await realFixture(t);
  db.exec("CREATE TABLE activity_metadata(key TEXT PRIMARY KEY,value TEXT); INSERT INTO activity_metadata VALUES('database_role','backup_read_only');");
  const denied = await send(`${base}/snapshot${core}`);
  assert.equal(denied.status, 503);
  assert.equal(errorCode(denied), 'backup_activation_unsupported');
  assert.equal(denied.body.error.retryable, true);
});
