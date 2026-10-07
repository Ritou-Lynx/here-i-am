// Versioned maintenance entry; not part of the fixed runtime. No work on import.
import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { readFileSync, existsSync, lstatSync, realpathSync } from 'node:fs';
import { createHash } from 'node:crypto';
import path from 'node:path';
import { pathToFileURL, fileURLToPath } from 'node:url';
const sha256=b=>createHash('sha256').update(b).digest('hex');
function plainPath(p,{missing=false}={}) {
 assert.equal(typeof p,'string');assert.ok(path.isAbsolute(p)&&path.normalize(p)===p&&!p.includes(':',2));
 for(let q=p;;q=path.dirname(q)){if(existsSync(q)){const s=lstatSync(q);assert.ok(!s.isSymbolicLink()&&(!s.isFile()||s.nlink===1));}if(path.dirname(q)===q)break;}
 if(!missing)assert.equal(realpathSync.native(p).toLowerCase(),p.toLowerCase());return p;
}
const hash = /^[a-f0-9]{64}$/;
const json = p => JSON.parse(readFileSync(plainPath(p), 'utf8'));
function anchored(p, h) { assert.match(h, hash); const b=readFileSync(plainPath(p)); assert.equal(sha256(b),h); return b; }
export function validateFrozenReceipt(f, c) {
 assert.equal(f.format,'schema6-frozen-legacy-runtime-ready-v2');
 assert.equal(f.passed,true); assert.equal(f.windowId,c.windowId);
 assert.equal(f.candidateSourceCommit,c.candidateSourceCommit);
 assert.equal(f.candidateManifestSha256,c.candidateManifestSha256);
 assert.equal(f.approvedXmlSha256,c.approvedXmlSha256);
 assert.equal(f.databaseReplaced,false);assert.equal(f.aclApplied,false);assert.ok(f.observationMs>=65000);
 const now=Date.now(),start=Date.parse(f.createdUtc),end=Date.parse(f.expiresUtc);
 assert.ok(Number.isFinite(start)&&Number.isFinite(end)&&start<=now&&now<=end&&end>start&&end-start<=60*60*1000);
 assert.equal(c.aclExpected.notBeforeUtc,f.createdUtc);assert.equal(c.aclExpected.notAfterUtc,f.expiresUtc);
 assert.ok(c.frozenTaskNames.length>0); assert.equal(new Set(c.frozenTaskNames).size,c.frozenTaskNames.length);
 assert.deepEqual(f.tasks.map(t=>t.name).sort(),[...c.frozenTaskNames].sort());
 for(const t of f.tasks){assert.equal(t.disabled,true);for(const k of ['triggers','retries','instances'])assert.equal(t[k],0);assert.equal(typeof t.taskPath,'string');assert.match(t.taskPath,/^\\(?:[^\\\r\n]+\\)*$/);assert.match(t.originalXmlSha256,hash);assert.match(t.frozenXmlSha256,hash);assert.ok(typeof t.originalSddl==='string'&&t.originalSddl.length>0);}
 assert.ok(c.frozenPorts.length>0);assert.deepEqual(f.portsFree.slice().sort(),c.frozenPorts.slice().sort());
 assert.equal(c.rawPaths.length,4);assert.equal(new Set(c.rawPaths).size,4);
 assert.deepEqual(f.rawAfter.map(r=>r.path).sort(),c.rawPaths.slice().sort());
 for(const r of f.rawAfter){assert.equal(typeof r.exists,'boolean');if(r.exists){assert.match(r.sha256,hash);assert.ok(Number.isSafeInteger(r.size)&&r.size>=0);}}
 assert.ok(Object.keys(c.externalFiles).length>0);
 assert.deepEqual(Object.keys(f.external).sort(),Object.keys(c.externalFiles).sort());
 for(const r of Object.values(f.external)){assert.match(r.sha256,hash);assert.ok(Number.isSafeInteger(r.size)&&r.size>=0);}
 return true;
}
export function taskSecurityBindings(c) {
 assert.equal(Object.hasOwn(c,'approvedSddl'),false);
 for(const k of ['registrationSddl','expectedRegisteredSddl'])assert.ok(typeof c[k]==='string'&&c[k].length>0);
 assert.match(c.parentSddlSha256,hash);assert.equal(c.taskSecurityPolicyVersion,'windows-file-oi-v1');
 assert.ok(Array.isArray(c.inheritedReadOnlyPrincipals));
 let previous='';
 for(const item of c.inheritedReadOnlyPrincipals){
  assert.deepEqual(Object.keys(item).sort(),['flags','mask','sid']);
  assert.match(item.sid,/^S-1-(?:[0-9]+-)*[0-9]+$/);assert.equal(item.flags,16);assert.match(item.mask,/^[0-9A-F]{8}$/);
  const rights=Number.parseInt(item.mask,16);assert.equal((rights&~0x00120089)>>>0,0);
  assert.equal([c.ownerSid,'S-1-5-18','S-1-5-32-544'].includes(item.sid),false);
  const key=item.sid+'|'+item.flags;assert.ok(key>previous);previous=key;
 }
 return {registrationSddlSha256:sha256(c.registrationSddl),expectedRegisteredSddlSha256:sha256(c.expectedRegisteredSddl),parentSddlSha256:c.parentSddlSha256,taskSecurityPolicyVersion:c.taskSecurityPolicyVersion,inheritedReadOnlyPrincipals:c.inheritedReadOnlyPrincipals};
}
export async function validatePreparationInputs(c) {
 assert.equal(c.format,'schema6-maintenance-login-config-v2');assert.match(c.windowId,/^[A-Za-z0-9][A-Za-z0-9_-]{7,79}$/);
 assert.match(c.candidateSourceCommit,/^[a-f0-9]{40}$/);assert.match(c.taskName,/^[A-Za-z0-9][A-Za-z0-9_.-]{0,180}$/);
 assert.equal(c.frozenTaskNames.some(n=>n.toLowerCase()===c.taskName.toLowerCase()),false);
 assert.equal(typeof c.ownerSid,'string');assert.match(c.ownerSid,/^S-1-/);taskSecurityBindings(c);
 const approval=JSON.parse(anchored(c.ownerApprovalPath,c.ownerApprovalSha256));
 assert.equal(approval.format,'schema6-owner-gates-approved-v2');assert.equal(Object.hasOwn(approval,'approved_sddl'),false);assert.equal(approval.windowId,c.windowId);
 assert.equal(approval.candidateSourceCommit,c.candidateSourceCommit);assert.equal(approval.candidateManifestSha256,c.candidateManifestSha256);
 assert.equal(approval.task_name,c.taskName);assert.equal(approval.owner_sid,c.ownerSid);assert.equal(approval.registration_sddl,c.registrationSddl);assert.equal(approval.expected_registered_sddl,c.expectedRegisteredSddl);
 assert.equal(approval.parent_sddl_sha256,c.parentSddlSha256);assert.equal(approval.task_security_policy_version,c.taskSecurityPolicyVersion);
 assert.deepEqual(approval.inherited_read_only_principals,c.inheritedReadOnlyPrincipals);
 assert.equal(approval.xml_review_sha256,c.approvedXmlSha256);assert.equal(approval.login_sha256,c.loginConfigurationSha256);
 assert.equal(approval.require_fixed_prepare_identical,true);
 const frozen=JSON.parse(anchored(c.frozenReceiptPath,c.frozenReceiptSha256));validateFrozenReceipt(frozen,c);
 const {validateMaintenanceOutputs}=await import('./maintenance_outputs.mjs');validateMaintenanceOutputs(c,frozen);
 const acl=JSON.parse(anchored(c.aclReceiptPath,c.aclReceiptSha256));
 for(const [key,value] of Object.entries({windowId:c.windowId,candidateSourceCommit:c.candidateSourceCommit,candidateManifestSha256:c.candidateManifestSha256,freezeSha256:c.frozenReceiptSha256}))assert.equal(c.aclExpected[key],value);
 const {validateAclApplyReceipt}=await import('./acl_receipt.mjs');
 validateAclApplyReceipt(acl,c.aclExpected);
 anchored(c.loginConfigurationPath,c.loginConfigurationSha256);anchored(c.approvedXmlPath,c.approvedXmlSha256);
 return { frozen, approval };
}
export function validatePreparedReceipt(r,c) {
 assert.equal(r.format,'schema6-production-login-prepare-v3');
 for(const k of ['passed','fixed_prepare_validated','identical_to_approved_xml'])assert.equal(r[k],true);
 for(const k of ['registered','started'])assert.equal(r[k],false);
 for(const k of ['windowId','candidateSourceCommit','candidateManifestSha256','frozenReceiptSha256','ownerApprovalSha256','aclReceiptSha256','approvedXmlSha256','loginConfigurationSha256','taskName'])assert.equal(r[k],c[k]);
 for(const [k,v] of Object.entries(taskSecurityBindings(c)))assert.deepEqual(r[k],v);
 assert.equal(r.outputXmlPath,c.outputXmlPath);
 assert.deepEqual(anchored(c.outputXmlPath,c.approvedXmlSha256),anchored(c.approvedXmlPath,c.approvedXmlSha256));
 return true;
}
export async function prepareProductionLogin(c,{validateOnly=false,configurationPath}={}) {
 const own=path.dirname(fileURLToPath(import.meta.url));
 const required=['register-approved-login.ps1','register_task_primitives.ps1','task_security_policy.ps1','maintenance_window.ps1','owned_artifacts.ps1','prepare-production-login.mjs','prepare-production-login.ps1','prepare_live_guard.ps1','acl_receipt.mjs','maintenance_outputs.mjs'].map(n=>path.join(own,n));
 required.push(path.resolve(own,'../release_schema6/package.mjs'));
 assert.equal(new Set(c.maintenanceFiles.map(e=>e.path)).size,c.maintenanceFiles.length);
 for(const p of required){const entries=c.maintenanceFiles.filter(e=>e.path===p);assert.equal(entries.length,1);anchored(p,entries[0].sha256);}
 const {verifyRelease,cleanEnvironment,PINNED_NODE_SHA256}=await import('../release_schema6/package.mjs');
 assert.equal(process.platform,'win32');assert.equal(sha256(readFileSync(process.execPath)),PINNED_NODE_SHA256);
 const verified=verifyRelease(c.releaseDirectory,c.candidateManifestSha256);
 assert.equal(verified.source_commit,c.candidateSourceCommit);
 const ps=path.join(process.env.SystemRoot,'System32','WindowsPowerShell','v1.0','powershell.exe');
 assert.equal(path.isAbsolute(ps)&&path.normalize(ps)===ps,true);
 const privateInputs=[configurationPath,c.ownerApprovalPath,c.frozenReceiptPath,c.aclReceiptPath,c.approvedXmlPath,c.loginConfigurationPath,...c.maintenanceFiles.map(e=>e.path),path.dirname(c.outputXmlPath),path.dirname(c.preparedReceiptPath)];
 if(validateOnly)privateInputs.push(c.outputXmlPath,c.preparedReceiptPath);
 for(const p of privateInputs)plainPath(p);
 const quote=v=>"'"+v.replaceAll("'","''")+"'";
 const checks='. '+quote(path.join(c.releaseDirectory,'tools/i_core/release_schema6/lifecycle/protected_paths.ps1'))+'; '+privateInputs.map(p=>'Assert-ProtectedPath '+quote(p)).join('; ');
 if(!validateOnly)execFileSync(ps,['-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-Command','. '+quote(path.join(own,'owned_artifacts.ps1'))+'; Assert-OwnedArtifactUnelevatedProcess '+quote(c.ownerSid)],{env:cleanEnvironment(),windowsHide:true,stdio:['ignore','pipe','pipe'],timeout:30000});
 execFileSync(ps,['-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-Command',checks],{env:cleanEnvironment(),windowsHide:true,stdio:['ignore','pipe','pipe'],timeout:30000});
 assert.deepEqual(json(configurationPath),c);
 await validatePreparationInputs(c);
 // Read-only parent COM checks apply to the direct API as well as its guarded
 // PS writer. They neither register tasks nor change the inheritance oracle.
 const securityChecks='. '+quote(path.join(own,'register_task_primitives.ps1'))+'; . '+quote(path.join(own,'task_security_policy.ps1'))+'; $c=Get-Content -LiteralPath '+quote(configurationPath)+' -Raw|ConvertFrom-Json; $s=New-Object -ComObject Schedule.Service; $s.Connect(); $null=Assert-TaskSecurityPolicy $c ($s.GetFolder("\\").GetSecurityDescriptor(7));';
 const assertParent=()=>execFileSync(ps,['-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-Command',securityChecks],{env:cleanEnvironment(),windowsHide:true,stdio:['ignore','pipe','pipe'],timeout:30000});
 assertParent();
 if(validateOnly){validatePreparedReceipt(json(c.preparedReceiptPath),c);return {validated:true,registered:false,started:false};}
 assert.equal(existsSync(c.outputXmlPath),false);assert.equal(existsSync(c.preparedReceiptPath),false);
 const raw=execFileSync(ps,['-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-File',path.join(c.releaseDirectory,'tools/i_core/release_schema6/lifecycle/prepare_login_schema6.ps1'),'-ReleaseDirectory',c.releaseDirectory,'-ManifestSha256',c.candidateManifestSha256,'-LoginConfigurationPath',c.loginConfigurationPath,'-LoginConfigurationSha256',c.loginConfigurationSha256,'-OutputXml',c.outputXmlPath,'-PrepareOnly'],{env:cleanEnvironment(),windowsHide:true,encoding:'utf8',stdio:['ignore','pipe','pipe'],timeout:120000,maxBuffer:65536});
 const prepared=JSON.parse(raw);assert.equal(prepared.prepared,true);assert.equal(prepared.registered,false);assert.equal(prepared.started,false);
 assert.equal(prepared.manifest_sha256,c.candidateManifestSha256);assert.equal(prepared.login_configuration_sha256,c.loginConfigurationSha256);
 assert.deepEqual(anchored(c.outputXmlPath,c.approvedXmlSha256),anchored(c.approvedXmlPath,c.approvedXmlSha256));
 assertParent();
 const report={...taskSecurityBindings(c),format:'schema6-production-login-prepare-v3',passed:true,fixed_prepare_validated:true,identical_to_approved_xml:true,registered:false,started:false,outputXmlPath:c.outputXmlPath};
 for(const k of ['windowId','candidateSourceCommit','candidateManifestSha256','frozenReceiptSha256','ownerApprovalSha256','aclReceiptSha256','approvedXmlSha256','loginConfigurationSha256','taskName'])report[k]=c[k];
 // Only the PS owner of the guard publishes this report, after its second live
 // freeze check. The API returns evidence; it never publishes a ready receipt.
 validatePreparedReceipt(report,c);return report;
}
export function dispatchPrepareCli(configurationPath,configurationSha256) {
 const c=JSON.parse(anchored(configurationPath,configurationSha256));
 const entry=path.join(path.dirname(fileURLToPath(import.meta.url)),'prepare-production-login.ps1');
 const pins=c.maintenanceFiles.filter(p=>p.path===entry);assert.equal(pins.length,1);anchored(entry,pins[0].sha256);
 const ps=path.join(process.env.SystemRoot,'System32','WindowsPowerShell','v1.0','powershell.exe');assert.ok(path.isAbsolute(ps)&&path.normalize(ps)===ps);
 const env=Object.fromEntries(Object.entries(process.env).filter(([k])=>['SYSTEMROOT','WINDIR','TEMP','TMP','COMSPEC'].includes(k.toUpperCase())));env.PATHEXT='.EXE';
 const quote=v=>"'"+v.replaceAll("'","''")+"'";
 // FileShare.Read leases bridge the hash-to-execution interval. The PS entry
 // also pins itself/its dependency closure, but only after this outer lease.
 const bootstrap=`$ErrorActionPreference='Stop';$c=$null;$s=$null;function H($h){$a=[Security.Cryptography.SHA256]::Create();try{$h.Position=0;return ([BitConverter]::ToString($a.ComputeHash($h))).Replace('-','').ToLowerInvariant()}finally{$a.Dispose();$h.Position=0}};try{$c=[IO.File]::Open(${quote(configurationPath)},[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read);if((H $c)-cne ${quote(configurationSha256)}){throw 'configuration_hash_rejected'};$s=[IO.File]::Open(${quote(entry)},[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read);if((H $s)-cne ${quote(pins[0].sha256)}){throw 'prepare_source_hash_rejected'};& ${quote(entry)} -ConfigPath ${quote(configurationPath)} -ExpectedConfigSha256 ${quote(configurationSha256)};exit $LASTEXITCODE}finally{if($s){$s.Dispose()};if($c){$c.Dispose()}}`;
 const raw=execFileSync(ps,['-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-EncodedCommand',Buffer.from(bootstrap,'utf16le').toString('base64')],{env,windowsHide:true,encoding:'utf8',stdio:['ignore','pipe','pipe'],maxBuffer:65536});return JSON.parse(raw);
}
if(process.argv[1]&&import.meta.url===pathToFileURL(path.resolve(process.argv[1])).href){
 try {assert.ok(process.argv[2]==='--config'&&process.argv[4]==='--config-sha256'&&[6,7].includes(process.argv.length));assert.ok(process.argv.length===6||process.argv[6]==='--validate-registration');
  const result=process.argv[6]==='--validate-registration'?await prepareProductionLogin(JSON.parse(anchored(process.argv[3],process.argv[5])),{validateOnly:true,configurationPath:process.argv[3]}):dispatchPrepareCli(process.argv[3],process.argv[5]);process.stdout.write(JSON.stringify(result)+'\n');
 }catch{process.stdout.write(JSON.stringify({passed:false,code:'production_login_prepare_rejected',registered:false,started:false})+'\n');process.exitCode=2;}
}
