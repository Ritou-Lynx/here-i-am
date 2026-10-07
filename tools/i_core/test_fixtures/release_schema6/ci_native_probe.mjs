// CI-only native startup diagnostics. Never part of the fixed release inventory.
import {spawnSync} from 'node:child_process';
import {lstatSync, readdirSync, realpathSync, rmdirSync} from 'node:fs';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {performance} from 'node:perf_hooks';
import {cleanEnvironment, plainPath} from '../../release_schema6/package.mjs';
import {syntheticRoot} from './synthetic_paths.mjs';

export const STAGES=Object.freeze(['no_op','prepare_root','default_acl','default_assert','system_module_assert','production_gate','cleanup']);
const quote=s=>"'"+s.replaceAll("'","''")+"'";
const elapsed=start=>Math.max(0,Math.round(performance.now()-start));
export function safeResult(stage,start,error=null,status=0,metrics=null) {
  const timed=error?.code==='ETIMEDOUT';
  return {stage,elapsed_ms:elapsed(start),exit_code:Number.isInteger(status)?status:null,timed_out:timed,
    error_code:timed?'timeout':error?'operation_failed':status===0?'none':'process_failed',metrics};
}
export function parseMetrics(text) {
  const value=JSON.parse(text);
  if(Object.keys(value).sort().join(',')!=='module_directory_count,module_path_count,script_elapsed_ms'
    ||Object.values(value).some(n=>!Number.isSafeInteger(n)||n<0||n>1e9))throw new Error('metrics_invalid');
  return value;
}
export function cleanProbeEnvironment(env) {
  const clean=cleanEnvironment(env);
  return Object.keys(env).length===Object.keys(clean).length
    &&Object.entries(env).every(([k,v])=>clean[k]===v);
}
export function runStage(stage,body,ps,env,run=spawnSync) {
  const start=performance.now();
  // Counts only, no module names, paths, environment dump, stdout or stderr text.
  const script="$ErrorActionPreference='Stop'; $clock=[Diagnostics.Stopwatch]::StartNew(); "+body+
    "; $ms=$clock.ElapsedMilliseconds; $count=[IO.Directory]::GetDirectories($PSHOME+'\\Modules').Length; "+
    "$paths=@($env:PSModulePath.Split(';') | Where-Object { $_ }).Count; "+
    "[Console]::Out.Write(('{\"script_elapsed_ms\":'+$ms+',\"module_directory_count\":'+$count+',\"module_path_count\":'+$paths+'}'))";
  let result;
  try { result=run(ps,['-NoProfile','-NonInteractive','-Command',script],
    {env,windowsHide:true,timeout:60000,maxBuffer:32768,encoding:'utf8',stdio:['ignore','pipe','pipe']}); }
  catch(error){return safeResult(stage,start,error,null);}
  if(result.error||result.status!==0)return safeResult(stage,start,result.error,result.status);
  try{return safeResult(stage,start,null,0,parseMetrics(result.stdout));}
  catch{return safeResult(stage,start,new Error('metrics_invalid'),0);}
}
export async function productionGate(root,check) {
  const start=performance.now();
  try {await check(root,true);return safeResult('production_gate',start);}
  catch(error){return safeResult('production_gate',start,error,Number.isInteger(error?.status)?error.status:null);}
}
export async function probe() {
  if(process.platform!=='win32'||!cleanProbeEnvironment(process.env))throw new Error('probe_environment_rejected');
  const ps=path.join(process.env.SystemRoot,'System32/WindowsPowerShell/v1.0/powershell.exe');
  const script=fileURLToPath(new URL('../../release_schema6/lifecycle/protected_paths.ps1',import.meta.url));
  const env=cleanEnvironment();
  let root,identity;
  const stages=[];
  try {
    root=syntheticRoot('schema6-ci-native-');identity=lstatSync(root);
    stages.push(runStage('no_op','$null=1',ps,env));
    // This one preparation may be slow. It is not the production deadline gate.
    stages.push(runStage('prepare_root','. '+quote(script)+'; Protect-NewDirectory '+quote(root),ps,env));
    stages.push(runStage('default_acl','$null=Get-Acl -LiteralPath '+quote(root),ps,env));
    stages.push(runStage('default_assert','. '+quote(script)+'; Assert-ProtectedPath '+quote(root)+' -Root',ps,env));
    stages.push(runStage('system_module_assert',"$env:PSModulePath=$PSHOME+'\\Modules'; Import-Module ($PSHOME+'\\Modules\\Microsoft.PowerShell.Security\\Microsoft.PowerShell.Security.psd1') -ErrorAction Stop; "+
      '. '+quote(script)+'; Assert-ProtectedPath '+quote(root)+' -Root',ps,env));
    // Import and invoke the actual production implementation exactly once.
    // Its new PowerShell child, cleanEnvironment and 10000ms timeout are unchanged.
    const {protectedPath}=await import('../../release_schema6/lifecycle/configuration.mjs');
    stages.push(await productionGate(root,protectedPath));
  } finally {
    const start=performance.now();
    try {
      if(root) {
        plainPath(root);
        const now=lstatSync(root);
        if(now.dev!==identity.dev||now.ino!==identity.ino||!path.basename(root).startsWith('schema6-ci-native-')
          ||realpathSync.native(root)!==root||readdirSync(root).length)throw new Error('cleanup_identity');
        rmdirSync(root); // Empty owned root only: never recursive and never follow links.
      }
      stages.push(safeResult('cleanup',start));
    }catch(error){stages.push(safeResult('cleanup',start,error,null));}
  }
  return {format:'schema6-ci-native-probe-v1',passed:stages.length===STAGES.length&&stages.every(s=>s.error_code==='none'),stages};
}
if(process.argv[1]&&path.resolve(process.argv[1])===fileURLToPath(import.meta.url)) {
  let report;
  try {
    if(process.argv.length!==2)throw new Error('arguments_rejected');
    report=await probe();
  }catch {report={format:'schema6-ci-native-probe-v1',passed:false,stages:[]};}
  process.stdout.write(JSON.stringify(report)+'\n');
  process.exitCode=report.passed?0:1;
}
