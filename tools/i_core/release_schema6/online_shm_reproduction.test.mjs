import test from 'node:test';
import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';
import {cleanEnvironment} from './package.mjs';

// Default is portable source-tree code; local pinned-release verification is an
// explicit opt-in. None of these variables or host configuration reach SQLite workers.
test('independent idle writer: read-only capture and SELECT update only synthetic SHM read marks',()=>{
  const options=JSON.parse(process.env.ONLINE_SHM_OPTIONS??'{}');
  const probe=fileURLToPath(new URL('../test_fixtures/release_schema6/online_shm_probe.mjs',import.meta.url));
  const result=spawnSync(process.execPath,[probe,JSON.stringify(options)],{env:cleanEnvironment(),windowsHide:true,encoding:'utf8',timeout:60000,maxBuffer:8*1024*1024});
  assert.equal(result.error,undefined);
  if(result.status!==0)process.stdout.write(result.stdout);
  assert.equal(result.status,0,result.stderr);
  const records=result.stdout.trim().split(/\r?\n/).map(line=>JSON.parse(line));
  const report=records.at(-1).report;
  assert.equal(report.scenarios.length,4*(options.repeats??1));
  assert.ok(report.scenarios.every(s=>s.scenario.endsWith('select')||s.copyCorrect));
  // All output contains synthetic bytes/identities only and is suitable for CI artifacts.
  process.stdout.write(JSON.stringify({report})+'\n');
});
