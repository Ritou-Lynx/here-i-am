import assert from 'node:assert/strict';
import { execFileSync, spawnSync } from 'node:child_process';
import { readFileSync, writeFileSync, mkdirSync, copyFileSync, existsSync, linkSync, unlinkSync } from 'node:fs';
import path from 'node:path';
import test from 'node:test';
import { sha256, cleanEnvironment } from './package.mjs';
import { createRuntimeLab, repository, ps, cleanReceipt } from './lifecycle/test-fixture.mjs';
import { loginConfig, configureManagedMcp, host, connectManaged } from './lifecycle/mcp-session-test-fixture.mjs';
const BASE='b71799706719b0e603124d108c2795caa0a98933',hashFile=p=>sha256(readFileSync(p));
async function historical(l){
 const execPath=execFileSync('git',['--exec-path'],{windowsHide:true,encoding:'utf8'}).trim(),gitPath=path.resolve(execPath,'../../../bin/git.exe');
 const bytes=execFileSync(gitPath,['-C',repository,'show',BASE+':tools/i_core/release_schema6/package.mjs'],{windowsHide:true,env:cleanEnvironment()});
 const api=await import('data:text/javascript;base64,'+bytes.toString('base64')),built=path.join(l.root,'old-built');
 const result=api.prepareRelease({repository,sourceCommit:BASE,output:built,nodePath:path.join(l.release,'runtime/node.exe'),gitPath}),release=l.dir('old-release');
 for(const name of [...api.INVENTORY,'manifest.json']){const p=path.join(release,name);mkdirSync(path.dirname(p),{recursive:true});copyFileSync(path.join(built,name),p);}
 l.release=release;l.lifecycle=path.join(release,'tools/i_core/release_schema6/lifecycle');l.manifestHash=result.manifest_sha256;l.configuration.manifest_sha256=l.manifestHash;writeFileSync(l.configPath,JSON.stringify(l.configuration));
 assert.equal(api.INVENTORY.length,47);
}
for(const old of [true,false])test('approved bound WM_CLOSE closes '+(old?'unchanged historical 47':'candidate 48')+' hidden session, managed MCP and Core',{skip:process.platform!=='win32',timeout:360000},async t=>{
 const l=await createRuntimeLab(t);if(old)await historical(l);
 const c=loginConfig(l);const mcp=await configureManagedMcp(l,c);
 const run=await host(l,c);await run.ready();await connectManaged(run,mcp,{requireMessage:false});
 const maintenance=l.dir('maintenance');
 for(const file of ['close-schema6-session.ps1','process_image_binding.ps1'])copyFileSync(path.join(repository,'tools/i_core/maintenance',file),path.join(maintenance,file));
 const script=path.join(maintenance,'close-schema6-session.ps1'),helper=path.join(maintenance,'process_image_binding.ps1');
 const metadata=JSON.parse(execFileSync(ps,['-NoProfile','NonInteractive','-Command',
  'Add-Type -TypeDefinition \'using System;using System.Runtime.InteropServices;public static class FixtureWindowThread{[DllImport("user32.dll")]public static extern uint GetWindowThreadProcessId(IntPtr w,out uint p);}\';'+
  '$p=Get-Process -Id '+run.child.pid+';$windowPid=0;$tid=[FixtureWindowThread]::GetWindowThreadProcessId([IntPtr]::new('+run.window.hwnd+'),[ref]$windowPid);'+
  '@{startedTicks=$p.StartTime.ToUniversalTime().Ticks.ToString();imagePath=$p.Path;sessionId=$p.SessionId;threadId=$tid;ownerSid=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value}|ConvertTo-Json -Compress'
 ].map(a=>a==='NonInteractive'?'-NonInteractive':a),{env:cleanEnvironment(),windowsHide:true,encoding:'utf8'}));
 const input={format:'schema6-session-close-approved-v1',approved:true,releaseDirectory:l.release,manifestSha256:l.manifestHash,loginConfigurationPath:c.file,loginConfigurationSha256:c.hash,
  sessionDirectory:run.session,controlDirectory:run.control,windowSha256:hashFile(path.join(run.session,'session-window.json')),launchSha256:hashFile(path.join(run.control,'launch.json')),readySha256:hashFile(path.join(run.control,'ready.json')),
  maintenanceScriptSha256:hashFile(script),processImageBindingSha256:hashFile(helper),host:{...metadata,pid:run.child.pid,hwnd:run.window.hwnd,imageSha256:hashFile(metadata.imagePath)},outputPath:path.join(maintenance,'close-receipt.json')};
 const inputPath=path.join(maintenance,'approved.json');
 const invoke=value=>{writeFileSync(inputPath,JSON.stringify(value));return spawnSync(ps,['-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-File',script,'-ConfigurationPath',inputPath,'-ConfigurationSha256',hashFile(inputPath)],{env:cleanEnvironment(),windowsHide:true,encoding:'utf8',timeout:120000});};
 const refused=invoke({...input,host:{...input.host,startedTicks:String(BigInt(input.host.startedTicks)+1n)}});assert.equal(refused.status,2);assert.equal(run.closed,false);assert.equal(existsSync(input.outputPath),false);
 const checkRefused=result=>{assert.equal(result.status,2,result.stdout+result.stderr);assert.equal(run.closed,false);assert.equal(existsSync(input.outputPath),false);assert.equal(existsSync(path.join(run.control,'session-close.json')),false);};
 checkRefused(invoke({...input,host:{...input.host,imageSha256:'0'.repeat(64)}}));
 writeFileSync(inputPath,JSON.stringify(input));const alias=path.join(maintenance,'input-hardlink.json');linkSync(inputPath,alias);
 try{checkRefused(invoke(input));}finally{unlinkSync(alias);}
 const changed=l.dir('tampered-release');for(const entry of [...JSON.parse(readFileSync(path.join(l.release,'manifest.json'))).files.map(e=>e.path),'manifest.json']){const p=path.join(changed,entry);mkdirSync(path.dirname(p),{recursive:true});copyFileSync(path.join(l.release,entry),p);}
 const tamperedEntry=path.join(changed,'tools/i_core/release_schema6/lifecycle/start_schema6.ps1'),tripwire=path.join(maintenance,'unverified-entry-executed');
 writeFileSync(tamperedEntry,"[IO.File]::WriteAllText('"+tripwire.replaceAll("'","''")+"','unsafe')\nexit 0\n");
 checkRefused(invoke({...input,releaseDirectory:changed}));assert.equal(existsSync(tripwire),false);
 const success=invoke(input);assert.equal(success.status,0,success.stdout+success.stderr);
 await run.wait();cleanReceipt(run);
 const receipt=JSON.parse(readFileSync(input.outputPath));assert.equal(receipt.closed,true);assert.equal(receipt.originalHostExitConfirmed,true);assert.equal(receipt.databaseExclusiveOpenConfirmed,true);assert.equal(receipt.wmCloseOnly,true);
 assert.equal(receipt.legacyExitManifestAbsent,old);assert.equal(receipt.budgetMs,30000);assert.ok(receipt.externalCloseElapsedMs>=0&&receipt.externalCloseElapsedMs<30000);assert.equal(existsSync(path.join(run.session,'session-exit-over-budget.json')),false);
 assert.equal(receipt.coreForced,false);assert.equal(receipt.custodyAuthenticated,false);assert.equal(receipt.offlineSwitchMustVerifyCustody,true);
 assert.equal(Object.keys(receipt.receiptSha256).length,7);
 assert.equal(run.read('mcp-stop.json').job_empty_confirmed,true);
 t.diagnostic(JSON.stringify({packageFileCount:old?47:48,externalCloseElapsedMs:receipt.externalCloseElapsedMs,budgetMs:receipt.budgetMs}));
 l.completed=true;
});
