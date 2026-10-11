#requires -Version 5.1
# Dormant metadata proofs. The original Run call lives only in the reviewed controller.
function Assert-IdentityActivationEvidence {
 param($Claim,$Returned,$Policy,[string]$ClaimSha256)
 $claimKeys=@('format','evidenceMode','attemptId','approvalSha256','planSha256','taskPath','historicalProductionRuns','newRunBudget','source','runCalls','consumed','createdAtUtc','mayHaveInvokedRun')
 $returnedKeys=@('format','evidenceMode','attemptId','approvalSha256','activationClaimSha256','source','runCalls','taskPath','instanceGuid','state','observedAtUtc')
 foreach($pair in @(@($Claim,$claimKeys),@($Returned,$returnedKeys))){
  [string[]]$actual=@($pair[0].PSObject.Properties.Name);[Array]::Sort($actual,[StringComparer]::Ordinal)
  [string[]]$expected=@($pair[1]);[Array]::Sort($expected,[StringComparer]::Ordinal)
  if(($actual-join',')-cne($expected-join',')){throw 'activation_proof_schema'}
 }
 if($Claim.format-cne'i-core-activation-claim-v1'-or$Returned.format-cne'i-core-run-returned-v1'-or$Claim.evidenceMode-cne$Policy.evidenceMode-or$Returned.evidenceMode-cne$Policy.evidenceMode){throw 'activation_proof_mode'}
 foreach($key in @('attemptId','approvalSha256','taskPath')){
  if($Claim.$key-cne$Policy.$key-or$Returned.$key-cne$Policy.$key){throw 'activation_proof_binding'}
 }
 foreach($value in @($Claim.historicalProductionRuns,$Claim.newRunBudget,$Claim.runCalls,$Returned.runCalls,$Returned.state)){if($value-isnot[int]-and$value-isnot[long]){throw 'activation_proof_integer'}}
 if($ClaimSha256-cnotmatch'^[a-f0-9]{64}$'){throw 'activation_proof_hash'}
 if($Claim.planSha256-cne$Policy.planSha256-or$Claim.historicalProductionRuns-ne2-or$Claim.newRunBudget-ne1-or$Claim.consumed-isnot[bool]-or$Claim.consumed-ne$true-or$Claim.mayHaveInvokedRun-isnot[bool]-or$Returned.activationClaimSha256-cne$ClaimSha256-or$Returned.source-cne$Claim.source-or$Returned.runCalls-ne$Claim.runCalls-or$Returned.state-ne4){throw 'activation_proof_consumption'}
 if(!(($Claim.source-ceq'original-run'-and$Claim.runCalls-eq1-and$Claim.mayHaveInvokedRun-eq$true)-or($Claim.source-ceq'registered-item-attach'-and$Claim.runCalls-eq0-and$Claim.mayHaveInvokedRun-eq$false))){throw 'activation_proof_run_count'}
 if($Returned.instanceGuid-cnotmatch'^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$'){throw 'activation_proof_guid'}
 $created=[DateTime]::Parse($Claim.createdAtUtc,[Globalization.CultureInfo]::InvariantCulture,[Globalization.DateTimeStyles]::RoundtripKind)
 $observed=[DateTime]::Parse($Returned.observedAtUtc,[Globalization.CultureInfo]::InvariantCulture,[Globalization.DateTimeStyles]::RoundtripKind)
 if($created.Kind-ne[DateTimeKind]::Utc-or$observed.Kind-ne[DateTimeKind]::Utc-or$observed-lt$created){throw 'activation_proof_time'}
 return $true
}
function Assert-IdentityEnabledTaskState {
 param($Enabled,$Policy,$ActivationPolicy)
 [string[]]$actual=@($Enabled.PSObject.Properties.Name);[Array]::Sort($actual,[StringComparer]::Ordinal)
 [string[]]$expected=@('format','evidenceMode','attemptId','approvalSha256','planSha256','taskPath','enableStartedTicks','actualRawXmlSha256','actualDefinitionSha256','taskSddlSha256','parentSddlSha256','enabled','actualExport');[Array]::Sort($expected,[StringComparer]::Ordinal)
 if(($actual-join',')-cne($expected-join',')){throw 'enabled_state_schema'}
 if($Enabled.format-cne'i-core-enabled-task-state-v1'-or$Enabled.evidenceMode-cne$Policy.evidenceMode-or$Enabled.enabled-isnot[bool]-or$Enabled.enabled-ne$true-or$Enabled.actualExport-isnot[bool]-or$Enabled.actualExport-ne$true){throw 'enabled_state_actual'}
 foreach($key in @('attemptId','approvalSha256','planSha256','taskPath')){if($Enabled.$key-cne$Policy.$key){throw 'enabled_state_binding'}}
 if($Enabled.enableStartedTicks-isnot[string]-or$Enabled.enableStartedTicks-cnotmatch'^[0-9]{18}$'-or[long]$Enabled.enableStartedTicks-le0){throw 'enabled_state_ticks'}
 foreach($pair in @(@('actualRawXmlSha256','expectedEnabledRawXmlSha256'),@('actualDefinitionSha256','expectedEnabledDefinitionSha256'),@('taskSddlSha256','taskSddlSha256'),@('parentSddlSha256','parentSddlSha256'))){
  if($Enabled.($pair[0])-isnot[string]-or$Enabled.($pair[0])-cnotmatch'^[a-f0-9]{64}$'-or$Enabled.($pair[0])-cne$ActivationPolicy.($pair[1])){throw 'enabled_state_anchor'}
 }
 return $true
}
function Open-ReviewedIdentityActivationEvidence {
 param([Parameter(Mandatory=$true)]$Lease,[Parameter(Mandatory=$true)][string]$Phase)
 $record=Get-P4LeaseRecord $Lease;$policy=Get-ReviewedIdentityRuntimePolicy $Lease
 if($Lease.Mode-cne'reviewed-live'-or!$record.Attached-or$Phase-cne$policy.phase){throw 'activation_proof_live_context'}
 $root=$record.Binding.observation.activationRoot;[P4EvidenceLease]::Plain($root)
 $activationDirectory=Join-Path $root $record.Policy.attemptId
 $directory=$activationDirectory
 if($Phase-cne'initial-activation'){$directory=$record.Attachment.ControlPath}
 $held=New-Object 'Collections.Generic.List[IDisposable]'
 try{
  $rootLease=[P4EvidenceLease]::new($activationDirectory,$record.Owner,$true,$true,0);$held.Add($rootLease)
  if($directory-cne$activationDirectory){$controlLease=[P4EvidenceLease]::new($directory,$record.Owner,$true,$true,0);$held.Add($controlLease)}
  $claim=[P4EvidenceLease]::new((Join-Path $directory '00-run-consumption.json'),$record.Owner,$false,$true,262144);$held.Add($claim)
  $returned=[P4EvidenceLease]::new((Join-Path $directory '01-run-returned.json'),$record.Owner,$false,$true,262144);$held.Add($returned)
  $enabled=[P4EvidenceLease]::new((Join-Path $activationDirectory '02-enabled-state.json'),$record.Owner,$false,$true,262144);$held.Add($enabled)
  $c=Read-P4StrictJson $claim.Bytes();$r=Read-P4StrictJson $returned.Bytes();$e=Read-P4StrictJson $enabled.Bytes();$h=$claim.Hash()
  $null=Assert-IdentityActivationEvidence $c $r $policy $h
  $null=Assert-IdentityEnabledTaskState $e $policy (Get-ActivationProofTaskPolicy -Lease $Lease)
  if([DateTime]::Parse($c.createdAtUtc,[Globalization.CultureInfo]::InvariantCulture,[Globalization.DateTimeStyles]::RoundtripKind).Ticks-lt[long]$e.enableStartedTicks){throw 'activation_claim_before_enable'}
  $value=@{Source=$c.source;RunCalls=[int]$c.runCalls;InstanceGuid=$r.instanceGuid;ActivationClaimSha256=$h;RunReturnedSha256=$returned.Hash();ActivationStateSha256=$enabled.Hash();Claim=$c;Returned=$r;EnabledState=$e;ClaimLease=$claim;ReturnedLease=$returned;EnabledLease=$enabled;DirectoryLease=$rootLease}
  foreach($l in $held){$record.All.Add($l)}
  $record.ActivationStartedTicks=[string]$e.enableStartedTicks
  $record.ActivationEvidence=$value
  return $value
 }catch{
  foreach($l in $held){$l.Dispose()}
  throw 'activation_proof_rejected'
 }
}
function Set-ReviewedIdentityActivation {
 [CmdletBinding()]param([Parameter(Mandatory=$true)]$Lease,[Parameter(Mandatory=$true)][ValidateSet('initial-activation','login-recovery','host-control-recovery')][string]$Phase,$OriginalRunInstance,$AttachedInstance)
 $record=Get-P4LeaseRecord $Lease
 if($Lease.Mode-cne'reviewed-live'-or!$record.Attached-or$record.ContainsKey('ActivationEvidence')){throw 'activation_context_rejected'}
 $base=$Lease.ReadJson('identity_policy')
 if(@($base.allowedPhases)-cnotcontains$Phase){throw 'activation_phase_not_approved'}
 $record.RuntimePhase=$Phase
 Initialize-ReviewedIdentity $Lease
 $policy=Get-ReviewedIdentityRuntimePolicy $Lease
 if($Phase-cne'initial-activation'){
  if($null-ne$OriginalRunInstance){throw 'activation_recovery_cannot_run'}
  $self=[ICoreIdentityNative]::Process($PID);$window=$Lease.ReadJson('session_window');$hostProcess=[ICoreIdentityNative]::Process([int]$window.pid)
  if($self.parentPid-ne$hostProcess.pid-or$self.ownerSid-cne$record.Owner-or$hostProcess.ownerSid-cne$record.Owner-or$self.sessionId-ne$hostProcess.sessionId-or![HereIAmTaskCallerContext]::HiddenWindow($hostProcess.pid,[long]$window.hwnd,[uint32]$window.thread_id)){throw 'activation_recovery_parent_host'}
  $service=New-Object -ComObject Schedule.Service;$service.Connect();$task=$service.GetFolder('\').GetTask($policy.taskPath.TrimStart('\'));$items=$task.GetInstances(0)
  $native=[HereIAmTaskInstanceProjection]::Observe($policy.taskPath.TrimStart('\'))
  if(!$native.ObservationCompleted-or$native.RegisteredInstances.NativeCount-ne1-or$native.RegisteredInstances.ExplicitItemsRead-ne1-or$native.RegisteredInstances.MatchingItems.Count-ne1-or$native.ServiceRunningIncludingHidden.MatchingItems.Count-ne1-or$items.Count-ne1){throw 'activation_recovery_unique'}
  $AttachedInstance=$items.Item(1);$actual=[HereIAmTaskInstanceProjection]::ProjectReturnedInstance($AttachedInstance)
  if($actual.Path-cne$policy.taskPath-or$actual.State-ne4-or$actual.InstanceGuid-ine$native.RegisteredInstances.MatchingItems[0].InstanceGuid-or$actual.InstanceGuid-ine$native.ServiceRunningIncludingHidden.MatchingItems[0].InstanceGuid){throw 'activation_recovery_instance'}
  . ([scriptblock]::Create([Text.UTF8Encoding]::new($false,$true).GetString($Lease.Bytes('owned_helper'))))
  Assert-OwnedArtifactUnelevatedProcess $record.Owner
  $claim=[ordered]@{format='i-core-activation-claim-v1';evidenceMode='reviewed-live';attemptId=$policy.attemptId;approvalSha256=$policy.approvalSha256;planSha256=$policy.planSha256;taskPath=$policy.taskPath;historicalProductionRuns=2;newRunBudget=1;source='registered-item-attach';runCalls=0;consumed=$true;createdAtUtc=[DateTime]::UtcNow.ToString('o');mayHaveInvokedRun=$false}
  $bytes=Get-IdentityCanonicalBytes $claim;$hash=Get-P4ByteHash $bytes
  Write-OwnedArtifactBytes (Join-Path $record.Attachment.ControlPath '00-run-consumption.json') $bytes $record.Owner
  $returned=[ordered]@{format='i-core-run-returned-v1';evidenceMode='reviewed-live';attemptId=$policy.attemptId;approvalSha256=$policy.approvalSha256;activationClaimSha256=$hash;source='registered-item-attach';runCalls=0;taskPath=$policy.taskPath;instanceGuid=[Guid]::Parse($actual.InstanceGuid).ToString('D');state=$actual.State;observedAtUtc=[DateTime]::UtcNow.ToString('o')}
  Write-OwnedArtifactBytes (Join-Path $record.Attachment.ControlPath '01-run-returned.json') (Get-IdentityCanonicalBytes $returned) $record.Owner
 }
 $proof=Open-ReviewedIdentityActivationEvidence -Lease $Lease -Phase $Phase
 if($proof.Source-ceq'original-run'){
  if($null-eq$OriginalRunInstance){throw 'activation_original_returned_missing'}
  $actual=[HereIAmTaskInstanceProjection]::ProjectReturnedInstance($OriginalRunInstance)
 }else{
  if($null-eq$AttachedInstance){
   $s=New-Object -ComObject Schedule.Service;$s.Connect();$c=$s.GetFolder('\').GetTask($policy.taskPath.TrimStart('\')).GetInstances(0)
   if($c.Count-ne1){throw 'activation_attached_unique'};$AttachedInstance=$c.Item(1)
  }
  $actual=[HereIAmTaskInstanceProjection]::ProjectReturnedInstance($AttachedInstance)
 }
 if($actual.Path-cne$policy.taskPath-or$actual.State-ne4-or([Guid]::Parse($actual.InstanceGuid).ToString('D'))-cne$proof.InstanceGuid){throw 'activation_actual_object_mismatch'}
 return [ordered]@{source=$proof.Source;runCalls=$proof.RunCalls;instanceGuid=$proof.InstanceGuid;activationClaimSha256=$proof.ActivationClaimSha256;runReturnedSha256=$proof.RunReturnedSha256;activationStateSha256=$proof.ActivationStateSha256}
}

function Get-ActivationProofTaskTargets {
 param([Parameter(Mandatory=$true)]$Lease)
 $record=Get-P4LeaseRecord $Lease
 $policy=$Lease.ReadJson('activation_policy')
 if($policy.format-cne'i-core-continuous-activation-policy-v2'-or$policy.taskDerivation.format-cne'i-core-task-exact-two-slot-v1'){throw 'activation_template_protocol'}
 $a=@($record.Binding.artifacts|Where-Object{$_.id-ceq'task_template_evaluator'})
 $pin=$policy.taskDerivation.evaluatorSha256
 if($pin-cnotmatch'^[a-f0-9]{64}$'-or$a.Count-ne1-or$a[0].role-cne'source'-or$a[0].private-isnot[bool]-or!$a[0].private-or$a[0].sha256-cne$pin-or$Lease.Hash('task_template_evaluator')-cne$pin){throw 'activation_template_evaluator_pin'}
 $bytes=$Lease.Bytes('task_template_evaluator')
 if((Get-P4ByteHash $bytes)-cne$pin){throw 'activation_template_evaluator_bytes'}
 . ([scriptblock]::Create([Text.UTF8Encoding]::new($false,$true).GetString($bytes)))
 return Get-ReviewedActivationTaskTargets -Lease $Lease
}
function Get-ActivationProofTaskPolicy {
 param([Parameter(Mandatory=$true)]$Lease)
 $policy=$Lease.ReadJson('activation_policy')
 if($policy.format-ceq'i-core-continuous-activation-policy-v1'){return $policy}
 return (Get-ActivationProofTaskTargets -Lease $Lease).Policy
}
