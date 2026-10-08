// Offline preparation only. Never stop/start processes or register/update tasks.
import { readFileSync, writeFileSync } from 'node:fs';
import path from 'node:path';
import { pathToFileURL } from 'node:url';
import { plainPath, sha256, fail } from '../release_schema6/package.mjs';
import { verifySwitchConfigurations } from '../release_schema6/package_switch.mjs';
import { validatePackageSwitchBindings } from './package-switch-bindings.mjs';
export function preparePackageSwitch(input){
 const {operationId,from,to,headPath,markerPath,artifacts,rollbackOf=null}=input;
 if(!(/^[a-zA-Z0-9_-]{8,80}$/).test(operationId??''))fail('switch_plan_invalid');
 const endpoints=[from,to].map(e=>({...e,configurationSha256:sha256(readFileSync(plainPath(e.configurationPath)))}));
 const plan={format:'schema6-package-switch-approved-v1',approved:false,operationId,from:endpoints[0],to:endpoints[1],
  expectedHeadSha256:sha256(readFileSync(plainPath(headPath))),expectedMarkerSha256:sha256(readFileSync(plainPath(markerPath))),rollbackOf,
  fromArtifacts:input.fromArtifacts?.map(a=>({role:a.role,path:plainPath(a.path),sha256:a.sha256})),
  artifacts:artifacts.map(a=>({role:a.role,path:plainPath(a.path),sha256:sha256(readFileSync(a.path))}))};
 if(JSON.stringify(plan.artifacts.map(a=>a.role).sort())!==JSON.stringify(['backup','login','mcp','task']))fail('switch_artifacts_required');
 verifySwitchConfigurations(plan);
 const bindingReport=validatePackageSwitchBindings(plan,{fromArtifacts:input.fromArtifacts});
 const marker=JSON.parse(readFileSync(markerPath));
 if(marker.format!=='schema6-lifecycle-v1'||marker.phase!=='clean_closed'||marker.manifest_sha256!==from.manifestSha256
   ||marker.configuration_sha256!==plan.from.configurationSha256)fail('switch_clean_close_required');
 return {plan,bindingReport,report:{format:'schema6-package-switch-preparation-v1',approved:false,applied:false,registered:false,started:false,
  operationId,fromManifestSha256:from.manifestSha256,toManifestSha256:to.manifestSha256,
  taskDisposition:'prepare_new_task_only',deploymentReady:false,unverifiedDeploymentGates:['fixed_prepare_receipt_and_approved_xml_equality','owner_sid_registration_sddl_expected_registered_sddl_and_parent_sddl_pins','disabled_old_task_and_new_task_registration_receipts'],requiredReview:['both_exact_packages','offline_clean_close','login_backup_mcp_task_anchors','forward_and_conditional_reverse']}};
}
if(process.argv[1]&&import.meta.url===pathToFileURL(path.resolve(process.argv[1])).href){
 try{
  if(process.argv.length!==6||process.argv[2]!=='--input'||process.argv[4]!=='--output')fail('switch_prepare_usage');
  const result=preparePackageSwitch(JSON.parse(readFileSync(plainPath(path.resolve(process.argv[3])))));
  const output=plainPath(path.resolve(process.argv[5]),{missing:true});
  writeFileSync(output,JSON.stringify(result,null,2)+'\n',{flag:'wx',mode:0o600,flush:true});
  process.stdout.write(JSON.stringify(result.report)+'\n');
 }catch{process.stdout.write(JSON.stringify({prepared:false,applied:false,code:'switch_prepare_rejected'})+'\n');process.exitCode=2;}
}
