import test from 'node:test';
import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import {mkdtempSync,rmSync,readFileSync,writeFileSync,mkdirSync,realpathSync} from 'node:fs';
import {tmpdir} from 'node:os';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {validateMaintenanceOutputs} from '../maintenance/maintenance_outputs.mjs';
const repository=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'../../..');
const fixtureParent=realpathSync.native(tmpdir());
test('standalone Prepare CLI uses real cross-process guard, releases it and preserves bytes',{skip:process.platform!=='win32',timeout:60000},()=>{
 const ps=path.join(process.env.SystemRoot,'System32/WindowsPowerShell/v1.0/powershell.exe');
 const raw=execFileSync(ps,['-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-File',path.join(repository,'tools/i_core/test_fixtures/release_schema6/maintenance_prepare_guard.ps1'),'-Repository',repository,'-NodePath',process.execPath,'-FixtureParent',fixtureParent],{windowsHide:true,encoding:'utf8',timeout:50000});
 const r=JSON.parse(raw);for(const k of ['passed','standaloneCliContentionRejected','releasedGuardReachedNextGate','guardBytesPreserved','noReceiptWritten'])assert.equal(r[k],true,k);assert.equal(r.tasksCreated,0);
});
test('output scope rejects journal collision, aliases and paths outside exact frozen window',()=>{
 const root=realpathSync.native(mkdtempSync(path.join(fixtureParent,'maintenance-prepare-scope-')));
 try{
 const maintenanceRoot=path.join(root,'maintenance'),windowId='synthetic-prepare',windowDirectory=path.join(maintenanceRoot,'windows',windowId);mkdirSync(windowDirectory,{recursive:true});
 const rawPaths=['db','db-wal','db-shm','db-journal'].map(n=>path.join(root,n));writeFileSync(rawPaths[3],'unchanged-journal');
 const c={maintenanceRoot,windowId,rawPaths,externalFiles:{approvals:[path.join(root,'approvals.json')],grants:[path.join(root,'grants.json')]},aclExpected:{paths:[path.join(root,'db')]},ownerApprovalPath:path.join(windowDirectory,'owner.json'),frozenReceiptPath:path.join(windowDirectory,'frozen.json'),aclReceiptPath:path.join(windowDirectory,'acl.json'),approvedXmlPath:path.join(windowDirectory,'approved.xml'),loginConfigurationPath:path.join(windowDirectory,'login.json'),outputXmlPath:path.join(windowDirectory,'prepared.xml'),preparedReceiptPath:path.join(windowDirectory,'prepared.json'),registrationReceiptPath:path.join(windowDirectory,'registered.json')};
 assert.ok(validateMaintenanceOutputs(c,{windowDirectory}));
 for(const patch of [{outputXmlPath:rawPaths[3]},{preparedReceiptPath:c.outputXmlPath},{registrationReceiptPath:path.join(root,'outside.json')},{outputXmlPath:c.approvedXmlPath}])assert.throws(()=>validateMaintenanceOutputs({...c,...patch},{windowDirectory}));
 assert.equal(readFileSync(rawPaths[3],'utf8'),'unchanged-journal');
 }finally{rmSync(root,{recursive:true,force:true});}
});
