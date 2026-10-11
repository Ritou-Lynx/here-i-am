#requires -Version 5.1
# Dormant total gate. Only an issued, promoted reviewed-live lease can execute.
function Assert-P4TotalKeys($Value,[string]$Required,[string]$Optional='') {
 if($null-eq$Value-or$Value-is[Array]-or$Value-is[string]){throw 'total_schema_object'}
 $keys=@($Value.PSObject.Properties.Name);$req=@($Required.Split(' ')|Where-Object{$_});$opt=@($Optional.Split(' ')|Where-Object{$_})
 if(@($req|Where-Object{$_-cnotin$keys}).Count-or@($keys|Where-Object{$_-cnotin($req+$opt)}).Count){throw 'total_schema_keys'}
}
function Assert-P4TotalBoolean($Value,[bool]$Expected) {if($Value-isnot[bool]-or$Value-ne$Expected){throw 'total_boolean'}}
function Assert-P4TotalCount($Value,[long]$Min=0,[long]$Max=9007199254740991) {
 if(($Value-isnot[int]-and$Value-isnot[long])-or$Value-lt$Min-or$Value-gt$Max){throw 'total_count'}
}
function Assert-P4TotalNumber($Value,[double]$Min=0,[double]$Max=9007199254740991) {
 if(($Value-isnot[int]-and$Value-isnot[long]-and$Value-isnot[double]-and$Value-isnot[decimal])-or[double]::IsNaN($Value)-or[double]::IsInfinity($Value)-or$Value-lt$Min-or$Value-gt$Max){throw 'total_number'}
}
function Assert-P4TotalHash($Value) {if($Value-isnot[string]-or$Value-cnotmatch'^[a-f0-9]{64}$'){throw 'total_hash'}}
function Assert-P4TotalEqual($Actual,$Expected) {
 if((ConvertTo-P4CanonicalJson $Actual)-cne(ConvertTo-P4CanonicalJson $Expected)){throw 'total_binding'}
}
function Assert-P4TotalHealth($Health,$Policy) {
 Assert-P4TotalKeys $Health 'format mode localHealth publicDiscovery healthStable backupEvidenceComplete overallP4Passed samples checks failure automaticRestart automaticClose bindingSha256 startedUtcMs startedMono completedUtcMs elapsedMonoMs'
 if($Health.format-cne'p4-health-result-v1'-or$Health.mode-cne'reviewed-live'-or$Health.bindingSha256-cne$Policy.bindingSha256-or$null-ne$Health.failure){throw 'total_health_failed'}
 foreach($k in @('localHealth','publicDiscovery','healthStable')){Assert-P4TotalBoolean $Health.$k $true}
 foreach($k in @('backupEvidenceComplete','overallP4Passed','automaticRestart','automaticClose')){Assert-P4TotalBoolean $Health.$k $false}
 Assert-P4TotalNumber $Health.elapsedMonoMs 30000 60000;Assert-P4TotalNumber $Health.startedMono
 foreach($k in @('startedUtcMs','completedUtcMs')){Assert-P4TotalCount $Health.$k $Policy.notBeforeUtcMs $Policy.notAfterUtcMs}
 if($Health.completedUtcMs-lt$Health.startedUtcMs-or@($Health.samples).Count-ne48-or@($Health.checks).Count-ne20){throw 'total_health_window'}
 $ids=@('core','local/.well-known/oauth-protected-resource','local/.well-known/oauth-protected-resource/mcp','local/.well-known/oauth-authorization-server','local/mcp','phone','public/.well-known/oauth-protected-resource','public/.well-known/oauth-protected-resource/mcp','public/.well-known/oauth-authorization-server','public/mcp')
 for($n=0;$n-lt20;$n++){
  $c=$Health.checks[$n];Assert-P4TotalKeys $c 'id status passed bodyDiscarded elapsedMs'
  if($c.id-cne$ids[$n%10]){throw 'total_health_request_order'}
  Assert-P4TotalBoolean $c.passed $true;Assert-P4TotalBoolean $c.bodyDiscarded ($c.id-ceq'phone');Assert-P4TotalNumber $c.elapsedMs 0 2000
  $status=if($c.id-ceq'phone'-or$c.id.EndsWith('/mcp')-and!$c.id.Contains('.well-known')){401}else{200}
  Assert-P4TotalCount $c.status $status $status
 }
 $prior=-1.0
 foreach($s in $Health.samples){
  Assert-P4TotalKeys $s 'mono utcMs identityUnchanged';Assert-P4TotalBoolean $s.identityUnchanged $true
  Assert-P4TotalNumber $s.mono;Assert-P4TotalCount $s.utcMs $Policy.notBeforeUtcMs $Policy.notAfterUtcMs
  if($s.mono-lt$prior){throw 'total_health_sample_order'};$prior=[double]$s.mono
 }
 if($Health.samples[20].mono-ne$Health.startedMono-or$Health.samples[26].mono-$Health.startedMono-lt30000-or$Health.samples[47].mono-$Health.startedMono-gt$Health.elapsedMonoMs){throw 'total_health_sample_window'}
 for($n=21;$n-le26;$n++){if($Health.samples[$n].mono-$Health.samples[$n-1].mono-gt7500){throw 'total_health_sample_gap'}}
}
function Assert-P4TotalHealthChain($Documents,$Hashes,$Policy,$Health,[string]$FinalSha256) {
 $previous=$null;$identityHash=Get-P4ByteHash ([Text.Encoding]::UTF8.GetBytes((ConvertTo-P4CanonicalJson $Policy.identity)+[char]10))
 for($n=0;$n-lt3;$n++){
  $d=$Documents[$n];$receiptFormat='p4-evidence-receipt-v1';$keys='format evidenceMode attemptId sequence phase previousSha256 bindingSha256 approvalSha256 p3ReceiptSha256 runLedgerSha256 utcMs identitySha256 payload'
  if($Policy.format-ceq'p4-evidence-policy-v2'){$keys+=' evidenceNamespace';$receiptFormat='p4-evidence-receipt-v2';Assert-P4TotalEqual $d.evidenceNamespace $Policy.evidenceNamespace}
  Assert-P4TotalKeys $d $keys
  Assert-P4TotalCount $d.sequence $n $n
  if($d.format-cne$receiptFormat-or$d.evidenceMode-cne'reviewed-live'-or$d.attemptId-cne$Policy.attemptId-or$d.phase-cne@('intent','result','commit')[$n]-or$d.previousSha256-cne$previous-or$d.identitySha256-cne$identityHash){throw 'total_health_chain'}
  foreach($k in @('bindingSha256','approvalSha256','p3ReceiptSha256','runLedgerSha256')){Assert-P4TotalHash $d.$k;if($d.$k-cne$Policy.$k){throw 'total_health_chain_binding'}}
  Assert-P4TotalCount $d.utcMs $Policy.notBeforeUtcMs $Policy.notAfterUtcMs
  $p=$d.payload;Assert-P4TotalKeys $p 'healthStable localHealth publicDiscovery backupEvidenceComplete overallP4Passed requestsCompleted sampleCount failureCode containmentRequired'
  foreach($k in @('backupEvidenceComplete','overallP4Passed','containmentRequired')){Assert-P4TotalBoolean $p.$k $false}
  if($p.failureCode-cne'none'){throw 'total_health_chain_failure'}
  foreach($k in @('healthStable','localHealth','publicDiscovery')){Assert-P4TotalBoolean $p.$k ($n-gt0)}
  $requests=if($n-eq0){0}else{20};$samples=if($n-eq0){0}else{48}
  Assert-P4TotalCount $p.requestsCompleted $requests $requests;Assert-P4TotalCount $p.sampleCount $samples $samples
  Assert-P4TotalHash $Hashes[$n];$previous=$Hashes[$n]
 }
 if($previous-cne$FinalSha256){throw 'total_health_final_hash'}
 Assert-P4TotalHealth $Health $Policy
}
function Assert-P4TotalEffects($Original,$Pruned,$Retention,[string]$AcceptanceMode,[int]$ExpectedRetentionDays) {
 Assert-P4TotalKeys $Original 'reportSchema verified status scope production_completeness_not_attested activation_supported mirrored mirrorPending nextDueAt effectEvidence' 'localBackupCreated artifactSha256 files pruned retentionDays crossComponentAtomic'
 if($Original.reportSchema-cne'i-core-automatic-result-v2'-or$Original.scope-cne'inventory_only'-or$Original.status-cnotin@('backed_up','not_due')){throw 'total_backup_status'}
 Assert-P4TotalBoolean $Original.verified $true;Assert-P4TotalBoolean $Original.production_completeness_not_attested $true
 Assert-P4TotalBoolean $Original.activation_supported $false;Assert-P4TotalBoolean $Original.mirrored $true;Assert-P4TotalBoolean $Original.mirrorPending $false
 Assert-P4TotalCount $Original.nextDueAt 1
 Assert-P4TotalKeys $Pruned 'present value knowledge';Assert-P4TotalKeys $Retention 'present value'
 $hasPruned=$null-ne$Original.PSObject.Properties['pruned'];$hasRetention=$null-ne$Original.PSObject.Properties['retentionDays']
 Assert-P4TotalBoolean $Pruned.present $hasPruned;Assert-P4TotalBoolean $Retention.present $hasRetention
 if($hasPruned){Assert-P4TotalCount $Original.pruned;Assert-P4TotalEqual $Pruned.value $Original.pruned;if($Pruned.knowledge-cne'observed'){throw 'total_pruned_knowledge'}}elseif($null-ne$Pruned.value-or$Pruned.knowledge-cne'unknown'){throw 'total_pruned_unknown'}
 if($hasRetention){Assert-P4TotalCount $Original.retentionDays $ExpectedRetentionDays $ExpectedRetentionDays;Assert-P4TotalEqual $Retention.value $Original.retentionDays}elseif($null-ne$Retention.value){throw 'total_retention_unknown'}
 $e=$Original.effectEvidence
 $counts='localRemovedBackupSets mirrorRemovedBackupSets deleteOperationsAttempted deleteOperationsCompleted mirrorAttempted mirrorAlreadyPresent mirrorCopied mirrorPending directoryCreateAttempted directoryCreateCompleted fileCopyAttempted fileCopyCompleted receiptWriteAttempted receiptWriteCompleted localValidatedReceipts mirrorValidatedReceipts'
 Assert-P4TotalKeys $e ('format pruneBranchEntered measurementComplete partial failureStage '+$counts)
 if($e.format-cne'i-core-backup-effects-v1'-or$null-ne$e.failureStage){throw 'total_effect_schema'}
 foreach($k in $counts.Split(' ')){Assert-P4TotalCount $e.$k}
 Assert-P4TotalBoolean $e.measurementComplete $true;Assert-P4TotalBoolean $e.partial $false
 if($e.pruneBranchEntered-isnot[bool]){throw 'total_prune_type'}
 foreach($k in @('deleteOperations','directoryCreate','fileCopy','receiptWrite')){if($e.($k+'Attempted')-ne$e.($k+'Completed')){throw 'total_effect_partial'}}
 if($e.mirrorPending-ne0-or$e.mirrorAttempted-lt1-or$e.mirrorAlreadyPresent+$e.mirrorCopied-ne$e.mirrorAttempted-or$e.mirrorValidatedReceipts-ne$e.mirrorAttempted-or$e.localValidatedReceipts-ne$e.mirrorAttempted){throw 'total_mirror_auth'}
 # The frozen mirror implementation performs two mkdirs, three managed-file copies,
 # and one receipt write per newly copied mirror; preexisting authenticated sets do none.
 if($e.directoryCreateAttempted-ne2*$e.mirrorCopied-or$e.fileCopyAttempted-ne3*$e.mirrorCopied-or$e.receiptWriteAttempted-ne$e.mirrorCopied){throw 'total_mirror_effect_counts'}
 foreach($k in @('deleteOperationsAttempted','deleteOperationsCompleted','localRemovedBackupSets','mirrorRemovedBackupSets')){if($e.$k-ne0){throw 'total_prune_effect_present'}}
 if($Original.status-ceq'backed_up'){
  foreach($k in @('localBackupCreated','artifactSha256','files','pruned','retentionDays','crossComponentAtomic')){if($null-eq$Original.PSObject.Properties[$k]){throw 'total_backed_up_schema'}}
  Assert-P4TotalBoolean $Original.localBackupCreated $true;Assert-P4TotalHash $Original.artifactSha256;Assert-P4TotalCount $Original.files 1;Assert-P4TotalBoolean $Original.crossComponentAtomic $false
  Assert-P4TotalBoolean $e.pruneBranchEntered $true
 }else{
  foreach($k in @('localBackupCreated','artifactSha256','files','pruned','retentionDays','crossComponentAtomic')){if($null-ne$Original.PSObject.Properties[$k]){throw 'total_not_due_schema'}}
  Assert-P4TotalBoolean $e.pruneBranchEntered $false
 }
 switch -CaseSensitive ($AcceptanceMode){
  'original-pruned-observed-zero-v1' {if(!$hasPruned-or$Pruned.knowledge-cne'observed'-or$Original.pruned-ne0-or$Original.status-cne'backed_up'){throw 'total_original_pruned_unknown'}}
  'measured-effects-no-prune-first-attempt-v1' {if($Original.status-cne'not_due'-or$hasPruned-or$Pruned.knowledge-cne'unknown'-or$e.pruneBranchEntered){throw 'total_new_effects_mode'}}
  default {throw 'total_acceptance_mode'}
 }
 return [ordered]@{originalPrunedKnowledge=$Pruned.knowledge;originalPrunedValue=$Pruned.value;newEffectsVerified=$true;acceptanceMode=$AcceptanceMode}
}
function Assert-P4TotalBackupChain($Index,[string]$IndexHash,$Documents,$Hashes,$Permit,[string]$PermitHash,$Expected,[string]$AcceptanceMode,[int]$RetentionDays) {
 Assert-P4TotalKeys $Index 'format firstAttemptId sessionId controlId permitSha256 manifestSha256 approvalSha256'
 if($Index.format-cne'i-core-backup-first-attempt-v1'-or$Index.firstAttemptId-cnotmatch'^[a-f0-9]{32}$'){throw 'total_first_attempt'}
 foreach($k in @('sessionId','controlId','manifestSha256','approvalSha256')){if($Index.$k-cne$Permit.$k){throw 'total_first_binding'}}
 if($Index.permitSha256-cne$PermitHash){throw 'total_first_permit'}
 Assert-P4TotalHash $IndexHash;$previous=$null;$elapsed=-1L;$created=[DateTimeOffset]::MinValue
 for($n=0;$n-lt4;$n++){
  $d=$Documents[$n];Assert-P4TotalKeys $d 'format attemptId firstAttemptId sequence phase createdUtc elapsedMs prevReceiptSha256 data'
  Assert-P4TotalCount $d.sequence ($n+1) ($n+1);Assert-P4TotalCount $d.elapsedMs 0 120000
  $t=[DateTimeOffset]::MinValue
  if($d.createdUtc-isnot[string]-or$d.createdUtc-cnotmatch'Z$'-or![DateTimeOffset]::TryParse($d.createdUtc,[ref]$t)-or$t-lt$created-or$d.elapsedMs-lt$elapsed){throw 'total_backup_clock'}
  if($d.format-cne'i-core-backup-delivery-v1'-or$d.attemptId-cne$Index.firstAttemptId-or$d.firstAttemptId-cne$Index.firstAttemptId-or$d.phase-cne@('intent','worker','result','commit')[$n]-or$d.prevReceiptSha256-cne$previous){throw 'total_backup_chain'}
  Assert-P4TotalHash $Hashes[$n];$previous=$Hashes[$n];$elapsed=$d.elapsedMs;$created=$t
 }
 $i=$Documents[0].data
 Assert-P4TotalKeys $i 'firstAttemptSha256 permitSha256 sessionId controlId manifestSha256 policySha256 bindingSha256 approvalSha256 planSha256 approvedSourceInventorySha256 sourceHashes nodeSha256 coreConfigSha256 automaticConfigSha256 loginConfigSha256 hostProcesses sessionHashes tokenEqual'
 if($i.firstAttemptSha256-cne$IndexHash-or$i.permitSha256-cne$PermitHash){throw 'total_intent_index'}
 foreach($k in @('sessionId','controlId','manifestSha256','approvalSha256','planSha256','nodeSha256','coreConfigSha256','automaticConfigSha256','loginConfigSha256')){if($i.$k-cne$Permit.$k){throw 'total_intent_permit'}}
 if($i.approvedSourceInventorySha256-cne$Permit.sourceInventorySha256-or$i.bindingSha256-cne$Expected.bindingSha256-or$i.policySha256-cne$Expected.backupPolicySha256){throw 'total_intent_source'}
 Assert-P4TotalEqual $i.sourceHashes $Expected.sourceHashes;Assert-P4TotalEqual $i.hostProcesses $Permit.processes
 Assert-P4TotalEqual $i.sessionHashes @($Permit.sessionWindowSha256,$Permit.launchSha256,$Permit.readySha256,$Permit.mcpStartSha256)
 Assert-P4TotalBoolean $i.tokenEqual $true
 $w=$Documents[1].data;$result=$Documents[2].data;$w2=$result.worker
 foreach($x in @($w,$w2)){
  Assert-P4TotalKeys $x 'pid startedTicks ownerSid sessionId imageSha256 assignedToOwnedJob resumed'
  Assert-P4TotalCount $x.pid 1;Assert-P4TotalCount $x.sessionId 0
  if($x.startedTicks-isnot[string]-or$x.startedTicks-cnotmatch'^[1-9][0-9]{10,18}$'-or$x.ownerSid-cne$Expected.ownerSid-or$x.sessionId-ne$Expected.osSessionId-or$x.imageSha256-cne$Expected.powerShellSha256){throw 'total_worker_identity'}
  Assert-P4TotalBoolean $x.assignedToOwnedJob $true
 }
 Assert-P4TotalBoolean $w.resumed $false;Assert-P4TotalBoolean $w2.resumed $true
 foreach($k in @('pid','startedTicks','ownerSid','sessionId','imageSha256','assignedToOwnedJob')){Assert-P4TotalEqual $w.$k $w2.$k}
 Assert-P4TotalKeys $result 'worker stdoutByteCount stdoutSha256 stderrByteCount stderrSha256 stderrCode stdoutEof stderrEof exitCode jobEmpty wrapperSchema wrapperPassed childCaptures originalResult pruned retentionDays crossComponentAtomic activation_supported'
 Assert-P4TotalCount $result.stdoutByteCount 1 65536;Assert-P4TotalHash $result.stdoutSha256;Assert-P4TotalCount $result.stderrByteCount 0 0
 if($result.stderrSha256-cne'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855'-or$null-ne$result.stderrCode){throw 'total_stderr'}
 foreach($k in @('stdoutEof','stderrEof','jobEmpty')){Assert-P4TotalBoolean $result.$k $true}
 foreach($k in @('crossComponentAtomic','activation_supported')){Assert-P4TotalBoolean $result.$k $false}
 Assert-P4TotalCount $result.exitCode 0 0
 if($result.wrapperSchema-cne'i-core-backup-wrapper-result-v3'){throw 'total_wrapper_schema'}
 Assert-P4TotalBoolean $result.wrapperPassed $true
 if($result.childCaptures-isnot[array]-or$result.childCaptures.Count-ne2){throw 'total_child_capture_count'}
 Assert-P4TotalChildCapture $result.childCaptures[0] 'cli-verify' $Expected.sourceHashes.'tools/i_core/release_schema6/cli.mjs'
 Assert-P4TotalChildCapture $result.childCaptures[1] 'key-child' $Expected.sourceHashes.'tools/i_core/release_schema6/backup_key_child.mjs'
 $verdict=Assert-P4TotalEffects $result.originalResult $result.pruned $result.retentionDays $AcceptanceMode $RetentionDays
 $c=$Documents[3].data;Assert-P4TotalKeys $c 'intentSha256 workerSha256 resultSha256 permitSha256 durableReadback detailDeliveryComplete backupEvidenceComplete productionCompletenessNotAttested'
 foreach($k in @('durableReadback','detailDeliveryComplete','productionCompletenessNotAttested')){Assert-P4TotalBoolean $c.$k $true}
 Assert-P4TotalBoolean $c.backupEvidenceComplete $false
 if($c.intentSha256-cne$Hashes[0]-or$c.workerSha256-cne$Hashes[1]-or$c.resultSha256-cne$Hashes[2]-or$c.permitSha256-cne$PermitHash){throw 'total_commit_binding'}
 return $verdict
}
function Invoke-ReviewedP4BackupTotalGate {
 [CmdletBinding()]param([Parameter(Mandatory=$true)]$Lease)
 $ErrorActionPreference='Stop';Set-StrictMode -Version 2
 $r=Get-P4LeaseRecord $Lease
 if($Lease.Mode-cne'reviewed-live'-or$Lease.Readiness-cne'p4-inputs-locked'-or!$r.Attached-or!$r.ContainsKey('ActivationEvidence')-or$r.ContainsKey('TotalGateConsumed')){throw 'total_actual_lease_required'}
 $operationClock=[Diagnostics.Stopwatch]::StartNew();$timer=$null
 $r.TotalGateConsumed=$true
 $held=[Collections.Generic.List[IDisposable]]::new();$health=$null;$backup=$null;$first=$null;$permitHash=$null
 $report=[ordered]@{evidenceNamespace=$(if($r.Policy.format-ceq'p4-evidence-policy-v2'){$r.Policy.evidenceNamespace}else{$null});format='p4-backup-total-result-v3';recordKind='candidate';authoritative=$false;evidenceMode='reviewed-live';attemptId=$r.Policy.attemptId;phase=$r.Attachment.Phase;approvalSha256=$Lease.ApprovalSha256;bindingSha256=$Lease.BindingSha256;planSha256=$r.Policy.planSha256;passed=$false;healthPassed=$false;backupPassed=$false;backupEvidenceComplete=$false;overallP4Passed=$false;originalPrunedKnowledge='unknown';originalPrunedValue=$null;newEffectsVerified=$false;acceptanceMode=$null;code='total_incomplete';retryAllowed=$false;containmentRequired=$true;pendingWorkPreserved=$true;healthResult=$null;healthReceiptHashes=@();firstAttemptSha256=$null;backupReceiptHashes=@();originalBackupResult=$null;effectEvidence=$null}
 $attemptPath=Get-P4EvidenceAttemptPath -Lease $Lease;$outputReady=$false
 try{
  Assert-P4TotalBudget $operationClock $r.Policy
  foreach($id in @('total_gate','p4_total_policy','backup_policy','owned_helper','manifest','source_inventory','login_config','backup_config','node','powershell')){$null=$Lease.Hash($id)}
  $policy=$Lease.ReadJson('p4_total_policy')
  Assert-P4TotalKeys $policy 'format evidenceMode attemptId planSha256 acceptanceMode allowedPhases'
  if($policy.format-cne'p4-backup-total-policy-v1'-or$policy.evidenceMode-cne'reviewed-live'-or$policy.attemptId-cne$r.Policy.attemptId-or$policy.planSha256-cne$r.Policy.planSha256-or$policy.acceptanceMode-cnotin@('original-pruned-observed-zero-v1','measured-effects-no-prune-first-attempt-v1')-or@($policy.allowedPhases).Count-lt1-or@($policy.allowedPhases|Select-Object -Unique).Count-ne@($policy.allowedPhases).Count-or@($policy.allowedPhases|Where-Object{$_-cnotin@('initial-activation','login-recovery','host-control-recovery')}).Count-or$r.Attachment.Phase-cnotin@($policy.allowedPhases)){throw 'total_policy'}
  $report.acceptanceMode=$policy.acceptanceMode
  $approval=Read-P4StrictJson $r.Map['approval'].Bytes()
  $now=[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
  if($approval.scope-cne'task-update-enable-run-attach-p3-p4-normal-close-once'-or$approval.planSha256-cne$policy.planSha256-or$now-lt$approval.notBeforeUtcMs-or$now-gt$approval.notAfterUtcMs){throw 'total_approval'}
  . ([scriptblock]::Create([Text.UTF8Encoding]::new($false,$true).GetString($Lease.Bytes('owned_helper'))))
  Assert-OwnedArtifactUnelevatedProcess $r.Owner
  $ip=Get-ReviewedIdentityRuntimePolicy $Lease
  $frames=$Lease.ReadJson('frames');$p3=$Lease.ReadJson('p3');$ledger=$Lease.ReadJson('ledger')
  $null=Assert-ReviewedActualP3Documents $p3 $ledger $frames $ip $r.ActivationEvidence $Lease.Hash('frames') $Lease.Hash('ledger')
  $full=$frames.frames[-1].identity
  $control=$r.Attachment.ControlPath;$r.Attachment.ControlLease.Assert()
  $pub=Open-P4PublishedEvidence -Lease $Lease -Path (Join-Path $control 'p3-backup-permit.json') -Clock $operationClock -TimeoutMs 185000 -MaxBytes 65536 -AssertBoundary {Assert-P4TotalBudget $operationClock $r.Policy};$permitLease=$pub.Lease;$held.Add($permitLease)
  $permit=$pub.Value;$permitHash=$pub.Hash
  $null=Assert-IdentityPermitBinding $permit $ip $full $Lease.Hash('p3') $Lease.Hash('ledger')
  $login=Read-P4StrictJson (Get-P4TotalLockedBytes -Lease $Lease -RoleId 'login_config');$automatic=Read-P4StrictJson (Get-P4TotalLockedBytes -Lease $Lease -RoleId 'backup_config');$bp=$Lease.ReadJson('backup_policy')
  $backupKeys='format evidenceMode producerSha256 phase sourceInventorySha256 nodeSha256 coreConfigSha256 mcpConfigSha256 automaticConfigSha256'
  if($bp.format-ceq'backup-evidence-policy-v2'){$backupKeys+=' recoveryEntrySha256 recoveryPolicySha256 recoveryCleanupSha256'}
  Assert-P4TotalKeys $bp $backupKeys
  if($bp.format-cnotin@('backup-evidence-policy-v1','backup-evidence-policy-v2')-or$bp.evidenceMode-cne'reviewed-live'-or$login.backup_evidence_policy_path-cne(Get-P4TotalLockedPath -Lease $Lease -RoleId 'backup_policy')-or$login.backup_evidence_policy_sha256-cne$Lease.Hash('backup_policy')){throw 'total_backup_policy'}
  foreach($k in @('sourceInventorySha256','nodeSha256','coreConfigSha256','mcpConfigSha256','automaticConfigSha256')){if($bp.$k-cne$permit.$k){throw 'total_backup_policy_binding'}}
  if($bp.producerSha256-cne$Lease.Hash('p3_producer')){throw 'total_producer_hash'}
  if($r.Attachment.Phase-cne'initial-activation'){if($bp.format-cne'backup-evidence-policy-v2'-or$bp.recoveryEntrySha256-cne$Lease.Hash('recovery_entrypoint')-or$bp.recoveryPolicySha256-cne$Lease.Hash('recovery_policy')-or$bp.recoveryCleanupSha256-cne$Lease.Hash('recovery_cleanup')){throw 'total_recovery_policy'}}
  $retention=30;if($automatic.policy.PSObject.Properties['retentionDays']){$retention=$automatic.policy.retentionDays}
  Assert-P4TotalCount $retention 1 3650
  if($automatic.policy.format-cne'i-core-automatic-backup-v1'-or[string]::IsNullOrWhiteSpace($automatic.policy.mirrorRoot)){throw 'total_mirror_policy'}
  $manifest=Read-P4StrictJson (Get-P4TotalLockedBytes -Lease $Lease -RoleId 'manifest');$sources=[ordered]@{}
  foreach($relative in @('tools/i_core/release_schema6/scheduler_once_schema6.ps1','tools/i_core/release_schema6/backup_bundle_schema6.ps1','tools/i_core/release_schema6/backup_key_child.mjs','tools/i_core/release_schema6/automatic_backup.mjs','tools/i_core/release_schema6/cli.mjs')){
   $entry=@($manifest.files|Where-Object{$_.path-ceq$relative});if($entry.Count-ne1){throw 'total_source_inventory'}
   Assert-P4TotalHash $entry[0].sha256;$sources[$relative]=$entry[0].sha256
   $pin=[P4EvidenceLease]::new((Join-Path $permit.releaseDirectory $relative.Replace('/','\')),$r.Owner,$false,$true,1048576);$held.Add($pin);if($pin.Hash()-cne$entry[0].sha256){throw 'total_source_changed'}
  }
  $expected=[pscustomobject]@{bindingSha256=$Lease.BindingSha256;backupPolicySha256=$Lease.Hash('backup_policy');sourceHashes=[pscustomobject]$sources;ownerSid=$r.Owner;osSessionId=$full.processes.host.sessionId;powerShellSha256=$Lease.Hash('powershell')}
  Assert-P4TotalBudget $operationClock $r.Policy
  Assert-P4TotalControlActive $Lease
  $health=Invoke-P4PinnedSession -Lease $Lease -Execute -TimeoutMs 65000
  Assert-P4TotalBudget $operationClock $r.Policy
  $report.healthResult=$health.healthResult
  $held.Add([P4EvidenceLease]::new($r.Binding.outputRoot,$r.Owner,$true,$true,0));$held.Add([P4EvidenceLease]::new($attemptPath,$r.Owner,$true,$true,0));$outputReady=$true
  if($health.format-cne'p4-evidence-native-result-v1'-or$health.attemptId-cne$r.Policy.attemptId){throw 'total_health_native'}
  Assert-P4TotalBoolean $health.verified $true;Assert-P4TotalBoolean $health.writerCompleted $true;Assert-P4TotalCount $health.exitCode 0 0;Assert-P4TotalBoolean $health.overallP4Passed $false
  $hd=@();$hh=@()
  foreach($name in @('00-intent.json','01-result.json','02-commit.json')){
   $pub=Open-P4PublishedEvidence -Lease $Lease -Path (Join-Path $attemptPath $name) -Clock $operationClock -TimeoutMs 185000 -MaxBytes 32768 -AssertBoundary {Assert-P4TotalBudget $operationClock $r.Policy};$l=$pub.Lease;$held.Add($l);$hd+=,$pub.Value;$hh+=,$pub.Hash;Assert-P4TotalBudget $operationClock $r.Policy
  }
  $report.healthReceiptHashes=$hh
  Assert-P4TotalHealthChain $hd $hh $r.Policy $health.healthResult $health.finalReceiptSha256;$report.healthPassed=$true
  $timer=[Diagnostics.Stopwatch]::StartNew();$firstPath=Join-Path $control 'backup-first-attempt.json'
  $pub=Open-P4PublishedEvidence -Lease $Lease -Path $firstPath -Clock $timer -TimeoutMs 120000 -MaxBytes 65536 -AssertBoundary {Assert-P4TotalBudget $operationClock $r.Policy $timer};$f=$pub.Lease;$held.Add($f);$first=$pub.Value
  Assert-P4TotalBudget $operationClock $r.Policy $timer
  Assert-P4TotalKeys $first 'format firstAttemptId sessionId controlId permitSha256 manifestSha256 approvalSha256'
  if($first.firstAttemptId-cnotmatch'^[a-f0-9]{32}$'){throw 'total_first_attempt'}
  $report.firstAttemptSha256=$f.Hash();$bd=@();$bh=@()
  foreach($phase in @('intent','worker','result','commit')){
   $path=Join-Path $control ('backup-'+$first.firstAttemptId+'-'+$phase+'.json')
   $pub=Open-P4PublishedEvidence -Lease $Lease -Path $path -Clock $timer -TimeoutMs 120000 -MaxBytes 262144 -AssertBoundary {Assert-P4TotalBudget $operationClock $r.Policy $timer};$l=$pub.Lease;$held.Add($l);$bd+=,$pub.Value;$bh+=,$pub.Hash;Assert-P4TotalBudget $operationClock $r.Policy $timer
  }
  Assert-P4TotalBudget $operationClock $r.Policy $timer
  Assert-P4TotalBackupApprovalTimes $bd $r.Policy
  $report.backupReceiptHashes=$bh;$report.originalBackupResult=$bd[2].data.originalResult;$report.effectEvidence=$bd[2].data.originalResult.effectEvidence
  $report.originalPrunedKnowledge=$bd[2].data.pruned.knowledge;$report.originalPrunedValue=$bd[2].data.pruned.value
  $backup=Assert-P4TotalBackupChain $first $f.Hash() $bd $bh $permit $permitHash $expected $policy.acceptanceMode $retention
  foreach($l in $held){$l.Assert()};foreach($l in $r.All){$l.Assert()}
  Assert-P4TotalBudget $operationClock $r.Policy $timer
  Assert-P4TotalControlActive $Lease
  Assert-P4TotalFreshIdentity $Lease $full
  Assert-P4TotalControlActive $Lease
  Assert-P4TotalBudget $operationClock $r.Policy $timer
  $report.backupPassed=$true;$report.backupEvidenceComplete=$true;$report.newEffectsVerified=$backup.newEffectsVerified
  $report.passed=$true;$report.overallP4Passed=$true;$report.containmentRequired=$false;$report.code='total_passed'
 }catch{
  $report.passed=$false;$report.overallP4Passed=$false;$report.backupEvidenceComplete=$false;$report.containmentRequired=$true
  $code=$_.Exception.Message;if($code-cmatch'^total_[a-z_]+$'){$report.code=$code}else{$report.code='total_validation_failed'}
 }finally{
  try{
   if(!$outputReady){throw 'total_output_not_ready'}
   if($report.passed){Assert-P4TotalBudget $operationClock $r.Policy $timer;Assert-P4TotalControlActive $Lease}
   $bytes=ConvertTo-P4TotalReportBytes $report
   $hash=Get-P4ByteHash $bytes;$path=Join-Path $attemptPath '03-total-result.json'
   if($report.passed){Assert-P4TotalBudget $operationClock $r.Policy $timer;Assert-P4TotalControlActive $Lease}
   [OwnedArtifactNative]::Write($path,$r.Owner,$bytes)
   $read=[P4EvidenceLease]::new($path,$r.Owner,$false,$true,1048576)
   try{
    if($read.Hash()-cne$hash-or$read.Length-ne$bytes.Length){throw 'total_report_readback'}
    $null=Read-P4StrictJson $read.Bytes();if((Get-P4ByteHash $read.Bytes())-cne$hash){throw 'total_report_readback'}
    foreach($l in $held){$l.Assert()};$r.Attachment.ControlLease.Assert()
   }finally{$read.Dispose()}
   if($report.passed){Assert-P4TotalBudget $operationClock $r.Policy $timer;Assert-P4TotalControlActive $Lease}
   $report['durableReportSha256']=$hash
   $report['durableReportWritten']=$true
  }catch{
   $report.passed=$false;$report.overallP4Passed=$false;$report.backupEvidenceComplete=$false;$report.containmentRequired=$true;$report.code='total_durable_report_failed'
   $report['durableReportWritten']=$false
  }
  foreach($l in $held){try{$l.Dispose()}catch{$report.passed=$false;$report.overallP4Passed=$false;$report.backupEvidenceComplete=$false;$report.containmentRequired=$true;$report.code='total_release_failed'}}
 }

 $residualState=@{residual=$true};try{$residualState=Complete-P4ResidualSession}catch{}
 if($residualState.residual){$report.passed=$false;$report.overallP4Passed=$false;$report.backupEvidenceComplete=$false;$report.containmentRequired=$true;$report.code='total_final_residual'}
 if($report.passed){try{Assert-P4TotalBudget $operationClock $r.Policy $timer;Assert-P4TotalControlActive $Lease}catch{$report.passed=$false;$report.overallP4Passed=$false;$report.backupEvidenceComplete=$false;$report.containmentRequired=$true;$report.code='total_final_state_failed'}}
 return Complete-P4TotalDisposition $Lease $report $operationClock $timer
}

function Get-P4TotalLockedPath {
 param([Parameter(Mandatory=$true)]$Lease,[Parameter(Mandatory=$true)][string]$RoleId)
 $r=Get-P4LeaseRecord $Lease
 if($RoleId-cnotin@('backup_policy','login_config','backup_config','manifest')-or!$r.Map.ContainsKey($RoleId)){throw 'total_locked_role'}
 $a=@($r.Binding.artifacts|Where-Object{$_.id-ceq$RoleId})
 if($a.Count-ne1-or$a[0].sha256-cne$r.Expected[$RoleId]-or$r.Map[$RoleId].Hash()-cne$a[0].sha256){throw 'total_locked_hash'}
 [P4EvidenceLease]::Plain($a[0].path);$r.Map[$RoleId].Assert()
 return [string]$a[0].path
}
function Get-P4TotalLockedBytes {
 param([Parameter(Mandatory=$true)]$Lease,[Parameter(Mandatory=$true)][string]$RoleId)
 $null=Get-P4TotalLockedPath -Lease $Lease -RoleId $RoleId
 $r=Get-P4LeaseRecord $Lease;$bytes=$r.Map[$RoleId].Bytes()
 if((Get-P4ByteHash $bytes)-cne$r.Expected[$RoleId]){throw 'total_locked_hash'}
 return ,$bytes
}

function ConvertTo-P4TotalReportBytes {
 param([Parameter(Mandatory=$true)]$Value)
 function AssertFinite($Item,[int]$Depth=0) {
  if($Depth-gt40){throw 'total_report_depth'}
  if($null-eq$Item-or$Item-is[string]-or$Item-is[bool]){return}
  if($Item-is[double]-or$Item-is[single]){if([double]::IsNaN($Item)-or[double]::IsInfinity($Item)){throw 'total_report_nonfinite'};return}
  if($Item-is[Collections.IDictionary]){foreach($v in $Item.Values){AssertFinite $v ($Depth+1)};return}
  if($Item-is[Collections.IEnumerable]){foreach($v in $Item){AssertFinite $v ($Depth+1)};return}
  if($Item-is[pscustomobject]){foreach($p in $Item.PSObject.Properties){AssertFinite $p.Value ($Depth+1)}}
 }
 AssertFinite $Value
 $bytes=[Text.UTF8Encoding]::new($false,$true).GetBytes(($Value|ConvertTo-Json -Depth 40 -Compress)+[char]10)
 if($bytes.Length-gt1048576){throw 'total_report_size'}
 $null=Read-P4StrictJson $bytes
 return ,$bytes
}

function Assert-P4TotalApprovalNow($Policy) {
 $now=[DateTimeOffset]::UtcNow.UtcTicks
 $lower=[DateTimeOffset]::FromUnixTimeMilliseconds([long]$Policy.notBeforeUtcMs).UtcTicks;$upper=[DateTimeOffset]::FromUnixTimeMilliseconds([long]$Policy.notAfterUtcMs).UtcTicks
 if($now-lt$lower-or$now-gt$upper){throw 'total_approval_expired'}
}
function Assert-P4TotalBackupApprovalTimes($Documents,$Policy) {
 $prior=-1L
 foreach($d in $Documents){
  if($d.createdUtc-isnot[string]-or$d.createdUtc-cnotmatch'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,7})?Z$'){throw 'total_backup_timestamp'}
  $t=[DateTimeOffset]::MinValue
  if(![DateTimeOffset]::TryParse($d.createdUtc,[Globalization.CultureInfo]::InvariantCulture,[Globalization.DateTimeStyles]::AssumeUniversal,[ref]$t)){throw 'total_backup_timestamp'}
  $ms=$t.UtcTicks
  if($ms-lt[DateTimeOffset]::FromUnixTimeMilliseconds([long]$Policy.notBeforeUtcMs).UtcTicks-or$ms-gt[DateTimeOffset]::FromUnixTimeMilliseconds([long]$Policy.notAfterUtcMs).UtcTicks-or$ms-lt$prior){throw 'total_backup_approval_interval'}
  $prior=$ms
 }
 Assert-P4TotalApprovalNow $Policy
}

function Assert-P4TotalChildCapture($Value,[string]$Role,[string]$ScriptSha256) {
 Assert-P4TotalKeys $Value 'role pid startedTicks imageSha256 scriptSha256 exitCode jobEmpty stdoutEof stderrEof inputComplete inputFailed stdoutByteCount stdoutSha256 stderrByteCount stderrSha256 stderrBase64 stderrDiagnostic'
 if($Value.role-cne$Role-or$Value.scriptSha256-cne$ScriptSha256-or$Value.imageSha256-cne'58e74bf02fc5bbacc41dcb8bef089961cd5bddd37830b87784e4fc624d145d1f'){throw 'total_child_capture_binding'}
 Assert-P4TotalCount $Value.pid 1 4294967295
 if($Value.startedTicks-isnot[string]-or$Value.startedTicks-cnotmatch'^[1-9][0-9]{10,18}$'){throw 'total_child_capture_identity'}
 foreach($k in @('jobEmpty','stdoutEof','stderrEof','inputComplete')){Assert-P4TotalBoolean $Value.$k $true}
 Assert-P4TotalBoolean $Value.inputFailed $false;Assert-P4TotalCount $Value.exitCode 0 0
 Assert-P4TotalCount $Value.stdoutByteCount 0 65536;Assert-P4TotalCount $Value.stderrByteCount 0 4096
 Assert-P4TotalHash $Value.stdoutSha256;Assert-P4TotalHash $Value.stderrSha256
 if($Value.stderrBase64-isnot[string]-or$Value.stderrDiagnostic-cnotin@('empty','sqlite_experimental_warning')){throw 'total_child_capture_diagnostic'}
 $raw=[Convert]::FromBase64String($Value.stderrBase64)
 if([Convert]::ToBase64String($raw)-cne$Value.stderrBase64-or$raw.Length-ne$Value.stderrByteCount-or(Get-P4ByteHash $raw)-cne$Value.stderrSha256){throw 'total_child_capture_raw'}
 $warning='(node:'+[string]$Value.pid+') ExperimentalWarning: SQLite is an experimental feature and might change at any time'+[char]10+'(Use '+[char]96+'node --trace-warnings ...'+[char]96+' to show where the warning was created)'+[char]10
 $expected=[byte[]]@();if($Value.stderrDiagnostic-ceq'sqlite_experimental_warning'){$expected=[Text.UTF8Encoding]::new($false,$true).GetBytes($warning)}
 if([Convert]::ToBase64String($raw)-cne[Convert]::ToBase64String($expected)){throw 'total_child_capture_warning'}
}

function Assert-P4TotalBudget($OperationClock,$Policy,$BackupClock=$null) {
 Assert-P4TotalApprovalNow $Policy
 if($null-eq$OperationClock-or$OperationClock.ElapsedMilliseconds-ge185000){throw 'total_operation_deadline'}
 if($null-ne$BackupClock-and$BackupClock.ElapsedMilliseconds-ge120000){throw 'total_backup_deadline'}
}

function Assert-P4TotalControlActive($Lease) {
 $r=Get-P4LeaseRecord $Lease;$r.Attachment.ControlLease.Assert()
 $paths=@([IO.Directory]::GetFiles($r.Attachment.ControlPath,'backup-failure-*.json'))
 $terminal=Join-Path $r.Attachment.ControlPath 'backup-terminal-requested.json'
 if(Test-Path -LiteralPath $terminal){$paths+=,$terminal}
 foreach($path in $paths){$h=[P4EvidenceLease]::new($path,$r.Owner,$false,$true,262144);try{$h.Assert();$null=Read-P4StrictJson $h.Bytes()}finally{$h.Dispose()};throw 'total_control_terminal'}
 $r.Attachment.ControlLease.Assert()
}
function Assert-P4TotalFreshIdentity($Lease,$ExpectedIdentity) {
 $sampler=$null
 try{
  $sampler=New-ReviewedIdentitySampler -Lease $Lease -PermitRecheck
  $sample=Invoke-ReviewedIdentitySampler -Sampler $sampler
  if(!$sample.ok-or$sample.retained-or$sample.elapsedMs-ge2500){throw 'total_final_identity'}
  # The original P3/ledger are already strictly verified by the total gate.
  # A fresh permit recheck observes the registered instance; it does not rewrite Run history.
  if($ExpectedIdentity.task.returnedSource-cnotin@('original-run','registered-item-attach')){throw 'total_recheck_source'}
  $recheckExpected=Read-P4StrictJson (Get-IdentityCanonicalBytes $ExpectedIdentity)
  $recheckExpected.task.returnedSource='registered-item-attach'
  Assert-P4TotalEqual $sample.frame.identity $recheckExpected
 }finally{
  if($null-ne$sampler){$state=Complete-ReviewedIdentitySampler $sampler;if($state.retained){$script:P4ResidualSampler=$sampler;throw 'total_final_identity_residual'}}
 }
}

function Get-P4FinalTuple($Lease) {
 $r=Get-P4LeaseRecord $Lease
 return [ordered]@{evidenceMode=$Lease.Mode;attemptId=$r.Policy.attemptId;phase=$r.Attachment.Phase;sessionId=[IO.Path]::GetFileName($r.Attachment.SessionPath);controlId=[IO.Path]::GetFileName($r.Attachment.ControlPath);bindingSha256=$Lease.BindingSha256;approvalSha256=$Lease.ApprovalSha256;planSha256=$r.Policy.planSha256;evidenceNamespace=$(if($r.Policy.format-ceq'p4-evidence-policy-v2'){$r.Policy.evidenceNamespace}else{$null})}
}
function Write-P4FinalArtifact($Lease,[ValidateSet('total','recovery','cleanup')][string]$Kind,[string]$Name,$Value) {
 $r=Get-P4LeaseRecord $Lease
 $allowed=if($Kind-ceq'total'){@('04-total-commit.json','05-total-reject.json','06-total-receiver.json','07-total-receiver-reject.json')}elseif($Kind-ceq'recovery'){@('recovery-p4-commit.json','recovery-p4-reject.json','recovery-p4-close-handoff.json')}else{@('recovery-p4-cleanup-commit.json','recovery-p4-cleanup-reject.json','recovery-p4-cleanup-close-handoff.json')}
 if($Name-cnotin$allowed){throw 'final_name'}
 $root=if($Kind-ceq'total'){Get-P4EvidenceAttemptPath -Lease $Lease}else{$r.Attachment.ControlPath}
 $r.Attachment.ControlLease.Assert()
 $bytes=ConvertTo-P4TotalReportBytes $Value;$hash=Get-P4ByteHash $bytes
 $path=Join-Path $root $Name
 [OwnedArtifactNative]::Write($path,$r.Owner,$bytes)
 $l=[P4EvidenceLease]::new($path,$r.Owner,$false,$true,1048576)
 try{if($l.Hash()-cne$hash-or$l.Length-ne$bytes.Length-or(Get-P4ByteHash $l.Bytes())-cne$hash){throw 'final_readback'};$null=Read-P4StrictJson $l.Bytes();$r.Attachment.ControlLease.Assert()}finally{$l.Dispose()}
 return $hash
}
function Write-P4FinalDisposition($Lease,[string]$Kind,[string]$Disposition,[string]$CandidateName,$CandidateHash,$CommitHash,$HandoffHash,[string]$Code,$Clock,[long]$BudgetMs) {
 if($Kind-cnotin@('total','recovery','cleanup')-or$Disposition-cnotin@('commit','reject')-or$Clock-isnot[Diagnostics.Stopwatch]){throw 'final_context'}
 if($Disposition-ceq'commit'-and($null-eq$CandidateHash-or$null-ne$CommitHash-or$null-ne$HandoffHash-or$Code-cne'committed')){throw 'final_commit'}
 foreach($h in @($CandidateHash,$CommitHash,$HandoffHash)){if($null-ne$h){Assert-P4TotalHash $h}}
 $t=Get-P4FinalTuple $Lease
 if($Kind-ceq'cleanup'){$t.evidenceNamespace=$null}
 $d=[ordered]@{format='evidence-final-disposition-v1';kind=$Kind;disposition=$Disposition}
 foreach($k in $t.Keys){$d[$k]=$t[$k]}
 $d.candidateName=$CandidateName;$d.candidateSha256=$CandidateHash;$d.previousCommitSha256=$CommitHash;$d.closeHandoffSha256=$HandoffHash;$d.code=$Code;$d.utcMs=[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds();$d.elapsedMs=[long]$Clock.ElapsedMilliseconds;$d.budgetMs=$BudgetMs;$d.authoritative=$false
 $name=if($Kind-ceq'total'){if($Disposition-ceq'commit'){'04-total-commit.json'}else{'05-total-reject.json'}}else{$(if($Kind-ceq'cleanup'){'recovery-p4-cleanup'}else{'recovery-p4'})+'-'+$Disposition+'.json'}
 return Write-P4FinalArtifact $Lease $Kind $name $d
}
function Assert-P4FinalDisposition($Value,$Lease,[string]$Kind,[string]$Disposition,[string]$CandidateName,$CandidateHash) {
 Assert-P4TotalKeys $Value 'format kind disposition evidenceMode attemptId phase sessionId controlId bindingSha256 approvalSha256 planSha256 evidenceNamespace candidateName candidateSha256 previousCommitSha256 closeHandoffSha256 code utcMs elapsedMs budgetMs authoritative'
 if($Value.format-cne'evidence-final-disposition-v1'-or$Value.kind-cne$Kind-or$Value.disposition-cne$Disposition-or$Value.candidateName-cne$CandidateName-or$Value.candidateSha256-cne$CandidateHash){throw 'final_binding'}
 Assert-P4TotalBoolean $Value.authoritative $false
 $t=Get-P4FinalTuple $Lease;if($Kind-ceq'cleanup'){$t.evidenceNamespace=$null}
 foreach($k in $t.Keys){Assert-P4TotalEqual $Value.$k $t[$k]}
 foreach($h in @($Value.candidateSha256,$Value.previousCommitSha256,$Value.closeHandoffSha256)){if($null-ne$h){Assert-P4TotalHash $h}}
 Assert-P4TotalCount $Value.utcMs;Assert-P4TotalCount $Value.elapsedMs;Assert-P4TotalCount $Value.budgetMs
 if($Value.budgetMs-ne$(if($Kind-ceq'total'){185000}else{300000})){throw 'final_budget'}
 if($Disposition-ceq'commit'){
  $r=Get-P4LeaseRecord $Lease
  if($Value.elapsedMs-ge$Value.budgetMs-or$Value.utcMs-lt$r.Policy.notBeforeUtcMs-or$Value.utcMs-gt$r.Policy.notAfterUtcMs-or$Value.previousCommitSha256-ne$null-or$Value.closeHandoffSha256-ne$null-or$Value.code-cne'committed'){throw 'final_commit'}
 }
}
function Complete-P4TotalDisposition($Lease,$Report,$Clock,$BackupClock) {
 $r=Get-P4LeaseRecord $Lease
 $Report['finalCommitSha256']=$null;$Report['finalRejectSha256']=$null;$Report['finalDisposition']='unknown'
 $candidate=if($Report.Contains('durableReportSha256')){$Report.durableReportSha256}else{$null}
 try{
  if(!$Report.passed){throw 'total_candidate_rejected'}
  Assert-P4TotalBudget $Clock $r.Policy $BackupClock;Assert-P4TotalControlActive $Lease
  $Report.finalCommitSha256=Write-P4FinalDisposition $Lease 'total' 'commit' '03-total-result.json' $candidate $null $null 'committed' $Clock 185000
  Assert-P4TotalBudget $Clock $r.Policy $BackupClock;Assert-P4TotalControlActive $Lease
  $Report.finalDisposition='commit'
 }catch{
  $Report.passed=$false;$Report.overallP4Passed=$false;$Report.backupEvidenceComplete=$false;$Report.containmentRequired=$true
  try{$Report.finalRejectSha256=Write-P4FinalDisposition $Lease 'total' 'reject' '03-total-result.json' $candidate $Report.finalCommitSha256 $null 'total_final_rejected' $Clock 185000;$Report.finalDisposition='reject'}catch{$Report.finalDisposition='unknown'}
 }
 $r.TotalOperationClock=$Clock;$r.TotalBackupClock=$BackupClock;$r.TotalReturnedReport=$Report
 return $Report
}
function Confirm-ReviewedP4TotalDisposition {
 [CmdletBinding()]param([Parameter(Mandatory=$true)]$Lease,[Parameter(Mandatory=$true)]$Result)
 $r=Get-P4LeaseRecord $Lease
 if(!$r.ContainsKey('TotalReturnedReport')-or![object]::ReferenceEquals($Result,$r.TotalReturnedReport)-or$r.ContainsKey('TotalReceiverConsumed')){throw 'total_receiver_context'}
 $r.TotalReceiverConsumed=$true;$root=Get-P4EvidenceAttemptPath $Lease
 $accepted=$false;$status='unknown';$receiverHash=$null;$receiverReject=$null;$held=New-Object 'Collections.Generic.List[IDisposable]'
 $candidate=if($Result.Contains('durableReportSha256')){$Result.durableReportSha256}else{$null}
 try{
  if(!$Result.passed-or$Result.finalDisposition-cne'commit'-or$null-ne$Result.finalRejectSha256-or((Test-Path -LiteralPath (Join-Path $root '05-total-reject.json'))-or(Test-Path -LiteralPath (Join-Path $root '07-total-receiver-reject.json')))){$status='reject';throw 'total_receiver_rejected'}
  $boundary={Assert-P4TotalBudget $r.TotalOperationClock $r.Policy $r.TotalBackupClock;Assert-P4TotalControlActive $Lease}
  & $boundary
  $c=Open-P4PublishedEvidence -Lease $Lease -Path (Join-Path $root '03-total-result.json') -Clock $r.TotalOperationClock -TimeoutMs 185000 -MaxBytes 1048576 -ExpectedSha256 $candidate -AssertBoundary $boundary;$held.Add($c.Lease)
  Assert-P4TotalCandidate $c.Value $Lease
  $d=Open-P4PublishedEvidence -Lease $Lease -Path (Join-Path $root '04-total-commit.json') -Clock $r.TotalOperationClock -TimeoutMs 185000 -MaxBytes 1048576 -ExpectedSha256 $Result.finalCommitSha256 -AssertBoundary $boundary;$held.Add($d.Lease)
  Assert-P4FinalDisposition $d.Value $Lease 'total' 'commit' '03-total-result.json' $candidate
  if((Test-Path -LiteralPath (Join-Path $root '05-total-reject.json'))-or(Test-Path -LiteralPath (Join-Path $root '07-total-receiver-reject.json'))){throw 'total_receiver_veto'}
  foreach($l in $held){$l.Assert()}
  & $boundary;$accepted=$true;$status='commit'
 }catch{$accepted=$false;if($status-cne'reject'){$status='unknown'}}
 finally{foreach($l in $held){try{$l.Dispose()}catch{$accepted=$false;$status='unknown'}}}
 $v=[ordered]@{format='p4-total-receiver-v1'}
 $tuple=Get-P4FinalTuple $Lease;foreach($k in $tuple.Keys){$v[$k]=$tuple[$k]}
 $v.candidateSha256=$candidate;$v.commitSha256=$Result.finalCommitSha256;$v.rejectSha256=$Result.finalRejectSha256;$v.disposition=$status;$v.passed=$accepted;$v.authoritative=$false;$v.utcMs=[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
 try{
  if($accepted){Assert-P4TotalBudget $r.TotalOperationClock $r.Policy $r.TotalBackupClock;Assert-P4TotalControlActive $Lease}
  $receiverHash=Write-P4FinalArtifact $Lease 'total' '06-total-receiver.json' $v
  if($accepted){Assert-P4TotalBudget $r.TotalOperationClock $r.Policy $r.TotalBackupClock;Assert-P4TotalControlActive $Lease;if((Test-Path -LiteralPath (Join-Path $root '05-total-reject.json'))-or(Test-Path -LiteralPath (Join-Path $root '07-total-receiver-reject.json'))){throw 'total_receiver_veto'}}
 }catch{
  $accepted=$false;$status='unknown';$v.passed=$false;$v.disposition='reject';$v.utcMs=[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
  try{$receiverReject=Write-P4FinalArtifact $Lease 'total' '07-total-receiver-reject.json' $v;$status='reject'}catch{}
 }
 return [ordered]@{format='p4-total-receiver-result-v1';passed=$accepted;disposition=$status;receiverSha256=$receiverHash;receiverRejectSha256=$receiverReject;candidateSha256=$candidate;commitSha256=$Result.finalCommitSha256;rejectSha256=$Result.finalRejectSha256;authoritative=$false}
}

function Assert-P4TotalCandidate($Value,$Lease) {
 Assert-P4TotalKeys $Value 'evidenceNamespace format evidenceMode attemptId phase approvalSha256 bindingSha256 planSha256 passed healthPassed backupPassed backupEvidenceComplete overallP4Passed originalPrunedKnowledge originalPrunedValue newEffectsVerified acceptanceMode code retryAllowed containmentRequired pendingWorkPreserved healthResult healthReceiptHashes firstAttemptSha256 backupReceiptHashes originalBackupResult effectEvidence recordKind authoritative'
 if($Value.format-cne'p4-backup-total-result-v3'-or$Value.recordKind-cne'candidate'-or$Value.code-cne'total_passed'){throw 'total_candidate_schema'}
 $tuple=Get-P4FinalTuple $Lease
 foreach($key in @('evidenceNamespace','evidenceMode','attemptId','phase','approvalSha256','bindingSha256','planSha256')){Assert-P4TotalEqual $Value.$key $tuple[$key]}
 foreach($key in @('passed','healthPassed','backupPassed','backupEvidenceComplete','overallP4Passed','newEffectsVerified','pendingWorkPreserved')){Assert-P4TotalBoolean $Value.$key $true}
 foreach($key in @('authoritative','retryAllowed','containmentRequired')){Assert-P4TotalBoolean $Value.$key $false}
 if($Value.acceptanceMode-cnotin@('original-pruned-observed-zero-v1','measured-effects-no-prune-first-attempt-v1')){throw 'total_candidate_mode'}
 Assert-P4TotalHash $Value.firstAttemptSha256
 if($Value.healthReceiptHashes-isnot[array]-or$Value.healthReceiptHashes.Count-ne3-or$Value.backupReceiptHashes-isnot[array]-or$Value.backupReceiptHashes.Count-ne4){throw 'total_candidate_hashes'}
 foreach($hash in @($Value.healthReceiptHashes)+@($Value.backupReceiptHashes)){Assert-P4TotalHash $hash}
 # The exact bytes are additionally pinned to the report produced by the same once-only Invoke.
}
