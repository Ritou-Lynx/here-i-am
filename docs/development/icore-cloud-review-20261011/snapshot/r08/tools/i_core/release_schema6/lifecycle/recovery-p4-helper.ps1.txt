#requires -Version 5.1
# Dormant recovery coordinator. All Execute functions require a factory-issued live lease.
function Assert-RecoveryKeys($Value,[string]$Names) {
 if($null-eq$Value-or$Value-is[string]-or$Value-is[Array]){throw 'recovery_schema'}
 if((@($Value.PSObject.Properties.Name|Sort-Object)-join',')-cne((@($Names.Split(' ')|Where-Object{$_})|Sort-Object)-join',')){throw 'recovery_schema'}
}
function Assert-RecoveryHash($Value){if($Value-isnot[string]-or$Value-cnotmatch'^[a-f0-9]{64}$'){throw 'recovery_hash'}}
function Assert-RecoveryTrue($Value){if($Value-isnot[bool]-or!$Value){throw 'recovery_boolean'}}
function Assert-RecoveryFalse($Value){if($Value-isnot[bool]-or$Value){throw 'recovery_boolean'}}
function Assert-RecoveryEqual($Actual,$Expected){if((ConvertTo-P4CanonicalJson $Actual)-cne(ConvertTo-P4CanonicalJson $Expected)){throw 'recovery_binding'}}
function Assert-RecoveryUtc($Value,$Policy) {
 if($Value-isnot[string]-or$Value-cnotmatch'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,7})?Z$'){throw 'recovery_time'}
 $t=[DateTimeOffset]::Parse($Value,[Globalization.CultureInfo]::InvariantCulture,[Globalization.DateTimeStyles]::AssumeUniversal).UtcTicks
 if($t-lt[DateTimeOffset]::FromUnixTimeMilliseconds([long]$Policy.notBeforeUtcMs).UtcTicks-or$t-gt[DateTimeOffset]::FromUnixTimeMilliseconds([long]$Policy.notAfterUtcMs).UtcTicks-or$t-gt[DateTimeOffset]::UtcNow.UtcTicks){throw 'recovery_time'}
 return $t
}
function Assert-RecoveryApprovalCurrent($Policy) {
 $n=[DateTimeOffset]::UtcNow.UtcTicks
 if($n-lt[DateTimeOffset]::FromUnixTimeMilliseconds([long]$Policy.notBeforeUtcMs).UtcTicks-or$n-gt[DateTimeOffset]::FromUnixTimeMilliseconds([long]$Policy.notAfterUtcMs).UtcTicks){throw 'recovery_approval_expired'}
}
function Assert-RecoveryPolicy($Policy,$RuntimePolicy) {
 Assert-RecoveryKeys $Policy 'format evidenceMode attemptId planSha256 allowedPhases namespaceVersion executeRecoveryP4 firstBackupOnly normalCloseBudgetMs coordinatorDeadlineMs'
 if($Policy.format-cne'i-core-recovery-p4-policy-v1'-or$Policy.evidenceMode-cne'reviewed-live'-or$Policy.attemptId-cne$RuntimePolicy.attemptId-or$Policy.planSha256-cne$RuntimePolicy.planSha256-or$Policy.namespaceVersion-cne'recovery-p4-evidence-namespace-v1'){throw 'recovery_policy'}
 Assert-RecoveryTrue $Policy.executeRecoveryP4;Assert-RecoveryTrue $Policy.firstBackupOnly
 if($Policy.normalCloseBudgetMs-isnot[int]-or$Policy.normalCloseBudgetMs-ne60000-or$Policy.coordinatorDeadlineMs-isnot[int]-or$Policy.coordinatorDeadlineMs-ne300000-or$Policy.allowedPhases-isnot[array]-or$Policy.allowedPhases.Count-lt1-or$Policy.allowedPhases.Count-gt2-or@($Policy.allowedPhases|Select-Object -Unique).Count-ne$Policy.allowedPhases.Count-or@($Policy.allowedPhases|Where-Object{$_-cnotin@('login-recovery','host-control-recovery')}).Count){throw 'recovery_policy_limits'}
}
function Get-RecoveryLockedPath($Lease,[string]$Id) {
 $allowed=@('recovery_entrypoint','recovery_cleanup','recovery_helper','recovery_policy','backup_policy','normal_close','process_image_binding','login_config','manifest')
 if($Id-cnotin$allowed){throw 'recovery_locked_role'}
 $r=Get-P4LeaseRecord $Lease;$a=@($r.Binding.artifacts|Where-Object{$_.id-ceq$Id})
 if($a.Count-ne1-or!$a[0].private-or!$r.Map.ContainsKey($Id)-or$a[0].sha256-cne$r.Expected[$Id]-or$r.Map[$Id].Hash()-cne$a[0].sha256){throw 'recovery_locked_artifact'}
 $r.Map[$Id].Assert();[P4EvidenceLease]::Plain($a[0].path);return [string]$a[0].path
}
function Open-RecoveryReceipt($Lease,[string]$Path,[int]$Limit=1048576,$Clock=$null,[int]$TimeoutMs=300000) {
 $r=Get-P4LeaseRecord $Lease
 if($null-eq$Clock){if(!$r.ContainsKey('RecoveryOperationClock')){throw 'recovery_publication_clock'};$Clock=$r.RecoveryOperationClock}
 $pub=Open-P4PublishedEvidence -Lease $Lease -Path $Path -Clock $Clock -TimeoutMs $TimeoutMs -MaxBytes $Limit -AssertBoundary {if($r.ContainsKey('RecoveryOperationClock')){Assert-ReviewedRecoveryDeadline $Lease}}
 $r.All.Add($pub.Lease);return @{Value=$pub.Value;Hash=$pub.Hash;Lease=$pub.Lease}
}

function Write-RecoveryReceipt($Lease,[string]$Name,$Value) {
 if($Name-cnotin@('recovery-p4-consumption.json','recovery-p4-completion.json','recovery-p4-close-approved.json','recovery-p4-cleanup-consumption.json','recovery-p4-cleanup-completion.json','recovery-p4-cleanup-close-approved.json','recovery-p4-disable-before.json','recovery-p4-disable-after.json','recovery-p4-cleanup-disable-before.json','recovery-p4-cleanup-disable-after.json')){throw 'recovery_write_name'}
 $r=Get-P4LeaseRecord $Lease;$r.Attachment.ControlLease.Assert()
 $bytes=[Text.UTF8Encoding]::new($false,$true).GetBytes(($Value|ConvertTo-Json -Depth 40 -Compress)+[char]10)
 if($bytes.Length-gt1048576){throw 'recovery_write_limit'};$null=Read-P4StrictJson $bytes
 $p=Join-Path $r.Attachment.ControlPath $Name;[OwnedArtifactNative]::Write($p,$r.Owner,$bytes)
 $l=[P4EvidenceLease]::new($p,$r.Owner,$false,$true,1048576)
 try{if($l.Hash()-cne(Get-P4ByteHash $bytes)-or$l.Length-ne$bytes.Length){throw 'recovery_write_readback'};$r.Attachment.ControlLease.Assert();return $l.Hash()}finally{$l.Dispose()}
}
function Assert-RecoveryInitialMarker($Marker,$Runtime,$Claim,$Returned,$Enabled,$Hashes) {
 Assert-RecoveryKeys $Marker 'format evidenceMode attemptId bindingSha256 approvalSha256 planSha256 instanceGuid sessionId sessionControlId sessionWindowSha256 launchSha256 readySha256 mcpStartSha256 activationClaimSha256 runReturnedSha256 activationStateSha256'
 if($Marker.format-cne'i-core-initial-session-binding-v1'-or$Marker.evidenceMode-cne'reviewed-live'-or$Marker.attemptId-cne$Runtime.attemptId-or$Marker.bindingSha256-cne$Runtime.bindingSha256-or$Marker.approvalSha256-cne$Runtime.approvalSha256-or$Marker.planSha256-cne$Runtime.planSha256-or$Marker.sessionId-cnotmatch'^session-[a-f0-9]{32}$'-or$Marker.sessionControlId-cnotmatch'^control-[a-f0-9]{32}$'-or$Marker.instanceGuid-cne$Returned.instanceGuid){throw 'recovery_initial_binding'}
 foreach($k in @('sessionWindowSha256','launchSha256','readySha256','mcpStartSha256','activationClaimSha256','runReturnedSha256','activationStateSha256')){Assert-RecoveryHash $Marker.$k}
 if($Marker.activationClaimSha256-cne$Hashes.claim-or$Marker.runReturnedSha256-cne$Hashes.returned-or$Marker.activationStateSha256-cne$Hashes.enabled){throw 'recovery_initial_hashes'}
 $null=Assert-IdentityActivationEvidence $Claim $Returned $Runtime $Hashes.claim
 if($Enabled.attemptId-cne$Runtime.attemptId-or$Enabled.approvalSha256-cne$Runtime.approvalSha256-or$Enabled.planSha256-cne$Runtime.planSha256){throw 'recovery_initial_enabled'}
}
function Resolve-RecoveryPhase($Marker,[string]$SessionId,[string]$ControlId,$Transition) {
 if($SessionId-cnotmatch'^session-[a-f0-9]{32}$'-or$ControlId-cnotmatch'^control-[a-f0-9]{32}$'){throw 'recovery_phase_identity'}
 if($null-ne$Transition){
  Assert-RecoveryKeys $Transition 'format evidenceMode sessionId previousControlId controlId hostPid hostStartedTicks sessionWindowSha256 bindingSha256 approvalSha256 previousMcpEmpty previousMcpHandlesReleased previousBackupExited previousBackupEmpty previousBackupFailed createdUtc'
  if($Transition.format-cne'i-core-control-recovery-transition-v1'-or$Transition.evidenceMode-cne'reviewed-live'-or$Transition.sessionId-cne$SessionId-or$Transition.controlId-cne$ControlId-or$Transition.previousControlId-cnotmatch'^control-[a-f0-9]{32}$'-or$Transition.previousControlId-ceq$ControlId){throw 'recovery_transition'}
  foreach($k in @('previousMcpEmpty','previousMcpHandlesReleased','previousBackupExited','previousBackupEmpty')){Assert-RecoveryTrue $Transition.$k};Assert-RecoveryFalse $Transition.previousBackupFailed
  return 'host-control-recovery'
 }
 if($SessionId-ceq$Marker.sessionId){if($ControlId-cne$Marker.sessionControlId){throw 'recovery_transition_required'};return 'initial-activation'}
 return 'login-recovery'
}
function Open-ReviewedLifecyclePhase {
 param([Parameter(Mandatory=$true)]$Lease)
 $r=Get-P4LeaseRecord $Lease
 if($Lease.Mode-cne'reviewed-live'-or!$r.Attached){throw 'recovery_phase_lease'}
 $root=Join-Path $r.Binding.observation.activationRoot $r.Policy.attemptId
 $markerPath=Join-Path $root '03-initial-session-binding.json';$clock=[Diagnostics.Stopwatch]::StartNew()
 $marker=Open-RecoveryReceipt $Lease $markerPath 262144 $clock 30000
 $claim=Open-RecoveryReceipt $Lease (Join-Path $root '00-run-consumption.json') 262144 $clock 30000
 $returned=Open-RecoveryReceipt $Lease (Join-Path $root '01-run-returned.json') 262144 $clock 30000
 $enabled=Open-RecoveryReceipt $Lease (Join-Path $root '02-enabled-state.json') 262144 $clock 30000
 $runtime=Get-ReviewedIdentityRuntimePolicy $Lease;$runtime|Add-Member NoteProperty bindingSha256 $Lease.BindingSha256 -Force
 Assert-RecoveryInitialMarker $marker.Value $runtime $claim.Value $returned.Value $enabled.Value @{claim=$claim.Hash;returned=$returned.Hash;enabled=$enabled.Hash}
 $activationPolicy=Get-ActivationProofTaskPolicy -Lease $Lease
 $null=Assert-IdentityEnabledTaskState $enabled.Value $runtime $activationPolicy
 $transition=$null;$transitionHash=$null;$transitionPath=Join-Path $r.Attachment.ControlPath 'recovery-control-transition.json'
 if(Test-Path -LiteralPath $transitionPath){
  $d=Open-RecoveryReceipt $Lease $transitionPath 262144 $clock 30000;$transition=$d.Value;$transitionHash=$d.Hash
  if($transition.bindingSha256-cne$Lease.BindingSha256-or$transition.approvalSha256-cne$Lease.ApprovalSha256-or$transition.sessionWindowSha256-cne$Lease.Hash('session_window')){throw 'recovery_transition_binding'}
  $window=$Lease.ReadJson('session_window');$native=[ICoreIdentityNative]::Process([int]$window.pid)
  if($transition.hostPid-ne$native.pid-or$transition.hostStartedTicks-cne[string]$native.startedTicks){throw 'recovery_transition_host'}
  $null=Assert-RecoveryUtc $transition.createdUtc $r.Policy
 }
 $sid=[IO.Path]::GetFileName($r.Attachment.SessionPath);$cid=[IO.Path]::GetFileName($r.Attachment.ControlPath)
 $phase=Resolve-RecoveryPhase $marker.Value $sid $cid $transition
 if($phase-ceq'initial-activation'){
  foreach($p in @(@('sessionWindowSha256','session_window'),@('launchSha256','launch'),@('readySha256','ready'),@('mcpStartSha256','mcp_start'))){if($marker.Value.($p[0])-cne$Lease.Hash($p[1])){throw 'recovery_initial_metadata'}}
 }
 if($phase-cne$r.Attachment.Phase-or$phase-cne$r.LifecyclePhase){throw 'recovery_phase_caller_mismatch'}
 Assert-RecoveryApprovalCurrent $r.Policy
 if($clock.ElapsedMilliseconds-ge30000){throw 'recovery_initial_marker_pending'}
 return @{Phase=$phase;InitialHash=$marker.Hash;TransitionHash=$transitionHash}
}

function Assert-RecoveryStart($Start,$Policy,$Expected) {
 Assert-RecoveryKeys $Start 'format evidenceMode attemptId phase sessionId controlId bindingSha256 approvalSha256 planSha256 permitSha256 firstAttemptId firstAttemptSha256 intentSha256 workerSha256 recoveryEntrySha256 recoveryPolicySha256 initialSessionBindingSha256 controlTransitionSha256 producer producerExitCode producerStdoutSha256 producerStdoutByteCount producerStderrSha256 producerStderrByteCount producerStdoutEof producerStderrEof producerJobEmpty backupResumed createdUtc'
 if($Start.format-cne'i-core-recovery-p4-start-v1'-or$Start.evidenceMode-cne'reviewed-live'){throw 'recovery_start_schema'}
 foreach($k in @('attemptId','phase','sessionId','controlId','bindingSha256','approvalSha256','planSha256','permitSha256','firstAttemptId','firstAttemptSha256','intentSha256','workerSha256','recoveryEntrySha256','recoveryPolicySha256','initialSessionBindingSha256','controlTransitionSha256')){if($Start.$k-cne$Expected.$k){throw 'recovery_start_binding'}}
 foreach($k in @('producerStdoutEof','producerStderrEof','producerJobEmpty','backupResumed')){Assert-RecoveryTrue $Start.$k}
 Assert-RecoveryKeys $Start.producer 'pid startedTicks ownerSid sessionId imageSha256 assignedToOwnedJob resumed'
 Assert-RecoveryTrue $Start.producer.assignedToOwnedJob;Assert-RecoveryTrue $Start.producer.resumed
 if(($Start.producer.pid-isnot[int]-and$Start.producer.pid-isnot[long])-or$Start.producer.pid-le0-or$Start.producer.startedTicks-isnot[string]-or$Start.producer.startedTicks-cnotmatch'^[1-9][0-9]{10,18}$'-or$Start.producer.ownerSid-cne$Expected.ownerSid-or$Start.producer.sessionId-ne$Expected.osSessionId-or$Start.producer.imageSha256-cne$Expected.powerShellSha256){throw 'recovery_producer_identity'}
 if(($Start.producerExitCode-isnot[int]-and$Start.producerExitCode-isnot[long])-or$Start.producerExitCode-ne0-or($Start.producerStderrByteCount-isnot[int]-and$Start.producerStderrByteCount-isnot[long])-or$Start.producerStderrByteCount-ne0-or$Start.producerStderrSha256-cne'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855'){throw 'recovery_producer_delivery'}
 $result=[ordered]@{format='p3-permit-producer-result-v1';passed=$true;permitSha256=$Expected.permitSha256}
 $bytes=[Text.UTF8Encoding]::new($false,$true).GetBytes((ConvertTo-P4CanonicalJson $result)+[char]13+[char]10)
 if($Start.producerStdoutByteCount-ne$bytes.Length-or$Start.producerStdoutSha256-cne(Get-P4ByteHash $bytes)){throw 'recovery_producer_stdout'}
 $null=Assert-RecoveryUtc $Start.createdUtc $Policy
}
function Open-ReviewedRecoveryInputs($Lease) {
 $r=Get-P4LeaseRecord $Lease
 if($Lease.Mode-cne'reviewed-live'-or$Lease.Readiness-cne'approval-authorized'-or!$r.Attached-or$r.Attachment.Phase-cnotin@('login-recovery','host-control-recovery')){throw 'recovery_live_lease'}
 $null=Get-RecoveryLockedPath $Lease 'recovery_policy';$rp=$Lease.ReadJson('recovery_policy')
 Assert-RecoveryPolicy $rp $r.Policy
 if($r.Attachment.Phase-cnotin$rp.allowedPhases){throw 'recovery_phase_policy'}
 foreach($id in @('recovery_entrypoint','recovery_cleanup','recovery_helper','normal_close','process_image_binding','login_config','manifest','backup_policy')){$null=Get-RecoveryLockedPath $Lease $id}
 $ap=$Lease.ReadJson('approval')
 if($ap.scope-cne'task-update-enable-run-attach-p3-p4-normal-close-once'-or$ap.failureContainment-cne'disable-and-exact-normal-close'){throw 'recovery_scope'}
 Assert-RecoveryApprovalCurrent $r.Policy
 Initialize-ReviewedIdentity $Lease
 $phase=Open-ReviewedLifecyclePhase -Lease $Lease
 $proof=Open-ReviewedIdentityActivationEvidence -Lease $Lease -Phase $phase.Phase
 if($proof.Source-cne'registered-item-attach'-or$proof.RunCalls-ne0){throw 'recovery_claim'}
 $ip=Get-ReviewedIdentityRuntimePolicy $Lease
 if($ip.taskPath-cne'\HereIAm-iCoreSchema6-chatgpt-20261009-f90058f2'-or$ip.oldTaskPath-cne'\HereIAm-iCoreSchema6-cleanclose-20261008-2c01de5b'){throw 'recovery_task_scope'}
 $self=[ICoreIdentityNative]::Process($PID);$window=$Lease.ReadJson('session_window');$observedHost=[ICoreIdentityNative]::Process([int]$window.pid)
 if($self.parentPid-ne$observedHost.pid-or$self.ownerSid-cne$r.Owner-or$observedHost.ownerSid-cne$r.Owner-or$self.sessionId-ne$observedHost.sessionId-or$self.imagePath-cne$Lease.Path('powershell')-or$observedHost.imagePath-cne$Lease.Path('powershell')-or![HereIAmTaskCallerContext]::HiddenWindow($observedHost.pid,[long]$window.hwnd,[uint32]$window.thread_id)){throw 'recovery_parent_host'}
 $r.RecoveryHost=$observedHost;$r.RecoveryContainmentReady=$true;$r.RecoveryPolicy=$rp
 $docs=@{};foreach($pair in @(@('p3','p3-actual-receipt.json'),@('ledger','p3-run-ledger.json'),@('frames','p3-observation-frames.json'),@('permit','p3-backup-permit.json'),@('first','backup-first-attempt.json'))){$docs[$pair[0]]=Open-RecoveryReceipt $Lease (Join-Path $r.Attachment.ControlPath $pair[1])}
 $null=Assert-ReviewedActualP3Documents $docs.p3.Value $docs.ledger.Value $docs.frames.Value $ip $proof $docs.frames.Hash $docs.ledger.Hash
 $full=$docs.frames.Value.frames[-1].identity
 $null=Assert-IdentityPermitBinding $docs.permit.Value $ip $full $docs.p3.Hash $docs.ledger.Hash
 if($observedHost.pid-ne$full.processes.host.pid-or$observedHost.startedTicks-cne$full.processes.host.startedTicks){throw 'recovery_current_host'}
 $first=$docs.first.Value
 Assert-RecoveryKeys $first 'format firstAttemptId sessionId controlId permitSha256 manifestSha256 approvalSha256'
 if($first.format-cne'i-core-backup-first-attempt-v1'-or$first.firstAttemptId-cnotmatch'^[a-f0-9]{32}$'-or$first.sessionId-cne$full.sessionId-or$first.controlId-cne$full.controlId-or$first.permitSha256-cne$docs.permit.Hash-or$first.manifestSha256-cne$ip.manifestSha256-or$first.approvalSha256-cne$Lease.ApprovalSha256){throw 'recovery_first_attempt'}
 foreach($name in @('intent','worker')){$docs[$name]=Open-RecoveryReceipt $Lease (Join-Path $r.Attachment.ControlPath ('backup-'+$first.firstAttemptId+'-'+$name+'.json')) 262144}
 $prior=$null;$seq=1
 foreach($name in @('intent','worker')){
  $d=$docs[$name].Value;Assert-RecoveryKeys $d 'format attemptId firstAttemptId sequence phase createdUtc elapsedMs prevReceiptSha256 data'
  if($d.format-cne'i-core-backup-delivery-v1'-or$d.attemptId-cne$first.firstAttemptId-or$d.firstAttemptId-cne$first.firstAttemptId-or$d.sequence-ne$seq-or$d.phase-cne$name-or$d.prevReceiptSha256-cne$prior){throw 'recovery_backup_prefix'}
  $null=Assert-RecoveryUtc $d.createdUtc $r.Policy;$seq++;$prior=$docs[$name].Hash
 }
 $intent=$docs.intent.Value.data
 foreach($pair in @(@('firstAttemptSha256',$docs.first.Hash),@('permitSha256',$docs.permit.Hash),@('bindingSha256',$Lease.BindingSha256),@('approvalSha256',$Lease.ApprovalSha256),@('planSha256',$r.Policy.planSha256),@('sessionId',$full.sessionId),@('controlId',$full.controlId))){if($intent.($pair[0])-cne$pair[1]){throw 'recovery_backup_prefix_binding'}}
 $worker=$docs.worker.Value.data;Assert-RecoveryKeys $worker 'pid startedTicks ownerSid sessionId imageSha256 assignedToOwnedJob resumed';Assert-RecoveryTrue $worker.assignedToOwnedJob;Assert-RecoveryFalse $worker.resumed
 $start=Open-RecoveryReceipt $Lease (Join-Path $r.Attachment.ControlPath 'recovery-p4-start.json') 262144
 $expected=[pscustomobject]@{attemptId=$r.Policy.attemptId;phase=$phase.Phase;sessionId=$full.sessionId;controlId=$full.controlId;bindingSha256=$Lease.BindingSha256;approvalSha256=$Lease.ApprovalSha256;planSha256=$r.Policy.planSha256;permitSha256=$docs.permit.Hash;firstAttemptId=$first.firstAttemptId;firstAttemptSha256=$docs.first.Hash;intentSha256=$docs.intent.Hash;workerSha256=$docs.worker.Hash;recoveryEntrySha256=$Lease.Hash('recovery_entrypoint');recoveryPolicySha256=$Lease.Hash('recovery_policy');initialSessionBindingSha256=$phase.InitialHash;controlTransitionSha256=$phase.TransitionHash;ownerSid=$r.Owner;osSessionId=$observedHost.sessionId;powerShellSha256=$Lease.Hash('powershell')}
 Assert-RecoveryStart $start.Value $r.Policy $expected
 if([DateTimeOffset]::Parse($start.Value.createdUtc)-lt[DateTimeOffset]::Parse($docs.worker.Value.createdUtc)){throw 'recovery_start_before_worker'}
 $r.RecoveryStart=$start;$r.RecoveryDocuments=$docs;$r.RecoveryFullIdentity=$full
 return $expected
}
function Confirm-ReviewedRecoveryFreshIdentity($Lease) {
 $r=Get-P4LeaseRecord $Lease;$sampler=$null
 try{
  $sampler=New-ReviewedIdentitySampler -Lease $Lease -PermitRecheck
  $sample=Invoke-ReviewedIdentitySampler -Sampler $sampler
  if(!$sample.ok-or$sample.retained-or$sample.elapsedMs-ge2500){throw 'recovery_fresh_identity'}
  $copy=Read-P4StrictJson (Get-IdentityCanonicalBytes $r.RecoveryFullIdentity);$copy.task.returnedSource='registered-item-attach'
  Assert-RecoveryEqual $sample.frame.identity $copy
  Assert-RecoveryApprovalCurrent $r.Policy
 }finally{if($sampler){$state=Complete-ReviewedIdentitySampler $sampler;if($state.retained){$r.RecoveryRetainedSampler=$sampler}}}
}
function Prepare-ReviewedRecoveryNamespace($Lease) {
 $r=Get-P4LeaseRecord $Lease
 if($Lease.Readiness-cne'p4-inputs-locked'-or!$r.ContainsKey('RecoveryStart')-or$r.ContainsKey('RecoveryNamespacePrepared')){throw 'recovery_namespace_state'}
 $s=$r.RecoveryStart.Value;$base=Join-Path $r.Binding.outputRoot $r.Policy.attemptId
 $parent=[P4EvidenceLease]::new($base,$r.Owner,$true,$true,0);$r.All.Add($parent);$r.RecoveryOriginalAttemptLease=$parent
 $n=[pscustomobject]@{version='recovery-p4-evidence-namespace-v1';phase=$s.phase;sessionId=$s.sessionId;controlId=$s.controlId;leaf=('recovery-p4-v1--'+$s.phase+'--'+$s.sessionId+'--'+$s.controlId);recoveryPolicySha256=$Lease.Hash('recovery_policy');startSha256=$r.RecoveryStart.Hash;permitSha256=$s.permitSha256;firstAttemptId=$s.firstAttemptId;firstAttemptSha256=$s.firstAttemptSha256}
 $null=Assert-P4RecoveryNamespace $n $r.Policy
 $r.Policy.format='p4-evidence-policy-v2';$r.Policy|Add-Member NoteProperty evidenceNamespace $n
 $r.Binding.policy=$r.Policy;$r.RecoveryNamespacePrepared=$true
 $path=Get-P4EvidenceAttemptPath $Lease;if(Test-Path -LiteralPath $path){throw 'recovery_output_exists'}
 return $path
}

function Invoke-RecoveryChild {
 param([string]$Image,[string]$Arguments,[string]$InputText,[int]$BudgetMs=30000,$EvidenceLease)
 if(!(Get-Variable RecoveryRetainedChildren -Scope Script -ErrorAction SilentlyContinue)){$script:RecoveryRetainedChildren=[Collections.Generic.List[object]]::new()}
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
   if($failed-or($child.HasExited-and$inputClosed-and$eof[0]-and$eof[1])){break}
   [Threading.Thread]::Sleep(5)
  }
  if($watch.ElapsedMilliseconds-ge$BudgetMs){$failed=$true}
  if($failed){if($null-eq$script:RecoveryRetainedChildren){$script:RecoveryRetainedChildren=[Collections.Generic.List[object]]::new()};$script:RecoveryRetainedChildren.Add(@{Process=$child;Reads=$reads;Streams=$streams;Buffers=$buffers;Input=$write;InputClosed=$inputClosed;Eof=$eof;Lease=$EvidenceLease;LeaseHeld=$held;OwnedLocks=@()});return @{exitCode=$null;retained=$true;elapsedMs=$watch.ElapsedMilliseconds;stdout=$null}}
  $code=$child.ExitCode;$child.Dispose();if($held){$EvidenceLease.Release();$held=$false}
  return @{exitCode=$code;retained=$false;elapsedMs=$watch.ElapsedMilliseconds;stdout=[Text.UTF8Encoding]::new($false,$true).GetString($output.ToArray())}
 }catch{
  if($null-eq$script:RecoveryRetainedChildren){$script:RecoveryRetainedChildren=[Collections.Generic.List[object]]::new()}
  $script:RecoveryRetainedChildren.Add(@{Process=$child;Reads=$reads;Streams=$streams;Buffers=$buffers;Input=$write;InputClosed=$inputClosed;Eof=$eof;Lease=$EvidenceLease;LeaseHeld=$held;OwnedLocks=@()})
  return @{exitCode=$null;retained=$true;elapsedMs=$watch.ElapsedMilliseconds;stdout=$null}
 }finally{$output.Dispose()}
}
function Complete-RecoveryChildren {
 if(!(Get-Variable RecoveryRetainedChildren -Scope Script -ErrorAction SilentlyContinue)){return @{retained=0}}
 foreach($x in $script:RecoveryRetainedChildren.ToArray()){
  # Drain and discard bounded chunks after a timeout/limit. No late output is accepted.
  try{
   if(!$x.InputClosed-and$x.Input.IsCompleted){$null=$x.Input.GetAwaiter().GetResult();$x.Process.StandardInput.Close();$x.InputClosed=$true}
   for($i=0;$i-lt2;$i++){
    if($null-ne$x.Reads[$i]-and$x.Reads[$i].IsCompleted){$n=$x.Reads[$i].GetAwaiter().GetResult();$x.Reads[$i]=$null;if($n-eq0){$x.Eof[$i]=$true}}
    if(!$x.Eof[$i]-and$null-eq$x.Reads[$i]){$x.Reads[$i]=$x.Streams[$i].ReadAsync($x.Buffers[$i],0,4096)}
   }
  }catch{}
  $complete=$false;try{$complete=$x.Process.HasExited-and$x.InputClosed-and$x.Eof[0]-and$x.Eof[1]-and$null-eq$x.Reads[0]-and$null-eq$x.Reads[1]}catch{}
  if($complete){$x.Process.Dispose();foreach($h in $x.OwnedLocks){$h.Dispose()};if($x.LeaseHeld){$x.Lease.Release()};$null=$script:RecoveryRetainedChildren.Remove($x)}
 }
 return @{retained=$script:RecoveryRetainedChildren.Count}
}

function Invoke-ReviewedRecoveryContainment($Lease,[switch]$Cleanup) {
 $r=Get-P4LeaseRecord $Lease
 if(!$r.ContainsKey('RecoveryContainmentReady')-or$r.RecoveryContainmentReady-ne$true){throw 'recovery_containment_unbound'}
 $prefix=if($Cleanup){'recovery-p4-cleanup'}else{'recovery-p4'}
 $result=[ordered]@{attempted=$true;disabled=$false;closed=$false;completed=$false;childRetained=$false;closeReportSha256=$null;disabledAnchors=$null;code='containment_unconfirmed'}
 try{
  Assert-ReviewedRecoveryDeadline $Lease
  $service=New-Object -ComObject Schedule.Service;$service.Connect();$folder=$service.GetFolder('\')
  $task=$folder.GetTask('HereIAm-iCoreSchema6-chatgpt-20261009-f90058f2')
  $before=@{}
  foreach($key in @('raw','definition','taskSddl','parentSddl','cmdlet')){
   $value=switch($key){raw{[string]$task.Xml}definition{[string]$task.Definition.XmlText}taskSddl{[string]$task.GetSecurityDescriptor(7)}parentSddl{[string]$folder.GetSecurityDescriptor(7)}cmdlet{[string](Export-ScheduledTask -TaskName 'HereIAm-iCoreSchema6-chatgpt-20261009-f90058f2' -TaskPath '\' -ErrorAction Stop)}}
   $before[$key]=Write-RecoveryActualAnchor $Lease $prefix 'before' $key $value
  }
  $targets=Get-ActivationProofTaskTargets -Lease $Lease
  $rawKey=if($task.Enabled){'enabledRaw'}else{'disabledRaw'};$defKey=if($task.Enabled){'enabledDefinition'}else{'disabledDefinition'}
  if($before.raw-cne$targets.Hashes[$rawKey]-or$before.definition-cne$targets.Hashes[$defKey]-or$before.taskSddl-cne$targets.Hashes.taskSddl-or$before.parentSddl-cne$targets.Hashes.parentSddl-or$before.cmdlet-cne$before.raw){throw 'recovery_disable_precondition'}
  Assert-ReviewedRecoveryDeadline $Lease
  if($task.Enabled){$task.Enabled=$false}
  $actual=$folder.GetTask('HereIAm-iCoreSchema6-chatgpt-20261009-f90058f2');$after=@{}
  foreach($key in @('raw','definition','taskSddl','parentSddl','cmdlet')){
   $value=switch($key){raw{[string]$actual.Xml}definition{[string]$actual.Definition.XmlText}taskSddl{[string]$actual.GetSecurityDescriptor(7)}parentSddl{[string]$folder.GetSecurityDescriptor(7)}cmdlet{[string](Export-ScheduledTask -TaskName 'HereIAm-iCoreSchema6-chatgpt-20261009-f90058f2' -TaskPath '\' -ErrorAction Stop)}}
   $after[$key]=Write-RecoveryActualAnchor $Lease $prefix 'after' $key $value
  }
  $targets=Get-ActivationProofTaskTargets -Lease $Lease
  if($actual.Enabled-or$after.taskSddl-cne$before.taskSddl-or$after.parentSddl-cne$before.parentSddl-or$after.raw-cne$targets.Hashes.disabledRaw-or$after.definition-cne$targets.Hashes.disabledDefinition-or$after.taskSddl-cne$targets.Hashes.taskSddl-or$after.parentSddl-cne$targets.Hashes.parentSddl-or$after.cmdlet-cne$after.raw){throw 'recovery_disable_unconfirmed'}
  $result.disabled=$true;$result.disabledAnchors=$after
 }catch{$result.code='recovery_disable_unconfirmed'}
 if($result.disabled){$result.code='recovery_disabled_close_deferred'}
 return [pscustomobject]$result
}

function Get-ReviewedRecoveryP4Plan {
 return [ordered]@{format='recovery-p4-plan-v1';mode='Plan';ioPerformed=$false;productionAuthorized=$false;taskUpdateAllowed=$false;enableAllowed=$false;runAllowed=$false;sequence=@('issued-locked-lease','host-attached-existing-P3-permit','first-backup-start-proof','fresh-identity','promote','fixed-recovery-namespace','actual-health-plus-first-backup-total','durable-completion','failure-only-fixed-disable-handoff-and-natural-exit')}
}


function Write-RecoveryActualAnchor($Lease,[string]$Prefix,[string]$Stage,[string]$Key,[string]$Value) {
 if($Prefix-cnotin@('recovery-p4','recovery-p4-cleanup')-or$Stage-cnotin@('before','after')-or$Key-cnotin@('raw','definition','taskSddl','parentSddl','cmdlet')){throw 'recovery_anchor_name'}
 $r=Get-P4LeaseRecord $Lease;$bytes=[Text.UTF8Encoding]::new($false,$true).GetBytes($Value)
 if($bytes.Length-gt1048576){throw 'recovery_anchor_limit'}
 $path=Join-Path $r.Attachment.ControlPath ($Prefix+'-disable-'+$Stage+'-'+$Key+'.actual.txt')
 $r.Attachment.ControlLease.Assert();[OwnedArtifactNative]::Write($path,$r.Owner,$bytes)
 $l=[P4EvidenceLease]::new($path,$r.Owner,$false,$true,1048576)
 try{if($l.Hash()-cne(Get-P4ByteHash $bytes)-or$l.Length-ne$bytes.Length){throw 'recovery_anchor_readback'};return $l.Hash()}finally{$l.Dispose()}
}
function Assert-RecoveryLaunchFailure($Failure,$Lease) {
 $r=Get-P4LeaseRecord $Lease
 Assert-RecoveryKeys $Failure 'format evidenceMode phase sessionId controlId bindingSha256 approvalSha256 startSha256 code coordinator coordinatorState createdUtc'
 if($Failure.format-cne'i-core-recovery-p4-launch-failure-v1'-or$Failure.evidenceMode-cne'reviewed-live'-or$Failure.phase-cne$r.Attachment.Phase-or$Failure.sessionId-cne[IO.Path]::GetFileName($r.Attachment.SessionPath)-or$Failure.controlId-cne[IO.Path]::GetFileName($r.Attachment.ControlPath)-or$Failure.bindingSha256-cne$Lease.BindingSha256-or$Failure.approvalSha256-cne$Lease.ApprovalSha256-or$Failure.startSha256-cne$r.RecoveryStart.Hash-or$Failure.code-cnotin@('prepare_failed','resume_failed','capture_failed','deadline','coordinator_failed')-or$Failure.coordinatorState-cnotin@('not-created','suspended','running','exited','unknown')){throw 'recovery_cleanup_input'}
 if($null-ne$Failure.coordinator){
  Assert-RecoveryKeys $Failure.coordinator 'pid startedTicks ownerSid sessionId imageSha256 assignedToOwnedJob resumed'
  if($Failure.coordinator.pid-le0-or$Failure.coordinator.startedTicks-cnotmatch'^[1-9][0-9]{10,18}$'-or$Failure.coordinator.ownerSid-cne$r.Owner-or$Failure.coordinator.imageSha256-cne$Lease.Hash('powershell')){throw 'recovery_cleanup_identity'}
 }elseif($Failure.coordinatorState-cne'not-created'-and$Failure.coordinatorState-cne'unknown'){throw 'recovery_cleanup_state'}
 $null=Assert-RecoveryUtc $Failure.createdUtc $r.Policy
}


function Assert-ReviewedRecoveryDeadline($Lease,[switch]$RequireActive) {
 $r=Get-P4LeaseRecord $Lease
 Assert-RecoveryApprovalCurrent $r.Policy
 if(!$r.ContainsKey('RecoveryOperationClock')-or$r.RecoveryOperationClock-isnot[Diagnostics.Stopwatch]-or!$r.RecoveryOperationClock.IsRunning-or$r.RecoveryOperationClock.ElapsedMilliseconds-ge300000){throw 'recovery_deadline'}
 if($RequireActive){Assert-P4TotalControlActive $Lease}
}
function Complete-ReviewedRecoveryResiduals($Lease) {
 $r=Get-P4LeaseRecord $Lease;$children=Complete-RecoveryChildren;$pending=$children.retained-gt0
 if($r.ContainsKey('RecoveryRetainedSampler')){$s=Complete-ReviewedIdentitySampler $r.RecoveryRetainedSampler;$pending=$pending-or$s.retained}
 $p4=Complete-P4ResidualSession;$pending=$pending-or$p4.residual
 return [bool]$pending
}
function Ensure-ReviewedRecoveryContainment($Lease) {
 $r=Get-P4LeaseRecord $Lease;$s=$r.RecoveryDeliveryState
 if($s.Consumed-and$null-eq$s.Containment-and$r.ContainsKey('RecoveryContainmentReady')){
  # One attempt even when the approved time window has already expired.
  # The containment function itself refuses mutation outside that window.
  $s.Containment=Invoke-ReviewedRecoveryContainment -Lease $Lease -Cleanup:($s.Kind-ceq'cleanup')
 }
}
function Write-ReviewedRecoveryCloseHandoff($Lease) {
 $r=Get-P4LeaseRecord $Lease;$s=$r.RecoveryDeliveryState
 Assert-ReviewedRecoveryDeadline $Lease
 if($null-eq$s.Containment-or!$s.Containment.disabled-or$null-eq$s.CompletionHash-or$null-eq$s.StartHash-or(Complete-ReviewedRecoveryResiduals $Lease)){throw 'recovery_handoff_unconfirmed'}
 if($s.Kind-ceq'cleanup'-and$null-eq$s.FailureHash){throw 'recovery_handoff_failure'}
 $self=[ICoreIdentityNative]::Process($PID);$observedHost=[ICoreIdentityNative]::Process([int]$r.RecoveryHost.pid)
 if($observedHost.startedTicks-cne$r.RecoveryHost.startedTicks-or$observedHost.ownerSid-cne$r.Owner-or$self.parentPid-ne$observedHost.pid-or$self.ownerSid-cne$r.Owner-or$self.sessionId-ne$observedHost.sessionId-or$self.imagePath-cne$Lease.Path('powershell')-or$observedHost.imagePath-cne$Lease.Path('powershell')){throw 'recovery_handoff_identity'}
 $t=Get-P4FinalTuple $Lease
 $v=[ordered]@{format='recovery-p4-close-handoff-v1';kind=$s.Kind}
 foreach($k in @('evidenceMode','attemptId','phase','sessionId','controlId','bindingSha256','approvalSha256','planSha256')){$v[$k]=$t[$k]}
 $v.startSha256=$s.StartHash;$v.failureSha256=$s.FailureHash;$v.candidateSha256=$s.CompletionHash
 $v.helperIdentity=[ordered]@{pid=[int]$self.pid;startedTicks=[string]$self.startedTicks;ownerSid=$self.ownerSid;sessionId=[int]$self.sessionId;imageSha256=$Lease.Hash('powershell');parentPid=[int]$self.parentPid;hostStartedTicks=[string]$observedHost.startedTicks}
 $anchors=$s.Containment.disabledAnchors
 foreach($key in @('raw','definition','taskSddl','parentSddl','cmdlet')){Assert-RecoveryHash $anchors[$key]}
 if($anchors.cmdlet-cne$anchors.raw){throw 'recovery_handoff_anchor'}
 $v.taskDisabled=$true;$v.disabledAnchors=$anchors;$v.closeOwner='session-host';$v.requestClose=$true;$v.closed=$false;$v.safeClosed=$false;$v.createdUtc=[DateTime]::UtcNow.ToString('o')
 Assert-ReviewedRecoveryDeadline $Lease
 return Write-P4FinalArtifact $Lease $s.Kind ($s.Prefix+'-close-handoff.json') $v
}
function New-ReviewedRecoveryCandidate($Lease) {
 $r=Get-P4LeaseRecord $Lease;$s=$r.RecoveryDeliveryState;$t=Get-P4FinalTuple $Lease
 $v=[ordered]@{format=($s.Prefix+'-completion-v2')}
 foreach($k in @('evidenceMode','attemptId','phase','sessionId','controlId','bindingSha256','approvalSha256','planSha256')){$v[$k]=$t[$k]}
 $v.startSha256=$s.StartHash
 if($s.Kind-ceq'cleanup'){$v.failureSha256=$s.FailureHash}else{$v.gateReportSha256=$(if($null-ne$s.Total-and$s.Total.Contains('durableReportSha256')){$s.Total.durableReportSha256}else{$null})}
 $v.evidenceNamespace=$(if($s.Kind-ceq'recovery'-and$r.ContainsKey('RecoveryNamespacePrepared')){$r.Policy.evidenceNamespace}else{$null})
 $v.passed=[bool]$s.Passed;$v.containmentAttempted=[bool]($null-ne$s.Containment);$v.containmentCompleted=$false;$v.retained=[bool]($s.ExternalRetained-or$s.Residual)
 $v.taskDisabled=[bool]($null-ne$s.Containment-and$s.Containment.disabled);$v.closed=$false;$v.safeClosed=$false;$v.code=$s.Code;$v.completedUtc=[DateTime]::UtcNow.ToString('o');$v.recordKind='candidate';$v.authoritative=$false
 $v.totalCommitSha256=$(if($null-ne$s.Total){$s.Total.finalCommitSha256}else{$null});$v.totalRejectSha256=$(if($null-ne$s.Total){$s.Total.finalRejectSha256}else{$null});$v.totalDisposition=$(if($null-ne$s.Total){$s.Total.finalDisposition}else{'not-run'})
 $v.totalReceiverSha256=$(if($null-ne$s.Receiver){$s.Receiver.receiverSha256}else{$null});$v.totalReceiverRejectSha256=$(if($null-ne$s.Receiver){$s.Receiver.receiverRejectSha256}else{$null});$v.totalReceiverDisposition=$(if($null-ne$s.Receiver){$s.Receiver.disposition}else{'not-run'})
 return $v
}
function Get-ReviewedRecoveryDeliveryResult($Lease) {
 $r=Get-P4LeaseRecord $Lease;$s=$r.RecoveryDeliveryState
 return [ordered]@{format=($s.Prefix+$(if($s.Kind-ceq'recovery'){'-entry'}else{''})+'-result-v2');passed=[bool]($s.Passed-and$s.Disposition-ceq'commit');completionSha256=$s.CompletionHash;commitSha256=$s.CommitHash;rejectSha256=$s.RejectHash;closeHandoffSha256=$s.HandoffHash;containmentAttempted=[bool]($null-ne$s.Containment);containmentCompleted=$false;retained=[bool]($s.ExternalRetained-or$s.Residual);disposition=$s.Disposition;code=$s.Code}
}
function Reject-ReviewedRecoveryDelivery($Lease,[string]$Code) {
 $r=Get-P4LeaseRecord $Lease;$s=$r.RecoveryDeliveryState;$s.Passed=$false;$s.Code=$Code
 Ensure-ReviewedRecoveryContainment $Lease
 $s.Residual=Complete-ReviewedRecoveryResiduals $Lease
 if($null-eq$s.RejectHash){
  if($null-eq$s.HandoffHash-and!$s.Residual-and$null-ne$s.Containment-and$s.Containment.disabled-and$null-ne$s.CompletionHash){try{$s.HandoffHash=Write-ReviewedRecoveryCloseHandoff $Lease}catch{}}
  try{$s.RejectHash=Write-P4FinalDisposition $Lease $s.Kind 'reject' ($s.Prefix+'-completion.json') $s.CompletionHash $s.CommitHash $s.HandoffHash 'recovery_final_rejected' $r.RecoveryOperationClock 300000;$s.Disposition='reject'}catch{$s.Disposition='unknown'}
 }else{$s.Disposition='reject'}
 # A handoff written before a later failure cannot be accepted beyond its own time window.
 return Get-ReviewedRecoveryDeliveryResult $Lease
}
function Complete-ReviewedRecoveryDelivery($Lease) {
 $r=Get-P4LeaseRecord $Lease
 if(!$r.ContainsKey('RecoveryDeliveryState')-or$r.ContainsKey('RecoveryDeliveryPublished')){throw 'recovery_delivery_context'}
 $r.RecoveryDeliveryPublished=$true;$s=$r.RecoveryDeliveryState
 $s.Residual=Complete-ReviewedRecoveryResiduals $Lease
 if($s.Residual){$s.Passed=$false;$s.Code='recovery_residual'}
 if(!$s.Passed){Ensure-ReviewedRecoveryContainment $Lease;$s.Residual=Complete-ReviewedRecoveryResiduals $Lease}
 try{
  if($s.Passed){Assert-ReviewedRecoveryDeadline $Lease -RequireActive}
  $candidate=New-ReviewedRecoveryCandidate $Lease
  $s.CompletionHash=Write-RecoveryReceipt $Lease ($s.Prefix+'-completion.json') $candidate
  if(!$s.Passed){throw 'recovery_candidate_rejected'}
  Assert-ReviewedRecoveryDeadline $Lease -RequireActive
  $s.CommitHash=Write-P4FinalDisposition $Lease $s.Kind 'commit' ($s.Prefix+'-completion.json') $s.CompletionHash $null $null 'committed' $r.RecoveryOperationClock 300000
  Assert-ReviewedRecoveryDeadline $Lease -RequireActive
  $s.Residual=Complete-ReviewedRecoveryResiduals $Lease
  if($s.Residual){throw 'recovery_final_residual'}
  Assert-ReviewedRecoveryDeadline $Lease -RequireActive
  $s.Disposition='commit'
 }catch{$null=Reject-ReviewedRecoveryDelivery $Lease 'recovery_final_rejected'}
 $result=Get-ReviewedRecoveryDeliveryResult $Lease;$r.RecoveryReturnedResult=$result
 return $result
}
function Finalize-ReviewedRecoveryEntry {
 [CmdletBinding()]param([Parameter(Mandatory=$true)]$Lease,[Parameter(Mandatory=$true)]$Result,[switch]$ReleaseFailed)
 $r=Get-P4LeaseRecord $Lease
 if(!$r.ContainsKey('RecoveryReturnedResult')-or![object]::ReferenceEquals($Result,$r.RecoveryReturnedResult)-or$r.ContainsKey('RecoveryEntryFinalized')){throw 'recovery_entry_context'}
 $r.RecoveryEntryFinalized=$true;$s=$r.RecoveryDeliveryState
 try{
  if($ReleaseFailed){throw 'recovery_release_failed'}
  $s.Residual=Complete-ReviewedRecoveryResiduals $Lease
  if($s.Residual){throw 'recovery_final_residual'}
  Assert-ReviewedRecoveryDeadline $Lease -RequireActive:($s.Passed)
  foreach($name in @($s.Prefix+'-reject.json')){if($s.Passed-and(Test-Path -LiteralPath (Join-Path $r.Attachment.ControlPath $name))){throw 'recovery_entry_veto'}}
 }catch{
  $null=Reject-ReviewedRecoveryDelivery $Lease 'recovery_entry_final_rejected'
  # Already durable rejection cannot authorize close if the final deadline expired or release failed.
  if($ReleaseFailed){$s.Disposition='unknown'}
  try{Assert-ReviewedRecoveryDeadline $Lease}catch{$s.Disposition='unknown'}
 }
 return Get-ReviewedRecoveryDeliveryResult $Lease
}
function New-ReviewedRecoveryDeliveryState([string]$Kind) {
 if($Kind-cnotin@('recovery','cleanup')){throw 'recovery_delivery_kind'}
 return @{Kind=$Kind;Prefix=$(if($Kind-ceq'cleanup'){'recovery-p4-cleanup'}else{'recovery-p4'});Consumed=$false;Passed=$false;Total=$null;Receiver=$null;Containment=$null;Code='recovery_validation_failed';StartHash=$null;FailureHash=$null;ExternalRetained=$false;Residual=$false;CompletionHash=$null;CommitHash=$null;RejectHash=$null;HandoffHash=$null;Disposition='unknown'}
}
function Invoke-ReviewedRecoveryP4 {
 [CmdletBinding()]param([ValidateSet('Plan','Execute')][string]$Mode='Plan',$Lease)
 if($Mode-ceq'Plan'){return Get-ReviewedRecoveryP4Plan}
 $ErrorActionPreference='Stop';Set-StrictMode -Version 2
 $r=Get-P4LeaseRecord $Lease
 if($Lease.Mode-cne'reviewed-live'-or$r.ContainsKey('RecoveryCoordinatorConsumed')){throw 'recovery_live_once'}
 $r.RecoveryCoordinatorConsumed=$true;$r.RecoveryOperationClock=[Diagnostics.Stopwatch]::StartNew();$r.RecoveryDeliveryState=New-ReviewedRecoveryDeliveryState 'recovery';$s=$r.RecoveryDeliveryState
 $u=[Text.UTF8Encoding]::new($false,$true)
 foreach($id in @('owned_helper','identity_library','activation_proof','p3_library','identity_sampler','total_gate')){. ([scriptblock]::Create($u.GetString($Lease.Bytes($id))))}
 Initialize-OwnedArtifactNative;Assert-OwnedArtifactUnelevatedProcess $r.Owner
 $script:RecoveryRetainedChildren=New-Object 'Collections.Generic.List[object]'
 try{
  $expected=Open-ReviewedRecoveryInputs $Lease;$s.StartHash=$r.RecoveryStart.Hash
  $claim=[ordered]@{format='recovery-p4-consumption-v1';evidenceMode='reviewed-live';attemptId=$r.Policy.attemptId;phase=$r.Attachment.Phase;sessionId=$expected.sessionId;controlId=$expected.controlId;bindingSha256=$Lease.BindingSha256;approvalSha256=$Lease.ApprovalSha256;planSha256=$r.Policy.planSha256;startSha256=$s.StartHash;runCalls=0;retryAllowed=$false}
  $null=Write-RecoveryReceipt $Lease 'recovery-p4-consumption.json' $claim;$s.Consumed=$true
  Assert-ReviewedRecoveryDeadline $Lease -RequireActive
  Confirm-ReviewedRecoveryFreshIdentity $Lease
  $null=Promote-P4ReviewedLease -Lease $Lease
  $null=Prepare-ReviewedRecoveryNamespace $Lease
  $s.Total=Invoke-ReviewedP4BackupTotalGate -Lease $Lease
  $s.Receiver=Confirm-ReviewedP4TotalDisposition -Lease $Lease -Result $s.Total
  if(!$s.Total.passed-or!$s.Total.overallP4Passed-or!$s.Total.durableReportWritten-or$s.Receiver.passed-ne$true-or$s.Receiver.disposition-cne'commit'-or$null-ne$s.Receiver.receiverRejectSha256){throw 'recovery_total_failed'}
  Assert-ReviewedRecoveryDeadline $Lease -RequireActive
  $s.Passed=$true;$s.Code='recovery_total_passed'
 }catch{
  $s.Passed=$false;$message=$_.Exception.Message;if($message-cmatch'^(recovery|evidence|total)_[a-z_]+$'){$s.Code=$message}
  if($r.ContainsKey('RecoveryContainmentReady')-and!$s.Consumed){
   try{$null=Write-RecoveryReceipt $Lease 'recovery-p4-consumption.json' ([ordered]@{format='recovery-p4-failed-consumption-v1';attemptId=$r.Policy.attemptId;phase=$r.Attachment.Phase;bindingSha256=$Lease.BindingSha256;approvalSha256=$Lease.ApprovalSha256;code=$s.Code;retryAllowed=$false});$s.Consumed=$true}catch{$s.Code='recovery_consumption_conflict'}
  }
 }
 return Complete-ReviewedRecoveryDelivery $Lease
}
function Invoke-ReviewedRecoveryCleanup {
 [CmdletBinding()]param([ValidateSet('Plan','Execute')][string]$Mode='Plan',$Lease)
 if($Mode-ceq'Plan'){return [ordered]@{format='recovery-p4-cleanup-plan-v1';mode='Plan';ioPerformed=$false;productionAuthorized=$false;healthAllowed=$false;runAllowed=$false}}
 $ErrorActionPreference='Stop';Set-StrictMode -Version 2
 $r=Get-P4LeaseRecord $Lease
 if($Lease.Mode-cne'reviewed-live'-or$r.ContainsKey('RecoveryCleanupConsumed')){throw 'recovery_cleanup_once'}
 $r.RecoveryCleanupConsumed=$true;$r.RecoveryOperationClock=[Diagnostics.Stopwatch]::StartNew();$r.RecoveryDeliveryState=New-ReviewedRecoveryDeliveryState 'cleanup';$s=$r.RecoveryDeliveryState
 $script:RecoveryRetainedChildren=New-Object 'Collections.Generic.List[object]';$u=[Text.UTF8Encoding]::new($false,$true)
 foreach($id in @('owned_helper','identity_library','activation_proof','p3_library','identity_sampler','total_gate')){. ([scriptblock]::Create($u.GetString($Lease.Bytes($id))))}
 Initialize-OwnedArtifactNative;Assert-OwnedArtifactUnelevatedProcess $r.Owner
 try{
  $null=Open-ReviewedRecoveryInputs $Lease;$s.StartHash=$r.RecoveryStart.Hash
  $f=Open-RecoveryReceipt $Lease (Join-Path $r.Attachment.ControlPath 'recovery-p4-launch-failure.json') 262144
  Assert-RecoveryLaunchFailure $f.Value $Lease;$s.FailureHash=$f.Hash
  $null=Write-RecoveryReceipt $Lease 'recovery-p4-cleanup-consumption.json' ([ordered]@{format='recovery-p4-cleanup-consumption-v1';attemptId=$r.Policy.attemptId;phase=$r.Attachment.Phase;bindingSha256=$Lease.BindingSha256;approvalSha256=$Lease.ApprovalSha256;failureSha256=$f.Hash;retryAllowed=$false;healthAllowed=$false})
  $s.Consumed=$true;$s.ExternalRetained=$f.Value.coordinatorState-cin@('suspended','running','unknown');$s.Code='recovery_cleanup_requested'
 }catch{$s.Code='recovery_cleanup_unconfirmed'}
 return Complete-ReviewedRecoveryDelivery $Lease
}
