// SYNTHETIC ONLY. Never included in the release inventory. The recovery test loads
// a separate source copy with its one fixed lease import redirected here.
const capabilities = new WeakMap();
export function syntheticLease(evidence, hook = () => {}) {
 const capability = Object.freeze({ synthetic: true });
 capabilities.set(capability,{evidence,hook}); return capability;
}
export function assertOfflineLease(capability,{databasePath,phase}) {
 const known = capabilities.get(capability);
 if (!known) throw Object.assign(new Error('synthetic_capability_rejected'),{code:'synthetic_capability_rejected'});
 known.hook(phase);
 if (databasePath !== known.evidence.databasePath) throw Object.assign(new Error('synthetic_path_mismatch'),{code:'synthetic_path_mismatch'});
 return {...known.evidence,checkedAt:Date.now(),allCoreWritersStopped:true};
}
