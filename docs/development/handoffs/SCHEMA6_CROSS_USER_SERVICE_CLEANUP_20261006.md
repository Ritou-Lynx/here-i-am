# Schema6 cross-user CI Secondary Logon cleanup — 2026-10-06

- Base: `e1116f5e02aded0553c63a1c8ec646d40123fe96`; branch `codex/schema6-ci-service-cleanup-20261006`.
- Scope: only the parent/common cross-user CI fixtures and this handoff. No production path, ACL, authentication, restore, or lifecycle checks changed. Parent integration owns global project state; this worker uses the authorized one-commit `SKIP_PROJECT_STATE=1` exception and restores its prior environment value in `finally`. No push.

## Evidence and behavior

Parent-provided hosted evidence: push run `37428994033`, job `112155458027` reported `secondaryLogonRestored=false`, `CouldNotStopService`, native error `1052`; Job, child, account and token cleanup were true. PR run `37428998170`, job `112155278130` had successful cleanup. Error 1052 means an unacceptable service control, not proof of StopPending. The exact failure-time state remains unknown. Parent subsequently confirmed both BOM-fixed baseline runs `37429716715` / `37429722424`, jobs `112157590807` / `112157585768`, passed the real different-SID password restore with all cleanup true (133300 / 135225 ms). Those results precede this state-machine change; they do not validate this new candidate.

The previous fixture sent Stop-Service without its own state/accepted-control gate. The new test-only transition helper polls fresh status every 250 ms within a 60,000 ms observation budget. It starts only after observing Stopped, records ownership immediately on successful Start(), and retains that ownership if later readiness times out. A concurrent start returning 1056 is unowned. Already-running services are left running; Paused is rejected without modification. Pending states are observed rather than controlled.

Cleanup requires fixture ownership, waits through pending/non-accepting states, and sends at most one STOP when Running and CanStop. Native STOP opens only fixed `seclogon` with SERVICE_STOP and closes both handles; it has no dependency traversal, force switch, service-host kill, configuration mutation, or arbitrary service name. Codes 1052/1061/1062 cause fresh observations, never success by themselves and never repeated STOP. Only observed Stopped sets the cleanup boolean true. Persistent refusal still fails cleanup.

Safe evidence contains numeric status enums (0 unobserved; 1 Stopped, 2 StartPending, 3 StopPending, 4 Running, 5 ContinuePending, 6 PausePending, 7 Paused), booleans, counts, numeric native error and elapsed times, including before/first-after STOP snapshots. No exception text, account identity, paths or credentials are added.

The 60 s budget bounds polling, not an in-flight synchronous Windows API call: SCM ControlService may itself block about 30 s. No hard real-time 60 s wall-clock claim is made. GuardOnly remains before all account/service/directory/pipe/process actions; the native adapter independently repeats the hosted-runner guard before constructing ServiceController.

Sources: [ControlService](https://learn.microsoft.com/en-us/windows/win32/api/winsvc/nf-winsvc-controlservice), [error 1052](https://learn.microsoft.com/en-us/windows/win32/debug/system-error-codes--1000-1299-), [ServiceController.Stop dependency behavior](https://learn.microsoft.com/en-us/dotnet/api/system.serviceprocess.servicecontroller.stop).

## Validation

- Windows PowerShell `5.1.26100.9444`: both edited scripts parse; full embedded native helper compiles.
- 18/18 deterministic in-memory transition scenarios below pass. They include custody on start timeout, 1056 unowned race, initial/pending/paused states, CanStop becoming true, 1052 waiting to real Stopped versus persistent refusal, 1061/1062 recheck, 1051 no-force failure, and exact fake-clock timeout. Before/after control evidence is asserted.
- Native adapter rejects local invocation before service access. Parent `powershell.exe -NoProfile -NonInteractive -File tools/i_core/test_fixtures/release_schema6/cross_user_restore.ps1 -GuardOnly` exits 2 with only `cross_user_restore_rejected:hosted_runner_required`.
- `git diff --check` passes. No actual service query/start/stop, account creation, real store, scheduled task, phone or hosted cross-user run was performed locally. Hosted end-to-end cleanup remains for root's CI integration; this is not a claim that the intermittent remote failure is reproduced or resolved.

Run the following body in Windows PowerShell 5.1 from the repository root. It deliberately refuses GitHub-hosted execution and does not invoke native service methods; only the hosted guard is exercised through the real adapter.

```powershell

$ErrorActionPreference='Stop'
if($env:GITHUB_ACTIONS -ceq 'true' -and $env:RUNNER_ENVIRONMENT -ceq 'github-hosted'){throw 'local_simulation_only'}
$ProgressPreference='SilentlyContinue'
$common=Join-Path (Get-Location) 'tools/i_core/test_fixtures/release_schema6/cross_user_restore_common.ps1'
$parent=Join-Path (Get-Location) 'tools/i_core/test_fixtures/release_schema6/cross_user_restore.ps1'
foreach($file in @($common,$parent)){
 $tokens=$null;$errors=$null;[void][Management.Automation.Language.Parser]::ParseFile($file,[ref]$tokens,[ref]$errors)
 if($errors.Count){throw 'syntax_failed'}
}
. $common
Initialize-CrossUserNative
function S([int]$n,[bool]$can=$false){[pscustomobject]@{State=$n;CanStop=$can}}
$results=@()
function Test-Sequence([string]$Name,[string]$Mode,[object[]]$States,[int]$StartCode=0,[int]$StopCode=0,[string]$ExpectedError='',[int]$Starts=0,[int]$Stops=0,[bool]$Owned=$false){
 $sim=@{index=0;elapsed=0;starts=0;stops=0}
 $e=New-CrossUserServiceEvidence
 if($Mode -eq 'Restore'){$e.startedByFixture=$true}
 $caught=''
 try{
  Invoke-CrossUserServiceTransition -Mode $Mode -Evidence $e -TimeoutMilliseconds 1000 -Query {$States[[Math]::Min($sim.index,$States.Length-1)]} -Start {$sim.starts++;$StartCode} -Stop {$sim.stops++;$StopCode} -Elapsed {$sim.elapsed} -Delay {$sim.index++;$sim.elapsed+=250}
 }catch{$caught=$_.Exception.Message}
 if($caught -cne $ExpectedError -or $sim.starts -ne $Starts -or $sim.stops -ne $Stops -or $e.startedByFixture -ne $Owned){throw ('case_failed:'+ $Name+':'+$caught)}
 if($ExpectedError -eq 'ci_service_transition_timeout' -and (-not $e.timedOut -or $sim.elapsed -ne 1000)){throw 'budget_failed'}
 if($Mode -eq 'Restore' -and -not $caught -and $e.lastState -ne 1){throw 'stopped_confirmation_failed'}
 if($sim.stops -gt 0 -and ($e.beforeStopState -ne 4 -or -not $e.beforeStopCanStop)){throw 'before_stop_evidence_failed'}
 if($Mode -eq 'Restore' -and -not $caught -and $sim.stops -gt 0 -and $e.afterStopState -eq 0){throw 'after_stop_evidence_failed'}
 [pscustomobject]@{name=$Name;passed=$true;starts=$sim.starts;stops=$sim.stops;owned=$e.startedByFixture;lastState=$e.lastState;nativeErrorCode=$e.nativeErrorCode;elapsed=$sim.elapsed}
}
$results+=Test-Sequence 'already_running_unowned' Start @((S 4 $true))
$results+=Test-Sequence 'stopped_start_owned' Start @((S 1),(S 2),(S 4 $true)) -Starts 1 -Owned $true
$results+=Test-Sequence 'start_pending_external' Start @((S 2),(S 4 $true))
$results+=Test-Sequence 'stop_pending_then_own_start' Start @((S 3),(S 1),(S 2),(S 4 $true)) -Starts 1 -Owned $true
$results+=Test-Sequence 'concurrent_start_1056_unowned' Start @((S 1),(S 4 $true)) -StartCode 1056 -Starts 1
$results+=Test-Sequence 'start_denied_unowned' Start @((S 1)) -StartCode 5 -Starts 1 -ExpectedError ci_service_start_rejected
$results+=Test-Sequence 'start_timeout_keeps_custody' Start @((S 1),(S 2)) -Starts 1 -Owned $true -ExpectedError ci_service_transition_timeout
$results+=Test-Sequence 'paused_not_mutated' Start @((S 7)) -ExpectedError ci_service_initial_paused
$results+=Test-Sequence 'already_stopped_no_stop' Restore @((S 1)) -Owned $true
$results+=Test-Sequence 'stop_pending_no_resend' Restore @((S 3),(S 1)) -Owned $true
$results+=Test-Sequence 'wait_until_accepts_stop' Restore @((S 4),(S 4 $true),(S 3),(S 1)) -Stops 1 -Owned $true
$results+=Test-Sequence '1052_then_real_stop' Restore @((S 4 $true),(S 3),(S 1)) -StopCode 1052 -Stops 1 -Owned $true
$results+=Test-Sequence '1052_never_false_success_or_resend' Restore @((S 4 $true)) -StopCode 1052 -Stops 1 -Owned $true -ExpectedError ci_service_transition_timeout
$results+=Test-Sequence '1061_then_real_stop' Restore @((S 4 $true),(S 3),(S 1)) -StopCode 1061 -Stops 1 -Owned $true
$results+=Test-Sequence '1062_requires_real_stop' Restore @((S 4 $true),(S 1)) -StopCode 1062 -Stops 1 -Owned $true
$results+=Test-Sequence 'dependent_service_error_no_force' Restore @((S 4 $true)) -StopCode 1051 -Stops 1 -Owned $true -ExpectedError ci_service_stop_rejected
$results+=Test-Sequence 'never_accepts_stop_timeout' Restore @((S 4)) -Owned $true -ExpectedError ci_service_transition_timeout
$results+=Test-Sequence 'pending_before_stop' Restore @((S 2),(S 4 $true),(S 3),(S 1)) -Stops 1 -Owned $true
$guarded=$false
try{Invoke-CrossUserSecondaryLogon -Mode Restore -Evidence (New-CrossUserServiceEvidence)}catch{if($_.Exception.Message -eq 'hosted_windows_ci_required'){$guarded=$true}else{throw}}
if(-not $guarded){throw 'local_native_adapter_guard_failed'}
@{powershell=$PSVersionTable.PSVersion.ToString();syntaxFiles=2;nativeCompiled=$true;stateCases=$results;nativeAdapterGuardRejected=$guarded}|ConvertTo-Json -Depth 5 -Compress

```


## Follow-up: fresh PS5.1 service type loading

Parent reported candidate `d9f66775` failing both hosted runs `37430777811` / `37430770899`, jobs `112160988489` / `112160898262`, at `secondary_logon_query`: RuntimeException, HResult -2146233087, no native code, all service observations/elapsed values zero, no child created, account removed. The new adapter constructed ServiceController before starting its clock, but fresh PS5.1 had not loaded its assembly. The earlier pure callback scenarios and local guard rejection did not exercise this type-resolution boundary.

Deterministic local reproduction in a fresh Windows PowerShell 5.1 process, after dot-sourcing common and compiling its native types, produced `System.Management.Automation.RuntimeException`, HResult `-2146233087`, FQID `TypeNotFound` from type resolution alone. The service-free `Initialize-CrossUserServiceTypes` now explicitly loads `System.ServiceProcess`; it runs after the hosted guard and before construction. The same type resolves afterward and repeated loading succeeds. No service instance was constructed and no live service was queried. This fixes the demonstrated initialization defect; hosted end-to-end remains for parent integration.

Validation: fresh-process before/after regression and repeated load pass; adapter guard/load/construct order checked; both scripts parse; embedded native helper compiles; parent GuardOnly still exits 2 before action; diff check passes. Existing 18 simulated state-machine tests remain prior evidence, not new native service coverage. Follow-up commit again uses only the authorized per-commit SKIP_PROJECT_STATE exception with finally restoration.

Exact fresh-process regression body (run with Windows PowerShell 5.1 `-NoProfile -NonInteractive -EncodedCommand`, UTF-16LE encoding of this body):

```powershell

$ErrorActionPreference='Stop'
$ProgressPreference='SilentlyContinue'
. ./tools/i_core/test_fixtures/release_schema6/cross_user_restore_common.ps1
Initialize-CrossUserNative
$before=$null
try{$null=[ServiceProcess.ServiceController];throw 'expected_fresh_type_failure'}catch{
 if($_.FullyQualifiedErrorId -ne 'TypeNotFound'){throw}
 $before=@{type=$_.Exception.GetType().FullName;hresult=$_.Exception.HResult;id=$_.FullyQualifiedErrorId}
}
Initialize-CrossUserServiceTypes
if([ServiceProcess.ServiceController].FullName -cne 'System.ServiceProcess.ServiceController'){throw 'type_load_failed'}
Initialize-CrossUserServiceTypes
$body=(Get-Command Invoke-CrossUserSecondaryLogon).Definition
$guard=$body.IndexOf('Assert-CrossUserCI -Parent')
$load=$body.IndexOf('Initialize-CrossUserServiceTypes')
$construct=$body.IndexOf('$controller=[ServiceProcess.ServiceController]::new')
if($guard -lt 0 -or $load -le $guard -or $construct -le $load){throw 'adapter_order_failed'}
$tokens=$null;$errors=$null
foreach($file in @('cross_user_restore_common.ps1','cross_user_restore.ps1')){
 [void][Management.Automation.Language.Parser]::ParseFile((Join-Path (Join-Path (Get-Location) 'tools/i_core/test_fixtures/release_schema6') $file),[ref]$tokens,[ref]$errors)
 if($errors.Count){throw 'syntax_failed'}
}
@{before=$before;after=[ServiceProcess.ServiceController].FullName;repeatedLoadPassed=$true;guardLoadConstructOrderPassed=$true;syntaxFiles=2;nativeCompiled=$true;serviceInstancesCreated=0}|ConvertTo-Json -Compress

```
