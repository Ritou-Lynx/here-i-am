import test from 'node:test';
import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import {readFileSync,rmSync} from 'node:fs';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {syntheticRoot} from '../test_fixtures/release_schema6/synthetic_paths.mjs';

const repository=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'../../..');
const sourcePath=path.join(repository,'tools/i_core/release_schema6/lifecycle/prepare_login_schema6.ps1');
const fixture=path.join(repository,'tools/i_core/test_fixtures/release_schema6/maintenance_task_template.ps1');
const source=readFileSync(sourcePath,'utf8');
function templateSettings(text){
 const templates=[...text.matchAll(/\$document\.LoadXml\('([^']+)'\)/g)];
 assert.equal(templates.length,1,'actual fixed template must be unique');
 const settings=templates[0][1].match(/<Settings>(.*?)<\/Settings>/)?.[1];
 assert.ok(settings);
 const values=[...settings.matchAll(/<([A-Za-z]+)>([^<]*)<\/\1>/g)];
 assert.equal(values.map(m=>m[0]).join(''),settings,'unexpected settings markup');
 assert.equal(new Set(values.map(m=>m[1])).size,values.length,'duplicate settings');
 return Object.fromEntries(values.map(m=>[m[1],m[2]]));
}
const expected={MultipleInstancesPolicy:'IgnoreNew',DisallowStartIfOnBatteries:'false',StopIfGoingOnBatteries:'false',AllowHardTerminate:'false',StartWhenAvailable:'true',Enabled:'true',Hidden:'true',UseUnifiedSchedulingEngine:'true',ExecutionTimeLimit:'PT0S'};
test('fixed login XML explicitly enables Unified and preserves all original settings',()=>{
 assert.deepEqual(templateSettings(source),expected);
 for(const text of [source.replace('<UseUnifiedSchedulingEngine>true</UseUnifiedSchedulingEngine>',''),source.replace('<UseUnifiedSchedulingEngine>true','<UseUnifiedSchedulingEngine>false'),source.replace('<AllowHardTerminate>false','<AllowHardTerminate>true')]){
  assert.throws(()=>assert.deepEqual(templateSettings(text),expected));
 }
 assert.match(source,/<LogonTrigger><Enabled>true<\/Enabled><UserId \/><\/LogonTrigger>/);
 assert.match(source,/<LogonType>InteractiveToken<\/LogonType><RunLevel>LeastPrivilege<\/RunLevel>/);
 assert.match(source,/\$arguments=@\('-NoProfile','-NonInteractive','-WindowStyle','Hidden','-ExecutionPolicy','Bypass','-File',\$login,'-ReleaseDirectory',\$ReleaseDirectory,'-ManifestSha256',\$ManifestSha256,'-LoginConfigurationPath',\$LoginConfigurationPath,'-LoginConfigurationSha256',\$LoginConfigurationSha256\)/);
});
test('template fixture extracts actual construction and has no task persistence entry',()=>{
 const text=readFileSync(fixture,'utf8');
 assert.match(text,/Parser\]::ParseFile\(\$SourcePath/);
 assert.match(text,/Invoke-Expression \$construction/);
 assert.match(text,/\$scheduler\.NewTask\(0\)/);
 assert.doesNotMatch(text,/RegisterTask|DeleteTask|GetFolder|GetTask\(|schtasks|Start-ScheduledTask|Register-ScheduledTask|\.Run(?:Ex)?\(/i);
 assert.doesNotMatch(text,/<Task\b/,'fixture must not mirror the template');
});
test('Windows actual prepared XML passes in-memory COM with no task creates',{skip:process.platform!=='win32'},t=>{
 const root=syntheticRoot('maintenance-task-template-');
 try{
  const ps=path.join(process.env.SystemRoot,'System32/WindowsPowerShell/v1.0/powershell.exe');
  const result=JSON.parse(execFileSync(ps,['-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-File',fixture,'-SourcePath',sourcePath,'-FixtureRoot',root],{windowsHide:true,encoding:'utf8',timeout:30000}));
  for(const key of ['passed','actualTemplateExtracted','savedXmlValidated','comMemoryValidated','settingsPreserved','bindingsValidated'])assert.equal(result[key],true,key);
  assert.equal(result.taskCreates,0);assert.equal(result.taskStarts,0);assert.equal(result.taskDeletes,0);
  assert.match(result.powerShellVersion,/^5\.1\./);
  t.diagnostic(JSON.stringify(result));
 }finally{rmSync(root,{recursive:true,force:true});}
});
