import { execFileSync } from 'node:child_process';
import { readFileSync, statSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { cleanEnvironment, plainPath, sha256, fail } from '../package.mjs';
import { separatePaths } from './common.mjs';
export function protectedPath(target, root=false) {
 plainPath(target);
 const quote=s=>"'"+s.replaceAll("'","''")+"'";
 const script=fileURLToPath(new URL('./protected_paths.ps1',import.meta.url));
 execFileSync(path.join(process.env.SystemRoot,'System32/WindowsPowerShell/v1.0/powershell.exe'),
 ['-NoProfile','-NonInteractive','-Command',"$ErrorActionPreference='Stop'; . "+quote(script)+"; Assert-ProtectedPath "+quote(target)+(root?' -Root':'')],
 {env:cleanEnvironment(),windowsHide:true,timeout:10000,stdio:['ignore','pipe','pipe']});
}
function loadKey(filename,purpose) {
 if(path.basename(filename)!=='runtime-'+purpose+'.dpapi')fail('protected_key_filename_required');
 let key;
 try {
  key=execFileSync(path.join(process.env.SystemRoot,'System32/WindowsPowerShell/v1.0/powershell.exe'),
   ['-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-File',fileURLToPath(new URL('../key_custody.ps1',import.meta.url)),
    '-Action','Read','-KeyDirectory',path.dirname(filename),'-Purpose',purpose],
   {env:cleanEnvironment(),windowsHide:true,timeout:15000,maxBuffer:1024*1024,stdio:['ignore','pipe','pipe']});
 }catch{fail('protected_key_load_failed');}
 if(key.length!==32)fail('protected_key_length_invalid');
 return key;
}
export function parseConfiguration(value,binding) {
 const allowed=['format','manifest_sha256','database_path','node_id','owner_sid','companion_upload_mode','companion_reply_jobs','activity_enabled','domain_policy','pairing_secret','grants_path','grants_sha256','approvals_path','approvals_sha256','recovery_custody_directory','recovery_key_path','backup_directory','backup_key_path'];
 if(!value || typeof value!=='object' || Array.isArray(value) || Object.keys(value).some(k=>!allowed.includes(k))) fail('config_fields_rejected');
 if(value.format!=='schema6-config-v1' || value.manifest_sha256!==binding.manifest_sha256 || value.database_path!==binding.database_path
  || value.owner_sid!==binding.owner_sid || !(value.node_id===binding.node_id || (binding.provisioned_empty && value.node_id==='new')))
   fail('config_binding_mismatch');
 if(value.companion_upload_mode!=='legacy_b3' || value.companion_reply_jobs!==false || value.activity_enabled!==false || value.domain_policy!=='owner_managed')
  fail('explicit_safe_config_required');
 if(value.pairing_secret!==null && !/^[a-f0-9]{64}$/.test(value.pairing_secret??'')) fail('pairing_secret_invalid');
 for(const k of ['grants_sha256','approvals_sha256']) if(!/^[a-f0-9]{64}$/.test(value[k]??'')) fail('external_anchor_required');
 for(const k of ['grants_path','approvals_path','recovery_custody_directory','recovery_key_path']) if(typeof value[k]!=='string') fail('external_path_required');
 return value;
}
export function readConfiguration(filename,binding) {
 protectedPath(path.dirname(filename),true); protectedPath(filename);
 if(statSync(filename).size>16384) fail('config_size_rejected');
 let value; try{value=JSON.parse(readFileSync(filename,'utf8'));}catch{fail('config_json_rejected');}
 value=parseConfiguration(value,binding);
 for(const key of ['grants_path','approvals_path','recovery_key_path']) {
  protectedPath(path.dirname(value[key]),true); protectedPath(value[key]);
  separatePaths(path.dirname(binding.database_path),value[key],binding.release);
 }
 protectedPath(value.recovery_custody_directory,true);
 separatePaths(path.dirname(binding.database_path),value.recovery_custody_directory,binding.release);
 if(value.grants_path===value.approvals_path || value.recovery_key_path===filename) fail('external_paths_must_differ');
 for(const kind of ['grants','approvals']) if(sha256(readFileSync(value[kind+'_path']))!==value[kind+'_sha256']) fail('external_file_changed');
 if(value.backup_directory || value.backup_key_path) {
  protectedPath(value.backup_directory,true);protectedPath(path.dirname(value.backup_key_path),true);protectedPath(value.backup_key_path);
  separatePaths(path.dirname(binding.database_path),value.recovery_custody_directory,value.backup_directory,binding.release);
  if(value.backup_key_path===value.recovery_key_path) fail('backup_key_invalid');
 }
 const key=loadKey(value.recovery_key_path,'recovery');
 const backupKey=value.backup_key_path?loadKey(value.backup_key_path,'backup'):null;
 return {value,configurationHash:sha256(readFileSync(filename)),custodyKey:key,backupKey,options:{
  pairingCode:value.pairing_secret,activityAdminSecret:null,workerSecret:null,companionReplyJobsEnabled:false,
  companionUploadMode:'legacy_b3',localTranscriptGrantsPath:value.grants_path,historicalReplayApprovalsPath:value.approvals_path,shortcutMailRelay:null
 }};
}
