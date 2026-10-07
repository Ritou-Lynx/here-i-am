import test from 'node:test';
import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';
import path from 'node:path';
const source=fileURLToPath(new URL('../maintenance/freeze-legacy-runtime.ps1',import.meta.url));
const fixture=fileURLToPath(new URL('../test_fixtures/release_schema6/maintenance_preflight_dispatch.ps1',import.meta.url));
test('read-only rehearsal returns before every live mutation and strict artifact pins reject double links',{skip:process.platform!=='win32',timeout:30000},()=>{
 const ps=path.join(process.env.SystemRoot,'System32/WindowsPowerShell/v1.0/powershell.exe');
 const r=spawnSync(ps,['-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-File',fixture,'-Source',source],{windowsHide:true,encoding:'utf8',timeout:25000});
 assert.equal(r.error,undefined);assert.equal(r.status,0,r.stderr);
 const result=JSON.parse(r.stdout.trim().split(/\r?\n/).at(-1));
 for(const field of ['passed','normalPreflightReturns','failedPreflightCannotMutate','dataDoubleLinkRejected','configurationDoubleLinkRejected','ordinaryPinLeasesRetained','formalIdReserved','noProductionPrepareReceipt','nonemptyWindowAclPreserved','emptyProtectedArtifactChildren','artifactReuseRejected','usbMismatchRejected','incompleteBackupRejected','realRestoreRequired'])assert.equal(result[field],true,field);
 assert.equal(result.liveMutationCalls,0);
});