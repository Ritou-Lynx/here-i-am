import { existsSync } from 'node:fs';
import path from 'node:path';
import { fail } from './package.mjs';
import { recoverCanonicalState, RECOVERY_PENDING } from './recovery_adapter.mjs';
import { RAW_SUFFIXES } from './raw_state_backup.mjs';

export function needsStartupRecovery(databasePath,previous){
 if(existsSync(path.join(path.dirname(databasePath),RECOVERY_PENDING)))fail('recovery_interrupted_review_required');
 return !previous || previous.phase!=='clean_closed' || RAW_SUFFIXES.slice(1).some(s=>existsSync(databasePath+s));
}
export function recoverAtStartup({config,settings,previous,supervisorLease}){
 const databasePath=path.join(config.state,'i-core.sqlite');
 if(previous && (previous.format!=='schema6-lifecycle-v1'||previous.database_path!==databasePath
   ||previous.manifest_sha256!==config.manifest_sha256||previous.configuration_sha256!==settings.configurationHash
   ||!previous.node_id||!/^[a-f0-9]{64}$/.test(previous.custody_sha256??'')))fail('recovery_configuration_binding_mismatch');
 return recoverCanonicalState({databasePath,supervisorLease,custodyDirectory:settings.value.recovery_custody_directory,
  custodyKey:settings.custodyKey,backupDirectory:settings.value.backup_directory,backupKey:settings.backupKey,
  configurationHash:settings.configurationHash,manifestSha256:config.manifest_sha256,receiptId:config.token,
  expectedNodeId:previous?.node_id??settings.value.node_id,previousCustodySha256:previous?.custody_sha256??null,legacy:!previous});
}
