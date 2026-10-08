import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import test from 'node:test';
import {cleanEnvironment} from './package.mjs';

// This full adapter test exercises the unchanged production Windows Node pin,
// fixed-release verification and private output ACL. Linux runs guard/repro tests;
// do not weaken the adapter's Node hash or ACL checks to make this test portable.
for(const mode of ['direct','missing-grant','cli'])test(`real fixed-release precutover adapter: ${mode}`,{skip:process.platform!=='win32',timeout:90000},()=>{
  const fixture=fileURLToPath(new URL('../test_fixtures/release_schema6/online_preflight_ordinary.ps1',import.meta.url));
  const external=JSON.parse(process.env.ONLINE_PREFLIGHT_FIXTURE_RELEASE??'{}');
  let gitPath;
  if(!external.releaseDirectory){
    const gitExec=spawnSync('git',['--exec-path'],{windowsHide:true,encoding:'utf8'});assert.equal(gitExec.status,0,gitExec.stderr);
    gitPath=path.resolve(gitExec.stdout.trim(),'git.exe');
  }
  const env=cleanEnvironment();
  for(const key of ['GITHUB_ACTIONS','RUNNER_ENVIRONMENT','RUNNER_OS'])if(process.env[key]!==undefined)env[key]=process.env[key];
  const ps=path.join(process.env.SystemRoot,'System32','WindowsPowerShell','v1.0','powershell.exe');
  const input=Buffer.from(JSON.stringify({mode,gitPath,...external})).toString('base64');
  const run=spawnSync(ps,['-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-File',fixture,'-NodePath',process.execPath,'-ArgumentsBase64',input],{env,windowsHide:true,encoding:'utf8',timeout:85000,maxBuffer:2*1024*1024});
  assert.equal(run.error,undefined);assert.equal(run.status,0,run.stderr);
  const result=JSON.parse(run.stdout);assert.equal(result.passed,true);assert.equal(result.mode,mode);assert.equal(result.sourceSchema,'4');assert.equal(result.migratedSchema,'5');assert.equal(result.originalDbWalStable,true);assert.equal(result.sqlCallsAfterReady,0);
  process.stdout.write(JSON.stringify({syntheticAdapter:result})+'\n');
});
