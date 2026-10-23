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

export async function sendNotification({ title, content, url }, notifyConfig = {}, fetchImpl = fetch) {
  const { pushplusToken, barkKey, barkServer = 'https://api.day.app' } = notifyConfig;
  if (!pushplusToken && !barkKey) {
    console.log('未配置通知通道');
    return { pushplus: 'off', bark: 'off' };
  }
  const [pushplus, bark] = await Promise.all([
    pushplusToken ? send('https://www.pushplus.plus/send', { token: pushplusToken, title, content, template: 'txt' }, fetchImpl, (_, body) => body?.code === 200) : 'off',
    barkKey ? (async () => {
      try {
        return await send(`${(barkServer || 'https://api.day.app').replace(/\/+$/, '')}/push`, { device_key: barkKey, title, body: content, url, group: 'agent-relay' }, fetchImpl, (response, body) => response.status === 200 && body?.code === 200);
      } catch { return 'failed'; }
    })() : 'off',
  ]);
  return { pushplus, bark };
}
