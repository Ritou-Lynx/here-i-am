import test from 'node:test';
import assert from 'node:assert/strict';
import {
  FOOD_PHONE_PRINCIPAL_ID,
  foodPrincipalConfigs,
  provisionFoodDomain,
} from './personal_data_domains.mjs';
import {foodHttp, foodOperation} from './test_fixtures/release_schema6/n2a_food.mjs';

const headers = token => ({
  connection: 'close',
  'content-type': 'application/json',
  'x-core-protocol': '0.1',
  ...(token ? {authorization: `Bearer ${token}`} : {}),
});

async function request(core, route, {token, body = '{}', protocol = true} = {}) {
  const address = core.server.address();
  const h = headers(token);
  if (!protocol) delete h['x-core-protocol'];
  const response = await fetch(`http://127.0.0.1:${address.port}${route}`, {
    method: 'POST', headers: h, body, signal: AbortSignal.timeout(5000),
  });
  return {status: response.status, headers: response.headers, body: await response.json()};
}

async function pair(core, pairingCode, {deviceId = 'synthetic-android', platform = 'android'} = {}) {
  const result = await request(core, '/v1/core/devices/pair', {body: JSON.stringify({
    pairing_code: pairingCode, device_id: deviceId, display_name: 'Synthetic phone',
    platform, client_version: '1', capabilities: ['chat'],
  })});
  assert.equal(result.status, 200, JSON.stringify(result.body));
  return result.body.device_token;
}

test('phone credential endpoint fails closed before food provisioning without database changes', async t => {
  const f = await foodHttp(t);
  const token = await pair(f.core, 'synthetic-pairing-code');
  const before = f.core.store.db.prepare("SELECT COUNT(*) n FROM domain_registry").get().n;
  const result = await request(f.core, '/v1/core/food/phone-credential', {token});
  assert.equal(result.status, 409);
  assert.equal(result.body.error.code, 'food_not_provisioned');
  assert.equal(f.core.store.db.prepare("SELECT COUNT(*) n FROM domain_registry").get().n, before);
  assert.equal(f.core.store.db.prepare("SELECT COUNT(*) n FROM domain_principals").get().n, 0);
});

test('Android claims rotate read-only food credentials while the writer remains usable', async t => {
  const f = await foodHttp(t);
  const issued = provisionFoodDomain(f.core.store.domains).issued;
  const deviceToken = await pair(f.core, 'synthetic-pairing-code');
  const first = await request(f.core, '/v1/core/food/phone-credential', {token: deviceToken});
  assert.equal(first.status, 200, JSON.stringify(first.body));
  assert.equal(first.headers.get('cache-control'), 'no-store');
  assert.equal(first.body.format, 'food-phone-credential-v1');
  assert.equal(first.body.domain, 'food_entries');
  assert.equal(first.body.principal_id, FOOD_PHONE_PRINCIPAL_ID);
  assert.equal(first.body.core_instance_id, f.core.store.nodeId);

  const base = '/v1/core/domains/food_entries';
  const created = await f.send(`${base}/ops`, issued.writer, foodOperation(f.core));
  assert.equal(created.status, 201, JSON.stringify(created.body));
  const snapshot = await f.send(`${base}/snapshot?core_instance_id=${f.core.store.nodeId}`, first.body.token);
  assert.equal(snapshot.status, 200);
  assert.equal((await f.send(`${base}/changes?core_instance_id=${f.core.store.nodeId}&cursor=${encodeURIComponent(snapshot.body.manifest.base_cursor)}`, first.body.token)).status, 200);
  const denied = await f.send(`${base}/ops`, first.body.token, foodOperation(f.core));
  assert.equal(denied.status, 403);
  assert.equal(denied.body.error.code, 'scope_forbidden');

  const second = await request(f.core, '/v1/core/food/phone-credential', {token: deviceToken});
  assert.equal(second.status, 200);
  assert.equal((await f.send(`${base}/snapshot?core_instance_id=${f.core.store.nodeId}`, first.body.token)).status, 401);
  assert.equal((await f.send(`${base}/snapshot?core_instance_id=${f.core.store.nodeId}`, second.body.token)).status, 200);
  assert.equal((await f.send(`${base}/ops`, issued.writer, foodOperation(f.core))).status, 201);
  assert.equal(JSON.stringify(second.body).includes(deviceToken), false);
});

test('phone credential endpoint rejects wrong devices, auth, protocol and bodies', async t => {
  const f = await foodHttp(t);
  provisionFoodDomain(f.core.store.domains);
  const android = await pair(f.core, 'synthetic-pairing-code');
  f.core.replacePairingCode('synthetic-external-code');
  const external = await pair(f.core, 'synthetic-external-code', {deviceId: 'frontend:claude', platform: 'external-frontend'});
  assert.equal((await request(f.core, '/v1/core/food/phone-credential', {token: external})).body.error.code, 'phone_device_required');
  assert.equal((await request(f.core, '/v1/core/food/phone-credential')).status, 401);
  assert.equal((await request(f.core, '/v1/core/food/phone-credential', {token: android, protocol: false})).status, 426);
  assert.equal((await request(f.core, '/v1/core/food/phone-credential', {token: android, body: '{"extra":true}'})).body.error.code, 'invalid_request');
  assert.equal((await request(f.core, '/v1/core/food/phone-credential', {token: android, body: JSON.stringify({padding: 'x'.repeat(1100)})})).body.error.code, 'invalid_request');
});

test('revoked or modified phone principal is not rotated', async t => {
  const f = await foodHttp(t);
  provisionFoodDomain(f.core.store.domains);
  const token = await pair(f.core, 'synthetic-pairing-code');
  const row = () => f.core.store.domains.db.prepare('SELECT generation,status,config_json FROM domain_principals WHERE principal_id=?').get(FOOD_PHONE_PRINCIPAL_ID);
  f.core.store.domains.revokePrincipal(FOOD_PHONE_PRINCIPAL_ID);
  const revoked = row();
  assert.equal((await request(f.core, '/v1/core/food/phone-credential', {token})).status, 409);
  assert.deepEqual(row(), revoked);

  const config = {...foodPrincipalConfigs().phone, scopes: ['food_entries:read', 'food_entries:create']};
  f.core.store.domains.configurePrincipal(config);
  const modified = row();
  assert.equal((await request(f.core, '/v1/core/food/phone-credential', {token})).status, 409);
  assert.deepEqual(row(), modified);
});
