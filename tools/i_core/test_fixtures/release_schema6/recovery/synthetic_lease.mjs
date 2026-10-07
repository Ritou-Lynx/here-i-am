// SYNTHETIC ONLY. Never included in the release inventory. The recovery test loads
// a separate source copy with its one fixed lease import redirected here.
import { closeSync, mkdirSync, openSync, unlinkSync } from 'node:fs';
import path from 'node:path';
const capabilities = new WeakMap();
export function syntheticLease(evidence, hook = () => {}) {
 const capability = Object.freeze({ synthetic: true });
 capabilities.set(capability,{evidence,hook}); return capability;
}
// Synthetic-only concurrency stand-in. Production relies exclusively on the
// fixed parent's native held handle; it never accepts this test capability.
export function withOfflineCustodyLock(capability,{databasePath,custodyDirectory},work){
 assertOfflineLease(capability,{databasePath,phase:'synthetic_custody_scope'});
 mkdirSync(custodyDirectory,{recursive:true});const file=path.join(custodyDirectory,'custody.lock');let fd;
 try{fd=openSync(file,'wx',0o600);}catch{throw Object.assign(new Error('custody_concurrent_operation'),{code:'custody_concurrent_operation'});}
 try{return work();}finally{closeSync(fd);unlinkSync(file);}
}
export function assertOfflineLease(capability,{databasePath,phase}) {
 const known = capabilities.get(capability);
 if (!known) throw Object.assign(new Error('synthetic_capability_rejected'),{code:'synthetic_capability_rejected'});
 known.hook(phase);
 if (databasePath !== known.evidence.databasePath) throw Object.assign(new Error('synthetic_path_mismatch'),{code:'synthetic_path_mismatch'});
 return {...known.evidence,checkedAt:Date.now(),allCoreWritersStopped:true};
}
