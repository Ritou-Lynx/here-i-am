import test from 'node:test';
import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {readFileSync} from 'node:fs';
import path from 'node:path';
import {fileURLToPath} from 'node:url';

const repository=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'../../..');
const lifecycle=path.join(repository,'tools/i_core/release_schema6/lifecycle');
const fixture=path.join(repository,'tools/i_core/test_fixtures/release_schema6/r1_diagnostics.ps1');
const source=name=>readFileSync(path.join(lifecycle,name),'utf8').replaceAll('\r\n','\n');
const windowsCI=process.platform==='win32'&&process.env.GITHUB_ACTIONS==='true';
const ps=path.join(process.env.SystemRoot??'C:\\Windows','System32/WindowsPowerShell/v1.0/powershell.exe');
const manifest='a'.repeat(64);
const originalPredicate=/Get-ChildItem Env: \| Where-Object \{ \$_\.Name -like 'I_CORE_\*' -or \$_\.Name -like 'NODE_\*' -or \$_\.Name -in @\(\s*'NODE_OPTIONS','NODE_PATH','NODE_EXTRA_CA_CERTS','OPENSSL_CONF','SSL_CERT_FILE','SSL_CERT_DIR'\s*\) \}/;
function cleanEnvironment(){
 return Object.fromEntries(Object.entries(process.env).filter(([name])=>!/^NODE_|^I_CORE_|^(OPENSSL_CONF|SSL_CERT_FILE|SSL_CERT_DIR)$/i.test(name)));
}
function run(script,args=[],injected={}){
 assert.equal(windowsCI,true,'PowerShell diagnostics may only execute in controlled Windows CI');
 // Clear inherited Node/Core variables for every PS child. Only callers below
 // inject explicit non-sensitive rejection probes; no synthetic task switch is set.
 const env={...cleanEnvironment(),...injected};
 assert.equal(Object.keys(env).some(name=>/^I_CORE_SYNTHETIC_TASKS$/i.test(name)),false);
 const result=spawnSync(ps,['-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-File',script,...args],{env,windowsHide:true,encoding:'utf8',timeout:15000});
 assert.ifError(result.error);assert.equal(result.signal,null);
 return result;
}

// Runs on Linux and local pure-test passes too: lock the original admission
// predicate and ensure it is reached before any release or runtime operation.
test('R1 start keeps the original environment predicate inside its outer try',()=>{
 const text=source('start_schema6.ps1');
 const match=text.match(originalPredicate);assert.ok(match,'the original rejection predicate is unchanged');
 assert.equal(text.match(/Get-ChildItem Env:/g)?.length,1);
 const outer=text.indexOf('try {\n  $rejectedEnvironmentNames');assert.ok(outer>=0);
 assert.ok(match.index>outer&&match.index<text.indexOf('  Assert-Tree $release'));
 assert.match(text,/Select-Object -ExpandProperty Name/);
 assert.doesNotMatch(text,/rejected_environment_names\s*=.*\.Value/);
});

for(const [name,prefix] of [
 ['prepare_login_schema6.ps1','schema6_login_prepare_rejected'],
 ['login_schema6.ps1','schema6_login_rejected'],
]){
 test(name+' executes its real catch for valid and unsafe exception messages',{skip:!windowsCI,timeout:180000},()=>{
  const cases=[
   ['x','x'],['known_internal_01','known_internal_01'],['a'.repeat(64),'a'.repeat(64)],
   ['',null],['a'.repeat(65),null],['UPPER_case',null],['错误',null],
   ['C:\\private\\credential.json',null],['private=value',null],['bad-code',null],
   ['valid_code\n',null],['valid_code\r\n',null],[' leading',null],
  ];
  for(const [message,expected] of cases){
   const result=run(fixture,['-Mode','Catch','-SourcePath',path.join(lifecycle,name),'-MessageBase64',Buffer.from(message).toString('base64')]);
   assert.equal(result.status,2,'catch preserves exit 2');assert.equal(result.stdout,'');
   assert.equal(result.stderr.trim(),prefix+':'+(expected??'configuration_or_release_rejected'));
  }
 });
 test(name+' full entry emits the real binding failure with exit 2',{skip:!windowsCI,timeout:30000},()=>{
  const args=['-ReleaseDirectory','C:\\r1-diagnostic-nonrelease','-ManifestSha256',manifest,'-LoginConfigurationPath','C:\\r1-diagnostic-unused.json','-LoginConfigurationSha256',manifest];
  if(name.startsWith('prepare_'))args.push('-OutputXml',path.join(process.env.TEMP,'r1-never-created-'+process.pid+'.xml'),'-PrepareOnly');
  else args.push('-ValidateOnly');
  const result=run(path.join(lifecycle,name),args);
  assert.equal(result.status,2);assert.equal(result.stdout,'');
  assert.equal(result.stderr.trim(),prefix+':'+(name.startsWith('prepare_')?'prepare':'login')+'_release_binding_mismatch');
 });
}

test('R1 start reports only refused variable names and preserves the legacy predicate and exit status',{skip:!windowsCI,timeout:180000},()=>{
 const names=['NODE_R1_DIAGNOSTIC','I_CORE_R1_DIAGNOSTIC','node_r1_lower','i_core_r1_lower','NODE_OPTIONS','NODE_PATH','NODE_EXTRA_CA_CERTS','OPENSSL_CONF','SSL_CERT_FILE','SSL_CERT_DIR'];
 for(const selected of [...names.map(name=>[name]),names]){
  const injected=Object.fromEntries(selected.map((name,i)=>[name,'r1_probe_value_'+i+'_never_disclose']));
  const legacy=run(fixture,['-Mode','LegacyEnvironment'],injected);
  const current=run(path.join(lifecycle,'start_schema6.ps1'),['-ManifestSha256',manifest,'-CorePort','0'],injected);
  assert.equal(legacy.status,1);assert.equal(current.status,legacy.status);
  assert.equal(current.stdout,'');
  const result=JSON.parse(current.stderr);
  assert.deepEqual(Object.keys(result).sort(),['code','rejected_environment_names','status']);
  assert.equal(result.status,'rejected');assert.equal(result.code,'inherited_runtime_environment_rejected');
  assert.deepEqual(result.rejected_environment_names.map(name=>name.toUpperCase()).sort(),selected.map(name=>name.toUpperCase()).sort());
  for(const value of Object.values(injected))assert.equal((current.stdout+current.stderr).includes(value),false);
 }
});

test('R1 start still accepts unrelated environment names and keeps ordinary rejection exit 2',{skip:!windowsCI,timeout:60000},()=>{
 for(const injected of [{},{R1_DIAGNOSTIC:'unrelated_value',NODE:'prefix_without_separator',I_CORE:'prefix_without_separator',OPENSSL_CONFIG:'near_match',SSL_CERT_FILE_EXTRA:'near_match'}]){
  const legacy=run(fixture,['-Mode','LegacyEnvironment'],injected);
  assert.equal(legacy.status,0);
  // This argument guard precedes all file validation, service or task activity.
  const current=run(path.join(lifecycle,'start_schema6.ps1'),['-ManifestSha256',manifest,'-CorePort','0'],injected);
  assert.equal(current.status,2);assert.equal(current.stdout,'');
  assert.deepEqual(JSON.parse(current.stderr),{status:'rejected',code:'start_required_for_runtime_arguments'});
 }
});
