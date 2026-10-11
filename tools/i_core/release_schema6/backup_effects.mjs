// Observation only: counters surround actual filesystem operations; policy is unchanged.
export function createEffectEvidence() {
 return {format:'i-core-backup-effects-v1',pruneBranchEntered:false,localRemovedBackupSets:0,mirrorRemovedBackupSets:0,deleteOperationsAttempted:0,deleteOperationsCompleted:0,mirrorAttempted:0,mirrorAlreadyPresent:0,mirrorCopied:0,mirrorPending:0,directoryCreateAttempted:0,directoryCreateCompleted:0,fileCopyAttempted:0,fileCopyCompleted:0,receiptWriteAttempted:0,receiptWriteCompleted:0,localValidatedReceipts:0,mirrorValidatedReceipts:0,measurementComplete:false,partial:false,failureStage:null};
}
export function observeEffect(e,kind,fn) {
 const fields={directory:['directoryCreateAttempted','directoryCreateCompleted'],copy:['fileCopyAttempted','fileCopyCompleted'],receipt:['receiptWriteAttempted','receiptWriteCompleted'],delete:['deleteOperationsAttempted','deleteOperationsCompleted']}[kind];
 if(!fields)throw new Error('effect_kind_rejected');
 e[fields[0]]++;
 try {const result=fn();e[fields[1]]++;return result;}
 catch(error){e.partial=true;e.measurementComplete=false;e.failureStage=kind;throw error;}
}
export function finishEffects(e) {e.measurementComplete=!e.partial;return {...e};}
