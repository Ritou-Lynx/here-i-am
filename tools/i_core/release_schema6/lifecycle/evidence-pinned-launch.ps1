#requires -Version 5.1
# Reviewed dormant functions only; no task, network, service or database calls.
# Bootstrap native source is hashed and evaluated from bytes held by root's
# already-reviewed entrypoint. Get-ReviewedEvidenceLease locks every later input.
function Get-ReviewedEvidenceLease {
 [CmdletBinding()]param([Parameter(Mandatory=$true)][string]$BindingPath,[Parameter(Mandatory=$true)][string]$ExpectedBindingSha256,[Parameter(Mandatory=$true)][string]$ExpectedApprovalSha256,[switch]$Synthetic,[switch]$ForIdentity,[ValidateSet('pre-p3','host-attached')][string]$ObservationPhase,[ValidateSet('initial-activation','login-recovery','host-control-recovery')][string]$LifecyclePhase)
 $ErrorActionPreference='Stop'
 $script:P4BundleRegistry=[P4EvidenceRegistry]::Items
 if(!('P4EvidenceLease' -as [type])){throw 'evidence_native_not_loaded'}
 if($ExpectedBindingSha256-cnotmatch'^[a-f0-9]{64}$' -or $ExpectedApprovalSha256-cnotmatch'^[a-f0-9]{64}$'){throw 'evidence_pin_missing'}
 $owner=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value
 $root='C:\ReviewFixture\candidate\evidence\production-readiness-r01\evidence-contract'
 [P4EvidenceLease]::Plain($BindingPath)
 if(!$BindingPath.StartsWith($root+'\',[StringComparison]::OrdinalIgnoreCase) -or [IO.Path]::GetFileName($BindingPath)-cne'binding.json'){throw 'evidence_binding_path'}
 $all=New-Object 'System.Collections.Generic.List[IDisposable]'
 $map=@{};$metadata=@{};$expected=@{}
 try{
  $bindingLease=[P4EvidenceLease]::new($BindingPath,$owner,$false,$true,1048576);$all.Add($bindingLease)
  if($bindingLease.Hash()-cne$ExpectedBindingSha256){throw 'evidence_binding_hash'}
  $binding=Read-P4StrictJson $bindingLease.Bytes()
  $known=@('format','mode','ownerSid','policy','artifacts','documents','outputRoot','entrypointId','observation','p4Expected','runIdentity')
  if(@($binding.PSObject.Properties.Name|Where-Object{$_ -cnotin $known}).Count-gt0 -or $binding.format-cne'p4-native-binding-v1' -or $binding.ownerSid-cne$owner){throw 'evidence_binding_schema'}
  if(($Synthetic -and $binding.mode-cne'offline-synthetic') -or (!$Synthetic -and $binding.mode-cne'reviewed-live') -or $binding.policy.mode-cne$binding.mode){throw 'evidence_mode_rejected'}
  if(!$Synthetic){
   if(!$LifecyclePhase-or!$ObservationPhase){throw 'evidence_runtime_phase_required'}
   Assert-P4UnfilledStaticApprovalSlots -BindingBytes $bindingLease.Bytes() -BindingPath $BindingPath -ExpectedApprovalSha256 $ExpectedApprovalSha256
   $binding.policy.approvalSha256=$ExpectedApprovalSha256;$binding.policy.bindingSha256=$ExpectedBindingSha256
   # Raw approval slots were validated before any in-memory pin substitution.
   $binding.documents.approval.sha256=$ExpectedApprovalSha256
   if(!$ForIdentity){throw 'evidence_static_requires_identity_promotion'}
  }
  if($binding.policy.approvalSha256-cne$ExpectedApprovalSha256 -or $binding.policy.attemptId-cnotmatch'^[a-f0-9-]{36}$' -or $binding.policy.ownerSid-cne$owner){throw 'evidence_approval_pin'}
  if($binding.outputRoot -cne (Join-Path $root 'runtime-evidence')){throw 'evidence_output_root_rejected'}
  $roles=@('plan','source','manifest','core_config','mcp_config','backup_config','node','tool','native_bridge','owned_helper','powershell','entrypoint','session-window','launch','ready','mcp-start','identity-policy','task_projection','caller_context','identity_library','p3_producer','login_config','identity_policy','p3_frames','full_identity','activation_claim','run_returned')
  if(@($binding.artifacts).Count-lt11 -or @($binding.artifacts).Count-gt256){throw 'evidence_inventory_size'}
  foreach($a in @($binding.artifacts)){
   if((@($a.PSObject.Properties.Name|Sort-Object)-join',')-cne'exportJson,id,maxBytes,path,private,role,sha256' -or $a.id-cnotmatch'^[a-z][a-z0-9_-]{0,47}$' -or $map.ContainsKey($a.id) -or $roles-cnotcontains$a.role -or $a.sha256-cnotmatch'^[a-f0-9]{64}$' -or $a.maxBytes-lt1 -or $a.maxBytes-gt268435456){throw 'evidence_inventory_rejected'}
   [P4EvidenceLease]::Plain($a.path)
   # True runtime content is never read by offline synthetic bundles.
   if($Synthetic -and $a.role -notin @('node','powershell','owned_helper') -and !$a.path.StartsWith($root+'\',[StringComparison]::OrdinalIgnoreCase)){throw 'evidence_synthetic_path_rejected'}
   if($a.path-match'(?i)\.(sqlite|sqlite3|db|aes256gcm)(-|$|\.)'){throw 'evidence_database_path_rejected'}
   if($a.role-eq'node' -and ($a.path-cne'C:\ReviewFixture\node\node.exe' -or $a.sha256-cne'58e74bf02fc5bbacc41dcb8bef089961cd5bddd37830b87784e4fc624d145d1f')){throw 'evidence_node_pin'}
   if($a.role-eq'powershell' -and ($a.path-cne'C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe' -or $a.sha256-cne'8bb6fa8c283b4d92120b1ef249a9b311b0f804d4cabbe9981159976c8be76a5e')){throw 'evidence_powershell_pin'}
   if($a.role-eq'owned_helper'){
    $helperExpected=if($Synthetic){'C:\ReviewFixture\candidate\maintenance-source-r02\tools\i_core\maintenance\owned_artifacts.ps1'}else{
     $ip=@($binding.artifacts|Where-Object{$_.id-ceq'identity_policy'});if($ip.Count-ne1){throw 'evidence_release_policy_missing'}
     $ipl=[P4EvidenceLease]::new($ip[0].path,$owner,$false,$true,262144)
     try{if($ipl.Hash()-cne$ip[0].sha256){throw 'evidence_release_policy_hash'};$ipv=Read-P4StrictJson $ipl.Bytes();[P4EvidenceLease]::Plain($ipv.releaseDirectory);Join-Path $ipv.releaseDirectory 'tools\i_core\maintenance\owned_artifacts.ps1'}finally{$ipl.Dispose()}
    }
    if($a.path-cne$helperExpected-or$a.sha256-cne'f285b79b8d2060391569a41c6a7fea3040a37cd7c73fcceaa39355c279ff8c7c'-or(!$Synthetic-and!$a.private)){throw 'evidence_helper_pin'}
   }
   if($a.private-isnot[bool]-or$a.exportJson-isnot[bool]){throw 'evidence_artifact_types'}
   if(!$Synthetic-and$a.role-notin@('node','powershell')-and!$a.private){throw 'evidence_private_required'}
   if($a.exportJson -and ($a.role -notin @('session-window','launch','ready','mcp-start','identity-policy','identity_policy','p3_frames','full_identity') -or !$a.private -or $a.maxBytes-gt262144)){throw 'evidence_export_rejected'}
   $l=[P4EvidenceLease]::new($a.path,$owner,$false,[bool]$a.private,[long]$a.maxBytes);$all.Add($l)
   if($l.Hash()-cne$a.sha256){throw 'evidence_artifact_hash'}
   $map[$a.id]=$l;$expected[$a.id]=$a.sha256;if($a.exportJson){$metadata[$a.id]=$true}
  }
  foreach($r in @('plan','source','manifest','core_config','mcp_config','backup_config','node','tool','native_bridge','owned_helper','powershell','entrypoint')){
   if(@($binding.artifacts|Where-Object{$_.role-ceq$r}).Count-lt1){throw 'evidence_role_missing'}
  }
  foreach($n in @('approval','p3','ledger','frames','claim','returned','enabled')){
   $d=$binding.documents.$n
   if($ForIdentity -and $n-ne'approval' -and $null-eq$d){continue}
   if((@($d.PSObject.Properties.Name|Sort-Object)-join',')-cne'path,sha256' -or $d.sha256-cnotmatch'^[a-f0-9]{64}$'){throw 'evidence_document_schema'}
   if($Synthetic -and !$d.path.StartsWith($root+'\',[StringComparison]::OrdinalIgnoreCase)){throw 'evidence_synthetic_document_path'}
   $l=[P4EvidenceLease]::new($d.path,$owner,$false,$true,$(if($n-ceq'frames'){1048576}else{262144}));$all.Add($l)
   if($l.Hash()-cne$d.sha256){throw 'evidence_document_hash'}
   $map[$n]=$l;$expected[$n]=$d.sha256;$metadata[$n]=$true
  }
  if($map['approval'].Hash()-cne$ExpectedApprovalSha256 -or (!$ForIdentity -and ($map['p3'].Hash()-cne$binding.policy.p3ReceiptSha256 -or $map['ledger'].Hash()-cne$binding.policy.runLedgerSha256))){throw 'evidence_document_binding'}
  $approval=Read-P4StrictJson $map['approval'].Bytes()
  if((@($approval.PSObject.Properties.Name|Sort-Object)-join',')-cne'approved,attemptId,directHumanApproval,evidenceMode,failureContainment,format,inventorySha256,notAfterUtcMs,notBeforeUtcMs,outputRootId,planSha256,requestWhitelistSha256,runBudget,scope'){throw 'evidence_approval_schema'}
  if($approval.approved-isnot[bool]-or$approval.directHumanApproval-isnot[bool]-or($approval.runBudget-isnot[int]-and$approval.runBudget-isnot[long])-or($approval.notBeforeUtcMs-isnot[long]-and$approval.notBeforeUtcMs-isnot[int])-or($approval.notAfterUtcMs-isnot[long]-and$approval.notAfterUtcMs-isnot[int])){throw 'evidence_approval_types'}
  if($approval.format-cne'p4-direct-approval-v1' -or $approval.approved-ne$true -or $approval.directHumanApproval-ne$true -or $approval.attemptId-cne$binding.policy.attemptId -or $approval.planSha256-cne$binding.policy.planSha256){throw 'evidence_direct_approval_rejected'}
  $now=[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
  if($approval.evidenceMode-cne$binding.mode-or$approval.scope-notin@('p3-p4-bounded-once','task-update-enable-run-attach-p3-p4-normal-close-once')-or$approval.runBudget-ne1-or$approval.failureContainment-cne'disable-and-exact-normal-close'-or$now-lt$approval.notBeforeUtcMs-or$now-gt$approval.notAfterUtcMs-or$approval.notAfterUtcMs-$approval.notBeforeUtcMs-gt86400000){throw 'evidence_approval_scope'}
  foreach($field in @('requestWhitelistSha256','outputRootId','notBeforeUtcMs','notAfterUtcMs')){if($approval.$field-cne$binding.policy.$field){throw 'evidence_approval_policy'}}
  if((Get-P4ByteHash ([Text.Encoding]::UTF8.GetBytes((ConvertTo-P4CanonicalJson $binding.policy.inventory)+[char]10)))-cne$approval.inventorySha256){throw 'evidence_approval_inventory'}
  if(@($binding.artifacts).Count-ne@($binding.policy.inventory).Count){throw 'evidence_inventory_count'}
  foreach($a in @($binding.policy.inventory)){$actual=@($binding.artifacts|Where-Object{$_.id-ceq$a.id});if($actual.Count-ne1-or$actual[0].role-cne$a.role-or$actual[0].sha256-cne$a.sha256-or$actual[0].maxBytes-ne$a.maxBytes){throw 'evidence_inventory_binding'}}
  if(!@($binding.policy.inventory|Where-Object{$_.role-ceq'plan'-and$_.sha256-ceq$approval.planSha256}).Count){throw 'evidence_plan_binding'}
  # Offline approval is a synthetic fixture, never a live permit.
  if($Synthetic -and $binding.policy.mode-cne'offline-synthetic'){throw 'evidence_synthetic_rejected'}
  $key=[Guid]::NewGuid().ToString('D')
  $script:P4BundleRegistry=[P4EvidenceRegistry]::Items
  $lease=[pscustomobject]@{Key=$key;Mode=$binding.mode;BindingSha256=$ExpectedBindingSha256;ApprovalSha256=$ExpectedApprovalSha256;Closed=$false;Readiness=$(if($ForIdentity){'approval-authorized'}else{'p4-inputs-locked'})}
  $record=@{RuntimePhase=$LifecyclePhase;ObservationPhase=$ObservationPhase;LifecyclePhase=$LifecyclePhase;Object=$lease;Binding=$binding;All=$all;Map=$map;Metadata=$metadata;Expected=$expected;Owner=$owner;Policy=$binding.policy;Root=$root;Sync=(New-Object object);Retains=0;CloseRequested=$false}
  $script:P4BundleRegistry[$key]=$record
  $lease|Add-Member ScriptMethod Retain { Retain-P4ReviewedLease -Lease $this }
  $lease|Add-Member ScriptMethod Release { Release-P4ReviewedLease -Lease $this }
  $lease|Add-Member ScriptMethod Hash {param([string]$RoleId) Get-P4ReviewedHash -Lease $this -RoleId $RoleId}
  $lease|Add-Member ScriptMethod Bytes {param([string]$RoleId) Read-P4ReviewedSourceBytes -Lease $this -RoleId $RoleId}
  $lease|Add-Member ScriptMethod DiscoverSession { Discover-P4Session -Lease $this }
  $lease|Add-Member ScriptMethod AttachSession {param([string]$Session,[string]$Control) Attach-P4Session -Lease $this -Session $Session -Control $Control}
  $lease|Add-Member ScriptMethod Path {param([string]$RoleId) Get-P4ReviewedPath -Lease $this -RoleId $RoleId}
  $lease|Add-Member ScriptMethod ReadJson {param([string]$RoleId) Read-P4ReviewedJson -Lease $this -RoleId $RoleId}
  $lease|Add-Member ScriptMethod Dispose {Close-P4ReviewedLease -Lease $this}
  return $lease
 }catch{foreach($l in $all){$l.Dispose()};if($Synthetic){$script:P4LastSyntheticFailure=$_.ToString()};if($_.Exception.Message-cmatch'^evidence_[a-z_]+$'){throw};throw 'evidence_bundle_rejected'}
}
function Get-P4SharedLeaseRegistry {return [P4EvidenceRegistry]::Items}
function Get-P4LeaseRecord($Lease){
 $script:P4BundleRegistry=[P4EvidenceRegistry]::Items
 if($null-eq$Lease -or $null-eq$script:P4BundleRegistry -or !$script:P4BundleRegistry.ContainsKey($Lease.Key)){throw 'evidence_lease_unknown'}
 $r=$script:P4BundleRegistry[$Lease.Key]
 if(![object]::ReferenceEquals($r.Object,$Lease) -or $Lease.Closed){throw 'evidence_lease_unknown'}
 foreach($l in $r.All){$l.Assert()}
 return $r
}
function Get-P4ReviewedHash($Lease,[string]$RoleId){
 $r=Get-P4LeaseRecord $Lease
 if(!$r.Map.ContainsKey($RoleId)){throw 'evidence_role_rejected'}
 $h=$r.Map[$RoleId].Hash();if($h-cne$r.Expected[$RoleId]){throw 'evidence_hash_changed'};return $h
}
function Read-P4ReviewedSourceBytes($Lease,[string]$RoleId){
 $r=Get-P4LeaseRecord $Lease
 $a=@($r.Binding.artifacts|Where-Object{$_.id-ceq$RoleId})
 if($a.Count-ne1-or$a[0].role-notin@('source','tool','native_bridge','owned_helper','entrypoint','task_projection','caller_context','identity_library','p3_producer')){throw 'evidence_source_role_rejected'}
 $b=$r.Map[$RoleId].Bytes();if((Get-P4ByteHash $b)-cne$r.Expected[$RoleId]){throw 'evidence_hash_changed'};return ,$b
}
function Get-P4ReviewedPath($Lease,[string]$RoleId){
 $r=Get-P4LeaseRecord $Lease
 $a=@($r.Binding.artifacts|Where-Object{$_.id-ceq$RoleId})
 if($a.Count-ne1-or$a[0].role-notin@('source','tool','native_bridge','owned_helper','powershell','node','entrypoint','task_projection','caller_context','identity_library','p3_producer')){throw 'evidence_path_role_rejected'}
 $null=Get-P4ReviewedHash $Lease $RoleId;return $a[0].path
}
function Read-P4ReviewedJson($Lease,[string]$RoleId){
 $r=Get-P4LeaseRecord $Lease
 if(!$r.Metadata.ContainsKey($RoleId)){throw 'evidence_body_rejected'}
 $b=$r.Map[$RoleId].Bytes();if((Get-P4ByteHash $b)-cne$r.Expected[$RoleId]){throw 'evidence_hash_changed'}
 return Read-P4StrictJson $b
}
function Retain-P4ReviewedLease($Lease){
 $r=Get-P4LeaseRecord $Lease;[Threading.Monitor]::Enter($r.Sync)
 try{if($r.CloseRequested){throw 'evidence_lease_closing'};$r.Retains++}finally{[Threading.Monitor]::Exit($r.Sync)}
}
function Release-P4ReviewedLease($Lease){
 $r=Get-P4LeaseRecord $Lease;[Threading.Monitor]::Enter($r.Sync)
 try{if($r.Retains-lt1){throw 'evidence_lease_unretained'};$r.Retains--;if($r.Retains-eq0-and$r.CloseRequested){foreach($l in $r.All){$l.Dispose()};$Lease.Closed=$true;[P4EvidenceRegistry]::Items.Remove($Lease.Key)}}finally{[Threading.Monitor]::Exit($r.Sync)}
}
function Close-P4ReviewedLease($Lease){
 $r=Get-P4LeaseRecord $Lease;[Threading.Monitor]::Enter($r.Sync)
 try{$r.CloseRequested=$true;if($r.Retains-eq0){foreach($l in $r.All){$l.Dispose()};$Lease.Closed=$true;[P4EvidenceRegistry]::Items.Remove($Lease.Key)}}finally{[Threading.Monitor]::Exit($r.Sync)}
}
function Invoke-P4PinnedSession {
 [CmdletBinding()]param([Parameter(Mandatory=$true)]$Lease,[switch]$Execute,[int]$TimeoutMs=65000)
 if(!$Execute){return [ordered]@{execution=$false;format='p4-evidence-native-plan-v1'}}
 if($TimeoutMs-lt1000 -or $TimeoutMs-gt120000){throw 'evidence_budget_rejected'}
 $ErrorActionPreference='Stop';if($Lease.Readiness-cne'p4-inputs-locked'){throw 'evidence_p3_required'};$r=Get-P4LeaseRecord $Lease;$b=$r.Binding;$owner=$r.Owner
 $entry=@($b.artifacts|Where-Object{$_.role-ceq'entrypoint'-and$_.id-ceq$b.entrypointId})
 $nodes=@($b.artifacts|Where-Object{$_.role-ceq'node'})
 $helpers=@($b.artifacts|Where-Object{$_.role-ceq'owned_helper'})
 if($entry.Count-ne1-or$nodes.Count-ne1-or$helpers.Count-ne1){throw 'evidence_entry_rejected'}

  # Every relative ESM import is held under the exact filename the Node resolver opens.
  if($Lease.Mode-ceq'reviewed-live'){
   $closure=@{
    'p4_runner'='p4-pinned-entry-r04.mjs'
    'transport-source'='p4-bounded-transport-r05.mjs'
    'verifier-source'='evidence-contract-r08.mjs'
    'transport-endpoints'='transport-endpoints-r04.json'
    'health_policy'='p4-health-policy-dormant-r01.mjs'
    'evidence_context'='evidence-context-r09.mjs'
    'native_bridge'='evidence-parent-bridge-r09.mjs'
   }
   $closureRoot=Join-Path ($Lease.ReadJson('identity_policy').releaseDirectory) 'tools\i_core\maintenance\p4'
   if($b.entrypointId-cne'p4_runner'){throw 'evidence_live_entrypoint'}
   foreach($id in $closure.Keys){
    $a=@($b.artifacts|Where-Object{$_.id-ceq$id})
    if($a.Count-ne1-or$a[0].path-cne(Join-Path $closureRoot $closure[$id])-or!$r.Map.ContainsKey($id)-or$r.Map[$id].Hash()-cne$a[0].sha256){throw 'evidence_import_closure'}
   }
  }

 # These source bytes are from the same denied-write/delete handles already hashed.
 . ([scriptblock]::Create([Text.Encoding]::UTF8.GetString($r.Map[$helpers[0].id].Bytes())))
 Initialize-OwnedArtifactNative;Assert-OwnedArtifactUnelevatedProcess $owner
 $bundle=[ordered]@{approval=$null;p3=$null;ledger=$null;frames=$null;claim=$null;returned=$null;enabled=$null;inventory=@()}
 foreach($n in @('approval','p3','ledger','frames','claim','returned','enabled')){
  $raw=$r.Map[$n].Bytes()
  $bundle[$n]=[ordered]@{bytesBase64=[Convert]::ToBase64String($raw);sha256=$r.Map[$n].Hash();proof=[ordered]@{parentHandlesHeld=$true;fileHandleHeld=$true;noReparse=$true;singleLink=$true;sameIdentity=$true;ownerSid=$owner;privateDacl=$true;protectedDacl=$true;deniedWriteDeleteSharing=$true}}
 }
 foreach($a in @($b.policy.inventory)){
  if(!$r.Map.ContainsKey($a.id) -or $r.Map[$a.id].Hash()-cne$a.sha256){throw 'evidence_policy_inventory'}
  $l=$r.Map[$a.id];$bundle.inventory+=,[ordered]@{id=$a.id;sha256=$l.Hash();byteCount=$l.Length;locked=$true;noReparse=$true;singleLink=($l.LinkCount-eq1);actualLinkCount=[long]$l.LinkCount;sameIdentity=$true;fixedSystemImagePinned=($a.role-ceq'powershell')}
 }
 $bootstrap=[ordered]@{format='p4-locked-bootstrap-v1';policy=$b.policy;bundle=$bundle;bindingRawSha256=$Lease.BindingSha256;expected=$b.p4Expected;endpointAllowlist=$(if($r.Map.ContainsKey('transport-endpoints')){Read-P4StrictJson $r.Map['transport-endpoints'].Bytes()}else{$null})}
 $psi=New-Object Diagnostics.ProcessStartInfo
 $psi.FileName=$nodes[0].path;$psi.Arguments='"'+$entry[0].path+'" --execute-pinned-p4'
 $psi.UseShellExecute=$false;$psi.CreateNoWindow=$true;$psi.RedirectStandardInput=$true;$psi.RedirectStandardOutput=$true;$psi.RedirectStandardError=$true
 $psi.StandardOutputEncoding=New-Object Text.UTF8Encoding($false,$true);$psi.StandardErrorEncoding=New-Object Text.UTF8Encoding($false,$true)
 $psi.EnvironmentVariables.Clear();$psi.EnvironmentVariables['SystemRoot']=$env:SystemRoot;$psi.EnvironmentVariables['WINDIR']=$env:WINDIR
 $psi.WorkingDirectory=$r.Root
 $p=New-Object Diagnostics.Process;$p.StartInfo=$psi
 $Lease.Retain();$started=$false;$sampler=$null;$pump=$null;$clock=[Diagnostics.Stopwatch]::StartNew();$totalBytes=0;$healthResult=$null;$complete=$false;$verified=$false;$context=$null;$rootLease=$null;$attemptLease=$null
 try{
  if($Lease.Mode-ceq'reviewed-live'){
   . ([scriptblock]::Create([Text.UTF8Encoding]::new($false,$true).GetString($Lease.Bytes('identity_sampler'))))
   $sampler=New-ReviewedIdentitySampler -Lease $Lease -PermitRecheck
  }
  if(!$p.Start()){throw 'evidence_child_start_failed'};$started=$true
  $p.StandardInput.WriteLine(($bootstrap|ConvertTo-Json -Depth 40 -Compress));$p.StandardInput.Flush()
  $pump=[P4EvidencePump]::new($p)
  while($clock.ElapsedMilliseconds-lt$TimeoutMs){
   $line=$pump.Next([Math]::Min(1000,[int]($TimeoutMs-$clock.ElapsedMilliseconds)))
   if($null-eq$line){if($p.HasExited-and$pump.OutputEof){break};continue}
   $message=Read-P4StrictJson ([Text.Encoding]::UTF8.GetBytes($line))
   if($message.op-ceq'verified'){
    if($verified-or$message.allowed-ne$true-or$message.identitySha256-cnotmatch'^[a-f0-9]{64}$'-or$message.policySha256-cne(Get-P4ByteHash ([Text.Encoding]::UTF8.GetBytes((ConvertTo-P4CanonicalJson $b.policy)+[char]10)))-or$message.identitySha256-cne(Get-P4ByteHash ([Text.Encoding]::UTF8.GetBytes((ConvertTo-P4CanonicalJson $b.policy.identity)+[char]10)))){throw 'evidence_verified_protocol'}
    # The sole pinned child entrypoint has completed the full JS verifier.
    $verified=$true
    if(!(Test-Path -LiteralPath $b.outputRoot)){New-OwnedArtifactDirectory $b.outputRoot $owner}
    $rootLease=[P4EvidenceLease]::new($b.outputRoot,$owner,$true,$true,0)
    $attemptPath=Get-P4EvidenceAttemptPath -Lease $Lease
    New-OwnedArtifactDirectory $attemptPath $owner
    $attemptLease=[P4EvidenceLease]::new($attemptPath,$owner,$true,$true,0)
    $context=@{Verified=$true;Failed=$false;Ended=$false;Next=0;Previous=$null;Policy=$b.policy;IdentitySha256=$message.identitySha256;Owner=$owner;RootLease=$rootLease;AttemptLease=$attemptLease;AttemptPath=$attemptPath}
    $script:P4IssuedContext=$context
    $p.StandardInput.WriteLine('{"op":"verified-ack","allowed":true}');$p.StandardInput.Flush()
   }elseif($message.op-ceq'observe'){
    if(!$verified-or$message.bindingSha256-cne$b.policy.bindingSha256-or$message.timeoutMs-ne2500){throw 'evidence_observe_rejected'}
    if($null-eq$sampler){throw 'evidence_identity_sampler_missing'}
    $sample=Invoke-ReviewedIdentitySampler -Sampler $sampler
    if(!$sample.ok-or$sample.retained-or$sample.elapsedMs-ge2500){throw 'evidence_identity_snapshot_failed'}
    $snapshot=$sample.frame
    if($snapshot.identity.approvalSha256-cne$Lease.ApprovalSha256){throw 'evidence_snapshot_approval'}
    $snapshot.identity|Add-Member NoteProperty p3Passed $true -Force
    $snapshot.identity|Add-Member NoteProperty p3ReceiptSha256 $r.Policy.p3ReceiptSha256 -Force
    $snapshot.identity|Add-Member NoteProperty approvalSha256 $Lease.ApprovalSha256 -Force
    $reply=[ordered]@{op='observe-ack';snapshot=$snapshot}
    $p.StandardInput.WriteLine(($reply|ConvertTo-Json -Depth 35 -Compress));$p.StandardInput.Flush()
   }elseif($message.op-ceq'write'){
    if(!$verified-or$message.requestId-cnotmatch'^[0-9]{1,3}$'-or$message.bytesBase64.Length-gt45000){throw 'evidence_write_protocol'}
    $raw=[Convert]::FromBase64String($message.bytesBase64)
    $w=Write-P4ReceiptNative -Context $context -Name $message.name -Bytes $raw -ExpectedSha256 $message.sha256
    $reply=[ordered]@{op='write-ack';requestId=$message.requestId;result=$w}
    $p.StandardInput.WriteLine(($reply|ConvertTo-Json -Depth 8 -Compress));$p.StandardInput.Flush()
   }elseif($message.op-ceq'complete'){
    if(!$verified-or!$context.Ended-or$message.completed-ne$true){throw 'evidence_complete_rejected'}
        if($Lease.Mode-ceq'reviewed-live'){
     if((@($message.PSObject.Properties.Name|Sort-Object)-join',')-cne'completed,healthResult,op'){throw 'evidence_complete_schema'}
     $healthResult=Assert-P4SanitizedHealthResult -Value $message.healthResult -BindingSha256 $Lease.BindingSha256
    }
    $complete=$true;break
   }else{throw 'evidence_protocol_rejected'}
  }
  $p.StandardInput.Close()
  $remaining=[Math]::Max(0,[int]($TimeoutMs-$clock.ElapsedMilliseconds))
  if(!$p.WaitForExit($remaining)){throw 'evidence_child_residual'}
  $pump.Finish()
  if(!$complete-or$p.ExitCode-ne0){throw 'evidence_child_incomplete'}
  if($clock.ElapsedMilliseconds-ge$TimeoutMs){throw 'evidence_total_deadline'}
  foreach($l in $r.All){$l.Assert()}
  if($clock.ElapsedMilliseconds-ge$TimeoutMs){throw 'evidence_total_deadline'}
  $finalResult=[ordered]@{format='p4-evidence-native-result-v1';mode=$b.mode;verified=$true;writerCompleted=$true;attemptId=$b.policy.attemptId;finalReceiptSha256=$context.Previous;exitCode=$p.ExitCode;healthResult=$healthResult;backupEvidenceComplete=$false;overallP4Passed=$false}

 }finally{
  if($null-ne$sampler){$samplerState=Complete-ReviewedIdentitySampler $sampler;if($samplerState.retained){$script:P4ResidualSampler=$sampler}}
  if($context){$context.AttemptLease.Dispose();$context.RootLease.Dispose()}else{if($attemptLease){$attemptLease.Dispose()};if($rootLease){$rootLease.Dispose()}};$script:P4IssuedContext=$null
  if($pump){$pump.Dispose()}
  # Never kill an unknown/running child; retain a residual indicator on timeout.
  if($started-and!$p.HasExited){try{$p.StandardInput.Close()}catch{};$null=$p.WaitForExit(1000)}
  if(!$started-or$p.HasExited){$p.Dispose();$Lease.Release()}else{$script:P4ResidualChild=[pscustomobject]@{Process=$p;Lease=$Lease;Pump=$pump;Held=$true}}
 }
 $residualState=Complete-P4ResidualSession
 if($residualState.residual){throw 'evidence_final_residual'}
 if($clock.ElapsedMilliseconds-ge$TimeoutMs){throw 'evidence_total_deadline'}
 return $finalResult
}

function Get-P4Observation($Lease){
 $r=Get-P4LeaseRecord $Lease;$o=$r.Binding.observation
 if($null-eq$o-or$o.attemptId-cne$r.Policy.attemptId){throw 'evidence_observation_rejected'}
 $copy=@{};foreach($p in $o.PSObject.Properties){$copy[$p.Name]=$p.Value}
 if($r.ObservationPhase){if(@($o.allowedPhases)-cnotcontains$r.ObservationPhase){throw 'evidence_observation_phase'};$copy.phase=$r.ObservationPhase}
 if($copy.phase-notin@('pre-p3','host-attached')){throw 'evidence_observation_phase'}
 # controlRoot is not caller-selectable: every control is a direct child of its session.
 if($copy.ContainsKey('controlRoot')){throw 'evidence_legacy_control_root'}
 $o=[pscustomobject]$copy
 [P4EvidenceLease]::Plain($o.sessionRoot)
 if($o.taskPath-cne'\HereIAm-iCoreSchema6-chatgpt-20261009-f90058f2'-or$o.oldTaskPath-cne'\HereIAm-iCoreSchema6-cleanclose-20261008-2c01de5b'-or$o.ownerSid-cne$r.Owner){throw 'evidence_observation_roots'}
 $loginArtifact=@($r.Binding.artifacts|Where-Object{$_.id-ceq'login_config'-and$_.role-ceq'login_config'})
 if($loginArtifact.Count-ne1-or!$r.Map.ContainsKey('login_config')-or$r.Map['login_config'].Hash()-cne$r.Expected['login_config']){throw 'evidence_observation_login'}
 $login=Read-P4StrictJson $r.Map['login_config'].Bytes()
 if($login.control_root-cne$o.sessionRoot){throw 'evidence_observation_login_root'}
 if($Lease.Mode-ceq'offline-synthetic'-and!$o.sessionRoot.StartsWith($r.Root+'\',[StringComparison]::OrdinalIgnoreCase)){throw 'evidence_synthetic_observation'}
 if($o.phase-ceq'pre-p3'){
  if($o.priorSessionNames-isnot[array]-or$o.priorControlNames-isnot[array]){throw 'evidence_discovery_baseline'}
  foreach($name in $o.priorSessionNames){if($name-isnot[string]-or$name-cnotmatch'^session-[a-f0-9]{32}$'){throw 'evidence_discovery_baseline'}}
  foreach($name in $o.priorControlNames){if($name-isnot[string]-or$name-cnotmatch'^control-[a-f0-9]{32}$'){throw 'evidence_discovery_baseline'}}
 }
 return $o
}
function Assert-P4NestedFreshSelection($Observation,[string]$Session,[string]$Control){
 if($Observation.phase-cne'pre-p3'){return}
 $ss=@([IO.Directory]::GetDirectories($Observation.sessionRoot)|Where-Object{[IO.Path]::GetFileName($_)-cnotin@($Observation.priorSessionNames)})
 $cc=@([IO.Directory]::GetDirectories($Session)|Where-Object{[IO.Path]::GetFileName($_)-cnotin@($Observation.priorControlNames)})
 if($ss.Count-ne1-or$cc.Count-ne1-or$ss[0]-cne$Session-or$cc[0]-cne$Control){throw 'evidence_attachment_difference'}
}
function Discover-P4Session($Lease){
 $r=Get-P4LeaseRecord $Lease;$o=Get-P4Observation $Lease
 if($o.phase-cne'pre-p3'){throw 'evidence_discovery_phase'}
 $roots=New-Object 'Collections.Generic.List[IDisposable]'
 try{
  $roots.Add([P4EvidenceLease]::new($o.sessionRoot,$r.Owner,$true,$true,0))
  $sessions=@([IO.Directory]::GetDirectories($o.sessionRoot)|Where-Object{[IO.Path]::GetFileName($_)-cnotin@($o.priorSessionNames)})
  if($sessions.Count-ne1-or[IO.Path]::GetFileName($sessions[0])-cnotmatch'^session-[a-f0-9]{32}$'){throw 'evidence_discovery_ambiguous'}
  $roots.Add([P4EvidenceLease]::new($sessions[0],$r.Owner,$true,$true,0))
  $controls=@([IO.Directory]::GetDirectories($sessions[0])|Where-Object{[IO.Path]::GetFileName($_)-cnotin@($o.priorControlNames)})
  if($controls.Count-ne1-or[IO.Path]::GetFileName($controls[0])-cnotmatch'^control-[a-f0-9]{32}$'){throw 'evidence_discovery_ambiguous'}
  $roots.Add([P4EvidenceLease]::new($controls[0],$r.Owner,$true,$true,0))
  foreach($l in $roots){$l.Assert()}
  return Attach-P4Session -Lease $Lease -Session $sessions[0] -Control $controls[0]
 }finally{foreach($l in $roots){$l.Dispose()}}
}
function Attach-P4Session($Lease,[string]$Session,[string]$Control){
 $r=Get-P4LeaseRecord $Lease;$o=Get-P4Observation $Lease
 if($r.ContainsKey('Attached')){throw 'evidence_attachment_repeat'}
 foreach($p in @($Session,$Control)){[P4EvidenceLease]::Plain($p)}
 if([IO.Path]::GetFileName($Session)-cnotmatch'^session-[a-f0-9]{32}$'-or[IO.Path]::GetFileName($Control)-cnotmatch'^control-[a-f0-9]{32}$'){throw 'evidence_attachment_name'}
 if([IO.Path]::GetDirectoryName($Session)-cne$o.sessionRoot-or[IO.Path]::GetDirectoryName($Control)-cne$Session){throw 'evidence_attachment_escape'}
 $ledger=$null
 if($r.Metadata.ContainsKey($o.runLedgerRole)){$ledger=Read-P4ReviewedJson -Lease $Lease -RoleId $o.runLedgerRole}
 if($null-eq$ledger-and$Lease.Readiness-cne'approval-authorized'){throw 'evidence_attachment_ledger_missing'}
 if($null-ne$ledger){
  if($ledger.attemptId-cne$r.Policy.attemptId-or$ledger.runGuid-cnotmatch'^[a-f0-9-]{36}$'-or$ledger.consumed-ne$true){throw 'evidence_attachment_ledger'}
  if($o.phase-ceq'host-attached'){if($ledger.source-cne'registered-item-attach'-or$ledger.runCalls-ne0){throw 'evidence_attachment_logon_source'}}
  elseif(!(($ledger.source-ceq'original-run'-and$ledger.runCalls-eq1)-or($ledger.source-ceq'registered-item-attach'-and$ledger.runCalls-eq0))){throw 'evidence_attachment_manual_source'}
 }
 $local=New-Object 'System.Collections.Generic.List[IDisposable]';$files=@{}
 try{
  foreach($p in @($o.sessionRoot,$Session,$Control)){$local.Add([P4EvidenceLease]::new($p,$r.Owner,$true,$true,0))}
  Assert-P4NestedFreshSelection $o $Session $Control
  $mapping=@{session_window=(Join-Path $Session 'session-window.json');launch=(Join-Path $Control 'launch.json');ready=(Join-Path $Control 'ready.json');mcp_start=(Join-Path $Control 'mcp-start.json')}
  foreach($id in @('session_window','launch','ready','mcp_start')){
   if($r.Map.ContainsKey($id)){throw 'evidence_attachment_role_conflict'}
   $l=[P4EvidenceLease]::new($mapping[$id],$r.Owner,$false,$true,262144);$local.Add($l);$files[$id]=$l
  }
  $window=Read-P4StrictJson $files.session_window.Bytes()
  $launch=Read-P4StrictJson $files.launch.Bytes();$ready=Read-P4StrictJson $files.ready.Bytes();$mcp=Read-P4StrictJson $files.mcp_start.Bytes()
  if(($null-ne$ledger-and$window.pid-ne$ledger.p3Identity.host.pid)-or$window.hook_ready-ne$true-or$launch.token-cne$ready.token-or$launch.token-cne$mcp.core_token-or$ready.pid-ne$mcp.core_pid){throw 'evidence_attachment_metadata_identity'}
  Assert-P4NestedFreshSelection $o $Session $Control
  foreach($l in $local){$l.Assert()}
  foreach($id in $files.Keys){$r.Map[$id]=$files[$id];$r.Expected[$id]=$files[$id].Hash();$r.Metadata[$id]=$true}
  foreach($l in $local){$r.All.Add($l)}
  $r.Attached=$true;$r.Attachment=@{SessionPath=$Session;ControlPath=$Control;RootLease=$local[0];SessionLease=$local[1];ControlLease=$local[2];Phase=$r.LifecyclePhase;ObservationPhase=$o.phase;IdentityVerified=$false}
  return [ordered]@{sessionDirectory=$Session;controlDirectory=$Control;sessionId=[IO.Path]::GetFileName($Session);controlId=[IO.Path]::GetFileName($Control);metadataLocked=$true;identityVerified=$false;backupPermitIssued=$false}
 }catch{foreach($l in $local){$l.Dispose()};throw 'evidence_attachment_rejected'}
}

function ConvertTo-P4CanonicalJson($Value){
 if($null-eq$Value){return 'null'}
 if($Value-is[string]){return ConvertTo-Json -InputObject $Value -Compress}
 if($Value-is[bool]){if($Value){return 'true'};return 'false'}
 if($Value-is[byte]-or$Value-is[int]-or$Value-is[long]-or$Value-is[double]-or$Value-is[decimal]){if([Math]::Abs([double]$Value)-gt9007199254740991-or[Math]::Truncate([double]$Value)-ne[double]$Value){throw 'evidence_number_rejected'};return $Value.ToString([Globalization.CultureInfo]::InvariantCulture)}
 if($Value-is[System.Collections.IEnumerable]-and$Value-isnot[System.Collections.IDictionary]){return '['+(@($Value|ForEach-Object{ConvertTo-P4CanonicalJson $_})-join',')+']'}
 $names=if($Value-is[System.Collections.IDictionary]){@($Value.Keys)}else{@($Value.PSObject.Properties.Name)}
 [Array]::Sort($names,[StringComparer]::Ordinal)
 return '{'+(@($names|ForEach-Object{(ConvertTo-Json -InputObject ([string]$_) -Compress)+':'+(ConvertTo-P4CanonicalJson $Value.$_)})-join',')+'}'
}

function Promote-P4ReviewedLease {
 [CmdletBinding()]param([Parameter(Mandatory=$true)]$Lease)
 $r=Get-P4LeaseRecord $Lease
 if($Lease.Readiness-cne'approval-authorized'-or!$r.Attached-or$r.ContainsKey('Promoted')){throw 'evidence_promotion_state'}
 $local=New-Object 'Collections.Generic.List[IDisposable]';$docs=@{}
 try{
  foreach($pair in @(@('p3','p3-actual-receipt.json'),@('ledger','p3-run-ledger.json'),@('frames','p3-observation-frames.json'))){
   if($r.Map.ContainsKey($pair[0])){throw 'evidence_dynamic_role_conflict'}
   $l=[P4EvidenceLease]::new((Join-Path $r.Attachment.ControlPath $pair[1]),$r.Owner,$false,$true,1048576);$local.Add($l);$docs[$pair[0]]=$l
  }
  $p3=Read-P4StrictJson $docs.p3.Bytes();$ledger=Read-P4StrictJson $docs.ledger.Bytes();$frames=Read-P4StrictJson $docs.frames.Bytes()
  $claimRoot=$r.Attachment.ControlPath
  if($r.Attachment.Phase-ceq'initial-activation'){
   $ob=Get-P4Observation $Lease;[P4EvidenceLease]::Plain($ob.activationRoot)
   $claimRoot=Join-Path $ob.activationRoot $r.Policy.attemptId
   $local.Add([P4EvidenceLease]::new($ob.activationRoot,$r.Owner,$true,$true,0))
   $local.Add([P4EvidenceLease]::new($claimRoot,$r.Owner,$true,$true,0))
  }
  foreach($pair in @(@('claim','00-run-consumption.json'),@('returned','01-run-returned.json'))){
   $l=[P4EvidenceLease]::new((Join-Path $claimRoot $pair[1]),$r.Owner,$false,$true,262144);$local.Add($l);$docs[$pair[0]]=$l
  }
  $ob=Get-P4Observation $Lease;[P4EvidenceLease]::Plain($ob.activationRoot)
  $enabledPath=Join-Path (Join-Path $ob.activationRoot $r.Policy.attemptId) '02-enabled-state.json'
  $enabledLease=[P4EvidenceLease]::new($enabledPath,$r.Owner,$false,$true,262144);$local.Add($enabledLease);$docs.enabled=$enabledLease
  if($ledger.activationStateSha256-cne$enabledLease.Hash()){throw 'evidence_enabled_binding'}
  if($p3.approvalSha256-cne$Lease.ApprovalSha256-or$p3.attemptId-cne$r.Policy.attemptId-or$p3.actual-ne$true-or$p3.passed-ne$true-or$p3.evidenceMode-cne$Lease.Mode-or$p3.phase-cne$r.Attachment.Phase-or$p3.runLedgerSha256-cne$docs.ledger.Hash()-or$p3.observationFramesSha256-cne$docs.frames.Hash()-or$ledger.activationClaimSha256-cne$docs.claim.Hash()-or$ledger.runReturnedSha256-cne$docs.returned.Hash()){throw 'evidence_dynamic_binding'}
  # The actual P3 producer's strict source is loaded from the existing held bytes.
  . ([scriptblock]::Create([Text.UTF8Encoding]::new($false,$true).GetString($Lease.Bytes('identity_library'))))
  . ([scriptblock]::Create([Text.UTF8Encoding]::new($false,$true).GetString($Lease.Bytes('activation_proof'))))
  . ([scriptblock]::Create([Text.UTF8Encoding]::new($false,$true).GetString($Lease.Bytes('p3_library'))))
  $r.RuntimePhase=$r.Attachment.Phase
  $proof=Open-ReviewedIdentityActivationEvidence -Lease $Lease -Phase $r.Attachment.Phase
  $policy=Get-ReviewedIdentityRuntimePolicy $Lease
  $null=Assert-ReviewedActualP3Documents -P3 $p3 -Ledger $ledger -Observations $frames -Policy $policy -Proof $proof -FramesSha256 $docs.frames.Hash() -LedgerSha256 $docs.ledger.Hash()
  $full=Read-P4StrictJson ([Text.Encoding]::UTF8.GetBytes((ConvertTo-P4CanonicalJson $frames.frames[-1].identity)))
  $compact=Get-IdentityCompactBinding $full
  if((ConvertTo-P4CanonicalJson $compact)-cne(ConvertTo-P4CanonicalJson $p3.identity)-or$p3.fullIdentitySha256-cne(Get-P4ByteHash ([Text.Encoding]::UTF8.GetBytes((ConvertTo-P4CanonicalJson $full)+[char]10)))){throw 'evidence_dynamic_identity'}
  foreach($pair in @(@('session_window','sessionWindowSha256'),@('launch','launchSha256'),@('ready','readySha256'),@('mcp_start','mcpStartSha256'))){if($Lease.Hash($pair[0])-cne$full.($pair[1])){throw 'evidence_dynamic_metadata'}}
  foreach($name in $docs.Keys){$r.Map[$name]=$docs[$name];$r.Metadata[$name]=$true;$r.Expected[$name]=$docs[$name].Hash()}
  foreach($l in $local){$r.All.Add($l)}
  $r.Policy.p3ReceiptSha256=$docs.p3.Hash();$r.Policy.runLedgerSha256=$docs.ledger.Hash();$r.Policy.identity=$compact
  $r.Binding.policy=$r.Policy
  $full.task.returnedSource='registered-item-attach'
  $full|Add-Member NoteProperty p3Passed $true -Force
  $full|Add-Member NoteProperty p3ReceiptSha256 $docs.p3.Hash() -Force
  $r.Binding.p4Expected=[pscustomobject]@{bindingSha256=$Lease.BindingSha256;identity=$full;httpFeatures=$r.Binding.p4Expected.httpFeatures;httpActivity=$r.Binding.p4Expected.httpActivity;recheckPolicyRevision='p4-fresh-registered-attach-v1'}
  $r.Promoted=$true;$Lease.Readiness='p4-inputs-locked'
  return $Lease
 }catch{foreach($l in $local){$l.Dispose()};throw 'evidence_promotion_rejected'}
}

function Complete-P4ResidualSession {
 $childResidual=$false;$samplerResidual=$false
 $cv=Get-Variable P4ResidualChild -Scope Script -ErrorAction SilentlyContinue
 if($null-ne$cv-and$null-ne$cv.Value){
  $res=$cv.Value
  try{
   if(!$res.Process.HasExited){$childResidual=$true}else{
    if($res.Pump){$res.Pump.Finish();$res.Pump.Dispose()}
    $res.Process.Dispose()
    if($res.Held){$res.Lease.Release();$res.Held=$false}
    $script:P4ResidualChild=$null
   }
  }catch{$childResidual=$true}
 }
 $sv=Get-Variable P4ResidualSampler -Scope Script -ErrorAction SilentlyContinue
 if($null-ne$sv-and$null-ne$sv.Value){
  try{
   $state=Complete-ReviewedIdentitySampler -Sampler $sv.Value
   $samplerResidual=[bool]$state.retained
   if(!$samplerResidual){$script:P4ResidualSampler=$null}
  }catch{$samplerResidual=$true}
 }
 return [ordered]@{residual=($childResidual-or$samplerResidual);childResidual=[bool]$childResidual;samplerResidual=[bool]$samplerResidual;locksRetained=($childResidual-or$samplerResidual)}
}

function Assert-P4SanitizedHealthResult {
 param([Parameter(Mandatory=$true)]$Value,[Parameter(Mandatory=$true)][string]$BindingSha256)
 function K($v,[string[]]$required,[string[]]$optional=@()){
  if($null-eq$v-or$v-is[array]){throw 'evidence_health_schema'}
  $names=@($v.PSObject.Properties.Name)
  foreach($key in $required){if($names-cnotcontains$key){throw 'evidence_health_schema'}}
  foreach($key in $names){if($required-cnotcontains$key-and$optional-cnotcontains$key){throw 'evidence_health_schema'}}
 }
 function N($v){if($null-eq$v-or$v-is[bool]-or$v-is[string]-or[double]::IsNaN([double]$v)-or[double]::IsInfinity([double]$v)-or[double]$v-lt0-or[double]$v-gt9007199254740991){throw 'evidence_health_number'}}
 function B($v){if($v-isnot[bool]){throw 'evidence_health_boolean'}}
 $required=@('format','mode','localHealth','publicDiscovery','healthStable','backupEvidenceComplete','overallP4Passed','samples','checks','failure','automaticRestart','automaticClose')
 K $Value $required @('bindingSha256','startedUtcMs','startedMono','completedUtcMs','elapsedMonoMs')
 if([Text.Encoding]::UTF8.GetByteCount((ConvertTo-Json -InputObject $Value -Depth 12 -Compress))-gt24576){throw 'evidence_health_limit'}
 if($Value.format-cne'p4-health-result-v1'-or$Value.mode-cnotin@('reviewed-live','injected')){throw 'evidence_health_schema'}
 foreach($key in @('localHealth','publicDiscovery','healthStable','backupEvidenceComplete','overallP4Passed','automaticRestart','automaticClose')){B $Value.$key}
 foreach($key in @('backupEvidenceComplete','overallP4Passed','automaticRestart','automaticClose')){if($Value.$key-ne$false){throw 'evidence_health_claim'}}
 if($Value.PSObject.Properties.Name-ccontains'bindingSha256'-and$Value.bindingSha256-cne$BindingSha256){throw 'evidence_health_binding'}
 if($Value.samples-isnot[array]-or$Value.checks-isnot[array]-or$Value.samples.Count-gt48-or$Value.checks.Count-gt20){throw 'evidence_health_counts'}
 $codes=@('authority_metadata','authorization_rejected','body_bounds','dependencies_missing','discard_contract','duplicate_header','duplicate_headers','expected_contract_missing','headers_invalid','headers_missing','health_activity_or_features','health_clock','health_core','health_not_authority_ready','health_unreviewed_fields','identity_anchors','identity_binding','identity_chain','identity_changed','identity_file_hash','identity_host','identity_launch_chain','identity_listeners','identity_node','identity_process','identity_process_unique','identity_processes','identity_sample_budget','identity_session','identity_strict_task','identity_task_instance','identity_task_key','invalid_json','monotonic_or_total_budget','phone_auth_boundary','request_timeout','resource_metadata','sample_admission_late','sample_gap','stability_short','unauth_body','unexpected_status_or_headers','dependency_or_transport_failure')
 if($null-ne$Value.failure-and$codes-cnotcontains$Value.failure){throw 'evidence_health_failure_code'}
 $ids=@('core','local/.well-known/oauth-protected-resource','local/.well-known/oauth-protected-resource/mcp','local/.well-known/oauth-authorization-server','local/mcp','phone','public/.well-known/oauth-protected-resource','public/.well-known/oauth-protected-resource/mcp','public/.well-known/oauth-authorization-server','public/mcp')
 $last=-1.0
 foreach($sample in $Value.samples){K $sample @('mono','utcMs','identityUnchanged');N $sample.mono;N $sample.utcMs;if($sample.identityUnchanged-isnot[bool]-or$sample.identityUnchanged-ne$true-or$sample.mono-lt$last){throw 'evidence_health_sample'};$last=$sample.mono}
 $index=0
 foreach($check in $Value.checks){
  K $check @('id','status','passed','bodyDiscarded') @('elapsedMs','failure')
  B $check.passed;B $check.bodyDiscarded
  if($check.id-cne$ids[$index%10]){throw 'evidence_health_check_order'}
  if($null-ne$check.status){N $check.status;if([double]$check.status-ne[Math]::Floor([double]$check.status)-or$check.status-lt200-or$check.status-gt599){throw 'evidence_health_status'}}
  if($check.PSObject.Properties.Name-ccontains'elapsedMs'){N $check.elapsedMs;if($check.elapsedMs-gt2000){throw 'evidence_health_deadline'}}
  if($check.PSObject.Properties.Name-ccontains'failure'){if($codes-cnotcontains$check.failure){throw 'evidence_health_failure_code'}}
  if($check.passed){$targetStatus=if($index%10 -in @(4,5,9)){401}else{200};if($check.PSObject.Properties.Name-ccontains'failure'-or$check.PSObject.Properties.Name-cnotcontains'elapsedMs'-or$check.status-ne$targetStatus-or$check.bodyDiscarded-ne($check.id-ceq'phone')){throw 'evidence_health_passed_check'}}
  $index++
 }
 foreach($key in @('startedUtcMs','startedMono','completedUtcMs','elapsedMonoMs')){if($Value.PSObject.Properties.Name-ccontains$key){N $Value.$key}}
 if($Value.healthStable){
  foreach($key in @('bindingSha256','startedUtcMs','startedMono','completedUtcMs','elapsedMonoMs')){if($Value.PSObject.Properties.Name-cnotcontains$key){throw 'evidence_health_completion'}}
  if($Value.mode-cne'reviewed-live'-or$Value.localHealth-ne$true-or$Value.publicDiscovery-ne$true-or$null-ne$Value.failure-or$Value.checks.Count-ne20-or$Value.samples.Count-ne48-or@($Value.checks|Where-Object{!$_.passed}).Count-ne0-or$Value.elapsedMonoMs-lt30000-or$Value.elapsedMonoMs-gt60000-or$Value.completedUtcMs-lt$Value.startedUtcMs){throw 'evidence_health_completion'}
 }elseif($null-eq$Value.failure){throw 'evidence_health_missing_failure'}
 return $Value
}

function Assert-P4RecoveryNamespace {
 param($Namespace,$Policy)
 $keys='version phase sessionId controlId leaf recoveryPolicySha256 startSha256 permitSha256 firstAttemptId firstAttemptSha256'.Split(' ')
 if((@($Namespace.PSObject.Properties.Name|Sort-Object)-join',')-cne(($keys|Sort-Object)-join',')){throw 'evidence_namespace_schema'}
 if($Namespace.version-cne'recovery-p4-evidence-namespace-v1'-or$Namespace.phase-cnotin@('login-recovery','host-control-recovery')-or$Namespace.sessionId-cnotmatch'^session-[a-f0-9]{32}$'-or$Namespace.controlId-cnotmatch'^control-[a-f0-9]{32}$'-or$Namespace.firstAttemptId-cnotmatch'^[a-f0-9]{32}$'){throw 'evidence_namespace_binding'}
 foreach($k in @('recoveryPolicySha256','startSha256','permitSha256','firstAttemptSha256')){if($Namespace.$k-isnot[string]-or$Namespace.$k-cnotmatch'^[a-f0-9]{64}$'){throw 'evidence_namespace_hash'}}
 $leaf='recovery-p4-v1--'+$Namespace.phase+'--'+$Namespace.sessionId+'--'+$Namespace.controlId
 if($Namespace.leaf-cne$leaf-or$Policy.attemptId-cnotmatch'^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$'){throw 'evidence_namespace_leaf'}
 foreach($k in @('sessionId','controlId')){if([Guid]::ParseExact($Namespace.$k.Split('-')[1],'N').ToString('D')-cne$Policy.identity.$k){throw 'evidence_namespace_identity'}}
 return $leaf
}
function Get-P4EvidenceAttemptPath {
 param([Parameter(Mandatory=$true)]$Lease)
 $r=Get-P4LeaseRecord $Lease;$base=Join-Path $r.Binding.outputRoot $r.Policy.attemptId
 if($r.Policy.format-ceq'p4-evidence-policy-v1'){
  if($r.ContainsKey('Attached')-and$r.Attachment.Phase-cne'initial-activation'){throw 'evidence_recovery_namespace_required'}
  return $base
 }
 if($r.Policy.format-cne'p4-evidence-policy-v2'-or!$r.ContainsKey('RecoveryNamespacePrepared')-or$r.RecoveryNamespacePrepared-ne$true-or!$r.Attached){throw 'evidence_namespace_unissued'}
 $n=$r.Policy.evidenceNamespace;$leaf=Assert-P4RecoveryNamespace $n $r.Policy
 if($n.phase-cne$r.Attachment.Phase-or$n.sessionId-cne[IO.Path]::GetFileName($r.Attachment.SessionPath)-or$n.controlId-cne[IO.Path]::GetFileName($r.Attachment.ControlPath)-or$n.recoveryPolicySha256-cne$Lease.Hash('recovery_policy')){throw 'evidence_namespace_attachment'}
 $r.Attachment.ControlLease.Assert();$r.RecoveryOriginalAttemptLease.Assert()
 return Join-Path $base $leaf
}

function Assert-P4UnfilledStaticApprovalSlots {
 param([Parameter(Mandatory=$true)][byte[]]$BindingBytes,[Parameter(Mandatory=$true)][string]$BindingPath,[Parameter(Mandatory=$true)][string]$ExpectedApprovalSha256)
 if($ExpectedApprovalSha256-cnotmatch'^[a-f0-9]{64}$'){throw 'evidence_static_approval_hash'}
 $binding=Read-P4StrictJson $BindingBytes
 if($null-eq$binding.policy-or$null-eq$binding.documents-or$null-eq$binding.documents.approval){throw 'evidence_static_raw_schema'}
 foreach($field in @('approvalSha256','p3ReceiptSha256','runLedgerSha256','identity','bindingSha256')){if(@($binding.policy.PSObject.Properties.Name)-cnotcontains$field){throw 'evidence_static_raw_missing'}}
 if(@($binding.documents.approval.PSObject.Properties.Name)-cnotcontains'sha256'-or@($binding.documents.approval.PSObject.Properties.Name)-cnotcontains'path'){throw 'evidence_static_raw_missing'}
 if($null-ne$binding.policy.approvalSha256-or$null-ne$binding.policy.p3ReceiptSha256-or$null-ne$binding.policy.runLedgerSha256-or$null-ne$binding.policy.identity-or$null-ne$binding.policy.bindingSha256){throw 'evidence_static_dynamic_fields'}
 if($null-ne$binding.documents.approval.sha256-or$binding.documents.approval.path-cne(Join-Path ([IO.Path]::GetDirectoryName($BindingPath)) 'approval.json')){throw 'evidence_static_approval_path'}
}


function Assert-P4PublicationBoundary {
 param([Parameter(Mandatory=$true)]$Lease,[Parameter(Mandatory=$true)][Diagnostics.Stopwatch]$Clock,[Parameter(Mandatory=$true)][ValidateRange(1,300000)][int]$TimeoutMs,[scriptblock]$AssertBoundary)
 if(!$Clock.IsRunning-or$Clock.ElapsedMilliseconds-ge$TimeoutMs){throw 'evidence_publication_deadline'}
 $r=Get-P4LeaseRecord $Lease;$now=[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
 if($now-lt$r.Policy.notBeforeUtcMs-or$now-gt$r.Policy.notAfterUtcMs){throw 'evidence_publication_approval_window'}
 if($null-ne$AssertBoundary){$null=& $AssertBoundary}
 if(!$Clock.IsRunning-or$Clock.ElapsedMilliseconds-ge$TimeoutMs){throw 'evidence_publication_deadline'}
 $now=[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
 if($now-lt$r.Policy.notBeforeUtcMs-or$now-gt$r.Policy.notAfterUtcMs){throw 'evidence_publication_approval_window'}
}
function Assert-P4PublicationPath {
 param([Parameter(Mandatory=$true)]$Lease,[Parameter(Mandatory=$true)][string]$Path)
 [P4EvidenceLease]::Plain($Path);$r=Get-P4LeaseRecord $Lease
 $parent=[IO.Path]::GetDirectoryName($Path);$name=[IO.Path]::GetFileName($Path)
 if($r.ContainsKey('Attached')-and$r.Attached-and$parent-ceq$r.Attachment.ControlPath){
  $r.Attachment.ControlLease.Assert()
  if($name-cin@('p3-observation-frames.json','p3-run-ledger.json','p3-actual-receipt.json','p3-backup-permit.json','backup-first-attempt.json','recovery-control-transition.json','recovery-p4-start.json','recovery-p4-launch-failure.json','recovery-p4-consumption.json','recovery-p4-completion.json','recovery-p4-close-approved.json','recovery-p4-cleanup-consumption.json','recovery-p4-cleanup-completion.json','recovery-p4-cleanup-close-approved.json','recovery-p4-disable-before.json','recovery-p4-disable-after.json','recovery-p4-cleanup-disable-before.json','recovery-p4-cleanup-disable-after.json','recovery-p4-commit.json','recovery-p4-reject.json','recovery-p4-close-handoff.json','recovery-p4-cleanup-commit.json','recovery-p4-cleanup-reject.json','recovery-p4-cleanup-close-handoff.json')-or$name-cmatch'^backup-[a-f0-9]{32}-(intent|worker|result|commit)\.json$'){return}
 }
 if($name-cin@('00-intent.json','01-result.json','02-commit.json','03-total-result.json','04-total-commit.json','05-total-reject.json','06-total-receiver.json','07-total-receiver-reject.json')){
  if($parent-ceq(Get-P4EvidenceAttemptPath $Lease)){return}
 }
 if($name-cin@('00-run-consumption.json','01-run-returned.json','02-enabled-state.json','03-initial-session-binding.json')){
  $ob=Get-P4Observation $Lease
  if($parent-ceq(Join-Path $ob.activationRoot $r.Policy.attemptId)){return}
 }
 throw 'evidence_publication_path_rejected'
}
function Open-P4PublishedEvidence {
 [CmdletBinding()]param([Parameter(Mandatory=$true)]$Lease,[Parameter(Mandatory=$true)][string]$Path,[Parameter(Mandatory=$true)][Diagnostics.Stopwatch]$Clock,[Parameter(Mandatory=$true)][ValidateRange(1,300000)][int]$TimeoutMs,[Parameter(Mandatory=$true)][ValidateRange(1,1048576)][int]$MaxBytes,[scriptblock]$AssertBoundary,[string]$ExpectedSha256,[scriptblock]$Validate)
 $ErrorActionPreference='Stop'
 if($PSBoundParameters.ContainsKey('ExpectedSha256')-and$ExpectedSha256-cnotmatch'^[a-f0-9]{64}$'){throw 'evidence_publication_expected_hash'}
 Assert-P4PublicationBoundary $Lease $Clock $TimeoutMs $AssertBoundary
 Assert-P4PublicationPath $Lease $Path
 $r=Get-P4LeaseRecord $Lease;$pending=0
 while($true){
  Assert-P4PublicationBoundary $Lease $Clock $TimeoutMs $AssertBoundary
  $held=$null
  try{$held=[P4EvidenceLease]::new($Path,$r.Owner,$false,$true,$MaxBytes)}
  catch{
   $cause=$_.Exception
   while($null-ne$cause-and$cause-isnot[P4EvidenceOpenException]){$cause=$cause.InnerException}
   if($null-eq$cause-or$cause.Directory-or$cause.RequestedPath-cne$Path-or$cause.NativeErrorCode-notin@(2,32)){throw}
   $pending++
   Assert-P4PublicationBoundary $Lease $Clock $TimeoutMs $AssertBoundary
   $remaining=$TimeoutMs-$Clock.ElapsedMilliseconds
   if($remaining-le0){throw 'evidence_publication_deadline'}
   Start-Sleep -Milliseconds ([int][Math]::Min(25,$remaining))
   continue
  }
  # Once open succeeds, every identity, ACL, byte, JSON, hash and schema error is final.
  try{
   Assert-P4PublicationBoundary $Lease $Clock $TimeoutMs $AssertBoundary
   $bytes=$held.Bytes();$hash=Get-P4ByteHash $bytes
   if($PSBoundParameters.ContainsKey('ExpectedSha256')-and$hash-cne$ExpectedSha256){throw 'evidence_publication_hash_rejected'}
   $value=Read-P4StrictJson $bytes
   if($null-ne$Validate){$null=& $Validate $value $hash}
   $held.Assert()
   Assert-P4PublicationBoundary $Lease $Clock $TimeoutMs $AssertBoundary
   return @{Lease=$held;Value=$value;Hash=$hash;Path=$Path;PendingOpenCount=$pending}
  }catch{$held.Dispose();throw}
 }
}
