// Test-only Job member and actual grandchild. No external input/data/transport.
import { spawn } from 'node:child_process';
import { createHmac } from 'node:crypto';
import { existsSync, readFileSync, writeFileSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
const [control, runId, mode] = process.argv.slice(2);
if (!/^[a-f0-9]{64}$/.test(runId) || !['parent','grandchild'].includes(mode)) throw new Error('fixture_arguments');
const launch = JSON.parse(readFileSync(path.join(control, 'launch.json')));
if (launch.token !== runId) throw new Error('fixture_binding');
let descendant;
if (mode === 'parent') descendant = spawn(process.execPath, [fileURLToPath(import.meta.url), control, runId, 'grandchild'], { windowsHide: true, stdio: 'ignore' });
else writeFileSync(path.join(control, 'descendant.json'), JSON.stringify({ run_id: runId, pid: process.pid }), { flag: 'wx' });
const timer = setInterval(() => {
  const key = readFileSync(path.join(control, 'stop.key'), 'utf8');
  for (const action of ['close','stop']) {
    const target = path.join(control, action);
    const expected = createHmac('sha256', key).update(`${runId}|${launch.manifest_sha256}|${action}`).digest('hex');
    if (existsSync(target) && readFileSync(target, 'utf8') === expected) clearInterval(timer);
  }
}, 15);
