import { existsSync, readFileSync, writeSync } from 'node:fs';
import path from 'node:path';
import { startSupervised } from '../../migration_m3/supervision.mjs';
const run = startSupervised({ mode: 'descendants', timeout: 20000 });
await run.ready();
writeSync(1, JSON.stringify({ root: run.root, token: run.token, supervisor_pid: run.supervisorPid() }) + '\n');
setInterval(() => {
  const request = path.join(run.root, 'parent-exit');
  if (existsSync(request) && readFileSync(request, 'utf8') === run.token) process.exit(91);
}, 20);
await run.wait();
