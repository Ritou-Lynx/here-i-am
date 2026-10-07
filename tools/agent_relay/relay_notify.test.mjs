import test from 'node:test';
import assert from 'node:assert/strict';
import { sendNotification } from './relay_notify.mjs';

const message = {
  title: 'Relay finished',
  content: 'Synthetic notification content',
  url: 'https://example.test/pr/17',
};

function jsonResponse(code, status = 200) {
  return { status, json: async () => ({ code }) };
}

test('sends exact PushPlus and default Bark requests with independent 10 second signals', async () => {
  const calls = [];
  const timeoutCalls = [];
  const originalTimeout = AbortSignal.timeout;
  AbortSignal.timeout = milliseconds => {
    timeoutCalls.push(milliseconds);
    return new AbortController().signal;
  };

  try {
    const result = await sendNotification(message, {
      pushplusToken: 'synthetic-push-token',
      barkKey: 'synthetic-device-key',
    }, async (url, options) => {
      calls.push({ url, options });
      return jsonResponse(200);
    });

    assert.deepEqual(result, { pushplus: 'ok', bark: 'ok' });
    assert.deepEqual(timeoutCalls, [10_000, 10_000]);
    assert.equal(calls.length, 2);
    assert.deepEqual(calls.map(call => call.url), [
      'https://www.pushplus.plus/send',
      'https://api.day.app/push',
    ]);
    assert.notEqual(calls[0].options.signal, calls[1].options.signal);
    assert.deepEqual(calls.map(call => ({
      method: call.options.method,
      headers: call.options.headers,
      body: JSON.parse(call.options.body),
    })), [
      {
        method: 'POST',
        headers: { 'content-type': 'application/json' },
        body: {
          token: 'synthetic-push-token',
          title: message.title,
          content: message.content,
          template: 'txt',
        },
      },
      {
        method: 'POST',
        headers: { 'content-type': 'application/json' },
        body: {
          device_key: 'synthetic-device-key',
          title: message.title,
          body: message.content,
          url: message.url,
          group: 'agent-relay',
        },
      },
    ]);
  } finally {
    AbortSignal.timeout = originalTimeout;
  }
});

test('uses a configured Bark server without a duplicate trailing slash', async () => {
  const urls = [];
  const result = await sendNotification(message, {
    barkKey: 'synthetic-device-key',
    barkServer: 'https://bark.example.test///',
  }, async url => {
    urls.push(url);
    return jsonResponse(200);
  });

  assert.deepEqual(result, { pushplus: 'off', bark: 'ok' });
  assert.deepEqual(urls, ['https://bark.example.test/push']);
});

test('reports PushPlus application failure', async () => {
  const result = await sendNotification(message, {
    pushplusToken: 'synthetic-push-token',
  }, async () => jsonResponse(500));

  assert.deepEqual(result, { pushplus: 'failed', bark: 'off' });
});

test('reports Bark HTTP and application failures', async t => {
  for (const [name, response] of [
    ['http', jsonResponse(200, 503)],
    ['application', jsonResponse(500, 200)],
  ]) {
    await t.test(name, async () => {
      const result = await sendNotification(message, {
        barkKey: 'synthetic-device-key',
      }, async () => response);
      assert.deepEqual(result, { pushplus: 'off', bark: 'failed' });
    });
  }
});

test('one channel exception does not stop the other channel', async () => {
  const urls = [];
  const result = await sendNotification(message, {
    pushplusToken: 'synthetic-push-token',
    barkKey: 'synthetic-device-key',
  }, async url => {
    urls.push(url);
    if (url.includes('pushplus')) throw new Error('synthetic network failure');
    return jsonResponse(200);
  });

  assert.deepEqual(result, { pushplus: 'failed', bark: 'ok' });
  assert.deepEqual(urls, [
    'https://www.pushplus.plus/send',
    'https://api.day.app/push',
  ]);
});

test('missing, blank, or non-string credentials disable channels without fetching', async () => {
  let fetchCount = 0;
  const fetchImpl = async () => {
    fetchCount += 1;
    throw new Error('fetch must not run');
  };

  for (const config of [undefined, {}, {
    pushplusToken: '   ',
    barkKey: null,
  }]) {
    assert.deepEqual(await sendNotification(message, config, fetchImpl), {
      pushplus: 'off',
      bark: 'off',
    });
  }
  assert.equal(fetchCount, 0);
});

test('JSON parse and network failures are contained without logging secrets', async () => {
  const originalConsole = {
    log: console.log,
    warn: console.warn,
    error: console.error,
  };
  const logged = [];
  console.log = (...args) => logged.push(args);
  console.warn = (...args) => logged.push(args);
  console.error = (...args) => logged.push(args);

  try {
    const parseFailure = await sendNotification(message, {
      pushplusToken: 'secret-push-token',
    }, async () => ({ status: 200, json: async () => { throw new Error('secret-push-token'); } }));
    assert.deepEqual(parseFailure, { pushplus: 'failed', bark: 'off' });

    const networkFailure = await sendNotification(message, {
      barkKey: 'secret-device-key',
    }, async () => { throw new Error('secret-device-key'); });
    assert.deepEqual(networkFailure, { pushplus: 'off', bark: 'failed' });
    assert.deepEqual(logged, []);
  } finally {
    console.log = originalConsole.log;
    console.warn = originalConsole.warn;
    console.error = originalConsole.error;
  }
});
