#requires -Version 5.1
# Dormant candidate. Plan returns literal metadata without source/config/COM/network/file access.
function Get-ContinuousActivationPlan {
 return [ordered]@{format='continuous-activation-plan-v1';mode='Plan';ioPerformed=$false;productionAuthorized=$false;sequence=@('verified-lease','closed-baseline','release-runtime-custody-locks','supervised-package-switch','relock-post-switch-closed-and-pending','TASK_UPDATE','actual-four-anchor-readback','enable','single-run-or-real-attach','actual-P3','promote','P4');runBudget=1;historicalProductionRuns=2}
}
function Invoke-ActivationChild {
 param([string]$Image,[string]$Arguments,[string]$InputText,[int]$BudgetMs=30000,$EvidenceLease)
 if(!(Get-Variable ActivationRetainedChildren -Scope Script -ErrorAction SilentlyContinue)){$script:ActivationRetainedChildren=[Collections.Generic.List[object]]::new()}
 $held=$false
 $psi=[Diagnostics.ProcessStartInfo]::new();$psi.FileName=$Image;$psi.Arguments=$Arguments;$psi.UseShellExecute=$false;$psi.CreateNoWindow=$true
 $psi.RedirectStandardInput=$true;$psi.RedirectStandardOutput=$true;$psi.RedirectStandardError=$true
 $psi.EnvironmentVariables.Clear()
 foreach($key in @('SystemRoot','WINDIR','TEMP','TMP')){$psi.EnvironmentVariables[$key]=[Environment]::GetEnvironmentVariable($key)}
 $psi.EnvironmentVariables['PATH']=$env:SystemRoot+'\System32';$psi.EnvironmentVariables['PATHEXT']='.EXE'
 $bytes=[Text.Encoding]::UTF8.GetBytes($InputText);if($bytes.Length-gt131072){throw 'child_input_limit'}
 if($null-ne$EvidenceLease){$EvidenceLease.Retain();$held=$true}
 $watch=[Diagnostics.Stopwatch]::StartNew();try{$child=[Diagnostics.Process]::Start($psi)}catch{if($held){$EvidenceLease.Release()};throw 'child_start_failed'}
 $write=$child.StandardInput.BaseStream.WriteAsync($bytes,0,$bytes.Length)
 $streams=@($child.StandardOutput.BaseStream,$child.StandardError.BaseStream)
 $buffers=@([byte[]]::new(4096),[byte[]]::new(4096));$reads=@($null,$null);$eof=@($false,$false)
 $output=[IO.MemoryStream]::new();$count=0;$failed=$false;$inputClosed=$false
 try{
  while($true){
   if($watch.ElapsedMilliseconds-ge$BudgetMs){$failed=$true;break}
   if(!$inputClosed-and$write.IsCompleted){$null=$write.GetAwaiter().GetResult();$child.StandardInput.Close();$inputClosed=$true}
   for($i=0;$i-lt2;$i++){
    if(!$eof[$i]-and$null-eq$reads[$i]){$reads[$i]=$streams[$i].ReadAsync($buffers[$i],0,4096)}
    if($null-ne$reads[$i]-and$reads[$i].IsCompleted){
     $n=$reads[$i].GetAwaiter().GetResult();$reads[$i]=$null
     if($n-eq0){$eof[$i]=$true}else{$count+=$n;if($count-gt65536){$failed=$true;break};if($i-eq0){$output.Write($buffers[$i],0,$n)}}
    }
   }
   if($failed-or($child.HasExited-and$inputClosed-and$write.IsCompleted-and$eof[0]-and$eof[1])){break}
   [Threading.Thread]::Sleep(5)
  }
  if($watch.ElapsedMilliseconds-ge$BudgetMs){$failed=$true}
  if($failed){if($null-eq$script:ActivationRetainedChildren){$script:ActivationRetainedChildren=[Collections.Generic.List[object]]::new()};$script:ActivationRetainedChildren.Add(@{Process=$child;Reads=$reads;Streams=$streams;Buffers=$buffers;Input=$write;InputClosed=$inputClosed;Eof=$eof;Lease=$EvidenceLease;LeaseHeld=$held;OwnedLocks=@()});return @{exitCode=$null;retained=$true;elapsedMs=$watch.ElapsedMilliseconds;stdout=$null}}
  $code=$child.ExitCode;$child.Dispose();if($held){$EvidenceLease.Release();$held=$false}
  return @{exitCode=$code;retained=$false;elapsedMs=$watch.ElapsedMilliseconds;stdout=[Text.UTF8Encoding]::new($false,$true).GetString($output.ToArray())}
 }catch{
  if($null-eq$script:ActivationRetainedChildren){$script:ActivationRetainedChildren=[Collections.Generic.List[object]]::new()}
  $script:ActivationRetainedChildren.Add(@{Process=$child;Reads=$reads;Streams=$streams;Buffers=$buffers;Input=$write;InputClosed=$inputClosed;Eof=$eof;Lease=$EvidenceLease;LeaseHeld=$held;OwnedLocks=@()})
  return @{exitCode=$null;retained=$true;elapsedMs=$watch.ElapsedMilliseconds;stdout=$null}
 }finally{$output.Dispose()}
}
function Complete-ActivationChildren {
 if(!(Get-Variable ActivationRetainedChildren -Scope Script -ErrorAction SilentlyContinue)){return @{retained=0}}
 foreach($x in $script:ActivationRetainedChildren.ToArray()){
  # Drain and discard bounded chunks after a timeout/limit. No late output is accepted.
  try{
   if(!$x.InputClosed-and$x.Input.IsCompleted){$null=$x.Input.GetAwaiter().GetResult();$x.Process.StandardInput.Close();$x.InputClosed=$true}
   for($i=0;$i-lt2;$i++){
    if($null-ne$x.Reads[$i]-and$x.Reads[$i].IsCompleted){$n=$x.Reads[$i].GetAwaiter().GetResult();$x.Reads[$i]=$null;if($n-eq0){$x.Eof[$i]=$true}}
    if(!$x.Eof[$i]-and$null-eq$x.Reads[$i]){$x.Reads[$i]=$x.Streams[$i].ReadAsync($x.Buffers[$i],0,4096)}
   }
  }catch{}
  if($x.Process.HasExited-and$x.InputClosed-and$x.Input.IsCompleted-and$x.Eof[0]-and$x.Eof[1]-and$null-eq$x.Reads[0]-and$null-eq$x.Reads[1]){$x.Process.Dispose();foreach($h in $x.OwnedLocks){$h.Dispose()};if($x.LeaseHeld){$x.Lease.Release()};$null=$script:ActivationRetainedChildren.Remove($x)}
 }
 return @{retained=$script:ActivationRetainedChildren.Count}
}
function Invoke-ReviewedContinuousActivation {
 [CmdletBinding()]param([ValidateSet('Plan','Execute')][string]$Mode='Plan',$Lease)
 if($Mode-ceq'Plan'){return Get-ContinuousActivationPlan}
 $ErrorActionPreference='Stop';Set-StrictMode -Version 2
 if(!(Get-Variable ActivationRetainedChildren -Scope Script -ErrorAction SilentlyContinue)){$script:ActivationRetainedChildren=[Collections.Generic.List[object]]::new()}
 $record=Get-P4LeaseRecord $Lease
 if($Lease.Mode-cne'reviewed-live'-or$Lease.Readiness-cne'approval-authorized'-or$record.ContainsKey('ActivationControllerConsumed')){throw 'activation_live_lease_required'}
 $approval=Read-P4StrictJson $record.Map['approval'].Bytes()
 if($approval.scope-cne'task-update-enable-run-attach-p3-p4-normal-close-once'-or$approval.runBudget-ne1-or$approval.failureContainment-cne'disable-and-exact-normal-close'){throw 'activation_scope_required'}
 $now=[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
 if($now-lt$approval.notBeforeUtcMs-or$now-gt$approval.notAfterUtcMs){throw 'activation_approval_expired'}
 $policy=$Lease.ReadJson('activation_policy')
 if($policy.format-cne'i-core-continuous-activation-policy-v2'-or$policy.evidenceMode-cne'reviewed-live'-or$policy.attemptId-cne$record.Policy.attemptId-or$policy.planSha256-cne$record.Policy.planSha256-or$policy.historicalProductionRuns-ne2-or$policy.newRunBudget-ne1){throw 'activation_policy_binding'}
 if($policy.approvalSha256-ne$null-and$policy.approvalSha256-cne$Lease.ApprovalSha256){throw 'activation_policy_approval'}
 $required=@('activation_policy','activation_controller','activation_entrypoint','activation_preflight','total_gate','p4_total_policy','backup_policy','identity_library','identity_native','activation_proof','identity_sampler','p3_library','evidence_native','evidence_launcher','owned_helper','task_primitives','task_security','task_projection','caller_context','login_config','core_config','mcp_config','backup_config','node','powershell','normal_close','process_image_binding','new_task_raw','new_task_definition','new_task_sddl','parent_sddl','old_task_raw','task_template_evaluator','task_template_rules','task_template_action','task_template_disabled_raw','task_template_enabled_raw','task_template_disabled_definition','task_template_enabled_definition','baseline_registration','baseline_login','baseline_daily','baseline_p0','manifest','source_inventory','package_switch_plan','package_switch_policy','start_schema6')
 foreach($id in $required){$null=$Lease.Hash($id)}
 foreach($pin in $policy.artifacts){if($Lease.Hash($pin.id)-cne$pin.sha256){throw 'activation_artifact_changed'}}
 if(@($policy.artifacts).Count-ne($required.Count-1)-or@($required|Where-Object{$_-cne'activation_policy'-and$_-cnotin@($policy.artifacts.id)}).Count){throw 'activation_artifact_inventory'}
 $utf8=[Text.UTF8Encoding]::new($false,$true)
 foreach($id in @('owned_helper','task_primitives','task_security','task_projection','caller_context','identity_library','activation_proof','identity_sampler','p3_library')){. ([scriptblock]::Create($utf8.GetString($Lease.Bytes($id))))}
 $owner=$record.Owner;Assert-OwnedArtifactUnelevatedProcess $owner;Initialize-OwnedArtifactNative;Initialize-TaskInstanceProjection
 function HashFile([string]$p){(Get-FileHash -LiteralPath $p -Algorithm SHA256).Hash.ToLowerInvariant()}
 function Ref([string]$p){[ordered]@{path=$p;sha256=(HashFile $p)}}
 function WriteJson([string]$p,$v){Write-OwnedArtifactBytes $p ($utf8.GetBytes(($v|ConvertTo-Json -Depth 30 -Compress)+[char]10)) $owner}
 function TextRole([string]$id){$utf8.GetString((Get-ActivationLockedBytes -Lease $Lease -RoleId $id))}
 function JsonRole([string]$id){Read-P4StrictJson (Get-ActivationLockedBytes -Lease $Lease -RoleId $id)}
 $cfg=$policy.registration;$login=JsonRole 'login_config';$core=JsonRole 'core_config';$daily=JsonRole 'backup_config';$mcpDeclaration=JsonRole 'mcp_config'
 $loginPath=(Get-ActivationLockedPath -Lease $Lease -RoleId 'login_config');$node=(Get-ActivationLockedPath -Lease $Lease -RoleId 'node')
 if($cfg.manifestSha256-cne$Lease.Hash('manifest')-or$login.owner_sid-cne$owner-or$cfg.taskName-cne$policy.taskPath.TrimStart('\')-or$policy.taskPath-ceq$policy.oldTaskPath){throw 'activation_static_identity'}
 foreach($pair in @(@('core_configuration','core_config'),@('backup_configuration','backup_config'),@('mcp_configuration','mcp_config'))){
  if($login.($pair[0]+'_path')-cne(Get-ActivationLockedPath -Lease $Lease -RoleId $pair[1])-or$login.($pair[0]+'_sha256')-cne$Lease.Hash($pair[1])){throw 'activation_configuration_link'}
 }
 $baseline=JsonRole 'baseline_login'
 if($baseline.state_directory-cne$login.state_directory-or$baseline.owner_sid-cne$owner){throw 'activation_baseline_state'}
 $oldCorePath=$baseline.core_configuration_path
 $copy=$policy.baselineCore
 if(@(Compare-Object @($copy.PSObject.Properties.Name|Sort-Object) @('path','sha256','originalPath','exactCopy'|Sort-Object)).Count-or$copy.exactCopy-isnot[bool]-or!$copy.exactCopy-or$copy.originalPath-cne$oldCorePath-or$copy.sha256-cne$baseline.core_configuration_sha256-or$copy.path-ceq$oldCorePath){throw 'activation_baseline_core_copy'}
 $oldCoreRef=@($policy.baselineFiles|Where-Object{$_.path-ceq$copy.path})
 if($oldCoreRef.Count-ne1-or$oldCoreRef[0].sha256-cne$baseline.core_configuration_sha256){throw 'activation_baseline_core_pin'}
 $baselineLeases=[Collections.Generic.List[IDisposable]]::new()
 foreach($ref in @($policy.baselineFiles)+@($policy.baselineSourceFiles)){$l=[P4EvidenceLease]::new($ref.path,$owner,$false,$true,16777216);$baselineLeases.Add($l);$record.All.Add($l);if($l.Hash()-cne$ref.sha256){throw 'activation_baseline_file_changed'}}
 $acl=Get-Acl -LiteralPath (Get-ActivationLockedPath -Lease $Lease -RoleId 'backup_config')
 if(!$acl.AreAccessRulesProtected-or$acl.GetOwner([Security.Principal.SecurityIdentifier]).Value-cne$owner){throw 'automatic_private_acl'}
 foreach($ace in $acl.GetAccessRules($true,$true,[Security.Principal.SecurityIdentifier])){if($ace.AccessControlType-eq[Security.AccessControl.AccessControlType]::Allow-and$ace.IdentityReference.Value-cne$owner-and$ace.IdentityReference.Value-cne'S-1-5-18'){throw 'automatic_extra_principal'}}
 $oldCore=Read-P4StrictJson ([IO.File]::ReadAllBytes($copy.path))
 $switchContract=Assert-ActivationSwitchContract $Lease $policy $baseline $core
 foreach($field in @('database_path','recovery_custody_directory','owner_sid')){if($oldCore.$field-cne$core.$field){throw 'activation_baseline_core_identity'}}
 $attempt=Join-Path $record.Binding.observation.activationRoot $record.Policy.attemptId
 if($policy.activationRoot-cne$record.Binding.observation.activationRoot){throw 'activation_output_root'}
 if(Test-Path -LiteralPath $attempt){throw 'activation_attempt_consumed'}
 New-OwnedArtifactDirectory $attempt $owner
 $record.ActivationControllerConsumed=$true
 $result=[ordered]@{format='continuous-activation-result-v1';passed=$false;evidenceMode='reviewed-live';attemptId=$record.Policy.attemptId;runCalls=0;enableAttempted=$false;taskUpdateAttempted=$false;productionP3=$false;productionP4=$false;beforeSessionDirectories=@();enableAttemptStartedAt=$null}
 $task=$null;$folder=$null;$service=$null
function ConvertToStrictUtcTicks([string]$value){
 if([string]::IsNullOrWhiteSpace($value)-or$value-cnotmatch'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,7})?(?:Z|[+-]\d{2}:\d{2})$'){throw 'explicit_valid_timestamp_required'}
 $parsed=[DateTimeOffset]::MinValue
 $formats=[string[]]@("yyyy-MM-dd'T'HH:mm:ss'Z'","yyyy-MM-dd'T'HH:mm:ss.FFFFFFF'Z'","yyyy-MM-dd'T'HH:mm:sszzz","yyyy-MM-dd'T'HH:mm:ss.FFFFFFFzzz")
 $styles=[Globalization.DateTimeStyles]::AssumeUniversal -bor [Globalization.DateTimeStyles]::AdjustToUniversal
 if(![DateTimeOffset]::TryParseExact($value,$formats,[Globalization.CultureInfo]::InvariantCulture,$styles,[ref]$parsed)){throw 'explicit_valid_timestamp_required'}
 return [long]$parsed.UtcDateTime.Ticks
}
function TestHostStartUtcLowerBound([datetime]$started,[string]$enabledAt){
 if($started.Kind-eq[DateTimeKind]::Unspecified){throw 'host_start_timezone_required'}
 return $started.ToUniversalTime().Ticks-ge(ConvertToStrictUtcTicks $enabledAt)
}
function AssertObservedStopped([string]$Name){
 $v=Get-TaskInstanceProjection $Name
 if(!$v.ObservationCompleted-or$v.Enabled-or$v.RegisteredState-ne1-or$v.RegisteredInstances.NativeCount-ne0-or$v.ServiceRunningIncludingHidden.MatchingItems.Count-ne0){throw 'native_stopped_task_unconfirmed'}
 return $v
}
function GetRelatedRuntimeProcesses{
 $entryAbsolute=[IO.Path]::GetFullPath((Join-Path $mcpDeclaration.working_directory $mcpDeclaration.entrypoint)).Replace('/','\')
 Initialize-ReviewedIdentity $Lease
 $self=[ICoreIdentityNative]::Process($PID)
 $current=[Diagnostics.Process]::GetCurrentProcess()
 try{if($self.pid-ne$current.Id-or$self.startedTicks-cne([string]$current.StartTime.ToUniversalTime().Ticks)){throw 'activation_self_identity'}}finally{$current.Dispose()}
 $entry=(Get-ActivationLockedPath -Lease $Lease -RoleId 'activation_entrypoint')
 $image=(Get-ActivationLockedPath -Lease $Lease -RoleId 'powershell')
 $argsActual=[Environment]::GetCommandLineArgs();$commandActual=[Environment]::CommandLine
 $matches=@(Get-CimInstance Win32_Process|Where-Object{
  $_.Name-in@('powershell.exe','node.exe')-and$_.CommandLine-and
  ($_.CommandLine.Replace('/','\').Contains($cfg.releaseDirectory.Replace('/','\'))-or$_.CommandLine.Replace('/','\').Contains($entryAbsolute))
 })
 $remaining=@()
 foreach($candidate in $matches){
  $exclude=$false
  if($candidate.ProcessId-eq$self.pid){
   $observed=[ICoreIdentityNative]::Process([int]$candidate.ProcessId)
   $exclude=Test-ActivationExactSelfProcess $candidate $self $observed $argsActual $entry $commandActual $image $owner
  }
  if(!$exclude){$remaining+=,$candidate}
 }
 return @($remaining|Select-Object ProcessId,ParentProcessId,Name,ExecutablePath,CreationDate)
}
function CloseRetryActualSession{
 $answer=[ordered]@{attempted=$false;closed=$false}
 $fresh=@(Get-ChildItem -LiteralPath $login.control_root -Directory -Filter 'session-*'|Where-Object{$_.Name-notin$result.beforeSessionDirectories})
 if($fresh.Count-eq0){$answer.code='no_new_session_observed';return $answer}
 if($fresh.Count-ne1){$answer.code='ambiguous_new_session';return $answer}
 $session=$fresh[0].FullName
 $controls=@(Get-ChildItem -LiteralPath $session -Directory -Filter 'control-*'|Where-Object{Test-Path -LiteralPath (Join-Path $_.FullName 'ready.json')})
 if($controls.Count-ne1){$answer.code='actual_ready_missing_or_ambiguous';return $answer}
 $control=$controls[0].FullName
 $windowPath=Join-Path $session 'session-window.json'
 $w=Get-Content -LiteralPath $windowPath -Raw -Encoding UTF8|ConvertFrom-Json
 $hostProcess=Get-Process -Id $w.pid -ErrorAction Stop
 $os=Get-CimInstance Win32_Process -Filter ("ProcessId="+[int]$w.pid)
 $sid=(Invoke-CimMethod -InputObject $os -MethodName GetOwnerSid).Sid
 $ps=Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
 if($hostProcess.Path-ine$ps-or$sid-cne$owner-or$hostProcess.SessionId-ne$w.session_id-or!(TestHostStartUtcLowerBound $hostProcess.StartTime $result.enableAttemptStartedAt)){throw 'retry_failure_host_binding'}
 $out=Join-Path $attempt 'failure-close-receipt.json'
 $cp=Join-Path $attempt 'failure-close-approved.json'
 $c=[ordered]@{format='schema6-session-close-approved-v1';approved=$true;releaseDirectory=$cfg.releaseDirectory;manifestSha256=$cfg.manifestSha256;maintenanceScriptSha256=$Lease.Hash('normal_close');processImageBindingSha256=$Lease.Hash('process_image_binding');loginConfigurationPath=$loginPath;loginConfigurationSha256=$Lease.Hash('login_config');sessionDirectory=$session;controlDirectory=$control;windowSha256=(HashFile $windowPath);launchSha256=(HashFile (Join-Path $control 'launch.json'));readySha256=(HashFile (Join-Path $control 'ready.json'));host=[ordered]@{pid=[int]$w.pid;startedTicks=[long]$hostProcess.StartTime.ToUniversalTime().Ticks;imagePath=$hostProcess.Path;imageSha256=(HashFile $hostProcess.Path);ownerSid=$sid;sessionId=$hostProcess.SessionId;hwnd=[long]$w.hwnd;threadId=[uint32]$w.thread_id};outputPath=$out}
 WriteJson $cp $c
 $helper=(Get-ActivationLockedPath -Lease $Lease -RoleId 'normal_close')
 if((HashFile $helper)-cne$c.maintenanceScriptSha256){throw 'retry_close_source_changed'}

 $run=Invoke-ActivationChild -Image $ps -Arguments ('-NoProfile -NonInteractive -ExecutionPolicy Bypass -File "'+$helper+'" -ConfigurationPath "'+$cp+'" -ConfigurationSha256 '+(HashFile $cp)) -InputText '' -BudgetMs 60000 -EvidenceLease $Lease
 $answer.attempted=$true;$answer.exitCode=$run.exitCode;$answer.elapsedMs=$run.elapsedMs;$answer.configuration=Ref $cp
 $answer.childRetained=$run.retained
 if(Test-Path -LiteralPath $out){$answer.receipt=Ref $out}
 $answer.closed=$run.exitCode-eq0-and(Test-Path -LiteralPath $out)
 return $answer
}

  function ReadFailureTask([ValidateSet('before','after')][string]$Stage){
   $values=@{};$hashes=@{};$field='get-task'
   try{
    $actual=$folder.GetTask($cfg.taskName)
    foreach($key in @('raw','definition','taskSddl','parentSddl','cmdlet')){
     $field=$key
     $value=switch($key){raw{[string]$actual.Xml}definition{[string]$actual.Definition.XmlText}taskSddl{[string]$actual.GetSecurityDescriptor(7)}parentSddl{[string]$folder.GetSecurityDescriptor(7)}cmdlet{[string](Export-ScheduledTask -TaskName $cfg.taskName -TaskPath '\' -ErrorAction Stop)}}
     $values[$key]=$value;$path=Join-Path $attempt ('failure-'+$Stage+'-'+$key+'.txt')
     Write-OwnedArtifactBytes $path ($utf8.GetBytes($value)) $owner;$hashes[$key]=HashFile $path
    }
    return @{Task=$actual;Values=$values;Hashes=$hashes;Enabled=[bool]$actual.Enabled}
   }catch{
    WriteJson (Join-Path $attempt ('failure-'+$Stage+'-readback-failure.json')) ([ordered]@{format='i-core-task-actual-readback-failure-v1';stage=$field;acquired=@($hashes.Keys|Sort-Object);expectedChanged=$false;passed=$false})
    throw
   }
  }
  function AssertFailureTaskState($Readback){
   $v=$Readback.Values
   foreach($key in @('taskSddl','parentSddl')){if([Convert]::ToBase64String($utf8.GetBytes($v[$key]))-cne[Convert]::ToBase64String($taskTargets.Bytes[$key])){throw 'failure_task_anchor_drift'}}
   if($v.cmdlet-cne$v.raw){throw 'failure_task_export_drift'}
   $allowed=@(
    @{name='enabled';enabled=$true;raw=$taskTargets.Bytes.enabledRaw;definition=$taskTargets.Bytes.enabledDefinition},
    @{name='disabled';enabled=$false;raw=$taskTargets.Bytes.disabledRaw;definition=$taskTargets.Bytes.disabledDefinition},
    @{name='baseline';enabled=$false;raw=$utf8.GetBytes($raw);definition=$utf8.GetBytes($definition)}
   )
   foreach($a in $allowed){
    if($Readback.Enabled-eq$a.enabled-and[Convert]::ToBase64String($utf8.GetBytes($v.raw))-ceq[Convert]::ToBase64String($a.raw)-and[Convert]::ToBase64String($utf8.GetBytes($v.definition))-ceq[Convert]::ToBase64String($a.definition)){return $a.name}
   }
   throw 'failure_task_anchor_drift'
  }
  function InvokeFailureContainment{
   if($result.Contains('failureContainmentAttempted')){return}
   $result.failureContainmentAttempted=$true
   if($result.taskUpdateAttempted-and$null-ne$folder){
    $result.failureSchedulingDisabled=$false;$result.failureDisabledReadbackVerified=$false;$result.failureTaskMutationAttempted=$false
    try{
     $before=ReadFailureTask 'before';$beforeState=AssertFailureTaskState $before
     if($beforeState-ceq'enabled'){
      $result.failureTaskMutationAttempted=$true;$before.Task.Enabled=$false
      $result.failureSchedulingDisabled=(!$before.Task.Enabled)
      $null=ReadbackFour 'failure-disabled' $false;$result.failureDisabledReadbackVerified=$true
     }else{
      $after=ReadFailureTask 'after';$afterState=AssertFailureTaskState $after
      if($afterState-cne$beforeState-or$after.Enabled){throw 'failure_task_changed_while_reading'}
      $result.failureSchedulingDisabled=$true;$result.failureDisabledReadbackVerified=$true
     }
    }catch{$result.failureContainmentCode='failure_task_unconfirmed'}
   }
   if($result.enableAttempted){try{$result.safeClosure=CloseRetryActualSession}catch{$result.safeClosure=@{attempted=$false;closed=$false;code='exact_close_unconfirmed'}}}
  }
  function UpdateActivationResidual{
   try{$result.childState=Complete-ActivationChildren}catch{$result.childState=@{retained=1;code='activation_child_cleanup_unconfirmed'}}
   try{$result.p4ResidualState=Complete-P4ResidualSession;if($result.p4ResidualState.residual-isnot[bool]){throw 'activation_residual_schema'}}catch{$result.p4ResidualState=@{residual=$true;childResidual=$true;samplerResidual=$true;locksRetained=$true}}
   $result.retained=($result.childState.retained-gt0-or$result.p4ResidualState.residual)
   if($result.retained){$result.passed=$false;$result.code='activation_residual'}
  }
  function TestActivationApprovalCurrent{
   $now=[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
   return ($now-ge$record.Policy.notBeforeUtcMs-and$now-le$record.Policy.notAfterUtcMs)
  }
  function CompleteActivationResult{
   UpdateActivationResidual
   if($result.passed-and!(TestActivationApprovalCurrent)){$result.passed=$false;$result.code='activation_approval_expired'}
   if(!$result.passed){InvokeFailureContainment;UpdateActivationResidual}
   $late=$false
   try{WriteJson (Join-Path $attempt 'activation-result.json') $result}catch{$result.passed=$false;$result.code='activation_result_write_failed';$late=$true}
   if($result.passed-and!(TestActivationApprovalCurrent)){$result.passed=$false;$result.code='activation_approval_expired';$late=$true}
   if($late){
    InvokeFailureContainment;UpdateActivationResidual
    WriteJson (Join-Path $attempt 'activation-final-rejection.json') $result
   }
  }

 try{
  $taskTargets=Get-ActivationProofTaskTargets -Lease $Lease
  $policy=$taskTargets.Policy
  foreach($name in @('action','disabledRaw','enabledRaw','disabledDefinition','enabledDefinition')){
   Write-OwnedArtifactBytes (Join-Path $attempt ('expected-task-'+$name+'.txt')) $taskTargets.Bytes[$name] $owner
  }
  WriteJson (Join-Path $attempt 'task-derivation.json') $taskTargets.Receipt
  function ReadbackFour([ValidateSet('updated','enabled','failure-disabled')][string]$Prefix,[bool]$Enabled){
   $values=@{};$hashes=@{};$stage='get-task';$cmdletSaved=$false
   try{
    $actual=$folder.GetTask($cfg.taskName)
    foreach($key in @('raw','definition','taskSddl','parentSddl')){
     $stage=$key
     $value=switch($key){raw{[string]$actual.Xml}definition{[string]$actual.Definition.XmlText}taskSddl{[string]$actual.GetSecurityDescriptor(7)}parentSddl{[string]$folder.GetSecurityDescriptor(7)}}
     $values[$key]=$value;$path=Join-Path $attempt ($Prefix+'-'+$key+'.txt');Write-OwnedArtifactBytes $path ($utf8.GetBytes($value)) $owner;$hashes[$key]=HashFile $path
    }
    $stage='cmdlet';$cmdletXml=[string](Export-ScheduledTask -TaskName $cfg.taskName -TaskPath '\')
    Write-OwnedArtifactBytes (Join-Path $attempt ($Prefix+'-cmdlet.txt')) ($utf8.GetBytes($cmdletXml)) $owner;$cmdletSaved=$true
    $stage='exact-byte-compare'
    $state=if($Enabled){'enabled'}else{'disabled'}
    $want=@{raw=$taskTargets.Bytes[$state+'Raw'];definition=$taskTargets.Bytes[$state+'Definition'];taskSddl=$taskTargets.Bytes.taskSddl;parentSddl=$taskTargets.Bytes.parentSddl}
    foreach($key in @('raw','definition','taskSddl','parentSddl')){
     if([Convert]::ToBase64String($utf8.GetBytes($values[$key]))-cne[Convert]::ToBase64String($want[$key])){throw 'actual_task_full_bytes_mismatch'}
    }
    if([Convert]::ToBase64String($utf8.GetBytes($cmdletXml))-cne[Convert]::ToBase64String($want.raw)){throw 'actual_export_disagrees'}
    $stage='full-semantic-check'
    $phaseExpected=$service.NewTask(0);$phaseExpected.XmlText=$utf8.GetString($want.definition)
    Assert-TaskDefinition $actual.Definition $phaseExpected
    $normalized=$service.NewTask(0);$normalized.XmlText=[string]$actual.Definition.XmlText
    if([string]$normalized.XmlText-cne[string]$phaseExpected.XmlText-or$actual.Enabled-ne$Enabled-or$actual.Definition.Settings.Hidden-or[string]$actual.GetSecurityDescriptor(7)-cne$taskSd-or[string]$folder.GetSecurityDescriptor(7)-cne$parentSd){throw 'updated_full_definition_or_sd'}
    if($Enabled-and($hashes.raw-cne$policy.expectedEnabledRawXmlSha256-or$hashes.definition-cne$policy.expectedEnabledDefinitionSha256-or$hashes.taskSddl-cne$policy.taskSddlSha256-or$hashes.parentSddl-cne$policy.parentSddlSha256)){throw 'enabled_exact_four_hashes'}
    return $hashes
   }catch{
    WriteJson (Join-Path $attempt ($Prefix+'-readback-failure.json')) ([ordered]@{format='i-core-task-actual-readback-failure-v1';stage=$stage;acquired=@($hashes.Keys|Sort-Object);cmdletSaved=$cmdletSaved;expectedChanged=$false;passed=$false})
    throw
   }
  }
  $service=New-Object -ComObject Schedule.Service;$service.Connect();$folder=$service.GetFolder('\');$task=$folder.GetTask($cfg.taskName)
  $raw=TextRole 'new_task_raw';$definition=TextRole 'new_task_definition';$taskSd=TextRole 'new_task_sddl';$parentSd=TextRole 'parent_sddl';$oldRaw=TextRole 'old_task_raw'
  function AssertOld {
   $old=$folder.GetTask($policy.oldTaskPath.TrimStart('\'))
   if($old.Enabled-or$old.GetInstances(0).Count-ne0-or[string]$old.Xml-cne$oldRaw-or(Get-TaskSecuritySha256 ($old.GetSecurityDescriptor(7)))-cne$policy.oldTaskSddlSha256){throw 'old_task_changed'}
   $null=AssertObservedStopped $policy.oldTaskPath.TrimStart('\')
  }
  function AssertDisabled {
   $fresh=$folder.GetTask($cfg.taskName)
   if($fresh.Enabled-or$fresh.GetInstances(0).Count-ne0-or[string]$fresh.Xml-cne$raw-or[string]$fresh.Definition.XmlText-cne$definition-or[string]$fresh.GetSecurityDescriptor(7)-cne$taskSd-or[string]$folder.GetSecurityDescriptor(7)-cne$parentSd){throw 'disabled_four_anchors_changed'}
   $null=AssertObservedStopped $cfg.taskName;AssertOld
  }
  AssertDisabled
  $currentExpected=$service.NewTask(0);$currentExpected.XmlText=$definition
  Assert-RegisteredTask $task $currentExpected $cfg.taskName $cfg.expectedRegisteredSddl
  $null=Assert-TaskSecurityPolicy $cfg $parentSd
  $expected=$service.NewTask(0);$expected.XmlText=$utf8.GetString($taskTargets.Bytes.disabledDefinition)
  if($expected.Settings.Enabled-or$expected.Settings.Hidden-or$expected.Principal.RunLevel-ne0-or(Convert-TaskSid ([string]$expected.Principal.UserId))-cne$owner-or$expected.Principal.LogonType-ne3-or$expected.Actions.Count-ne1){throw 'new_definition_principal'}
  $action=$expected.Actions.Item(1)
  if($action.Path-cne(Get-ActivationLockedPath -Lease $Lease -RoleId 'powershell')-or$action.Arguments-cne$policy.expectedActionArguments-or$action.WorkingDirectory-cne$cfg.releaseDirectory-or!$action.Arguments.Contains((Get-ActivationLockedPath -Lease $Lease -RoleId 'login_config'))){throw 'new_definition_action'}
  $caller=Get-TaskCallerContext
  if($caller.UserSid-cne$owner-or$caller.Elevated-or$caller.AdministratorRoleEnabled){throw 'unelevated_owner_required'}
  $volume=Get-Volume -DriveLetter T;$disk=Get-Partition -DriveLetter T|Get-Disk
  if($volume.FileSystem-cne'NTFS'-or$volume.UniqueId-cne'\\?\Volume{901faf2a-0000-0000-0000-100000000000}\'-or$disk.SerialNumber.Trim()-cne'F211007Y0LNUK7S'-or$disk.UniqueId-cne'5000000000000001'-or$disk.Size-ne1000204886016){throw 't9_identity_changed'}
  if(@(Get-NetTCPConnection -State Listen -ErrorAction Stop|Where-Object{$_.LocalPort-in@(47841,47860,47862)}).Count){throw 'runtime_port_occupied'}
  if(@(GetRelatedRuntimeProcesses).Count){throw 'existing_runtime_process'}
  if($Lease.Hash('node')-cne'58e74bf02fc5bbacc41dcb8bef089961cd5bddd37830b87784e4fc624d145d1f'-or(HashFile $mcpDeclaration.executable_path)-cne$mcpDeclaration.executable_sha256-or$mcpDeclaration.source_files.Count-ne$policy.mcpSourceCount){throw 'runtime_executable_inventory'}
  Assert-OwnedArtifact $mcpDeclaration.working_directory $owner $true
  $listed=@()
  foreach($entry in $mcpDeclaration.source_files){$target=Join-Path $mcpDeclaration.working_directory $entry.path;Assert-OwnedArtifact $target $owner $false;if((HashFile $target)-cne$entry.sha256){throw 'mcp_source_changed'};$listed+=$entry.path}
  $actualNames=@(Get-ChildItem -LiteralPath $mcpDeclaration.working_directory -Recurse -File -Force|ForEach-Object{$_.FullName.Substring($mcpDeclaration.working_directory.Length+1).Replace('\','/')})
  if(@(Compare-Object ($listed|Sort-Object) ($actualNames|Sort-Object)).Count){throw 'mcp_inventory_changed'}
  $inventory=JsonRole 'source_inventory'
  if($inventory.format-cne'i-core-activation-source-inventory-v1'-or$inventory.releaseDirectory-cne$cfg.releaseDirectory){throw 'release_inventory_schema'}
  foreach($entry in $inventory.files){$target=[IO.Path]::GetFullPath((Join-Path $cfg.releaseDirectory $entry.path));if(!$target.StartsWith($cfg.releaseDirectory.TrimEnd('\')+'\',[StringComparison]::OrdinalIgnoreCase)){throw 'release_source_scope'};Assert-OwnedArtifact $target $owner $false;if((HashFile $target)-cne$entry.sha256){throw 'release_source_changed'}}
  $actualRelease=@(Get-ChildItem -LiteralPath $cfg.releaseDirectory -Recurse -File -Force|ForEach-Object{$_.FullName.Substring($cfg.releaseDirectory.Length+1).Replace('\','/')})
  if(@(Compare-Object (@($inventory.files.path)|Sort-Object) ($actualRelease|Sort-Object)).Count){throw 'release_inventory_changed'}
  $locks=[Collections.Generic.List[IDisposable]]::new();$switchState=@{oldReleased=$false;postLocks=[Collections.Generic.List[IDisposable]]::new()}
  try{
   foreach($path in @((Join-Path ([IO.Path]::GetDirectoryName($core.database_path)) 'shortcut-mail-relay.runtime.lock'),(Join-Path $core.recovery_custody_directory 'custody.lock'))){
    [OwnedArtifactNative]::Assert($path,$owner,$false);$h=[IO.File]::Open($path,[IO.FileMode]::Open,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
    $null=[OwnedArtifactNative]::Check($h.SafeFileHandle,$path,$false);$locks.Add($h)
   }
   function PinRef([string]$id){@{path=(Get-ActivationLockedPath -Lease $Lease -RoleId $id);sha256=$Lease.Hash($id)}}
   $spec=[ordered]@{format='continuous-activation-preflight-input-v1';evidenceMode='reviewed-live';operation='closed';sourceRoot=$policy.baselineSourceRoot;sourceFiles=@($policy.baselineSourceFiles);baselineRegistration=(PinRef 'baseline_registration');baselineLogin=(PinRef 'baseline_login');baselineDaily=(PinRef 'baseline_daily');baselineP0=(PinRef 'baseline_p0');launchMcp=(PinRef 'mcp_config');attemptDirectory=$attempt;capture=(Join-Path $attempt 'pending-private-capture')}
   $pre=Invoke-ActivationChild $node ('"'+(Get-ActivationLockedPath -Lease $Lease -RoleId 'activation_preflight')+'"') ($spec|ConvertTo-Json -Depth 20 -Compress) -EvidenceLease $Lease
   if($pre.retained-or$pre.exitCode-ne0){throw 'closed_preflight_failed'}
   $closed=Read-P4StrictJson ($utf8.GetBytes($pre.stdout))
   if(!$closed.passed-or!$closed.custodyHmacVerified-or$closed.generation-ne12-or$closed.headSha256-cne'bc6d6941bc9d93e4c56d1dd11a7f9d11d66a09f9c83a4afc1f426d4bd24d1ce8'-or!$closed.sourceGen10DatabaseUnchanged-or!$closed.sourceGen10StateUnchanged-or!$closed.sidecarsAbsent-or!$closed.coreStateUnchangedDuringCheck){throw 'closed_preflight_rejected'}
   WriteJson (Join-Path $attempt 'prestart-closed.json') $closed
   foreach($item in @(@((Join-Path $login.state_directory 's6-lifecycle.json'),'pre-switch-marker.json',$switchContract.Policy.expectedMarkerSha256),@((Join-Path $core.recovery_custody_directory 'current-head.json'),'pre-switch-head.json',$switchContract.Policy.expectedHeadSha256))){
    $b=[IO.File]::ReadAllBytes($item[0]);if((Get-P4ByteHash $b)-cne$item[2]){throw 'switch_before_anchor_changed'};Write-OwnedArtifactBytes (Join-Path $attempt $item[1]) $b $owner
   }
   $db=[IO.File]::Open($core.database_path,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::None)
   try{$null=[OwnedArtifactNative]::Check($db.SafeFileHandle,$core.database_path,$false);$sha=[Security.Cryptography.SHA256]::Create();try{$digest=([BitConverter]::ToString($sha.ComputeHash($db))).Replace('-','').ToLowerInvariant();if($digest-cne'848fb6b71ce767fc548ededc8d63e0b06ae055bffbfd7f037f196ab98f660491'){throw 'exclusive_database_changed'}}finally{$sha.Dispose()}}finally{$db.Dispose()}
   New-OwnedArtifactDirectory $spec.capture $owner;$spec.operation='pending'
   $pre=Invoke-ActivationChild $node ('"'+(Get-ActivationLockedPath -Lease $Lease -RoleId 'activation_preflight')+'"') ($spec|ConvertTo-Json -Depth 20 -Compress) -EvidenceLease $Lease
   if($pre.retained-or$pre.exitCode-ne0){throw 'pending_preflight_failed'}
   $pending=Read-P4StrictJson ($utf8.GetBytes($pre.stdout))
   if(!$pending.passed-or$pending.globalPending-ne0-or!$pending.privateCaptureCleaned-or!$pending.mainAndWalUnchangedSinceP0-or!$pending.originalFamilyUnchangedDuringCapture){throw 'pending_preflight_rejected'}
   WriteJson (Join-Path $attempt 'global-pending.json') $pending
  }finally{
   $null=Complete-ActivationChildren
   if($script:ActivationRetainedChildren.Count){$script:ActivationRetainedChildren[0].OwnedLocks=$locks.ToArray()}
   else{foreach($h in $locks){$h.Dispose()};$switchState.oldReleased=$true}
  }
  # PACKAGE_SWITCH_BEGIN: old locks are relinquished before the original supervised entry.
  function AssertSwitchWindow{$now=[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds();if($now-lt$approval.notBeforeUtcMs-or$now-ge$approval.notAfterUtcMs){throw 'switch_approval_expired'}}
  $switchControl=Join-Path $attempt 'package-switch-control'
  Invoke-ActivationSwitchTransition -ReleaseOld {
   if(!$switchState.oldReleased-or$script:ActivationRetainedChildren.Count){throw 'switch_lock_handoff_unconfirmed'}
  } -Launch {
   AssertSwitchWindow;AssertDisabled;AssertOld
   New-OwnedArtifactDirectory $switchControl $owner
   $result.packageSwitchAttempted=$true
   $args='-NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "'+(Get-ActivationLockedPath $Lease 'start_schema6')+'" -Start -OfflineOperation package-switch -ManifestSha256 '+$switchContract.Plan.to.manifestSha256+' -ConfigurationFile "'+$switchContract.Plan.to.configurationPath+'" -StateDirectory "'+$login.state_directory+'" -ControlDirectory "'+$switchControl+'" -PackageSwitchPlan "'+(Get-ActivationLockedPath $Lease 'package_switch_plan')+'" -PackageSwitchSha256 '+$Lease.Hash('package_switch_plan')
   $child=Invoke-ActivationChild (Get-ActivationLockedPath $Lease 'powershell') $args '' -BudgetMs 120000 -EvidenceLease $Lease
   WriteJson (Join-Path $attempt 'package-switch-child.json') ([ordered]@{format='i-core-activation-switch-child-v1';exitCode=$child.exitCode;retained=$child.retained;elapsedMs=$child.elapsedMs;stdoutSha256=if($null-ne$child.stdout){Get-P4ByteHash ($utf8.GetBytes($child.stdout))}else{$null};switchPlanSha256=$Lease.Hash('package_switch_plan')})
   return $child
  } -AcquireNew {
   AssertSwitchWindow
   foreach($path in @((Join-Path ([IO.Path]::GetDirectoryName($core.database_path)) 'shortcut-mail-relay.runtime.lock'),(Join-Path $core.recovery_custody_directory 'custody.lock'))){
    [OwnedArtifactNative]::Assert($path,$owner,$false);$h=[IO.File]::Open($path,[IO.FileMode]::Open,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
    $null=[OwnedArtifactNative]::Check($h.SafeFileHandle,$path,$false);$switchState.postLocks.Add($h)
   }
  } -VerifyNew {
   $spec.operation='post-switch';$spec.switchPlan=PinRef 'package_switch_plan';$spec.switchPolicy=PinRef 'package_switch_policy';$spec.targetCore=PinRef 'core_config';$spec.switchControl=$switchControl
   $spec.beforeMarker=@{path=(Join-Path $attempt 'pre-switch-marker.json');sha256=$switchContract.Policy.expectedMarkerSha256}
   $spec.beforeHead=@{path=(Join-Path $attempt 'pre-switch-head.json');sha256=$switchContract.Policy.expectedHeadSha256}
   $post=Invoke-ActivationChild $node ('"'+(Get-ActivationLockedPath $Lease 'activation_preflight')+'"') ($spec|ConvertTo-Json -Depth 20 -Compress) -EvidenceLease $Lease
   if($post.retained-or$post.exitCode-ne0){throw 'post_switch_preflight_failed'}
   $proof=Read-P4StrictJson ($utf8.GetBytes($post.stdout))
   if($proof.format-cne'schema6-post-switch-closed-proof-v1'-or$proof.passed-ne$true-or$proof.custodyHmacVerified-ne$true-or$proof.planSha256-cne$Lease.Hash('package_switch_plan')-or$proof.operationId-cne$switchContract.Plan.operationId-or$proof.generation-ne($switchContract.Policy.expectedGeneration+1)-or$proof.previousHeadSha256-cne$switchContract.Policy.expectedHeadSha256-or$proof.pendingAbsent-ne$true-or$proof.sidecarsAbsent-ne$true-or$proof.coreStateUnchangedDuringCheck-ne$true){throw 'post_switch_preflight_rejected'}
   WriteJson (Join-Path $attempt 'post-switch-closed.json') $proof
   $spec.operation='pending';New-OwnedArtifactDirectory $spec.capture $owner
   $post=Invoke-ActivationChild $node ('"'+(Get-ActivationLockedPath $Lease 'activation_preflight')+'"') ($spec|ConvertTo-Json -Depth 20 -Compress) -EvidenceLease $Lease
   if($post.retained-or$post.exitCode-ne0){throw 'post_switch_pending_failed'}
   $pending=Read-P4StrictJson ($utf8.GetBytes($post.stdout))
   if(!$pending.passed-or$pending.globalPending-ne0-or!$pending.privateCaptureCleaned-or!$pending.mainAndWalUnchangedSinceP0-or!$pending.originalFamilyUnchangedDuringCapture){throw 'post_switch_pending_rejected'}
   WriteJson (Join-Path $attempt 'post-switch-pending.json') $pending
   AssertSwitchWindow;AssertDisabled;AssertOld
   if(@(GetRelatedRuntimeProcesses).Count){throw 'post_switch_runtime_present'}
   $result.packageSwitchConfirmed=$true;$result.packageSwitchHeadSha256=$proof.headSha256;$result.packageSwitchEventSha256=$proof.eventSha256
  } -Update {
   AssertSwitchWindow
   $result.beforeSessionDirectories=@(Get-ChildItem -LiteralPath $login.control_root -Directory -Filter 'session-*'|Select-Object -ExpandProperty Name)
   $result.taskUpdateAttempted=$true
   $null=$folder.RegisterTaskDefinition($cfg.taskName,$expected,4,$owner,$null,3,$taskSd)
   $null=ReadbackFour 'updated' $false;AssertOld
  } -ReleaseNew {
   $null=Complete-ActivationChildren
   if($script:ActivationRetainedChildren.Count){$script:ActivationRetainedChildren[0].OwnedLocks=$switchState.postLocks.ToArray()}
   else{foreach($h in $switchState.postLocks){$h.Dispose()}}
  }
  # PACKAGE_SWITCH_END: a confirmed new closed package is never automatically reversed.
  $task=$folder.GetTask($cfg.taskName);if($task.GetInstances(0).Count-ne0){throw 'task_started_while_disabled'}
  foreach($pin in $policy.artifacts){if((HashFile (Get-ActivationLockedPath -Lease $Lease -RoleId $pin.id))-cne$pin.sha256){throw 'source_changed_before_enable'}}
  $expected.Settings.Enabled=$true
  $ticks=[DateTime]::UtcNow.Ticks.ToString([Globalization.CultureInfo]::InvariantCulture)
  $result.enableAttemptStartedAt=[DateTime]::UtcNow.ToString('o');$result.enableAttempted=$true
  $task.Enabled=$true
  $actualHashes=ReadbackFour 'enabled' $true
  WriteJson (Join-Path $attempt '02-enabled-state.json') ([ordered]@{format='i-core-enabled-task-state-v1';evidenceMode='reviewed-live';attemptId=$record.Policy.attemptId;approvalSha256=$Lease.ApprovalSha256;planSha256=$record.Policy.planSha256;taskPath=$policy.taskPath;enableStartedTicks=$ticks;actualRawXmlSha256=$actualHashes.raw;actualDefinitionSha256=$actualHashes.definition;taskSddlSha256=$actualHashes.taskSddl;parentSddlSha256=$actualHashes.parentSddl;enabled=$true;actualExport=$true})
  $running=Get-TaskInstanceProjection $cfg.taskName;$actual=$folder.GetTask($cfg.taskName)
  if(!$running.ObservationCompleted-or!$running.Enabled){throw 'pre_run_observation_failed'}
  $instance=$null;$attached=$null;$source=$null;$calls=0
  if($running.RegisteredInstances.NativeCount-eq0-and$running.ServiceRunningIncludingHidden.MatchingItems.Count-eq0-and$running.RegisteredState-eq3){
   $sessions=@(Get-ChildItem -LiteralPath $login.control_root -Directory -Filter 'session-*'|Where-Object{$_.Name-cnotin$result.beforeSessionDirectories})
   $fresh=Get-TaskInstanceProjection $cfg.taskName
   if(@(GetRelatedRuntimeProcesses).Count-or$sessions.Count-or!$fresh.ObservationCompleted-or!$fresh.Enabled-or$fresh.RegisteredState-ne3-or$fresh.RegisteredInstances.NativeCount-ne0-or$fresh.ServiceRunningIncludingHidden.MatchingItems.Count-ne0){throw 'pre_run_zero_runtime'}
   $source='original-run';$calls=1
  }elseif($running.RegisteredInstances.NativeCount-eq1-and$running.RegisteredInstances.ExplicitItemsRead-eq1-and$running.RegisteredInstances.MatchingItems.Count-eq1-and$running.ServiceRunningIncludingHidden.MatchingItems.Count-eq1-and$running.RegisteredState-eq4-and$running.RegisteredInstances.MatchingItems[0].InstanceGuid-ieq$running.ServiceRunningIncludingHidden.MatchingItems[0].InstanceGuid){
   $items=$actual.GetInstances(0);if($items.Count-ne1){throw 'attached_instance_count'};$attached=$items.Item(1);$source='registered-item-attach'
  }else{throw 'pre_run_ambiguous'}
  $claim=[ordered]@{format='i-core-activation-claim-v1';evidenceMode='reviewed-live';attemptId=$record.Policy.attemptId;approvalSha256=$Lease.ApprovalSha256;planSha256=$record.Policy.planSha256;taskPath=$policy.taskPath;historicalProductionRuns=2;newRunBudget=1;source=$source;runCalls=$calls;consumed=$true;createdAtUtc=[DateTime]::UtcNow.ToString('o');mayHaveInvokedRun=($calls-eq1)}
  $claimPath=Join-Path $attempt '00-run-consumption.json';WriteJson $claimPath $claim
  $claimLock=[P4EvidenceLease]::new($claimPath,$owner,$false,$true,262144);$record.All.Add($claimLock)
  $readClaim=Read-P4StrictJson $claimLock.Bytes()
  if((ConvertTo-P4CanonicalJson $claim)-cne(ConvertTo-P4CanonicalJson $readClaim)){throw 'claim_readback'}
  $claimHash=$claimLock.Hash();$result.runCalls=$calls
  if($calls-eq1){$instance=$actual.Run($null)}
  $returned=if($calls-eq1){[HereIAmTaskInstanceProjection]::ProjectReturnedInstance($instance)}else{[HereIAmTaskInstanceProjection]::ProjectReturnedInstance($attached)}
  if($returned.Path-cne$policy.taskPath-or$returned.State-ne4){throw 'returned_refresh_state'}
  WriteJson (Join-Path $attempt '01-run-returned.json') ([ordered]@{format='i-core-run-returned-v1';evidenceMode='reviewed-live';attemptId=$record.Policy.attemptId;approvalSha256=$Lease.ApprovalSha256;activationClaimSha256=$claimHash;source=$source;runCalls=$calls;taskPath=$policy.taskPath;instanceGuid=[Guid]::Parse($returned.InstanceGuid).ToString('D');state=4;observedAtUtc=[DateTime]::UtcNow.ToString('o')})
  $limit=[Diagnostics.Stopwatch]::StartNew()
  do{
   try{$null=$Lease.DiscoverSession();break}catch{if($limit.ElapsedMilliseconds-ge30000){throw 'session_attachment_timeout'};[Threading.Thread]::Sleep(100)}
  }while($true)
  $activation=Set-ReviewedIdentityActivation -Lease $Lease -Phase initial-activation -OriginalRunInstance $instance -AttachedInstance $attached
  WriteJson (Join-Path $attempt '03-initial-session-binding.json') ([ordered]@{format='i-core-initial-session-binding-v1';evidenceMode='reviewed-live';attemptId=$record.Policy.attemptId;bindingSha256=$Lease.BindingSha256;approvalSha256=$Lease.ApprovalSha256;planSha256=$record.Policy.planSha256;instanceGuid=$activation.instanceGuid;sessionId=[IO.Path]::GetFileName($record.Attachment.SessionPath);sessionControlId=[IO.Path]::GetFileName($record.Attachment.ControlPath);sessionWindowSha256=$Lease.Hash('session_window');launchSha256=$Lease.Hash('launch');readySha256=$Lease.Hash('ready');mcpStartSha256=$Lease.Hash('mcp_start');activationClaimSha256=$activation.activationClaimSha256;runReturnedSha256=$activation.runReturnedSha256;activationStateSha256=$activation.activationStateSha256})
  $p3=Invoke-ReviewedP3Permit -Lease $Lease -OriginalRunInstance $instance -AttachedInstance $attached
  if(!$p3.passed){throw 'actual_p3_failed'};$result.productionP3=$true
  $null=Promote-P4ReviewedLease -Lease $Lease
  . ([scriptblock]::Create($utf8.GetString($Lease.Bytes('total_gate'))))
  $p4=Invoke-ReviewedP4BackupTotalGate -Lease $Lease
  $received=Confirm-ReviewedP4TotalDisposition -Lease $Lease -Result $p4
  foreach($key in @('format','disposition','receiverSha256','candidateSha256','commitSha256')){if($received.$key-isnot[string]){throw 'actual_p4_total_disposition_type'}}
  $receiverKeys=if($received-is[Collections.IDictionary]){@($received.Keys)}else{@($received.PSObject.Properties.Name)}
  if((($receiverKeys|Sort-Object)-join',')-cne'authoritative,candidateSha256,commitSha256,disposition,format,passed,receiverRejectSha256,receiverSha256,rejectSha256'-or$received.format-cne'p4-total-receiver-result-v1'-or$received.passed-isnot[bool]-or!$received.passed-or$received.disposition-cne'commit'-or$received.authoritative-isnot[bool]-or$received.authoritative-or$received.receiverSha256-cnotmatch'^[a-f0-9]{64}$'-or$null-ne$received.receiverRejectSha256-or$null-ne$received.rejectSha256-or$received.commitSha256-cnotmatch'^[a-f0-9]{64}$'-or$received.candidateSha256-cne$p4.durableReportSha256){throw 'actual_p4_total_disposition_failed'}
  if($p4.passed-ne$true-or$p4.overallP4Passed-ne$true-or$p4.durableReportWritten-ne$true-or$p4.durableReportSha256-cnotmatch'^[a-f0-9]{64}$'){throw 'actual_p4_total_failed'}
  $result.p4TotalReportSha256=$p4.durableReportSha256;$result.p4TotalReceiverSha256=$received.receiverSha256;$result.productionP4=$true
  AssertOld;$result.activationAndP3Passed=$true;$result.passed=$true;$result.code='actual_p3_p4_total_passed'
 }catch{
  $result.code='activation_failed'
  InvokeFailureContainment
 }finally{
  CompleteActivationResult
 }
 return $result
}

function Get-ActivationLockedPath {
 param([Parameter(Mandatory=$true)]$Lease,[Parameter(Mandatory=$true)][string]$RoleId)
 $r=Get-P4LeaseRecord $Lease
 $allowed=@('activation_policy','activation_controller','activation_entrypoint','activation_preflight','total_gate','p4_total_policy','backup_policy','identity_library','identity_native','activation_proof','identity_sampler','p3_library','evidence_native','evidence_launcher','owned_helper','task_primitives','task_security','task_projection','caller_context','login_config','core_config','mcp_config','backup_config','node','powershell','normal_close','process_image_binding','new_task_raw','new_task_definition','new_task_sddl','parent_sddl','old_task_raw','task_template_evaluator','task_template_rules','task_template_action','task_template_disabled_raw','task_template_enabled_raw','task_template_disabled_definition','task_template_enabled_definition','baseline_registration','baseline_login','baseline_daily','baseline_p0','manifest','source_inventory','package_switch_plan','package_switch_policy','start_schema6')
 if($RoleId-cnotin$allowed-or!$r.Map.ContainsKey($RoleId)){throw 'activation_locked_role'}
 $a=@($r.Binding.artifacts|Where-Object{$_.id-ceq$RoleId})
 if($a.Count-ne1-or$a[0].sha256-cne$r.Expected[$RoleId]-or$r.Map[$RoleId].Hash()-cne$a[0].sha256){throw 'activation_locked_hash'}
 [P4EvidenceLease]::Plain($a[0].path);$r.Map[$RoleId].Assert()
 return [string]$a[0].path
}
function Get-ActivationLockedBytes {
 param([Parameter(Mandatory=$true)]$Lease,[Parameter(Mandatory=$true)][string]$RoleId)
 $null=Get-ActivationLockedPath -Lease $Lease -RoleId $RoleId
 $r=Get-P4LeaseRecord $Lease;$bytes=$r.Map[$RoleId].Bytes()
 if((Get-P4ByteHash $bytes)-cne$r.Expected[$RoleId]){throw 'activation_locked_hash'}
 return ,$bytes
}

function Test-ActivationExactSelfProcess {
 param($Candidate,$ExpectedSelf,$ObservedSelf,[string[]]$Arguments,[string]$ExpectedEntry,[string]$ExpectedCommandLine,[string]$ExpectedImage,[string]$ExpectedOwner)
 if($Candidate.ProcessId-ne$ExpectedSelf.pid-or$ObservedSelf.pid-ne$ExpectedSelf.pid-or$ObservedSelf.startedTicks-cne$ExpectedSelf.startedTicks-or$ObservedSelf.imagePath-ine$ExpectedImage-or$ExpectedSelf.imagePath-ine$ExpectedImage-or$Candidate.ExecutablePath-ine$ExpectedImage-or$ObservedSelf.ownerSid-cne$ExpectedOwner-or$ExpectedSelf.ownerSid-cne$ExpectedOwner-or$ObservedSelf.sessionId-ne$ExpectedSelf.sessionId-or$Candidate.CommandLine-cne$ExpectedCommandLine){return $false}
 $fileSlots=@();for($n=0;$n-lt$Arguments.Count;$n++){if($Arguments[$n]-ieq'-File'){$fileSlots+=,$n}}
 if($fileSlots.Count-ne1-or$fileSlots[0]+1-ge$Arguments.Count-or$Arguments[$fileSlots[0]+1]-ine$ExpectedEntry-or@($Arguments|Where-Object{$_-ieq'-Execute'}).Count-ne1){return $false}
 return $true
}


function Assert-ActivationSwitchContract {
 param($Lease,$Policy,$Baseline,$Core)
 $r=Get-P4LeaseRecord $Lease
 $plan=Read-P4StrictJson (Get-ActivationLockedBytes $Lease 'package_switch_plan')
 $p=Read-P4StrictJson (Get-ActivationLockedBytes $Lease 'package_switch_policy')
 function Keys($v,[string[]]$k){if(@(Compare-Object @($v.PSObject.Properties.Name|Sort-Object) @($k|Sort-Object)).Count){throw 'switch_contract_keys'}}
 Keys $plan @('format','approved','operationId','expectedHeadSha256','expectedMarkerSha256','rollbackOf','from','to','artifacts','fromArtifacts')
 Keys $p @('format','evidenceMode','attemptId','planSha256','switchPlanSha256','operationId','startScriptSha256','fromTaskEvidence','toTaskEvidence','expectedGeneration','expectedHeadSha256','expectedMarkerSha256','timeoutMs')
 if($plan.format-cne'schema6-package-switch-approved-v1'-or$plan.approved-isnot[bool]-or!$plan.approved-or$null-ne$plan.rollbackOf-or$plan.operationId-cnotmatch'^[A-Za-z0-9_-]{8,80}$'){throw 'switch_plan_approval_required'}
 if($p.format-cne'i-core-activation-package-switch-policy-v1'-or$p.evidenceMode-cne'reviewed-live'-or$p.attemptId-cne$r.Policy.attemptId-or$p.planSha256-cne$r.Policy.planSha256-or$p.switchPlanSha256-cne$Lease.Hash('package_switch_plan')-or$p.startScriptSha256-cne$Lease.Hash('start_schema6')-or$p.operationId-cne$plan.operationId-or$p.timeoutMs-ne120000-or$p.expectedGeneration-ne12-or$p.fromTaskEvidence-cne'baseline-actual-task-xml'-or$p.toTaskEvidence-cne'exact-two-slot-rules-expected-only'){throw 'switch_policy_binding'}
 if($p.expectedHeadSha256-cne'bc6d6941bc9d93e4c56d1dd11a7f9d11d66a09f9c83a4afc1f426d4bd24d1ce8'-or$p.expectedMarkerSha256-cne'7ea847cae5b9a1f0d44f7b6f757162d407089a28373fa31bcc28cfc05cffa2cb'-or$plan.expectedHeadSha256-cne$p.expectedHeadSha256-or$plan.expectedMarkerSha256-cne$p.expectedMarkerSha256){throw 'switch_old_anchor'}
 foreach($e in @($plan.from,$plan.to)){Keys $e @('releaseDirectory','manifestSha256','configurationPath','configurationSha256');foreach($h in @($e.manifestSha256,$e.configurationSha256)){if($h-isnot[string]-or$h-cnotmatch'^[a-f0-9]{64}$'){throw 'switch_endpoint_hash'}}}
 $old=Read-P4StrictJson (Get-ActivationLockedBytes $Lease 'baseline_registration')
 if($plan.from.releaseDirectory-cne$old.releaseDirectory-or$plan.from.manifestSha256-cne$old.manifestSha256-or$plan.from.configurationPath-cne$Baseline.core_configuration_path-or$plan.from.configurationSha256-cne$Baseline.core_configuration_sha256-or$plan.to.releaseDirectory-cne$Policy.registration.releaseDirectory-or$plan.to.manifestSha256-cne$Lease.Hash('manifest')-or$plan.to.configurationPath-cne(Get-ActivationLockedPath $Lease 'core_config')-or$plan.to.configurationSha256-cne$Lease.Hash('core_config')-or$plan.from.releaseDirectory-ceq$plan.to.releaseDirectory-or$plan.from.manifestSha256-ceq$plan.to.manifestSha256){throw 'switch_endpoint_binding'}
 if((Get-ActivationLockedPath $Lease 'start_schema6')-cne(Join-Path $plan.to.releaseDirectory 'tools\i_core\release_schema6\lifecycle\start_schema6.ps1')){throw 'switch_start_path'}
 foreach($setName in @('artifacts','fromArtifacts')){
  $set=@($plan.$setName);if($set.Count-ne4-or@($set.role|Sort-Object -Unique).Count-ne4){throw 'switch_artifact_inventory'}
  foreach($x in $set){Keys $x @('role','path','sha256');if($x.role-cnotin@('backup','login','mcp','task')){throw 'switch_artifact_role'}
   $id=if($setName-ceq'artifacts'){@{backup='backup_config';login='login_config';mcp='mcp_config';task='task_template_rules'}[$x.role]}else{@{backup='baseline_daily';login='baseline_login';task='new_task_raw'}[$x.role]}
   if($id){if($x.path-cne(Get-ActivationLockedPath $Lease $id)-or$x.sha256-cne$Lease.Hash($id)){throw 'switch_artifact_binding'}}
   elseif($x.path-cne$Baseline.mcp_configuration_path-or$x.sha256-cne$Baseline.mcp_configuration_sha256-or@($Policy.baselineFiles|Where-Object{$_.path-ceq$x.path-and$_.sha256-ceq$x.sha256}).Count-ne1){throw 'switch_old_mcp_binding'}
  }
 }
 $mutable=@($Core.database_path,(Join-Path $Baseline.state_directory 's6-lifecycle.json'),(Join-Path $Core.recovery_custody_directory 'current-head.json'),(Join-Path $Core.recovery_custody_directory 'custody.lock'),(Join-Path $Baseline.state_directory 'shortcut-mail-relay.runtime.lock'))
 foreach($ref in @($Policy.baselineFiles)+@($r.Binding.artifacts)){if($ref.path-in$mutable){throw 'switch_mutable_static_lock_conflict'}}
 return @{Plan=$plan;Policy=$p}
}
function Invoke-ActivationSwitchTransition {
 param([scriptblock]$ReleaseOld,[scriptblock]$Launch,[scriptblock]$AcquireNew,[scriptblock]$VerifyNew,[scriptblock]$Update,[scriptblock]$ReleaseNew)
 # Only the trusted controller calls this sequence. Callbacks are local implementation, never binding data.
 & $ReleaseOld
 $physical=& $Launch
 if($null-eq$physical-or$physical.retained-isnot[bool]-or$physical.retained-or$null-eq$physical.exitCode-or$physical.exitCode-ne0){throw 'package_switch_physical_exit_unconfirmed'}
 try{& $AcquireNew;& $VerifyNew;& $Update}finally{& $ReleaseNew}
}
