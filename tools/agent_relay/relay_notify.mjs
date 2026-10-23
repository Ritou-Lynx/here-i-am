import { createHmac } from 'node:crypto';

// Each channel owns its deadline, including response parsing. Never expose errors
// from providers: they can contain the credential or request payload.
async function send(url, payload, fetchImpl, accepts) {
  const controller = new AbortController();
  let timer;
  try {
    return await Promise.race([
      (async () => {
        const response = await fetchImpl(url, {
          method: 'POST', headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify(payload), signal: controller.signal,
        });
        const body = await response.json();
        return accepts(response, body) ? 'ok' : 'failed';
      })(),
      new Promise(resolve => {
        timer = setTimeout(() => { resolve('failed'); controller.abort(); }, 10000);
      }),
    ]);
  } catch { return 'failed'; }
  finally { clearTimeout(timer); }
}

export async function sendNotification({ title, content, url }, notifyConfig = {}, fetchImpl = fetch, now = Date.now) {
  const { feishuWebhook, feishuSecret, barkKey, barkServer = 'https://api.day.app' } = notifyConfig;
  if (!feishuWebhook && !barkKey) {
    console.log('未配置通知通道');
    return { feishu: 'off', bark: 'off' };
  }
  const [feishu, bark] = await Promise.all([
    feishuWebhook ? (async () => {
      try {
        const payload = { msg_type: 'text', content: { text: `${title}\n\n${content}` } };
        if (feishuSecret) {
          payload.timestamp = String(Math.floor(now() / 1000));
          payload.sign = createHmac('sha256', `${payload.timestamp}\n${feishuSecret}`).update('').digest('base64');
        }
        return await send(feishuWebhook, payload, fetchImpl, (response, body) => response.status === 200 && (body?.code === 0 || body?.StatusCode === 0));
      } catch { return 'failed'; }
    })() : 'off',
    barkKey ? (async () => {
      try {
        return await send(`${(barkServer || 'https://api.day.app').replace(/\/+$/, '')}/push`, { device_key: barkKey, title, body: content, url, group: 'agent-relay' }, fetchImpl, (response, body) => response.status === 200 && body?.code === 200);
      } catch { return 'failed'; }
    })() : 'off',
  ]);
  return { feishu, bark };
}
