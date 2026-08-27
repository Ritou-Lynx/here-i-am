import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import path from 'node:path';
import test from 'node:test';
import { fileURLToPath } from 'node:url';

const directory = path.dirname(fileURLToPath(import.meta.url));
const read = (name) => readFileSync(path.join(directory, name), 'utf8');

test('service launcher is loopback-only and clears all cutover credentials', () => {
  const script = read('start_i_core_service.ps1');
  assert.match(script, /\$env:I_CORE_HOST\s*=\s*'127\.0\.0\.1'/);
  assert.match(script, /\$env:I_CORE_PORT\s*=\s*'47841'/);
  assert.match(script, /\.state\\i-core\.sqlite/);
  for (const name of [
    'I_CORE_PAIRING_CODE',
    'I_CORE_CERT',
    'I_CORE_KEY',
    'I_CORE_WORKER_SECRET',
    'I_CORE_COMPANION_REPLY_JOBS',
  ]) {
    assert.match(script, new RegExp(`Remove-Item Env:${name}`));
  }
  assert.match(script, /& \$resolvedNode \$serverPath/);
  assert.match(script, /exit \$exitCode/);
});

test('installer registers a limited current-user logon task with daemon-safe settings', () => {
  const script = read('install_i_core_autostart.ps1');
  assert.match(script, /\$taskName\s*=\s*'HereIAm-iCore'/);
  assert.match(script, /\$existingTask\.Description -ne \$ownershipMarker/);
  assert.match(script, /Refusing to replace an unowned scheduled task/);
  assert.match(script, /New-ScheduledTaskTrigger -AtLogOn -User \$currentUser/);
  assert.match(script, /\$trigger\.Delay\s*=\s*'PT10S'/);
  assert.match(script, /-LogonType Interactive/);
  assert.match(script, /-RunLevel Limited/);
  assert.match(script, /-AllowStartIfOnBatteries/);
  assert.match(script, /-DontStopIfGoingOnBatteries/);
  assert.match(script, /-RestartCount 5/);
  assert.match(script, /-ExecutionTimeLimit \(\[TimeSpan\]::Zero\)/);
  assert.match(script, /-MultipleInstances IgnoreNew/);
  assert.match(script, /start_i_core_service\.ps1/);
  assert.doesNotMatch(script, /I_CORE_PAIRING_CODE|I_CORE_WORKER_SECRET/);
});

test('uninstaller removes only the scheduled task and explicitly preserves data', () => {
  const script = read('uninstall_i_core_autostart.ps1');
  assert.match(script, /\$task\.Description -ne \$ownershipMarker/);
  assert.match(script, /Refusing to remove an unowned scheduled task/);
  assert.match(script, /Unregister-ScheduledTask/);
  assert.match(script, /data_removed\s*=\s*\$false/);
  assert.doesNotMatch(script, /Remove-Item|\.state\\/);
});
