const PUSHPLUS_URL = 'https://www.pushplus.plus/send';
const DEFAULT_BARK_SERVER = 'https://api.day.app';
const NOTIFICATION_TIMEOUT_MS = 10_000;

function nonEmpty(value) {
  return typeof value === 'string' && value.trim() ? value.trim() : null;
}

async function sendPushPlus({ title, content }, notifyConfig, fetchImpl) {
  const token = nonEmpty(notifyConfig?.pushplusToken);
  if (!token) return 'off';

  try {
    const response = await fetchImpl(PUSHPLUS_URL, {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({ token, title, content, template: 'txt' }),
      signal: AbortSignal.timeout(NOTIFICATION_TIMEOUT_MS),
    });
    const result = await response.json();
    return result?.code === 200 ? 'ok' : 'failed';
  } catch {
    return 'failed';
  }
}

async function sendBark({ title, content, url }, notifyConfig, fetchImpl) {
  const deviceKey = nonEmpty(notifyConfig?.barkKey);
  if (!deviceKey) return 'off';

  const server = nonEmpty(notifyConfig?.barkServer) ?? DEFAULT_BARK_SERVER;
  try {
    const response = await fetchImpl(`${server.replace(/\/+$/u, '')}/push`, {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({ device_key: deviceKey, title, body: content, url, group: 'agent-relay' }),
      signal: AbortSignal.timeout(NOTIFICATION_TIMEOUT_MS),
    });
    const result = await response.json();
    return response.status === 200 && result?.code === 200 ? 'ok' : 'failed';
  } catch {
    return 'failed';
  }
}

export async function sendNotification(message, notifyConfig, fetchImpl = fetch) {
  const [pushplus, bark] = await Promise.all([
    sendPushPlus(message, notifyConfig, fetchImpl),
    sendBark(message, notifyConfig, fetchImpl),
  ]);
  return { pushplus, bark };
}
