import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {readFileSync} from 'node:fs';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import test from 'node:test';
const modulePath=fileURLToPath(new URL('../maintenance/maintenance_window.ps1',import.meta.url));
const fixture=fileURLToPath(new URL('../test_fixtures/release_schema6/maintenance_window_native.ps1',import.meta.url));
test('maintenance windows: real exclusive handles, fresh IDs and append-only legacy artifacts',{skip:process.platform!=='win32',timeout:30000},()=>{
 const ps=path.join(process.env.SystemRoot,'System32','WindowsPowerShell','v1.0','powershell.exe');
 const result=spawnSync(ps,['-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-File',fixture,'-ModulePath',modulePath],{windowsHide:true,encoding:'utf8',timeout:25000});
 assert.equal(result.error,undefined);assert.equal(result.status,0,result.stderr);
 const report=JSON.parse(result.stdout.trim());
 for(const field of ['passed','parallelRejected','sameWindowRejected','freshWindowAccepted','oldBytesPreserved','guardBytesPreserved','interruptedWindowRejected','traversalRejected','stageGuardRejected','hardlinkGuardRejected','formalAclConsumerPassed','existingAclsPreserved','nonemptyProtectionRejected'])assert.equal(report[field],true,field);
});
test('production freeze entry contains no callback, test flag or private deployment constants',()=>{
 const entry=readFileSync(new URL('../maintenance/enter-maintenance-window.ps1',import.meta.url),'utf8');
 assert.match(entry,/freeze-legacy-runtime\.ps1/);assert.doesNotMatch(entry,/\[scriptblock\]|TestMode|SkipGuard/);
 const freeze=readFileSync(new URL('../maintenance/freeze-legacy-runtime.ps1',import.meta.url),'utf8');
 assert.doesNotMatch(freeze,/D:\\HereIAmRuntime|HereIAm-iCore|HereIAm-iRemoteMCP|47841|47860|47862|S-1-5-21-\d/);
 assert.match(freeze,/precutover_validate_copy\.mjs/);assert.match(freeze,/--config/);
 assert.match(freeze,/schema6-frozen-legacy-runtime-ready-v2/);
});
test('exact frozen-file and process-handle primitives reject byte drift and reused identity',{skip:process.platform!=='win32',timeout:30000},()=>{
 const ps=path.join(process.env.SystemRoot,'System32','WindowsPowerShell','v1.0','powershell.exe');
 const primitiveFixture=fileURLToPath(new URL('../test_fixtures/release_schema6/maintenance_window_primitives.ps1',import.meta.url));
 const source=fileURLToPath(new URL('../maintenance/freeze-legacy-runtime.ps1',import.meta.url));
 const result=spawnSync(ps,['-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-File',primitiveFixture,'-Source',source],{windowsHide:true,encoding:'utf8',timeout:25000});
 assert.equal(result.error,undefined);assert.equal(result.status,0,result.stderr);
 const report=JSON.parse(result.stdout.trim());
 for(const field of ['passed','allFourByteMutationsRejected','initialShmMutationRejected','sidecarDisappearanceRejected','forgedProcessIdentityRejected','boundProcessStopped','entryPinnedReadStable'])assert.equal(report[field],true,field);
});
