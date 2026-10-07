import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { lstatSync, rmSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import test from 'node:test';
import { syntheticRoot } from '../test_fixtures/release_schema6/synthetic_paths.mjs';
const source=fileURLToPath(new URL('../maintenance/owned_artifacts.ps1',import.meta.url));
const fixture=fileURLToPath(new URL('../test_fixtures/release_schema6/maintenance_owned_artifacts.ps1',import.meta.url));
test('Windows owned artifacts: native creation, readback, collisions and source lease rejection',{skip:process.platform!=='win32',timeout:60000},t=>{
 const root=syntheticRoot('maintenance-owned-artifacts-');const parent=path.dirname(root);
 t.after(()=>{assert.equal(path.dirname(path.resolve(root)),parent);assert.ok(path.basename(root).startsWith('maintenance-owned-artifacts-'));assert.equal(lstatSync(root).isSymbolicLink(),false);rmSync(root,{recursive:true,force:true});});
 const ps=path.join(process.env.SystemRoot,'System32','WindowsPowerShell','v1.0','powershell.exe');
 const result=spawnSync(ps,['-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-File',fixture,'-SourcePath',source,'-FixtureParent',root],{windowsHide:true,encoding:'utf8',timeout:55000,env:{...process.env,PSModulePath:path.join(path.dirname(ps),'Modules')}});
 assert.equal(result.error,undefined);assert.equal(result.status,0,`${result.stdout}\n${result.stderr}`);
 const r=JSON.parse(result.stdout.trim());assert.equal(r.passed,true);assert.equal(r.productionPathsTouched,false);assert.equal(r.privilegeEnabled,false);assert.equal(r.skipped,false);
 for(const name of ['directory_private_owner','directory_handle_identity_stable','directory_rename_denied','directory_rename_after_lease_release','file_private_owner','file_bytes_readback','real_prepare_consumer','duplicate_file_rejected','duplicate_file_bytes_preserved','wrong_owner_zero_artifact','hardlink_rejected','window_private_owner','guard_exclusive','guard_reacquired','old_window_id_rejected','directory_collision_preserves_sddl','ordinary_token_gate_matches_actual_token','ordinary_token_wrong_sid_rejected','acl_helper_wrong_hash_rejected_before_config','acl_helper_linked_source_rejected_before_config'])assert.ok(r.checks.includes(name),name);
 assert.equal(r.checks.length,20);assert.ok(['ordinary_owner','elevated_or_nonowner_default'].includes(r.tokenClassification));t.diagnostic(`${r.checks.length} native assertions; token ${r.tokenClassification}; no production state or privilege changes`);
});
