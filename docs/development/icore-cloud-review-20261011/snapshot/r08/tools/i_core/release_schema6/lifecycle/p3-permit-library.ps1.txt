#requires -Version 5.1
# Dormant P3 producer library. Only the reviewed entrypoint may call the live functions.
if(!(Get-Variable -Name IdentityIssuedWriter -Scope Script -ErrorAction SilentlyContinue)){
 $script:IdentityIssuedWriter=$null
}
function Write-IdentityControlReceipt {
 param($Context,[string]$Name,[byte[]]$Bytes)
 if($null-eq$script:IdentityIssuedWriter-or![object]::ReferenceEquals($Context,$script:IdentityIssuedWriter)-or$Context.Failed){throw 'p3_writer_capability'}
 $names=@('p3-observation-frames.json','p3-run-ledger.json','p3-actual-receipt.json','p3-backup-permit.json')
 if($Context.Next-ge4-or$Name-cne$names[$Context.Next]-or$Bytes.Length-gt1048576){throw 'p3_writer_sequence'}
 try{
  $record=Get-P4LeaseRecord $Context.Lease
  if(!$record.Attached-or$record.Attachment.ControlPath-cne$Context.ControlPath){throw 'p3_writer_control'}
  $record.Attachment.ControlLease.Assert()
  $path=Join-Path $Context.ControlPath $Name
  Write-OwnedArtifactBytes $path $Bytes $record.Owner
  $read=[P4EvidenceLease]::new($path,$record.Owner,$false,$true,1048576)
  try{
   $digest=Get-P4ByteHash $Bytes
   if($read.Hash()-cne$digest-or$read.Length-ne$Bytes.Length){throw 'p3_writer_readback'}
   $null=Read-P4StrictJson $read.Bytes();$record.Attachment.ControlLease.Assert()
  }finally{$read.Dispose()}
  $Context.Next++
  return $digest
 }catch{$Context.Failed=$true;throw 'p3_writer_failed'}
}
function Get-IdentityPermitValue {
 param($Policy,$Identity,[string]$P3Sha256,[string]$LedgerSha256)
 $processes=[ordered]@{}
 foreach($name in @('host','supervisor','core','mcp')){$q=$Identity.processes.$name;$processes[$name]=[ordered]@{pid=[int]$q.pid;startedTicks=[string]$q.startedTicks}}
 return [ordered]@{
  format='p4-start-permit-v1';evidenceMode=$Policy.evidenceMode;attemptId=$Policy.attemptId;phase=$Policy.phase;approvalSha256=$Policy.approvalSha256;planSha256=$Policy.planSha256;p3ReceiptSha256=$P3Sha256;runLedgerSha256=$LedgerSha256
  releaseDirectory=$Policy.releaseDirectory;manifestSha256=$Policy.manifestSha256;sourceInventorySha256=$Policy.sourceInventorySha256;nodeSha256=$Policy.nodeSha256;coreConfigSha256=$Policy.coreConfigSha256;loginConfigSha256=$Policy.loginConfigSha256;mcpConfigSha256=$Policy.mcpConfigSha256;automaticConfigSha256=$Policy.automaticConfigSha256
  sessionId=$Identity.sessionId;controlId=$Identity.controlId;instanceGuid=[Guid]::Parse($Identity.task.registeredGuid).ToString('D');sessionWindowSha256=$Identity.sessionWindowSha256;launchSha256=$Identity.launchSha256;readySha256=$Identity.readySha256;mcpStartSha256=$Identity.mcpStartSha256;processes=$processes;tokenEqual=$Identity.tokenEqual
 }
}
function Assert-IdentityPermitBinding {
 param($Permit,$Policy,$Identity,[string]$P3Sha256,[string]$LedgerSha256)
 $expected=Get-IdentityPermitValue $Policy $Identity $P3Sha256 $LedgerSha256
 if((ConvertTo-IdentityCanonicalJson $Permit)-cne(ConvertTo-IdentityCanonicalJson $expected)){throw 'p3_permit_binding'}
 return $true
}
function Invoke-ReviewedP3Permit {
 [CmdletBinding()]param([Parameter(Mandatory=$true)]$Lease,$OriginalRunInstance,$AttachedInstance)
 $ErrorActionPreference='Stop'
 $record=Get-P4LeaseRecord $Lease
 if($Lease.Mode-cne'reviewed-live'-or$Lease.Readiness-cne'approval-authorized'-or!$record.Attached){throw 'p3_verified_lease_required'}
 $policy=Get-ReviewedIdentityRuntimePolicy $Lease
 Initialize-ReviewedIdentity $Lease
 if($policy.phase-cnotin@('initial-activation','login-recovery','host-control-recovery')){throw 'p3_phase'}
 if(!$record.ContainsKey('ActivationEvidence')){throw 'p3_actual_activation_evidence_required'}
 if($policy.phase-cne'initial-activation'){
  # Parent identity is measured from an actual handle, never inferred from caller metadata.
  $self=[ICoreIdentityNative]::Process($PID)
  $hostPid=($Lease.ReadJson('session_window')).pid
  if($self.parentPid-ne$hostPid){throw 'p3_producer_parent_host'}
 }
 if($null-ne$script:IdentityIssuedWriter){throw 'p3_writer_already_used'}
 $helper=$Lease.Bytes('owned_helper')
 . ([scriptblock]::Create([Text.UTF8Encoding]::new($false,$true).GetString($helper)))
 Assert-OwnedArtifactUnelevatedProcess $record.Owner
 $context=@{Lease=$Lease;ControlPath=$record.Attachment.ControlPath;Next=0;Failed=$false}
 $script:IdentityIssuedWriter=$context
 $sampler=$null;$frames=New-Object 'Collections.Generic.List[object]';$watch=[Diagnostics.Stopwatch]::StartNew()
 try{
  # Factory accepts only the issued lease and locked sources; prewarming is outside
  # the 30-second observation window. Its timeout retains unresolved worker locks.
  $sampler=New-ReviewedIdentitySampler -Lease $Lease -OriginalRunInstance $OriginalRunInstance -AttachedInstance $AttachedInstance
  $watch.Restart();$baseline=$null;$firstValidMs=$null
  do{
   $result=Invoke-ReviewedIdentitySampler -Sampler $sampler
   if(!$result.ok-or$result.elapsedMs-gt2500-or$result.retained){throw 'p3_fresh_sample_failed'}
   $frame=$result.frame
   $null=Assert-StrictObservedIdentity $frame.identity $policy
   $current=ConvertTo-IdentityCanonicalJson $frame.identity
   if($null-eq$baseline){$baseline=$current}elseif($current-cne$baseline){throw 'p3_identity_changed'}
   $sampleAt=[long]$watch.ElapsedMilliseconds;if($null-eq$firstValidMs){$firstValidMs=$sampleAt}
   $frames.Add([ordered]@{elapsedMs=$sampleAt;snapshotElapsedMs=[long]$result.elapsedMs;identity=$frame.identity})
   if(($sampleAt-$firstValidMs)-ge30000){break}
   Start-Sleep -Milliseconds ([Math]::Min(500,[int](30000-($sampleAt-$firstValidMs))))
  }while($watch.ElapsedMilliseconds-lt35000)
  $null=Assert-IdentityObservationWindow @($frames.ToArray()) $policy
  $final=$frames[$frames.Count-1].identity
  $compact=Get-IdentityCompactBinding $final
  $framesValue=[ordered]@{format='p3-actual-observation-frames-v1';evidenceMode='reviewed-live';phase=$policy.phase;attemptId=$policy.attemptId;frames=@($frames.ToArray())}
  $framesSha=Write-IdentityControlReceipt $context 'p3-observation-frames.json' (Get-IdentityCanonicalBytes $framesValue)
  $source=$final.task.returnedSource;$runCalls=$record.ActivationEvidence.RunCalls
  if($source-cne$record.ActivationEvidence.Source-or([Guid]::Parse($final.task.registeredGuid).ToString('D'))-cne$record.ActivationEvidence.InstanceGuid){throw 'p3_actual_activation_changed'}
  $ledger=[ordered]@{format='p3-run-consumption-v1';evidenceMode='reviewed-live';approvalSha256=$policy.approvalSha256;attemptId=$policy.attemptId;historicalProductionRuns=2;newRunBudget=1;consumed=$true;source=$source;runCalls=$runCalls;runGuid=$compact.runGuid;p3Identity=$compact;activationClaimSha256=$record.ActivationEvidence.ActivationClaimSha256;runReturnedSha256=$record.ActivationEvidence.RunReturnedSha256;activationStateSha256=$record.ActivationEvidence.ActivationStateSha256}
  $ledgerSha=Write-IdentityControlReceipt $context 'p3-run-ledger.json' (Get-IdentityCanonicalBytes $ledger)
  $p3=[ordered]@{
   format='p3-actual-passed-v1';evidenceMode='reviewed-live';actual=$true;passed=$true;approvalSha256=$policy.approvalSha256;attemptId=$policy.attemptId;taskPath=$policy.taskPath;oldTaskPath=$policy.oldTaskPath;registeredFlags=0;registeredNativeCount=1;registeredItems=1;psCount=1;serviceExactCount=1;registeredState=4;serviceState=4;returnedState=4;registeredGuid=$compact.runGuid;serviceGuid=$compact.runGuid;returnedGuid=$compact.runGuid;oldDisabled=$true;oldRegisteredCount=0;oldServiceCount=0;observationWindowMs=([long]$frames[$frames.Count-1].elapsedMs-[long]$frames[0].elapsedMs);identity=$compact;receiptSequence=1;runLedgerSha256=$ledgerSha
   phase=$policy.phase;returnedSource=$source;observationFramesSha256=$framesSha;fullIdentitySha256=(Get-P4ByteHash (Get-IdentityCanonicalBytes $final))
  }
  $p3Sha=Write-IdentityControlReceipt $context 'p3-actual-receipt.json' (Get-IdentityCanonicalBytes $p3)
  $permit=Get-IdentityPermitValue $policy $final $p3Sha $ledgerSha
  $permitSha=Write-IdentityControlReceipt $context 'p3-backup-permit.json' (Get-IdentityCanonicalBytes $permit)
  return [ordered]@{format='p3-permit-producer-result-v1';passed=$true;permitSha256=$permitSha}
 }catch{$context.Failed=$true;throw 'p3_producer_failed'}
 finally{
  if($null-ne$sampler){$samplerState=Complete-ReviewedIdentitySampler -Sampler $sampler;if($samplerState.retained){$script:IdentityRetainedSampler=$sampler}}
  # Keep the one-shot writer sealed after success or failure, never permit retry.
 }
}
function Wait-InitialReviewedP3Permit {
 [CmdletBinding()]param([Parameter(Mandatory=$true)]$Lease)
 $ErrorActionPreference='Stop';$record=Get-P4LeaseRecord $Lease;$policy=Get-ReviewedIdentityRuntimePolicy $Lease
 Initialize-ReviewedIdentity $Lease
 if($Lease.Mode-cne'reviewed-live'-or!$record.Attached-or$policy.phase-cne'initial-activation'){throw 'p3_initial_wait_lease'}
 $clock=[Diagnostics.Stopwatch]::StartNew();$control=$record.Attachment.ControlPath
 $held=New-Object 'Collections.Generic.List[IDisposable]';$docs=@{};$hashes=@{};$sampler=$null
 try{
  foreach($name in @('p3-backup-permit.json','p3-observation-frames.json','p3-run-ledger.json','p3-actual-receipt.json')){
   $published=Open-P4PublishedEvidence -Lease $Lease -Path (Join-Path $control $name) -Clock $clock -TimeoutMs 60000 -MaxBytes 1048576;$held.Add($published.Lease);$docs[$name]=$published.Value;$hashes[$name]=$published.Hash
  }
  $p3=$docs['p3-actual-receipt.json'];$ledger=$docs['p3-run-ledger.json'];$observations=$docs['p3-observation-frames.json'];$permit=$docs['p3-backup-permit.json']
  $proof=Open-ReviewedIdentityActivationEvidence -Lease $Lease -Phase $policy.phase
  $policy=Get-ReviewedIdentityRuntimePolicy $Lease
  $null=Assert-ReviewedActualP3Documents $p3 $ledger $observations $policy $proof $hashes['p3-observation-frames.json'] $hashes['p3-run-ledger.json']
  if($p3.format-cne'p3-actual-passed-v1'-or$p3.evidenceMode-cne'reviewed-live'-or$p3.actual-ne$true-or$p3.passed-ne$true-or$p3.phase-cne'initial-activation'-or$p3.returnedSource-cnotin@('original-run','registered-item-attach')-or$p3.approvalSha256-cne$policy.approvalSha256-or$p3.attemptId-cne$policy.attemptId-or$p3.observationFramesSha256-cne$hashes['p3-observation-frames.json']-or$p3.runLedgerSha256-cne$hashes['p3-run-ledger.json']){throw 'p3_initial_actual_receipt'}
  if($observations.format-cne'p3-actual-observation-frames-v1'-or$observations.evidenceMode-cne'reviewed-live'-or$observations.phase-cne$policy.phase-or$observations.attemptId-cne$policy.attemptId){throw 'p3_initial_frames'}
  $null=Assert-IdentityObservationWindow @($observations.frames) $policy
  $full=$observations.frames[-1].identity;$compact=Get-IdentityCompactBinding $full
  if($p3.fullIdentitySha256-cne(Get-P4ByteHash (Get-IdentityCanonicalBytes $full))-or(ConvertTo-IdentityCanonicalJson $p3.identity)-cne(ConvertTo-IdentityCanonicalJson $compact)-or$ledger.source-cne$full.task.returnedSource-or!(($ledger.source-ceq'original-run'-and$ledger.runCalls-eq1)-or($ledger.source-ceq'registered-item-attach'-and$ledger.runCalls-eq0))-or$ledger.runGuid-cne$compact.runGuid-or$ledger.consumed-ne$true-or$ledger.approvalSha256-cne$policy.approvalSha256-or$ledger.attemptId-cne$policy.attemptId-or(ConvertTo-IdentityCanonicalJson $ledger.p3Identity)-cne(ConvertTo-IdentityCanonicalJson $compact)){throw 'p3_initial_run_binding'}
  $null=Assert-IdentityPermitBinding $permit $policy $full $hashes['p3-actual-receipt.json'] $hashes['p3-run-ledger.json']
  $self=[ICoreIdentityNative]::Process($PID)
  if($self.parentPid-ne$full.processes.host.pid){throw 'p3_initial_parent_host'}
  $sampler=New-ReviewedIdentitySampler -Lease $Lease -PermitRecheck
  $result=Invoke-ReviewedIdentitySampler -Sampler $sampler
  if(!$result.ok-or$result.retained-or$result.elapsedMs-gt2500){throw 'p3_initial_fresh_recheck'}
  $actual=$result.frame.identity
  # The current recheck is explicitly attached; the original P3 proof retains
  # its own original-run source. All remaining identity fields must be exact.
  $copy=Read-P4StrictJson (Get-IdentityCanonicalBytes $full);$copy.task.returnedSource='registered-item-attach'
  if((ConvertTo-IdentityCanonicalJson $actual)-cne(ConvertTo-IdentityCanonicalJson $copy)){throw 'p3_initial_identity_changed'}
  foreach($l in $held){$l.Assert()}
  $answer=[ordered]@{format='p3-permit-producer-result-v1';passed=$true;permitSha256=$hashes['p3-backup-permit.json']}
 }finally{
  if($null-ne$sampler){$s=Complete-ReviewedIdentitySampler -Sampler $sampler;if($s.retained){$script:IdentityRetainedSampler=$sampler}}
  foreach($l in $held){$l.Dispose()}
 }
 Assert-P4PublicationBoundary -Lease $Lease -Clock $clock -TimeoutMs 60000
 return $answer
}

function Assert-ReviewedActualP3Documents {
 param($P3,$Ledger,$Observations,$Policy,$Proof,[string]$FramesSha256,[string]$LedgerSha256)
 [string[]]$actualKeys=@($Observations.PSObject.Properties.Name);[Array]::Sort($actualKeys,[StringComparer]::Ordinal)
 [string[]]$expectedKeys=@('format','evidenceMode','phase','attemptId','frames');[Array]::Sort($expectedKeys,[StringComparer]::Ordinal)
 if(($actualKeys-join',')-cne($expectedKeys-join',')){throw 'p3_actual_frames_extra_fields'}
 foreach($frame in @($Observations.frames)){
  [string[]]$frameKeys=@($frame.PSObject.Properties.Name);[Array]::Sort($frameKeys,[StringComparer]::Ordinal)
  if(($frameKeys-join',')-cne'elapsedMs,identity,snapshotElapsedMs'){throw 'p3_actual_frame_schema'}
 }
 $null=Assert-IdentityObservationWindow @($Observations.frames) $Policy
 if($Observations.format-cne'p3-actual-observation-frames-v1'-or$Observations.evidenceMode-cne$Policy.evidenceMode-or$Observations.phase-cne$Policy.phase-or$Observations.attemptId-cne$Policy.attemptId){throw 'p3_actual_frames_schema'}
 $i=$Observations.frames[-1].identity;$compact=Get-IdentityCompactBinding $i
 if($i.task.returnedSource-cne$Proof.Source-or$compact.runGuid-cne$Proof.InstanceGuid){throw 'p3_actual_activation_binding'}
 $ledgerExpected=[ordered]@{format='p3-run-consumption-v1';evidenceMode=$Policy.evidenceMode;approvalSha256=$Policy.approvalSha256;attemptId=$Policy.attemptId;historicalProductionRuns=2;newRunBudget=1;consumed=$true;source=$Proof.Source;runCalls=[int]$Proof.RunCalls;runGuid=$compact.runGuid;p3Identity=$compact;activationClaimSha256=$Proof.ActivationClaimSha256;runReturnedSha256=$Proof.RunReturnedSha256;activationStateSha256=$Proof.ActivationStateSha256}
 if((ConvertTo-IdentityCanonicalJson $Ledger)-cne(ConvertTo-IdentityCanonicalJson $ledgerExpected)){throw 'p3_actual_ledger_schema'}
 $p3Expected=[ordered]@{
  format='p3-actual-passed-v1';evidenceMode=$Policy.evidenceMode;actual=$true;passed=$true;approvalSha256=$Policy.approvalSha256;attemptId=$Policy.attemptId;taskPath=$Policy.taskPath;oldTaskPath=$Policy.oldTaskPath;registeredFlags=0;registeredNativeCount=1;registeredItems=1;psCount=1;serviceExactCount=1;registeredState=4;serviceState=4;returnedState=4;registeredGuid=$compact.runGuid;serviceGuid=$compact.runGuid;returnedGuid=$compact.runGuid;oldDisabled=$true;oldRegisteredCount=0;oldServiceCount=0;observationWindowMs=([long]$Observations.frames[-1].elapsedMs-[long]$Observations.frames[0].elapsedMs);identity=$compact;receiptSequence=1;runLedgerSha256=$LedgerSha256
  phase=$Policy.phase;returnedSource=$Proof.Source;observationFramesSha256=$FramesSha256;fullIdentitySha256=(Get-P4ByteHash (Get-IdentityCanonicalBytes $i))
 }
 if((ConvertTo-IdentityCanonicalJson $P3)-cne(ConvertTo-IdentityCanonicalJson $p3Expected)){throw 'p3_actual_receipt_schema'}
 return $true
}
