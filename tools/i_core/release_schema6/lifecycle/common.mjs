import { existsSync, readFileSync, readdirSync, statSync, openSync, readSync, closeSync } from 'node:fs';
import { createHash } from 'node:crypto';
import path from 'node:path';
import { DatabaseSync } from 'node:sqlite';
import { pathToFileURL } from 'node:url';
import { plainPath, sha256, fail, PINNED_NODE_SHA256 } from '../package.mjs';
export const MARKER = 's6-lifecycle.json';
export const LOCK = 'shortcut-mail-relay.runtime.lock';
function fileSha256(filename) {
 const digest=createHash('sha256'),buffer=Buffer.alloc(1024*1024),fd=openSync(plainPath(filename),'r');
 try{let count;while((count=readSync(fd,buffer,0,buffer.length,null))>0)digest.update(buffer.subarray(0,count));return digest.digest('hex');}
 finally{buffer.fill(0);closeSync(fd);}
}

export function assertNode() {
 if (process.version !== 'v24.14.1' || fileSha256(process.execPath) !== PINNED_NODE_SHA256 || process.execArgv.length) fail('node_runtime_unbound');
}
export function separatePaths(...paths) {
 for (let i=0;i<paths.length;i++) for(let j=i+1;j<paths.length;j++) {
  const a=paths[i].toLowerCase(), b=paths[j].toLowerCase();
  if(a===b || a.startsWith(b+path.sep) || b.startsWith(a+path.sep)) fail('paths_must_be_separate');
 }
}
export function closedStateSnapshot(root) {
 let databaseSha256=null;
 plainPath(root);
 const walk = (directory, prefix='') => readdirSync(directory,{withFileTypes:true}).sort((a,b)=>a.name<b.name?-1:1).flatMap(e=>{
  const relative=prefix+e.name;
  if(!prefix && [MARKER,LOCK].includes(e.name)) return [];
  const filename=plainPath(path.join(directory,e.name));
  if(e.isDirectory()) return [[relative+'/',null],...walk(filename,relative+'/')];
  if(!e.isFile()) fail('state_inventory_invalid');
  const digest=fileSha256(filename);if(relative==='i-core.sqlite')databaseSha256=digest;
  return [[relative,digest]];
 });
 const stateTreeSha256=sha256(JSON.stringify(walk(root)));
 return {stateTreeSha256,databaseSha256};
}
export function stateDigest(root) {return closedStateSnapshot(root).stateTreeSha256;}
export function inspectExisting(filename, versions=['6']) {
 plainPath(filename);
 for(const suffix of ['-wal','-shm','-journal']) if(existsSync(filename+suffix)) fail('state_sidecars_require_review');
 const before=fileSha256(filename);
 const db=new DatabaseSync(pathToFileURL(filename).href+'?mode=ro&immutable=1',{readOnly:true});
 try {
  const meta=new Map(db.prepare('SELECT key,value FROM core_metadata').all().map(r=>[r.key,r.value]));
  const version=meta.get('schema_version');
  if(!versions.includes(version) || !meta.get('node_id') || !meta.get('cursor_secret')) fail('existing_core_identity_or_schema_required');
  if(meta.get('domain_backup_role')) fail('backup_activation_unsupported');
  if(db.prepare('PRAGMA quick_check').get().quick_check!=='ok') fail('integrity_check_failed');
  if(version!=='4') {
   if(db.prepare("SELECT value FROM activity_metadata WHERE key='database_role'").get()?.value!=='live') fail('backup_activation_unsupported');
   const claim=db.prepare('SELECT runtime_id,lease_expires_at_ms FROM activity_runtime_claim WHERE singleton=1').get();
   if(!claim || claim.runtime_id!=='' || claim.lease_expires_at_ms!==0) fail('activity_recovery_required');
  }
  return {version,nodeId:meta.get('node_id'),database_sha256:before};
 } finally { db.close(); if(fileSha256(filename)!==before) fail('state_changed_during_preflight'); }
}
export function validatePrevious(marker, config, before, configurationHash) {
 if(!marker || marker.format!=='schema6-lifecycle-v1' || marker.phase!=='clean_closed'
  || marker.database_path!==path.join(config.state,'i-core.sqlite')
  || marker.database_sha256!==before.database_sha256 || marker.node_id!==before.nodeId
  || marker.manifest_sha256!==config.manifest_sha256 || marker.configuration_sha256!==configurationHash
  || marker.state_tree_sha256!==stateDigest(config.state)
  || !/^[a-f0-9]{64}$/.test(marker.custody_sha256??'')
  || marker.supervisor?.job_empty_confirmed!==true || marker.supervisor?.child_exit_code!==0
  || marker.supervisor?.guardian_exit_code!==0 || marker.supervisor?.termination_requested!==false)
   fail('recovery_required');
 return marker;
}

const SAFE_STARTUP_CODES=new Set([
 'domain_receipt_authentication_failed','domain_operation_authentication_failed','domain_record_result_mismatch','domain_record_envelope_invalid',
 'domain_accepted_target_invalid','domain_record_witness_limit', 'recovery_witness_unavailable', 'offline_probe_failed', 'offline_probe_cleanup_failed','domain_record_revision_invalid','old_domain_witness_unverifiable',
 'domain_record_rollback_rejected','domain_record_advance_unproven','domain_record_materialization_mismatch',
 'active_runtime_claim','activity_authority_busy','activity_database_binding_invalid','activity_database_binding_mismatch','activity_database_role_changed',
 'activity_disabled','activity_floor_not_created','activity_floor_required','activity_integrity_upgrade_unsupported','activity_migration_incomplete',
 'activity_preflight_prefix_invalid','activity_preflight_unstable','activity_recovery_required','activity_retention_authority_required','activity_retention_failed',
 'activity_role_unverified','activity_rollback_requires_empty_domain','activity_schema_not_ready','approval_duplicate_identity','approval_invalid',
 'approval_ledger_set_mismatch','artifact_anchor_required','artifact_changed','artifact_hash_mismatch','authority_secret_conflict',
 'backup_activation_unsupported','backup_authentication_failed','backup_child_rejected','backup_ciphertext_changed','backup_destination_exists',
 'backup_directory_changed','backup_directory_inside_scratch','backup_entry_hash_mismatch','backup_format_invalid','backup_json_invalid',
 'backup_key_invalid','backup_key_not_independent','backup_key_required','backup_manifest_changed','backup_manifest_invalid',
 'backup_missing_without_cleanup_receipt','backup_spec_invalid','backup_trailing_data','backup_truncated','backup_verification_failed',
 'batch_too_large','cancelled_before_store','clean_close_identity_mismatch','clean_close_receipt_required','cleanup_owner_authorization_required',
 'closed_identity_mismatch','companion_executor_conflict','companion_jobs_conflict','companion_publish_shadow_only','companion_upload_mode_conflict',
 'component_cannot_be_disabled','config_binding_mismatch','config_fields_rejected','config_json_rejected','config_size_rejected',
 'control_receipt_exists','copy_artifact_changed','copy_consistency_unverified','copy_descriptor_changed','copy_descriptor_unverified',
 'copy_must_be_distinct_from_live_path','copy_read_only_marker_changed','copy_replace_unverified','copy_source_binding_mismatch','copy_validation_authorization_required',
 'core_device_rollback_rejected','core_error','core_identity_invalid','core_identity_or_schema_invalid','core_identity_rollback_rejected',
 'core_metadata_invariant_failed','core_sequence_rollback_rejected','custody_authentication_failed','custody_collision','custody_context_invalid',
 'custody_context_required','custody_digest_mismatch','custody_genesis_not_empty','custody_head_chain_invalid','custody_head_changed',
 'custody_head_invalid','custody_head_rollback_rejected','custody_head_write_unverified','custody_identity_mismatch','custody_invalid',
 'custody_key_not_independent','custody_lock_lost','custody_must_be_independent','custody_too_large','custody_write_unverified',
 'database_binding_mismatch','database_changed_before_custody_commit','database_changed_during_inspection','database_integrity_failed','database_metadata_mismatch',
 'database_path_changed','database_path_missing','database_sidecar_rejected','device_mismatch','device_not_found',
 'disabled_component_evidence_required','domain_principal_rollback_rejected','domain_progress_rollback_rejected','domain_rollback_not_empty','domain_schema_conflict',
 'domain_schema_present','domain_schema_verifier_required','duplicate_inventory_entry','durable_ledger_required','dynamic_dependency_requires_review',
 'empty_provision_backup_required','event_id_prefix_collision','event_id_prefix_invalid','event_retained_out','exact_72_bindings_required',
 'existing_core_identity_or_schema_required','explicit_safe_config_required','external_anchor_required','external_file_changed','external_file_hash_mismatch',
 'external_path_required','external_paths_must_differ','fixed_supervisor_child_required','fresh_inspection_directory_required','fresh_output_required',
 'genesis_close_unconfirmed','grant_character_mismatch','grant_current_credential_mismatch','grant_invalid','grant_primary_character_mismatch',
 'historical_digest_mismatch','historical_event_identity_mismatch','historical_row_invalid','idempotency_conflict','identity_binding_mismatch',
 'immutable_message_conflict','independent_backup_key_required','independent_custody_head_required','independent_custody_key_required','independent_output_required',
 'independent_recovery_floor_required','initial_backup_binding_mismatch','initial_backup_database_mismatch','initialize_requires_empty_state','input_changed_during_preflight',
 'input_missing_or_aliased','input_paths_must_differ','input_size_exceeded','inspection_activation_unsupported','inspection_baseline_mismatch',
 'inspection_baseline_required','inspection_business_route_exposed','inspection_configuration_rejected','inspection_data_changed','inspection_database_changed',
 'inspection_database_hash_mismatch','inspection_file_changed','inspection_health_failed','inspection_must_be_separate','inspection_path_collision',
 'inspection_path_escape','inspection_probe_timeout','inspection_report_limit_exceeded','inspection_response_oversized','integrity_check_failed',
 'interrupted_migration_review_required','invalid_authority_configuration','invalid_cleanup_mode','invalid_companion_upload_mode','invalid_coverage',
 'invalid_cursor','invalid_diagnostic_token','invalid_identifier','invalid_internal_arguments','invalid_json',
 'invalid_pairing_code','invalid_request','invalid_time_range','inventory_entry_invalid','inventory_invalid',
 'inventory_limit_exceeded','inventory_role_missing','launch_identity_mismatch','lease_not_found','ledger_too_large',
 'legacy_content_changed','legacy_schema4_required','linked_path_rejected','local_drive_path_required','local_transcript_forbidden',
 'local_transcript_grants_invalid','local_transcript_scope_mismatch','logical_name_invalid','manifest_anchor_required','manifest_contract_mismatch',
 'manifest_hash_mismatch','manifest_size_exceeded','missing_required_field','node_hash_mismatch','node_runtime_unbound',
 'nonempty_grants_required','not_found','offline_backup_configuration_required','offline_launch_unbound','offline_proof_required',
 'offline_supervisor_adapter_required','offline_supervisor_capability_required','old_custody_progress_unverifiable','old_manifest_anchor_mismatch','origin_sequence_conflict',
 'pairing_secret_invalid','paths_must_be_separate','payload_too_large','phone_device_required','phone_reply_request_forbidden',
 'plain_absolute_path_required','primary_character_mismatch','principal_not_found','principal_revoked','private_inspection_parent_required',
 'private_output_required','probe_already_paired','probe_not_found','progress_sequence_invalid','progress_witness_required',
 'protected_key_filename_required','protected_key_length_invalid','protected_key_load_failed','protocol_mismatch','quiescent_checkpointed_copy_required',
 'rate_limited','raw_backup_must_be_external','raw_ciphertext_changed','raw_ciphertext_invalid','raw_ciphertext_truncated',
 'raw_copy_mismatch','raw_manifest_changed','raw_manifest_invalid','raw_plaintext_mismatch','raw_restore_mismatch',
 'raw_source_changed','raw_state_file_invalid','reader_already_paired','recovery_configuration_binding_mismatch','recovery_configuration_binding_required',
 'recovery_custody_invalid','recovery_floor_required','recovery_history_diverged','recovery_interrupted_review_required','recovery_lineage_unverified',
 'recovery_required','recovery_requires_normal_start','release_file_changed','release_inventory_mismatch','release_path_mismatch',
 'replay_device_invalid','request_too_large','reserved_sequence_collision','resource_close_unconfirmed','resync_required',
 'revoked_replay','runtime_identity_mismatch','runtime_operation_failed','schema4_custody_history_exists','schema4_genesis_not_empty',
 'schema6_required','schema_not_ready','scope_denied','secret_in_argument_path_rejected','singleton_role_required',
 'source_binding_mismatch','source_changed','source_commit_required','source_commit_unresolved','sqlite_sidecars_not_quiescent',
 'stale_activity_restore','stale_activity_runtime','stale_authority_epoch','state_changed_during_preflight','state_inventory_invalid',
 'state_sidecars_require_review','synthetic_smoke_timeout','test_hook_forbidden','trusted_anchor_mismatch','trusted_custody_lease_required',
 'trusted_offline_lease_required','ttl_expired','unauthorized','unknown_field','unlisted_runtime_dependency',
 'unregistered_diagnostic','unsafe_backup_cleanup_path','unsafe_database_path','unsafe_path','unsupported_core_schema_version',
 'unsupported_kind','unsupported_transition','usage_domain_migrate_database_path','usage_prepare_verify_or_explicit_preflight_only','windows_acl_unavailable'
]);
export function publicLifecycleErrorCode(error){
 const candidate=typeof error?.code==='string'?error.code:error?.message;
 return SAFE_STARTUP_CODES.has(candidate)?candidate:'runtime_operation_failed';
}
export function readConfigurationDeclaration(filename){
 plainPath(filename);
 if(statSync(filename).size>16384)fail('config_size_rejected');
 let value;try{value=JSON.parse(readFileSync(filename,'utf8'));}catch{fail('config_json_rejected');}
 return {node_id:value?.node_id};
}
