import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import test from 'node:test';

const source = resolve('tools/dev_agent_bridge/windows_text_gate_job_limit_probe.cs');
const text = readFileSync(source, 'utf8');
const literal = value => `'${value.replaceAll("'", "''")}'`;
const pidBytes = (assigned, count, ids = [], bytes = 136) => {
  const buffer = Buffer.alloc(bytes); if(bytes >= 8) { buffer.writeUInt32LE(assigned,0); buffer.writeUInt32LE(count,4); }
  ids.forEach((id,index) => buffer.writeBigUInt64LE(BigInt(id),8+index*8)); return buffer.toString('base64');
};
const parserVectors = [
  ['empty',pidBytes(0,0),8,true,'parsed'],
  ['one',pidBytes(1,1,[123456789]),16,true,'parsed'],
  ['capacity',pidBytes(16,16,Array.from({length:16},(_,i)=>i+1)),136,true,'parsed'],
  ['wide-dword-valid',pidBytes(1,1,[0xffffffff]),16,true,'parsed'],
  ['query-failed',pidBytes(1,1,[123456789]),16,false,'query-failed'],
  ['null',null,0,true,'buffer-rejected'],
  ['short-buffer',pidBytes(0,0,[],135),128,true,'buffer-rejected'],
  ['long-buffer',pidBytes(0,0,[],144),136,true,'buffer-rejected'],
  ['zero-length',pidBytes(0,0),0,true,'length-rejected'],
  ['short-header',pidBytes(0,0),4,true,'length-rejected'],
  ['long-length',pidBytes(0,0),144,true,'length-rejected'],
  ['unaligned-length',pidBytes(1,1,[1]),17,true,'length-rejected'],
  ['huge-length',pidBytes(0,0),0xffffffff,true,'length-rejected'],
  ['assigned-limit',pidBytes(17,16),136,true,'count-limit'],
  ['listed-limit',pidBytes(16,17),136,true,'count-limit'],
  ['overflow-count',pidBytes(0xffffffff,0xffffffff),136,true,'count-limit'],
  ['incomplete-list',pidBytes(2,1,[1]),136,true,'count-mismatch'],
  ['listed-exceeds-assigned',pidBytes(1,2,[1,2]),24,true,'count-mismatch'],
  ['truncated',pidBytes(2,2,[1,2]),16,true,'truncated'],
  ['zero-id',pidBytes(1,1,[0]),16,true,'invalid-id'],
  ['id-not-dword',pidBytes(1,1,[0x100000000n]),16,true,'invalid-id'],
  ['duplicate-id',pidBytes(2,2,[123456789,123456789]),24,true,'duplicate-id'],
  ['empty-padding',pidBytes(0,0),16,true,'parsed'],
].map(([name,base64,returned,success,expected])=>({name,base64,returned,success,expected}));
// Compile, invoke managed modes, and exercise pure policy. Never call Apply/Sentinel.
const script = `
$ErrorActionPreference='Stop'
Add-Type -Path ${literal(source)}
function Run-Managed([string[]]$probeArgs) {
 $writer=New-Object System.IO.StringWriter; $previous=[Console]::Out
 try { [Console]::SetOut($writer); $code=[HereIAm.R7.JobLimitProbe]::Main($probeArgs) }
 finally { [Console]::SetOut($previous) }
 return @{ exit=$code; report=($writer.ToString()|ConvertFrom-Json) }
}
$selftest=Run-Managed @('--selftest')
if($selftest.exit -ne 0) { exit $selftest.exit }
$plan=Run-Managed @('--plan'); $default=Run-Managed @(); $invalid=Run-Managed @('--invalid-test-only')
$base=[HereIAm.R7.JobLimitProbe]::PassingFixture(); $unknown=New-Object HereIAm.R7.JobLimitProbe+Evidence
$rejections=@()
foreach($created in @($null,$false,$true)) { foreach($errorCode in @($null,0,5,1816)) { foreach($marker in @($null,$false,$true)) {
 $e=[HereIAm.R7.JobLimitProbe]::PassingFixture(); $e.SecondCreated=$created; $e.SecondCreateError=$errorCode; $e.SecondEntryObserved=$marker
 $rejections+=@{ created=$created; error=$errorCode; marker=$marker; pass=[HereIAm.R7.JobLimitProbe]::Passed($e); report=([HereIAm.R7.JobLimitProbe]::Report($e)|ConvertFrom-Json) }
}}}
$cleanups=@()
foreach($children in @($false,$true)) { foreach($handles in @($false,$true)) { foreach($active in @($null,0,1)) {
 $e=[HereIAm.R7.JobLimitProbe]::PassingFixture(); $e.ChildrenClosed=$children; $e.AllHandlesClosed=$handles
 if($null -eq $active) { $e.After=$null } else { $a=New-Object HereIAm.R7.JobLimitProbe+JobAccounting; $a.ActiveProcesses=$active; $e.After=$a }
 $cleanups+=@{ children=$children; handles=$handles; active=$active; pass=[HereIAm.R7.JobLimitProbe]::Passed($e); pending=[HereIAm.R7.JobLimitProbe]::CleanupPending($e); report=([HereIAm.R7.JobLimitProbe]::Report($e)|ConvertFrom-Json) }
}}}
$exits=@()
foreach($exact in @($false,$true)) { foreach($exitCode in @($null,0,3,91)) {
 $e=[HereIAm.R7.JobLimitProbe]::PassingFixture(); $e.FirstExactExit=$exact; $e.FirstExitCode=$exitCode
 $exits+=@{ exact=$exact; code=$exitCode; pass=[HereIAm.R7.JobLimitProbe]::Passed($e) }
}}
$parserRows=@()
$vectors=${literal(JSON.stringify(parserVectors))}|ConvertFrom-Json
foreach($vector in $vectors) {
 $bytes=$null; if($null -ne $vector.base64) { $bytes=[Convert]::FromBase64String($vector.base64) }
 $parsed=[HereIAm.R7.JobLimitProbe]::ParseProcessList($bytes,[uint32]$vector.returned,[bool]$vector.success)
 $parserRows+=@{ name=$vector.name; report=([HereIAm.R7.JobLimitProbe]::ParsedListJson($parsed)|ConvertFrom-Json) }
}
$snapshots=@()
foreach($change in @('baseline','complete','list-query','counts','count-missing','count-limit','declared-mismatch','member-count','accounting-missing','active-mismatch','total-changed','identity','creation','creation-post-list','own-job','close','image-query-failed','wait-before-failed','wait-before-signaled','wait-after-failed','wait-after-signaled','other-class')) {
 $s=[HereIAm.R7.JobLimitProbe]::SnapshotFixture()
 switch($change) {
  'complete' {$s.Complete=$false} 'list-query' {$s.List.Status='QueryFailed'} 'counts' {$s.CountsConsistent=$false}
  'count-missing' {$s.List.Count=$null} 'count-limit' {$s.List.Assigned=17;$s.List.Count=17} 'declared-mismatch' {$s.List.Assigned=2}
  'member-count' {$s.Members.Clear()} 'accounting-missing' {$s.AccountingBefore=$null}
  'active-mismatch' {$a=$s.AccountingAfter;$a.ActiveProcesses=2;$s.AccountingAfter=$a}
  'total-changed' {$a=$s.AccountingAfter;$a.TotalProcesses=2;$s.AccountingAfter=$a}
  'identity' {$s.Members[0].IdentityConfirmed=$false} 'creation' {$s.Members[0].CreationObserved=$false}
  'creation-post-list' {$s.Members[0].CreationPrecedesList=$false} 'own-job' {$s.Members[0].OwnJobMember=$false}
  'close' {$s.Members[0].HandleClosed=$false} 'image-query-failed' {$s.Members[0].Image='QueryFailed'}
  'wait-before-failed' {$s.Members[0].BeforeWait='Unknown'} 'wait-before-signaled' {$s.Members[0].BeforeWait='Signaled'}
  'wait-after-failed' {$s.Members[0].AfterWait='Unknown'} 'wait-after-signaled' {$s.Members[0].AfterWait='Signaled'}
  'other-class' {$s.Members[0].Image='Other'}
 }
 $e=[HereIAm.R7.JobLimitProbe]::PassingFixture();$e.AfterReady=$s
 $snapshots+=@{ name=$change; accepted=[HereIAm.R7.JobLimitProbe]::SnapshotAccepted($s); passed=[HereIAm.R7.JobLimitProbe]::Passed($e); report=([HereIAm.R7.JobLimitProbe]::SnapshotJson($s)|ConvertFrom-Json) }
}
$classes=@()
foreach($path in @('D:\\synthetic-probe\\probe.exe','C:\\Windows\\System32\\conhost.exe','C:\\Windows\\System32\\OpenConsole.exe','D:\\other\\conhost.exe','C:\\Windows\\System32\\conhost.exe.extra','C:\\Windows\\System32\\subfolder\\conhost.exe','\\\\server\\share\\conhost.exe')) {
 $classes+=[int][HereIAm.R7.JobLimitProbe]::ClassifyImage($path,'D:\\synthetic-probe\\probe.exe','C:\\Windows\\System32')
}
$flagRows=@()
foreach($detached in @($false,$true)) {
 $e=[HereIAm.R7.JobLimitProbe]::PassingFixture();$e.Detached=$detached
 $report=([HereIAm.R7.JobLimitProbe]::Report($e)|ConvertFrom-Json)
 $e.After=$null; $missingCleanupPass=[HereIAm.R7.JobLimitProbe]::Passed($e)
 $e=[HereIAm.R7.JobLimitProbe]::PassingFixture();$e.Detached=$detached;$a=$e.Before;$a.ActiveProcesses=2;$a.TotalProcesses=2;$e.Before=$a
 $flagRows+=@{ detached=$detached; flags=[HereIAm.R7.JobLimitProbe]::CreationFlags($detached); report=$report; missing_cleanup_pass=$missingCleanupPass; extra_member_pass=[HereIAm.R7.JobLimitProbe]::Passed($e) }
}
@{ selftest=$selftest; plan=$plan; default=$default; invalid=$invalid; base=([HereIAm.R7.JobLimitProbe]::Report($base)|ConvertFrom-Json); unknown=([HereIAm.R7.JobLimitProbe]::Report($unknown)|ConvertFrom-Json); rejections=$rejections; cleanups=$cleanups; exits=$exits; parserRows=$parserRows; snapshots=$snapshots; classes=$classes; flagRows=$flagRows } | ConvertTo-Json -Depth 12 -Compress
`;
const run = JSON.parse(execFileSync('powershell.exe', ['-NoProfile', '-NonInteractive', '-Command', script], { encoding: 'utf8', maxBuffer: 1024 * 1024 }));

test('compile and real managed selftest exit: 29 policy cases and 16 parser cases', () => {
  assert.equal(run.selftest.exit, 0);
  assert.equal(run.selftest.report.passed, true);
  assert.equal(run.selftest.report.native_executed, false);
  assert.equal(run.selftest.report.policy_cases, 29);
  assert.equal(run.selftest.report.negative_cases, 27);
  assert.equal(run.selftest.report.parser_cases, 16);
  assert.equal(run.selftest.report.launch_flag_cases, 2);
  assert.equal(run.selftest.report.abi_checked, true);
});
test('default/plan are read-only; invalid mode returns real exit 2', () => {
  for (const result of [run.plan, run.default]) {
    assert.equal(result.exit, 0); assert.equal(result.report.mode, 'plan');
    assert.equal(result.report.native_executed, false); assert.equal(result.report.passed, false);
  }
  assert.equal(run.invalid.exit, 2); assert.equal(run.invalid.report.passed, false);
});
test('complete pure evidence exposes the limit, rejection, exact exit and close proof', () => {
  for (const [key, value] of Object.entries({ passed:true, code:'limit_rejected_second', limit_flags:0x2008, active_process_limit:1, second_create_error:1816, first_exit_code:0, after_active:0, all_owned_handles_closed:true, cleanup_pending:false })) assert.equal(run.base[key],value,key);
});
test('36 second-create combinations accept only not-created, quota-1816, no entry', () => {
  assert.equal(run.rejections.length,36);
  for(const row of run.rejections) {
    const expected=row.created===false && row.error===1816 && row.marker===false;
    assert.equal(row.pass,expected,JSON.stringify(row)); assert.equal(row.report.passed,expected);
    assert.equal(row.report.second_create_error,row.error); assert.equal(row.report.second_created,row.created); assert.equal(row.report.second_entry_observed,row.marker);
  }
});
test('12 cleanup combinations require final held-Job query zero and every close successful', () => {
  assert.equal(run.cleanups.length,12);
  for(const row of run.cleanups) {
    const expected=row.children && row.handles && row.active===0;
    assert.equal(row.pass,expected,JSON.stringify(row)); assert.equal(row.pending,!expected);
    assert.equal(row.report.cleanup_pending,!expected); assert.equal(row.report.after_active,row.active);
    assert.equal(row.report.cleanup_query_success,row.active!==null);
  }
});
test('8 first-exit combinations require exact exit plus normal code zero', () => {
  assert.equal(run.exits.length,8);
  for(const row of run.exits) assert.equal(row.pass,row.exact && row.code===0,JSON.stringify(row));
});
test('unknown accounting and errors remain null; cleanup remains pending', () => {
  assert.equal(run.unknown.passed,false); assert.equal(run.unknown.cleanup_pending,true);
  for(const prefix of ['before','during','after']) for(const field of ['active','total','terminated']) assert.equal(run.unknown[`${prefix}_${field}`],null);
  for(const field of ['limit_flags','active_process_limit','second_create_error','first_exit_code']) assert.equal(run.unknown[field],null);
});
test('JSON schema contains only fixed strings and typed evidence', () => {
  const strings={schema:'p6_r7_job_limit_probe_v4',mode:'apply_job_limit_synthetic'};
  const snapshotKeys=['after_create_members','after_ready_members','before_cleanup_members'];
  const keys=['schema','mode','passed','code','failure_stage','requested_creation_flags','limit_flags','active_process_limit','first_pre_resume_identity','first_ready_alive','first_before_second_alive','first_after_second_alive','second_created','second_create_error','second_entry_observed','first_exact_exit','first_exit_code','child_handles_closed','all_owned_handles_closed','before_active','before_total','before_terminated','during_active','during_total','during_terminated','after_active','after_total','after_terminated','cleanup_query_success','cleanup_pending','network_used','external_requests','model_turns_requested',...snapshotKeys].sort();
  const codes=new Set(['limit_rejected_second','second_child_created','second_create_unknown_error','evidence_incomplete']);
  for(const report of [run.base,run.unknown,...run.rejections.map(x=>x.report),...run.cleanups.map(x=>x.report)]) {
    assert.deepEqual(Object.keys(report).sort(),keys);
    for(const [key,value] of Object.entries(report)) {
      if(key in strings) assert.equal(value,strings[key]);
      else if(key==='code') assert.ok(codes.has(value));
      else if(snapshotKeys.includes(key)) validateSnapshot(value);
      else assert.ok(value===null || typeof value==='boolean' || Number.isSafeInteger(value),`${key}:${value}`);
    }
    assert.equal(report.network_used,false); assert.equal(report.external_requests,0); assert.equal(report.model_turns_requested,0);
  }
});
function validateSnapshot(value) {
  if(value===null) return;
  const keys=['atomic_snapshot','member_capacity','list','query_error','returned_bytes','query_ms','snapshot_ms','accounting_before_active','accounting_before_total','accounting_before_terminated','accounting_after_active','accounting_after_total','accounting_after_terminated','counts_consistent','complete','members'].sort();
  assert.deepEqual(Object.keys(value).sort(),keys); assert.equal(value.atomic_snapshot,false); assert.equal(value.member_capacity,16);
  assert.deepEqual(Object.keys(value.list).sort(),['assigned','listed','status']);
  const statuses=new Set(['unqueried','query-failed','buffer-rejected','length-rejected','count-limit','count-mismatch','truncated','invalid-id','duplicate-id','parsed']);
  assert.ok(statuses.has(value.list.status));
  for(const [key,item] of Object.entries(value)) if(!['list','members'].includes(key)) assert.ok(item===null || typeof item==='boolean' || Number.isSafeInteger(item));
  const memberKeys=['status','image_class','wait_before','wait_after','opened','identity_confirmed','creation_observed','creation_precedes_list','own_job_member','matches_first_identity','handle_closed','error'].sort();
  const memberStatuses=new Set(['unqueried','open-failed','identity-failed','membership-failed','wait-failed','signaled-before-image','image-query-failed','observed','close-failed']);
  const images=new Set(['query-failed','expected-probe','system32-conhost','system32-openconsole','other']);
  const waits=new Set(['query-failed','signaled','timeout']);
  assert.ok(value.members.length<=16);
  for(const member of value.members) {
    assert.deepEqual(Object.keys(member).sort(),memberKeys);
    assert.ok(memberStatuses.has(member.status)); assert.ok(images.has(member.image_class));
    assert.ok(waits.has(member.wait_before)); assert.ok(waits.has(member.wait_after));
    for(const [key,item] of Object.entries(member)) if(!['status','image_class','wait_before','wait_after'].includes(key)) assert.ok(item===null || typeof item==='boolean' || Number.isSafeInteger(item));
  }
  assert.doesNotMatch(JSON.stringify(value),/123456789|synthetic-probe|[CD]:\\\\/);
}
test('23 independently encoded fixed-buffer vectors reject bad lengths, counts, overflow and IDs', () => {
  assert.equal(run.parserRows.length,parserVectors.length);
  for(const [index,row] of run.parserRows.entries()) {
    assert.equal(row.name,parserVectors[index].name);
    assert.equal(row.report.status,parserVectors[index].expected,row.name);
    assert.deepEqual(Object.keys(row.report).sort(),['assigned','listed','status']);
    assert.doesNotMatch(JSON.stringify(row.report),/123456789/);
  }
});
test('22 snapshot evidence cases prevent incomplete observations from enabling second-create or final pass', () => {
  assert.equal(run.snapshots.length,22);
  for(const row of run.snapshots) {
    const expected=['baseline','other-class'].includes(row.name);
    assert.equal(row.accepted,expected,row.name); assert.equal(row.passed,expected,row.name); validateSnapshot(row.report);
  }
  const missingImage=run.snapshots.find(x=>x.name==='image-query-failed').report.members[0];
  assert.equal(missingImage.image_class,'query-failed'); assert.equal(missingImage.wait_before,'timeout');
});
test('exact canonical path projection rejects basename-only, extension, directory and UNC lookalikes', () => {
  assert.deepEqual(run.classes,[1,2,3,4,4,4,0]);
});
test('detached candidate uses only DETACHED_PROCESS; both modes retain identical limit and cleanup gates', () => {
  assert.equal(run.flagRows.length,2);
  for(const row of run.flagRows) {
    assert.equal(row.flags,row.detached?0x0008040c:0x08080404);
    assert.equal(row.flags&0x00080404,0x00080404);
    assert.equal(row.flags&0x10,0);
    assert.equal(row.flags&0x8,row.detached?8:0);
    assert.equal(row.flags&0x08000000,row.detached?0:0x08000000);
    assert.equal(row.report.requested_creation_flags,row.flags);
    assert.equal(row.report.mode,row.detached?'apply_job_limit_synthetic_detached':'apply_job_limit_synthetic');
    assert.equal(row.report.passed,true); assert.equal(row.missing_cleanup_pass,false); assert.equal(row.extra_member_pass,false);
    const {mode,requested_creation_flags,...unchanged}=row.report;
    const {mode:baseMode,requested_creation_flags:baseFlags,...baseline}=run.base;
    assert.deepEqual(unchanged,baseline);
  }
});
test('native API boundary: no network/elevation, exactly one atomic second attempt and no second Resume', () => {
  assert.doesNotMatch(text,/Fwpm|Socket|HttpClient|WebRequest|ShellExecute|runas|AssignProcessToJobObject|Process\.Start|Environment\.GetEnvironmentVariables|e\.Message/);
  for(const api of ['GetFinalPathNameByHandleW','GetFileInformationByHandle','GetSecurityInfo','CreateDirectoryW','GetProcessId','GetProcessTimes','IsProcessInJob','QueryFullProcessImageNameW','GetExitCodeProcess']) assert.ok(text.includes(api));
  assert.equal((text.match(/result\.Created=Native\.CreateProcessW\(/g)??[]).length,1);
  assert.equal((text.match(/CreateSuspendedInJob\(second,/g)??[]).length,1);
  assert.equal((text.match(/Native\.ResumeThread\(/g)??[]).length,1);
  assert.ok(text.includes('Native.ResumeThread(first.Info.Thread)==1'));
  assert.ok(text.includes('CreateProcessW(string app, StringBuilder command'));
  assert.ok(text.includes('CreateSuspended|ExtendedStartupInfoPresent|CreateUnicodeEnvironment|(detached?DetachedProcess:CreateNoWindow)'));
  assert.ok(text.includes('false,CreationFlags(detached),environment,root,ref startup,out result.Info'));
  assert.ok(text.includes('if(initialized) Native.DeleteProcThreadAttributeList(list)'));
  const jobBody=text.slice(text.indexOf('static IntPtr CreateJob('),text.indexOf('static JobAccounting ReadAccounting'));
  assert.ok(jobBody.indexOf('Require(error!=183')<jobBody.indexOf('Native.SetInformationJobObject'));
  assert.ok(text.includes('Require(IntPtr.Size==8,"x64_required")')); assert.doesNotMatch(text,/x86|==108|==44/);
  assert.doesNotMatch(text,/EnumProcesses|CreateToolhelp32Snapshot|GetProcesses\(|NtQuerySystemInformation|Win32_Process/);
  assert.equal((text.match(/Native\.OpenProcess\(/g)??[]).length,1);
  assert.ok(text.includes('Native.OpenProcess(0x00101000,false,listedId)'));
  assert.ok(text.includes('JobObjectBasicProcessIdList = 3, ProcessListCapacity = 16'));
  assert.ok(text.includes('foreach(uint id in result.List.Ids)'));
  assert.equal((text.match(/=CaptureMembers\(/g)??[]).length,3);
  assert.ok(text.includes('evidence.Before.Value.ActiveProcesses==1 && evidence.Before.Value.TotalProcesses==1'));
  assert.ok(text.includes('if(args.Length==1 && args[0]=="--apply-job-limit-synthetic-detached") return Apply(true)'));
  assert.ok(text.includes('if(args.Length==1 && args[0]=="--apply-job-limit-synthetic") return Apply(false)'));
  assert.doesNotMatch(text,/AllocConsole|AttachConsole|FreeConsole|ReadConsole|GetStdHandle/);
  const sentinel=text.slice(text.indexOf('static int Sentinel('),text.indexOf('static int Apply('));
  assert.doesNotMatch(sentinel,/Console\./);
});
