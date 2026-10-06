import { execFileSync } from 'node:child_process';
import { readFileSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { cleanEnvironment, plainPath, verifyRelease, fail } from '../package.mjs';
import { assertNode } from './common.mjs';
const leases=new WeakMap();
function probe(data,checkDatabase=true) {
 const ps=path.join(process.env.SystemRoot,'System32/WindowsPowerShell/v1.0/powershell.exe');
 execFileSync(ps,['-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-File',fileURLToPath(new URL('./probe_offline.ps1',import.meta.url)),
 '-ControlDirectory',data.control,'-RunId',data.token,'-ChildPid',String(process.pid),...(checkDatabase?['-CheckDatabase']:[])],
 {env:cleanEnvironment(),windowsHide:true,timeout:15000,stdio:['ignore','pipe','pipe']});
}
// Exported only for the fixed runtime child. A caller-supplied JSON object cannot
// satisfy the native Job membership and original-process/lock evidence.
export function createOfflineLease({control,token,config,cleanCloseReceipt,origin='canonical_restart'}) {
 assertNode();
 if(process.platform!=='win32' || process.argv[1]!==fileURLToPath(new URL('./runtime_child.mjs',import.meta.url))
  || process.argv[2]!==control || process.argv[3]!==token) fail('fixed_supervisor_child_required');
 verifyRelease(config.release,config.manifest_sha256);
 const onDisk=JSON.parse(readFileSync(plainPath(path.join(control,'launch.json'))));
 if(JSON.stringify(onDisk)!==JSON.stringify(config)) fail('offline_launch_unbound');
 let settings;try{settings=JSON.parse(readFileSync(plainPath(config.configuration_file)));}catch{fail('config_json_rejected');}
 const custodyDirectory=plainPath(settings.recovery_custody_directory);
 const data={control,token,config,databasePath:path.join(config.state,'i-core.sqlite'),custodyDirectory,cleanCloseReceipt,origin};
 probe(data,origin!=='empty_provision');
 const lease=Object.freeze({}); leases.set(lease,data); return lease;
}
// The fixed parent owns an actual FileShare.None handle throughout the child
// lifetime. A leftover filename is harmless after kernel handle cleanup.
export function withOfflineCustodyLock(lease,{databasePath,custodyDirectory},work){
 const data=leases.get(lease);
 if(!data||data.databasePath!==databasePath||data.custodyDirectory!==custodyDirectory)fail('trusted_custody_lease_required');
 probe(data);return work();
}
export function assertOfflineLease(lease,{databasePath,phase}) {
 const data=leases.get(lease);
 if(!data || data.databasePath!==databasePath || typeof phase!=='string') fail('trusted_offline_lease_required');
 plainPath(databasePath);
 const transactionPhases=new Set(['domain_before_backup','domain_before_ddl','domain_before_commit',
  'activity_after_ddl','activity_before_commit','activity_after_commit']);
 // Only reviewed migration checkpoints own a SQLite handle here. At these
 // checkpoints the Core holds its own transaction; retain OS identity/lock checks.
 probe(data,!transactionPhases.has(phase));
 return {databasePath,checkedAt:Date.now(),allCoreWritersStopped:true,origin:data.origin,cleanCloseReceipt:data.cleanCloseReceipt};
}
// Called only after a fixed child's store.close() has returned and a native
// exclusive DB-handle probe succeeds. Update never changes the branded lease.
export function recordClosedDatabase(lease,receipt) {
 const data=leases.get(lease); if(!data || receipt.databasePath!==data.databasePath) fail('trusted_offline_lease_required');
 probe(data); data.cleanCloseReceipt=Object.freeze({...receipt});
}
