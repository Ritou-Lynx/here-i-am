// Hosted fixture only. This file is never executed by local validation.
import fs from 'node:fs';
import path from 'node:path';

const directory = process.argv[2];
const permit = JSON.parse(fs.readFileSync(path.join(directory, 'hosted-job.json'), 'utf8').replace(/^\uFEFF/, ''));
if (permit.githubHosted !== true || permit.machine !== process.env.COMPUTERNAME ||
    Date.now() >= Date.parse(permit.expiresUtc)) {
  throw new Error('hosted_job_permit_required');
}
const fd = fs.openSync(path.join(directory, 'child-events.jsonl'), 'a');
function record(event, extra = {}) {
  // hrtime is a child-local clock. The collector never compares its epoch to QPC.
  const line = JSON.stringify({ event, pid: process.pid, utc: new Date().toISOString(),
    hrtime_ns: process.hrtime.bigint().toString(), ...extra }) + '\n';
  const data = Buffer.from(line);
  let offset = 0;
  while (offset < data.length) offset += fs.writeSync(fd, data, offset, data.length - offset);
  fs.fsyncSync(fd);
}
for (const signal of ['SIGINT', 'SIGTERM', 'SIGBREAK']) {
  process.on(signal, () => {
    record(signal);
    process.exit(0);
  });
}
process.on('exit', code => record('exit', { code }));
record('child_ready');
record('heartbeat');
setInterval(() => record('heartbeat'), 200);
const readyFd = fs.openSync(path.join(directory, 'child-ready.json'), 'w');
try {
  fs.writeFileSync(readyFd, JSON.stringify({ pid: process.pid }));
  fs.fsyncSync(readyFd);
} finally {
  fs.closeSync(readyFd);
}
