import assert from 'node:assert/strict';
import { execFileSync, spawn } from 'node:child_process';
import { createHmac, randomBytes } from 'node:crypto';
import { existsSync, mkdirSync, readFileSync, writeFileSync, unlinkSync } from 'node:fs';
import path from 'node:path';
import net from 'node:net';
import { performance } from 'node:perf_hooks';
import test from 'node:test';
import { fileURLToPath } from 'node:url';
import { createLab, protect, ps, sleep, until } from '../../test_fixtures/runtime_upgrade/r3/lab.mjs';
import { cleanEnvironment, sha256 } from './package.mjs';

const secret = () => randomBytes(32).toString('hex');
const quote = s => "'" + s.replaceAll("'", "''") + "'";
function configuration(lab, features = {}) {
  const dir = lab.owned(`config-${randomBytes(6).toString('hex')}`); mkdirSync(dir); protect(dir);
  const owner_sid = execFileSync(ps, ['-NoProfile','-NonInteractive','-Command','[Security.Principal.WindowsIdentity]::GetCurrent().User.Value'], { windowsHide: true, env: cleanEnvironment(), encoding: 'utf8', timeout: 10000 }).trim();
  const value = { format: 'r3-config-v1', manifest_sha256: lab.packageResult.manifest_sha256, database_path: lab.database, node_id: lab.identity, owner_sid, ...features };
  const filename = path.join(dir, 'config.json'); writeFileSync(filename, JSON.stringify(value), { flag: 'wx' });
  return { filename, value, save() { writeFileSync(filename, JSON.stringify(value)); } };
}
async function request(ready, route, token, body) {
  const response = await fetch(`http://127.0.0.1:${ready.address.port}/v1/core${route}`, {
    method: body === undefined ? 'GET' : 'POST', signal: AbortSignal.timeout(4000),
    headers: { 'x-core-protocol': '0.1', ...(token ? { Authorization: `Bearer ${token}` } : {}), ...(body !== undefined ? { 'content-type': 'application/json' } : {}) },
    ...(body !== undefined ? { body: JSON.stringify(body) } : {}),
  });
  return { status: response.status, body: await response.json() };
}
function ok(result) { assert.equal(result.status, 200, result.body.error?.code); return result.body; }
async function witness(t, run, crashGuardian = false) {
  const helper = spawn(ps, ['-NoProfile','-NonInteractive','-File',fileURLToPath(new URL('../../test_fixtures/runtime_upgrade/r3/job_witness.ps1',import.meta.url)), '-ControlDirectory',run.control,...(crashGuardian?['-CrashGuardian']:[])], { windowsHide: true, env: cleanEnvironment(), stdio:['ignore','ignore','pipe'] });
  let closed = false, code, stderr = '';
  helper.stderr.on('data', b => stderr += b); helper.on('close', c => { closed=true;code=c; });
  run.witnessWait = async () => { await until(()=>closed,20000); assert.equal(code,0,stderr); };
  t.after(async () => { if(!run.closed) await run.stop('stop'); await until(()=>closed,20000); assert.equal(code,0,stderr); });
  await until(()=>existsSync(path.join(run.control,'witness-ready')) || closed,15000);
  assert.equal(closed,false,stderr);
  return async () => {
    await until(()=>closed,20000); assert.equal(code,0,stderr);
    const report=run.read('process-witness.json');
    assert.equal(report.run_id,run.read('launch.json').token);
    for(const field of ['job_active_zero_query','service_exit_confirmed','member_exit_confirmed','grandchild_exit_confirmed','guardian_exit_confirmed','parent_exit_confirmed']) assert.equal(report[field],true,field);
    assert.equal(report.guardian_exit_code,crashGuardian?137:0);
    return report;
  };
}
async function verifyStopped(run, ready) {
  const result = await run.wait();
  assert.equal(result.exit, 0, result.stderr);
  assert.equal(result.receipt.child_receipt_confirmed, true);
  assert.equal(result.receipt.guardian_receipt_confirmed, true);
  assert.equal(result.receipt.lock_released_confirmed, true);
  assert.equal(result.receipt.result.child_exit_code,0);
  assert.equal(result.child.phase,'clean_closed');
  await assert.rejects(request(ready,'/health'));
  return result;
}

test('continuous configured service exceeds 120 seconds, public APIs work, protected operator close confirms complete Job', async t => {
  const lab=await createLab(t);
  const keys={ pairing:secret(), owner:secret(), worker:secret(), relay:secret() };
  const config=configuration(lab,{ pairing:{enabled:true,secret:keys.pairing},activity_owner:{enabled:true,secret:keys.owner},worker:{enabled:true,secret:keys.worker},jobs:{enabled:true},relay:{enabled:true,mode:'no-egress-test',secret:keys.relay} });
  const run=lab.launch({configurationFile:config.filename,timeout:170000});
  const ready=await run.ready(), sinceReady=performance.now();
  const getWitness=await witness(t,run);
  assert.throws(()=>config.save(),/EBUSY|EPERM|EACCES/);
  assert.equal(ready.commandline_secret_free,true);
  assert.equal(ready.activity_enabled,true);
  const phone=ok(await request(ready,'/devices/pair',null,{ device_id:'r3-chat',display_name:'synthetic',platform:'test',client_version:'1',capabilities:['chat'],pairing_code:keys.pairing }));
  assert.equal((await request(ready,'/devices/pair',null,{pairing_code:keys.pairing})).status,401);
  const probeBody={device_id:'r3-device',probe_id:'r3-wts',display_name:'synthetic',source:'windows_wts',coverage_mode:'continuous',expected_report_interval_ms:30000,expiry_slo_ms:300000,allowed_kinds:['session.unlocked'],capabilities:[]};
  assert.equal((await request(ready,'/activity/probes/pair',keys.worker,probeBody)).status,401);
  const probe=ok(await request(ready,'/activity/probes/pair',keys.owner,probeBody));
  const reader=ok(await request(ready,'/activity/readers/pair',keys.owner,{installation_id:'r3-reader',display_name:'synthetic',capabilities:[]}));
  const now=Date.now();
  const event={contract:'device.activity.v1',schema_version:1,event_id:`${probe.event_id_prefix}.1`,device_id:'r3-device',probe_id:'r3-wts',origin_sequence:1,kind:'session.unlocked',signal_at_ms:now,ttl_ms:300000,confidence:'high',source:'windows_wts',coverage:{mode:'continuous',window_start_ms:now-30000,window_end_ms:now,expected_report_interval_ms:30000},payload:{}};
  const accepted=ok(await request(ready,'/activity/events',probe.probe_token,{events:[event]}));
  assert.match(JSON.stringify(accepted),/accepted/);
  const summary=ok(await request(ready,'/activity/summary',reader.reader_token));
  const projection=summary.devices.find(device=>device.device_id==='r3-device');
  assert.equal(projection.state,'active');assert.equal(projection.sources[0].source,'windows_wts');assert.equal(projection.sources[0].freshness.fresh,true);
  assert.equal((await request(ready,'/activity/summary',probe.probe_token)).status,403);
  ok(await request(ready,'/chat/messages',phone.device_token,{device_id:'r3-chat',request_companion_reply:true,messages:[{sync_id:'r3-turn',origin_device_id:'r3-chat',origin_sequence:1,character_id:'lin-ai',sender:'user',content:'synthetic R3 turn',created_at_ms:Date.now(),message_type:'chat',asset_refs:[],addenda:[]}]}));
  const lease=ok(await request(ready,'/workers/leases',keys.worker,{workload:'companion_reply',holder_id:'r3-worker',ttl_ms:300000}));
  const leaseBody={workload:'companion_reply',holder_id:'r3-worker',lease_token:lease.lease_token,fencing_token:lease.fencing_token};
  ok(await request(ready,'/workers/leases/renew',keys.worker,{...leaseBody,ttl_ms:300000}));
  const claimed=ok(await request(ready,'/workers/companion-replies/claim',keys.worker,leaseBody));
  assert.equal(claimed.job.trigger_sync_id,'r3-turn');
  const complete=ok(await request(ready,'/workers/companion-replies/complete',keys.worker,{...leaseBody,job_id:claimed.job.job_id,content:'synthetic reply',created_at_ms:Date.now()}));
  assert.equal(complete.publication_status,'accepted');
  ok(await request(ready,'/workers/leases/release',keys.worker,leaseBody));
  // The existing relay API accepts a provider object. This object can only return test_no_egress.
  const relayResponse=await fetch(`http://127.0.0.1:${ready.address.port}/v1/core/actions/shortcut-email/manual-test`,{method:'POST',headers:{'x-core-protocol':'0.1',Authorization:`Bearer ${keys.relay}`,'content-type':'application/json','Idempotency-Key':'r3-no-egress'},body:JSON.stringify({trigger:'ios_shortcut_test_v0'}),signal:AbortSignal.timeout(4000)});
  assert.equal(relayResponse.status,200); const relayResult=await relayResponse.json();
  assert.equal(relayResult.receipt.status,'test_no_egress'); assert.equal(relayResult.receipt.external_send_attempted,false);
  assert.equal((await request(ready,'/actions/shortcut-email/manual-test/receipts/r3-no-egress',keys.worker)).status,401);
  assert.equal(ok(await request(ready,'/actions/shortcut-email/manual-test/receipts/r3-no-egress',keys.relay)).receipt.status,'test_no_egress');
  // Wrong run binding and a forged request cannot stop a different/same candidate.
  const refused = spawn(ps,['-NoProfile','-File',path.join(lab.release,'request_stop.ps1'),'-ControlDirectory',run.control,'-RunId',secret(),'-ManifestSha256',lab.packageResult.manifest_sha256],{windowsHide:true,stdio:'ignore',env:cleanEnvironment()});
  assert.equal(await new Promise(resolve=>refused.on('close',resolve)),2);
  writeFileSync(path.join(run.control,'close'),secret()); await sleep(150); ok(await request(ready,'/health')); unlinkSync(path.join(run.control,'close'));
  // Independent finite test budget, never a service runtime timeout.
  while(performance.now()-sinceReady<125000) {
    await sleep(Math.min(1000,125000-(performance.now()-sinceReady)));
    if(run.closed) {
      const child=run.read('child.json'),supervisor=run.read('supervisor.json'),guardian=run.read('guardian.json');
      t.diagnostic(JSON.stringify({scenario:'continuous_configured_early_exit',listening_elapsed_ms:performance.now()-sinceReady,parent_exit_code:run.exit,parent_reason:supervisor?.result?.reason??null,parent_job_empty:supervisor?.result?.job_empty_confirmed??null,child_phase:child?.phase??null,child_reason:child?.reason??null,child_error_code:child?.error_code??null,guardian_reason:guardian?.result?.reason??null,guardian_job_empty:guardian?.result?.job_empty_confirmed??null,stderr_sha256:sha256(Buffer.from(run.stderr))}));
      assert.fail('continuous_service_exited_early');
    }
  }
  ok(await request(ready,'/health')); const elapsed=performance.now()-sinceReady;
  await run.stop(); const result=await verifyStopped(run,ready), report=await getWitness();
  for(const key of Object.values(keys)) assert.equal((run.stdout+run.stderr+JSON.stringify(result.receipt)+JSON.stringify(result.child)+readFileSync(path.join(lab.release,'manifest.json'),'utf8')).includes(key),false);
  assert.equal(report.service_exit_code,0); assert.equal(report.member_exit_code,0); assert.equal(report.grandchild_exit_code,0);
  const again=lab.launch({configurationFile:config.filename,migrate:false}); await again.ready(); await again.stop(); assert.equal((await again.wait()).exit,0);
  t.diagnostic(JSON.stringify({scenario:'continuous_configured',listening_elapsed_ms:elapsed,manifest_sha256:lab.packageResult.manifest_sha256,listener_closed:true,lock_released:true,clean_receipt:true,original_path_restart:true,configuration_write_locked:true,core_argv_self_check_secret_free:true,api:['pairing_once','independent_owner_probe_reader','event_summary_active_fresh','worker_acquire_renew_release','jobs_claim_complete','relay_no_egress_send_receipt'],...report}));
});

test('authenticated close removed after both observers have checked it does not stop the service',async t=>{
  const lab=await createLab(t);
  const parentPath=path.join(lab.release,'owned_job.ps1'),childPath=path.join(lab.release,'runtime_child.mjs');
  const parentOriginal=readFileSync(parentPath,'utf8'),childOriginal=readFileSync(childPath,'utf8');
  const parentInstrumented=parentOriginal
    .replace('  public static Receipt Run(string node,string entry,string root,string token,string mode,int timeout) {',`  static string FixtureReadClose(string root,string token,string target) {
    string armed=Path.Combine(root,"control-race-parent-armed.json");
    if(!File.Exists(armed)) {
      WriteAtomic(armed,"{\\"token\\":\\""+token+"\\"}");
      var clock=Stopwatch.StartNew();
      while(!File.Exists(Path.Combine(root,"control-race-start")) && clock.ElapsedMilliseconds<30000) Thread.Sleep(25);
      if(!File.Exists(Path.Combine(root,"control-race-start"))) throw new Exception("fixture_control_race_start_timeout");
      if(!File.Exists(target)) throw new Exception("fixture_control_race_request_missing");
      WriteAtomic(Path.Combine(root,"control-race-parent.json"),"{\\"token\\":\\""+token+"\\"}");
      clock.Restart();
      while(!File.Exists(Path.Combine(root,"control-race-release")) && clock.ElapsedMilliseconds<30000) Thread.Sleep(25);
      if(!File.Exists(Path.Combine(root,"control-race-release"))) throw new Exception("fixture_control_race_release_timeout");
    }
    return ReadOptionalControl(target);
  }
  public static Receipt Run(string node,string entry,string root,string token,string mode,int timeout) {`)
    .replace('ReadOptionalControl(Path.Combine(root,"close")) == closeValue','FixtureReadClose(root,token,Path.Combine(root,"close")) == closeValue');
  assert.notEqual(parentInstrumented,parentOriginal);
  const childInstrumented=childOriginal.replace(`        const key = readFileSync(path.join(control, 'stop.key'), 'utf8');`, `        const armed = path.join(control, 'control-race-child-armed.json');
        if (name === 'close' && !existsSync(armed)) {
          writeFileSync(armed, JSON.stringify({ token }) + '\\n', { flag: 'wx' });
          const gate = new Int32Array(new SharedArrayBuffer(4));
          let deadline = performance.now() + 30000;
          while (!existsSync(path.join(control, 'control-race-start')) && performance.now() < deadline) Atomics.wait(gate, 0, 0, 25);
          if (!existsSync(path.join(control, 'control-race-start'))) throw new Error('fixture_control_race_start_timeout');
          if (!existsSync(stop)) throw new Error('fixture_control_race_request_missing');
          writeFileSync(path.join(control, 'control-race-child.json'), JSON.stringify({ token }) + '\\n', { flag: 'wx' });
          deadline = performance.now() + 30000;
          while (!existsSync(path.join(control, 'control-race-release')) && performance.now() < deadline) Atomics.wait(gate, 0, 0, 25);
          if (!existsSync(path.join(control, 'control-race-release'))) throw new Error('fixture_control_race_release_timeout');
        }
        const key = readFileSync(path.join(control, 'stop.key'), 'utf8');`);
  assert.notEqual(childInstrumented,childOriginal);
  // Validate the exact generated source before starting its owned runtime.
  execFileSync(process.execPath,['--input-type=module','--check'],{input:childInstrumented,windowsHide:true,env:cleanEnvironment(),timeout:10000});
  writeFileSync(parentPath,parentInstrumented);writeFileSync(childPath,childInstrumented);
  const manifestPath=path.join(lab.release,'manifest.json'),manifest=JSON.parse(readFileSync(manifestPath));
  for(const [name,contents] of [['owned_job.ps1',parentInstrumented],['runtime_child.mjs',childInstrumented]]) {
    const entry=manifest.files.find(file=>file.path===name);assert.ok(entry,name);
    entry.sha256=sha256(Buffer.from(contents));entry.bytes=Buffer.byteLength(contents);
  }
  const raw=Buffer.from(JSON.stringify(manifest,null,2)+'\n');writeFileSync(manifestPath,raw);lab.packageResult.manifest_sha256=sha256(raw);
  const run=lab.launch(),ready=await run.ready(),getWitness=await witness(t,run);
  const launch=run.read('launch.json'),key=readFileSync(path.join(run.control,'stop.key'),'utf8');
  const close=createHmac('sha256',key).update(`${launch.token}|${launch.manifest_sha256}|close`).digest('hex');
  const waitPair = async (suffix, phase) => {
    const names=['parent','child'].map(side=>`control-race-${side}${suffix}.json`);
    try { await until(()=>names.every(name=>existsSync(path.join(run.control,name))) || run.closed,15000); }
    catch(error) {
      t.diagnostic(JSON.stringify({scenario:'control_race_wait_failure',phase,present:names.map(name=>existsSync(path.join(run.control,name))),closed:run.closed,parent_exit_code:run.exit,child_phase:run.read('child.json')?.phase??null,child_reason:run.read('child.json')?.reason??null,parent_reason:run.read('supervisor.json')?.result?.reason??null,stderr_sha256:sha256(Buffer.from(run.stderr))}));
      throw error;
    }
    assert.equal(run.closed,false,run.stderr);
    for(const name of names) assert.deepEqual(JSON.parse(readFileSync(path.join(run.control,name),'utf8')),{token:launch.token});
  };
  // Both observers must stop before any request is created. Otherwise the test
  // itself can create close between an absent check and an unbarriered read.
  await waitPair('-armed','armed');
  writeFileSync(path.join(run.control,'close'),close,{flag:'wx'});
  writeFileSync(path.join(run.control,'control-race-start'),'start',{flag:'wx'});
  await waitPair('','checked');
  unlinkSync(path.join(run.control,'close'));writeFileSync(path.join(run.control,'control-race-release'),'released',{flag:'wx'});
  await sleep(300);assert.equal(run.closed,false,run.stderr);assert.equal(run.read('child.json'),null);ok(await request(ready,'/health'));
  await run.stop('stop');const result=await verifyStopped(run,ready),report=await getWitness();
  t.diagnostic(JSON.stringify({scenario:'control_file_delete_race_ignored',base_owned_job_sha256:sha256(Buffer.from(parentOriginal)),base_runtime_child_sha256:sha256(Buffer.from(childOriginal)),fixture_manifest_sha256:lab.packageResult.manifest_sha256,listener_remained_live:true,clean_stop_after_race:true,...report,result_exit:result.exit}));
});

test('non-ENOENT control read failure remains fail closed',async t=>{
  const lab=await createLab(t),run=lab.launch(),ready=await run.ready(),getWitness=await witness(t,run);
  mkdirSync(path.join(run.control,'close'));
  const result=await run.wait(),report=await getWitness();
  assert.notEqual(result.exit,0);
  assert.equal(result.receipt.result.job_empty_confirmed,true);
  if(result.child) { assert.equal(result.child.reason,'control_failed');assert.notEqual(result.child.error_code,'ENOENT'); }
  await assert.rejects(request(ready,'/health'));
  t.diagnostic(JSON.stringify({scenario:'control_read_non_enoent_rejected',parent_exit_code:result.exit,child_phase:result.child?.phase??null,child_error_code:result.child?.error_code??null,clean_close_observed:result.child?.store_close_confirmed??false,...report}));
});
test('explicit disabled configuration rejects all enablement routes and inherited environment; cancellation is clean',async t=>{
  const lab=await createLab(t), config=configuration(lab,{pairing:{enabled:false},activity_owner:{enabled:false},worker:{enabled:false},jobs:{enabled:false},relay:{enabled:false}});
  const env={I_CORE_PAIRING_CODE:secret(),I_CORE_ACTIVITY_ADMIN_SECRET:secret(),I_CORE_WORKER_SECRET:secret(),I_CORE_COMPANION_REPLY_JOBS:'1',I_CORE_SHORTCUT_MAIL_MANUAL_TEST_ENABLED:'1',NODE_OPTIONS:'--require=Z:/not-allowed.cjs'};
  const run=lab.launch({configurationFile:config.filename,env}), ready=await run.ready(); const getWitness=await witness(t,run);
  assert.deepEqual(ready.inherited_core_keys,[]); assert.equal(ready.activity_enabled,false);
  const matrix=[];
  for(const [route,body] of [['/devices/pair',{}],['/activity/probes/pair',{}],['/activity/summary',undefined],['/workers/leases',{}],['/workers/companion-replies/claim',{}],['/actions/shortcut-email/manual-test',{trigger:'ios_shortcut_test_v0'}]]) {
    const result=await request(ready,route,secret(),body); assert.ok(result.status>=400); matrix.push({route,status:result.status,code:result.body.error.code});
  }
  await run.stop('stop'); await verifyStopped(run,ready); const report=await getWitness();
  assert.equal(report.service_exit_code,0);assert.equal(report.member_exit_code,0);assert.equal(report.grandchild_exit_code,0);
  t.diagnostic(JSON.stringify({scenario:'disabled_cancel',matrix,listener_closed:true,lock_released:true,clean_receipt:true,...report}));
});

test('parent process death reaps actual Job members but cannot mint a clean receipt or authorize crash restart',async t=>{
  const lab=await createLab(t), config=configuration(lab,{activity_owner:{enabled:true,secret:secret()}});
  const run=lab.launch({configurationFile:config.filename}),ready=await run.ready(),getWitness=await witness(t,run);
  // ChildProcess owns the already-created parent native handle; no PID/name search or killing unrelated processes.
  run.child.kill('SIGKILL'); await until(()=>run.closed,10000);
  const report=await getWitness(); await run.wait(); run.childStarted=true;run.confirmed=true;
  for(const field of ['service_exit_code','member_exit_code','grandchild_exit_code']) assert.equal(report[field],137);
  const guardian=run.read('guardian.json');assert.equal(guardian.run_id,run.read('launch.json').token);assert.equal(guardian.result.parent_exit_observed,true);assert.equal(guardian.result.job_empty_confirmed,true);
  assert.equal(run.read('supervisor.json'),null);assert.equal(run.read('child.json'),null);
  assert.equal(JSON.parse(readFileSync(path.join(lab.state,'r3-lifecycle.json'))).phase,'listening');
  await assert.rejects(request(ready,'/health'));
  execFileSync(ps,['-NoProfile','-NonInteractive','-Command',`$ErrorActionPreference='Stop'; $f=[IO.File]::Open(${quote(path.join(lab.state,'shortcut-mail-relay.runtime.lock'))},[IO.FileMode]::Open,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None); $f.Dispose()`],{windowsHide:true,env:cleanEnvironment(),timeout:10000});
  const before=['','-wal','-shm'].map(s=>existsSync(lab.database+s)?sha256(readFileSync(lab.database+s)):null);
  const retry=await lab.launch({configurationFile:config.filename,migrate:false}).wait();
  assert.equal(retry.exit,1);assert.equal(retry.child.store_construction_attempted,false);
  assert.match(retry.child.error_code,/state_sidecars_require_review|activity_recovery_required|prior_shutdown_unconfirmed/);
  assert.deepEqual(['','-wal','-shm'].map(s=>existsSync(lab.database+s)?sha256(readFileSync(lab.database+s)):null),before);
  t.diagnostic(JSON.stringify({scenario:'parent_death',parent_exit_code:run.exit,parent_exit_confirmed:run.closed,listener_closed:true,lock_released:true,clean_receipt:false,restart_rejected:retry.child.error_code,...report}));
});

test('config path ACL, binding, unknown fields, overlap and unsupported relay reject before store construction',async t=>{
  const lab=await createLab(t), before=sha256(readFileSync(lab.database));
  const cases=[{unexpected:true},{node_id:'wrong'},{owner_sid:'wrong'},{manifest_sha256:'f'.repeat(64)},{database_path:lab.database+'.wrong'},{pairing:{enabled:true,secret:'short'}},{worker:{enabled:true,secret:'a'.repeat(64)},activity_owner:{enabled:true,secret:'a'.repeat(64)}},{pairing:{enabled:false,secret:secret()}},{jobs:{enabled:true}},{relay:{enabled:true,secret:secret(),mode:'smtp'}},{relay:{enabled:true,secret:secret(),mode:'no-egress-test',url:'https://invalid'}}];
  for(const bad of cases){
    const config=configuration(lab,bad),result=await lab.launch({configurationFile:config.filename}).wait();
    assert.equal(result.exit,1,result.stderr);assert.equal(result.child.store_construction_attempted,false);assert.match(result.child.error_code,/config_|jobs_|relay_/);
    assert.equal(sha256(readFileSync(lab.database)),before);assert.equal(existsSync(path.join(lab.state,'r3-lifecycle.json')),false);
  }
  const config=configuration(lab);
  execFileSync(ps,['-NoProfile','-NonInteractive','-Command',`$acl=Get-Acl -LiteralPath ${quote(config.filename)}; $acl.AddAccessRule([Security.AccessControl.FileSystemAccessRule]::new([Security.Principal.SecurityIdentifier]::new('S-1-1-0'),'Read','Allow')); Set-Acl -LiteralPath ${quote(config.filename)} -AclObject $acl`],{windowsHide:true,env:cleanEnvironment(),timeout:10000});
  const rejected=await lab.launch({configurationFile:config.filename}).wait();assert.equal(rejected.exit,2);assert.match(rejected.stderr,/protected_acl_required/);
  assert.equal(sha256(readFileSync(lab.database)),before);
  t.diagnostic(JSON.stringify({scenario:'config_preflight',invalid_cases:cases.length,acl_read_exposure_rejected:true,database_unchanged:true,store_not_constructed:true}));
});

test('guardian process alone dies: live parent fails closed and reaps its root and descendants without clean receipt',async t=>{
  const lab=await createLab(t), run=lab.launch(),ready=await run.ready();
  const getWitness=await witness(t,run,true),report=await getWitness(),result=await run.wait();
  assert.equal(result.exit,1);assert.equal(result.receipt.result.reason,'guardian_lost');
  assert.equal(result.receipt.result.job_empty_confirmed,true);assert.equal(result.receipt.result.child_exit_confirmed,true);
  assert.equal(result.receipt.result.guardian_exit_confirmed,true);assert.equal(result.receipt.result.guardian_exit_code_confirmed,true);assert.equal(result.receipt.result.guardian_exit_code,137);
  assert.equal(result.receipt.guardian_receipt_confirmed,false);assert.equal(result.receipt.child_receipt_confirmed,false);assert.equal(result.receipt.lock_released_confirmed,true);
  for(const field of ['service_exit_code','member_exit_code','grandchild_exit_code']) assert.equal(report[field],124);
  assert.equal(result.child,null);assert.equal(JSON.parse(readFileSync(path.join(lab.state,'r3-lifecycle.json'))).phase,'listening');
  await assert.rejects(request(ready,'/health'));
  t.diagnostic(JSON.stringify({scenario:'guardian_death',reason:'guardian_lost',listener_closed:true,lock_released:true,clean_receipt:false,...report}));
});

test('parent death at each real guardian bootstrap barrier cannot leave suspended processes or a held runtime lock',async t=>{
  for(const stage of ['CREATED','DUPLICATED','PUBLISHED']) {
    await t.test(stage,async sub=>{
      const lab=await createLab(sub),before=sha256(readFileSync(lab.database));
      const sourcePath=path.join(lab.release,'owned_job.ps1'),original=readFileSync(sourcePath,'utf8');
      // No production runtime option: this new, self-owned package explicitly
      // compiles one test-only phase barrier and obtains a different manifest.
      const instrumented=original.replace("Add-Type -TypeDefinition @'",`$fixtureParameters=New-Object System.CodeDom.Compiler.CompilerParameters\n$fixtureParameters.GenerateInMemory=$true\n$fixtureParameters.ReferencedAssemblies.Add('System.dll') | Out-Null\n$fixtureParameters.ReferencedAssemblies.Add('System.Core.dll') | Out-Null\n$fixtureParameters.CompilerOptions='/define:R3_BARRIER_${stage}'\nAdd-Type -CompilerParameters $fixtureParameters -TypeDefinition @'`);
      assert.notEqual(instrumented,original);writeFileSync(sourcePath,instrumented);
      const manifestPath=path.join(lab.release,'manifest.json'),manifest=JSON.parse(readFileSync(manifestPath));
      const sourceEntry=manifest.files.find(file=>file.path==='owned_job.ps1');
      sourceEntry.sha256=sha256(Buffer.from(instrumented));sourceEntry.bytes=Buffer.byteLength(instrumented);
      const raw=Buffer.from(JSON.stringify(manifest,null,2)+'\n');writeFileSync(manifestPath,raw);lab.packageResult.manifest_sha256=sha256(raw);
      const reservation=net.createServer();await new Promise(resolve=>reservation.listen(0,'127.0.0.1',resolve));
      const port=reservation.address().port;await new Promise(resolve=>reservation.close(resolve));
      const run=lab.launch({port});
      await until(()=>run.read('startup-barrier.json') || run.closed,20000);assert.equal(run.closed,false,run.stderr);
      const getWitness=await witness(sub,run);
      run.child.kill('SIGKILL');await until(()=>run.closed,10000);
      const report=await getWitness();await run.wait();run.childStarted=true;run.confirmed=true;
      assert.equal(run.read('ready.json'),null);assert.equal(run.read('child.json'),null);assert.equal(run.read('supervisor.json'),null);
      assert.equal(existsSync(path.join(lab.state,'r3-lifecycle.json')),false);
      assert.equal(sha256(readFileSync(lab.database)),before);
      for(const field of ['service_exit_code','member_exit_code','grandchild_exit_code']) assert.equal(report[field],137);
      const guardian=run.read('guardian.json');assert.equal(guardian.run_id,run.read('launch.json').token);assert.equal(guardian.result.parent_exit_observed,true);assert.equal(guardian.result.job_empty_confirmed,true);
      execFileSync(ps,['-NoProfile','-NonInteractive','-Command',`$ErrorActionPreference='Stop'; $f=[IO.File]::Open(${quote(path.join(lab.state,'shortcut-mail-relay.runtime.lock'))},[IO.FileMode]::Open,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None); $f.Dispose()`],{windowsHide:true,env:cleanEnvironment(),timeout:10000});
      await assert.rejects(request({address:{port}},'/health'));
      sub.diagnostic(JSON.stringify({scenario:'bootstrap_parent_death',stage,manifest_sha256:lab.packageResult.manifest_sha256,base_owned_job_sha256:sha256(Buffer.from(original)),instrumented_owned_job_sha256:sourceEntry.sha256,parent_exit_confirmed:run.closed,parent_exit_code:run.exit,guardian_reason:guardian.result.reason,listener_never_started:true,original_database_bytes_unchanged:true,lock_released:true,clean_receipt:false,...report}));
    });
  }
});
