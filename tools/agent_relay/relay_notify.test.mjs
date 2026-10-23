import assert from 'node:assert/strict';
import test from 'node:test';
import { createHmac } from 'node:crypto';
import { sendNotification } from './relay_notify.mjs';

const webhook = 'https://open.feishu.cn/open-apis/bot/v2/hook/synthetic-hook';
const message = { title: '测试', content: '正文', url: 'https://github.com/example/repo/pull/1' };
const response = (status = 200, code = 200) => ({ status, json: async () => ({ code }) });

test('Feishu sends exact unsigned and signed JSON with independently verified signature', async () => {
  for (const feishuSecret of [undefined, 'synthetic-signing-secret']) {
    let calls = 0;
    const now = () => 1792752000123;
    const result = await sendNotification(message, { feishuWebhook: webhook, feishuSecret }, async (url, opts) => {
      calls++;
      assert.equal(url, webhook);
      assert.equal(opts.method, 'POST');
      assert.equal(opts.headers['Content-Type'], 'application/json');
      assert.equal(opts.signal.aborted, false);
      const expected = { msg_type: 'text', content: { text: `${message.title}\n\n${message.content}` } };
      if (feishuSecret) {
        expected.timestamp = '1792752000';
        expected.sign = createHmac('sha256', `1792752000\n${feishuSecret}`).update('').digest('base64');
      }
      assert.deepEqual(JSON.parse(opts.body), expected);
      return response(200, 0);
    }, now);
    assert.deepEqual(result, { feishu: 'ok', bark: 'off' });
    assert.equal(calls, 1);
  }
});

test('Feishu accepts legacy StatusCode zero and requires HTTP 200 and numeric success', async () => {
  for (const body of [{ code: 0 }, { StatusCode: 0 }]) {
    assert.equal((await sendNotification(message, { feishuWebhook: webhook }, async () => ({ status: 200, json: async () => body }))).feishu, 'ok');
    assert.equal((await sendNotification(message, { feishuWebhook: webhook }, async () => ({ status: 503, json: async () => body }))).feishu, 'failed');
  }
  for (const body of [{ code: 1 }, { code: '0' }, { StatusCode: '0' }]) {
    assert.equal((await sendNotification(message, { feishuWebhook: webhook }, async () => ({ status: 200, json: async () => body }))).feishu, 'failed');
  }
});

test('Bark sends exact JSON with default, empty and custom server URLs', async () => {
  for (const barkServer of [undefined, '', 'https://bark.example.test/base/']) {
    const result = await sendNotification(message, { barkKey: 'synthetic-bark-key', barkServer }, async (url, opts) => {
      assert.equal(url, barkServer ? 'https://bark.example.test/base/push' : 'https://api.day.app/push');
      assert.equal(opts.method, 'POST');
      assert.deepEqual(JSON.parse(opts.body), { device_key: 'synthetic-bark-key', title: message.title, body: message.content, url: message.url, group: 'agent-relay' });
      return response();
    });
    assert.deepEqual(result, { feishu: 'off', bark: 'ok' });
  }
});

for (const channel of ['feishu', 'bark']) {
  const config = channel === 'feishu' ? { feishuWebhook: webhook } : { barkKey: 'synthetic-bark-key' };
  test(`${channel} returns failed on exceptions, malformed JSON and provider errors`, async () => {
    for (const fetchImpl of [
      async () => { throw new Error('synthetic credential must never be logged'); },
      async () => ({ status: 200, json: async () => { throw new Error('invalid JSON'); } }),
      async () => response(200, 500), async () => response(200, '200'),
      async () => ({ status: 200, json: async () => null }),
    ]) assert.equal((await sendNotification(message, config, fetchImpl))[channel], 'failed');
  });

  test(`${channel} enforces a ten-second deadline even if fetch ignores abort`, async t => {
    t.mock.timers.enable({ apis: ['setTimeout'] });
    let signal;
    const promise = sendNotification(message, config, async (_, opts) => { signal = opts.signal; return new Promise(() => {}); });
    t.mock.timers.tick(9999);
    assert.equal(signal.aborted, false);
    t.mock.timers.tick(1);
    assert.equal((await promise)[channel], 'failed');
    assert.equal(signal.aborted, true);
  });

  test(`${channel} also times out a response body that never resolves`, async t => {
    t.mock.timers.enable({ apis: ['setTimeout'] });
    const promise = sendNotification(message, config, async () => ({ status: 200, json: () => new Promise(() => {}) }));
    await Promise.resolve();
    t.mock.timers.tick(10000);
    assert.equal((await promise)[channel], 'failed');
  });
}

test('Bark requires HTTP 200 as well as provider code 200', async () => {
  assert.equal((await sendNotification(message, { barkKey: 'synthetic-key' }, async () => response(503, 200))).bark, 'failed');
});

test('a malformed Bark server fails that channel without rejecting or suppressing Feishu', async () => {
  assert.deepEqual(await sendNotification(message, { feishuWebhook: webhook, barkKey: 'synthetic-key', barkServer: 1 }, async () => response(200, 0)), { feishu: 'ok', bark: 'failed' });
});

test('one failing or timing-out channel never prevents the other channel succeeding', async t => {
  t.mock.timers.enable({ apis: ['setTimeout'] });
  const promise = sendNotification(message, { feishuWebhook: webhook, barkKey: 'synthetic-key' }, async url => {
    if (url.includes('feishu')) return new Promise(() => {});
    return response();
  });
  await Promise.resolve();
  await Promise.resolve();
  t.mock.timers.tick(10000);
  assert.deepEqual(await promise, { feishu: 'failed', bark: 'ok' });
  assert.deepEqual(await sendNotification(message, { feishuWebhook: webhook, barkKey: 'synthetic-key' }, async url => {
    if (url.includes('day.app')) throw new Error('synthetic error');
    return response(200, 0);
  }), { feishu: 'ok', bark: 'failed' });
});

test('unconfigured channels log once and never call fetch', async t => {
  const logged = [];
  t.mock.method(console, 'log', text => logged.push(text));
  assert.deepEqual(await sendNotification(message, {}, () => { assert.fail('fetch called'); }), { feishu: 'off', bark: 'off' });
  assert.deepEqual(logged, ['未配置通知通道']);
});
