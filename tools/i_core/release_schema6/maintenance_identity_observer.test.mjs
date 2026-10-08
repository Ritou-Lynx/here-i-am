import test from 'node:test';
import assert from 'node:assert/strict';
import {mkdtempSync,writeFileSync,readFileSync,rmSync,realpathSync} from 'node:fs';
import {execFileSync} from 'node:child_process';
import {createHash} from 'node:crypto';
import {tmpdir} from 'node:os';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
const fixture=fileURLToPath(new URL('../test_fixtures/release_schema6/identity_prepare_observer.ps1',import.meta.url));
const hash=value=>createHash('sha256').update(value).digest('hex');
const quote=value=>"'"+value.replaceAll("'","''")+"'";
test('fixture observer captures both existing Node tasks and leaves source/control flow unchanged',{skip:process.platform!=='win32',timeout:30000},()=>{
 const root=realpathSync.native(mkdtempSync(path.join(tmpdir(),'schema6-identity-')));
 const source=path.join(root,'prepare-production-login.ps1');
 // A transport-only synthetic source, not a production Prepare success fixture.
 const code1="process.stdout.write('first-node')";
 const code2="process.stderr.write('second-node-error');process.exitCode=7";
 const text=`param([string]$ConfigPath,[string]$ExpectedConfigSha256)
$ErrorActionPreference='Stop'
function Invoke-PrepareNode([string]$Code){
 $info=[Diagnostics.ProcessStartInfo]::new();$info.FileName=${quote(process.execPath)};$info.Arguments='--eval "'+$Code+'"';$info.UseShellExecute=$false;$info.CreateNoWindow=$true;$info.RedirectStandardOutput=$true;$info.RedirectStandardError=$true
 $child=[Diagnostics.Process]::new();$child.StartInfo=$info
 try{$null=$child.Start();$out=$child.StandardOutput.ReadToEndAsync();$err=$child.StandardError.ReadToEndAsync()
  $child.WaitForExit();$null=$err.GetAwaiter().GetResult();if($child.ExitCode-ne 0){throw 'synthetic_node_rejected'};return $out.GetAwaiter().GetResult()
 }finally{$child.Dispose()}
}
try{$null=Invoke-PrepareNode ${quote(code1)};$null=Invoke-PrepareNode ${quote(code2)};throw 'second_exit_not_observed'}catch{[Console]::WriteLine(($_.Exception.Message|ConvertTo-Json -Compress));exit 2}
`;
 try{
  writeFileSync(source,text);
  let failure;
  try{execFileSync(path.join(process.env.SystemRoot,'System32/WindowsPowerShell/v1.0/powershell.exe'),['-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-File',fixture,'-PrepareScript',source,'-ConfigPath',path.join(root,'unused-config.json'),'-ExpectedConfigSha256','a'.repeat(64),'-ExpectedSourceSha256',hash(text),'-FixtureRoot',root],{encoding:'utf8',windowsHide:true,timeout:25000,stdio:['ignore','pipe','pipe']});}catch(error){failure=error;}
  assert.equal(failure?.status,2,JSON.stringify({stdout:failure?.stdout,stderr:failure?.stderr}));
  assert.equal(JSON.parse(failure.stdout),'synthetic_node_rejected');
  const r=JSON.parse(readFileSync(path.join(root,'prepare-node-observations.json'),'utf8'));
  assert.equal(r.observationError,null);assert.equal(r.sourceUnchanged,true);assert.equal(r.breakpointRemoved,true);
  assert.equal(hash(readFileSync(source)),hash(text));assert.equal(r.calls.length,2);
  assert.deepEqual(r.calls.map(c=>[c.phase,c.exitCode,c.codeSha256]),[['precheck',0,hash(code1)],['prepare',7,hash(code2)]]);
  assert.equal(r.calls[0].stdout,'first-node');assert.equal(r.calls[1].stderr,'second-node-error');
 }finally{assert.match(path.basename(root),/^schema6-identity-[A-Za-z0-9]+$/);rmSync(root,{recursive:true,force:true});}
});
