import { EventEmitter } from 'node:events';
import { PassThrough } from 'node:stream';
import { CodexAppServerClient } from '../codex_app_server_client.mjs';

// In-memory child: no executable, provider, account or network is involved.
export function stopReceiptFixture(t, { ready = true, ...options } = {}) {
  const child = new EventEmitter();
  child.stdin = new PassThrough();
  child.stdout = new PassThrough();
  child.stderr = new PassThrough();
  child.kill = () => true;
  const client = new CodexAppServerClient({
    commandSpec: { command: 'in-memory-stop-fixture' },
    spawnImpl: () => child,
    requestTimeoutMs: 50,
    stopTimeoutMs: 10,
    killTimeoutMs: 30,
    ...options,
  });
  if (ready) {
    client.child = child;
    client.state = 'ready';
    client._attachChild(child);
  }
  const keepAlive = setInterval(() => {}, 50);
  t.after(() => {
    child.emit('close', 0, null);
    for (const stream of [child.stdin, child.stdout, child.stderr]) stream.destroy();
    clearInterval(keepAlive);
  });
  const send = (message) => child.stdout.write(`${JSON.stringify(message)}\n`);
  return { child, client, send };
}
