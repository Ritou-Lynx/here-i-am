#requires -Version 5.1
# Dormant shared identity/P3 library. No top-level IO, task Run, mutation or service start.
function Initialize-ReviewedIdentity {
 param([Parameter(Mandatory=$true)]$Lease)
 $null=Get-P4LeaseRecord $Lease
 if(!('ICoreIdentityNative' -as [type])){
  Add-Type -TypeDefinition ([Text.UTF8Encoding]::new($false,$true).GetString($Lease.Bytes('identity_native')))
 }
 if(!(Get-Command Get-TaskInstanceProjection -ErrorAction SilentlyContinue)){
  . ([scriptblock]::Create([Text.UTF8Encoding]::new($false,$true).GetString($Lease.Bytes('task_projection'))))
 }
 if(!(Get-Command Get-TaskCallerContext -ErrorAction SilentlyContinue)){
  . ([scriptblock]::Create([Text.UTF8Encoding]::new($false,$true).GetString($Lease.Bytes('caller_context'))))
 }
 Initialize-TaskInstanceProjection
 $null=Get-TaskCallerContext
}
function Assert-StrictObservedIdentity {
 param([Parameter(Mandatory=$true)]$Identity,[Parameter(Mandatory=$true)]$Policy)
 $i=$Identity;$t=$i.task;$p=$i.processes
 if($Policy.evidenceMode-cnotin@('offline-synthetic','reviewed-live')){throw 'identity_policy_mode'}
 foreach($key in @('newSessionCount','newControlCount','windowsSessionId','hwnd','threadId','launchParentPid','readyPid','mcpCorePid')){
  if($i.$key-isnot[int]-and$i.$key-isnot[long]-and$i.$key-isnot[uint32]){throw 'identity_integer_type'}
 }
 foreach($key in @('registeredFlags','registeredNativeCount','registeredItems','registeredMatchingItems','psCount','psExplicitCount','serviceExactCount','registeredTaskState','oldRegisteredCount','oldServiceCount','registeredState','serviceState','returnedState')){
  if($t.$key-isnot[int]-and$t.$key-isnot[long]){throw 'identity_task_integer_type'}
 }
 foreach($key in @('newEnabled','oldDisabled')){if($t.$key-isnot[bool]){throw 'identity_task_boolean_type'}}
 if($i.format-cne'i-core-observed-identity-v1'-or$i.evidenceMode-cne$Policy.evidenceMode){throw 'identity_mode'}
 foreach($key in @('approvalSha256','manifestSha256','sourceInventorySha256','coreConfigSha256','loginConfigSha256','mcpConfigSha256','automaticConfigSha256','nodeSha256')){
  if($i.$key-cnotmatch'^[a-f0-9]{64}$'-or$i.$key-cne$Policy.$key){throw 'identity_anchor'}
 }
 if($i.sessionId-cnotmatch'^session-[a-f0-9]{32}$'-or$i.controlId-cnotmatch'^control-[a-f0-9]{32}$'-or$i.newSessionCount-ne1-or$i.newControlCount-ne1){throw 'identity_session'}
 foreach($key in @('sessionWindowSha256','launchSha256','readySha256','mcpStartSha256')){
  if($i.$key-cnotmatch'^[a-f0-9]{64}$'){throw 'identity_metadata_hash'}
 }
 foreach($key in @('tokenEqual','readyManifestEqual','mcpManifestEqual','coreConfigEqual','coreReadyBound','readyNodeEqual','authorityNodeEqual','hostSystemPowerShell','hiddenWindow')){
  if($i.$key-isnot[bool]-or$i.$key-ne$true){throw 'identity_metadata_binding'}
 }
 if($i.nodeId-cne$Policy.nodeId-or$i.ownerSid-cne$Policy.ownerSid-or$i.windowsSessionId-ne$Policy.windowsSessionId){throw 'identity_owner'}
 if($t.path-cne$Policy.taskPath-or$t.oldPath-cne$Policy.oldTaskPath-or$t.registeredFlags-ne0-or$t.registeredNativeCount-ne1-or$t.registeredItems-ne1-or$t.registeredMatchingItems-ne1-or$t.psCount-ne1-or$t.psExplicitCount-ne1-or$t.serviceExactCount-ne1-or$t.registeredTaskState-ne4-or$t.newEnabled-ne$true-or$t.oldDisabled-ne$true-or$t.oldRegisteredCount-ne0-or$t.oldServiceCount-ne0){throw 'identity_task_count'}
 $guid=[Guid]::Empty
 if(![Guid]::TryParse([string]$t.registeredGuid,[ref]$guid)-or$guid-eq[Guid]::Empty){throw 'identity_guid'}
 if($t.registeredGuid-ine$t.serviceGuid-or$t.registeredGuid-ine$t.returnedGuid-or$t.registeredState-ne4-or$t.serviceState-ne4-or$t.returnedState-ne4){throw 'identity_instance'}
 if($t.returnedSource-cnotin@('original-run','registered-item-attach')){throw 'identity_returned_source'}
 if($null-eq$Policy.PSObject.Properties['expectedSource']-or$Policy.expectedSource-cnotin@('original-run','registered-item-attach')-or$t.returnedSource-cne$Policy.expectedSource){throw 'identity_returned_source_mismatch'}
 $ids=@()
 foreach($name in @('host','supervisor','core','mcp')){
  $q=$p.$name
  if(($q.pid-isnot[int]-and$q.pid-isnot[long])-or($q.parentPid-isnot[int]-and$q.parentPid-isnot[long])-or($q.sessionId-isnot[int]-and$q.sessionId-isnot[long])){throw 'identity_process_integer_type'}
  if($q.pid-le0-or$q.startedTicks-cnotmatch'^[1-9][0-9]{10,18}$'-or$q.imageSha256-cnotmatch'^[a-f0-9]{64}$'-or$q.ownerSid-cne$Policy.ownerSid-or$q.sessionId-ne$Policy.windowsSessionId-or$q.parentPid-lt0){throw 'identity_process'}
  $ids+=,[int]$q.pid
 }
 if(@($ids|Select-Object -Unique).Count-ne4){throw 'identity_pid_unique'}
 if($p.supervisor.parentPid-ne$p.host.pid-or$p.core.parentPid-ne$p.supervisor.pid-or$p.mcp.parentPid-ne$p.host.pid-or$p.core.imageSha256-cne$Policy.nodeSha256-or$p.mcp.imageSha256-cne$Policy.nodeSha256-or$p.host.imageSha256-cne$Policy.powerShellSha256-or$p.supervisor.imageSha256-cne$Policy.powerShellSha256){throw 'identity_process_tree'}
 if($i.hwnd-le0-or$i.threadId-le0-or$i.enableStartedTicks-cne[string]$Policy.activationUtcTicks-or$i.enableStartedTicks-cnotmatch'^[1-9][0-9]{10,18}$'-or[long]$p.host.startedTicks-lt[long]$i.enableStartedTicks){throw 'identity_activation_time'}
 if($i.launchParentPid-ne$p.supervisor.pid-or$i.launchParentStartedTicks-cne$p.supervisor.startedTicks-or$i.readyPid-ne$p.core.pid-or$i.mcpCorePid-ne$p.core.pid-or$i.mcpStartedTicks-cne$p.mcp.startedTicks){throw 'identity_launch_tree'}
 if(@($i.listeners).Count-ne3){throw 'identity_listener_count'}
 foreach($port in @(47841,47860,47862)){
  $rows=@($i.listeners|Where-Object{$_.port-eq$port})
  $requiredPid=if($port-eq47841){$p.core.pid}else{$p.mcp.pid}
  if($rows.Count-ne1-or$rows[0].address-cne'127.0.0.1'-or$rows[0].pid-ne$requiredPid-or$rows[0].count-ne1){throw 'identity_listener'}
 }
 return $true
}
function Get-ReviewedCoreNodePath {
 param([Parameter(Mandatory=$true)]$Lease)
 $record=Get-P4LeaseRecord $Lease
 $policy=$Lease.ReadJson('identity_policy')
 $release=[string]$policy.releaseDirectory
 if($release-cnotmatch'^[A-Za-z]:\\'-or[IO.Path]::GetFullPath($release)-cne$release){throw 'identity_core_release_path'}
 $expected=Join-Path $release 'runtime\node.exe'
 $artifact=@($record.Binding.artifacts|Where-Object{$_.id-ceq'core_node'})
 if($artifact.Count-ne1-or$artifact[0].role-cne'tool'-or$artifact[0].private-isnot[bool]-or!$artifact[0].private){throw 'identity_core_node_artifact'}
 $path=$Lease.Path('core_node')
 if($path-cne$expected-or$artifact[0].path-cne$expected){throw 'identity_core_node_path'}
 $pin='58e74bf02fc5bbacc41dcb8bef089961cd5bddd37830b87784e4fc624d145d1f'
 if($artifact[0].sha256-cne$pin-or$Lease.Hash('core_node')-cne$pin-or$Lease.Hash('node')-cne$pin){throw 'identity_core_node_hash'}
 return $path
}
function Get-FreshIdentityFrame {
 [CmdletBinding()]param([Parameter(Mandatory=$true)]$Lease,$OriginalRunInstance,$AttachedInstance,[switch]$PermitRecheck)
 $ErrorActionPreference='Stop'
 $record=Get-P4LeaseRecord $Lease
 if($Lease.Mode-cne'reviewed-live'){throw 'identity_live_lease_required'}
 $policy=Get-ReviewedIdentityRuntimePolicy $Lease
 if($policy.format-cne'i-core-identity-policy-v1'-or$policy.evidenceMode-cne'reviewed-live'){throw 'identity_policy'}
 if($PermitRecheck){$policy.phase='permit-recheck';$policy|Add-Member NoteProperty expectedSource 'registered-item-attach' -Force}
 $coreNode=Get-ReviewedCoreNodePath $Lease
 Initialize-ReviewedIdentity $Lease
 $watch=[Diagnostics.Stopwatch]::StartNew()
 $window=$Lease.ReadJson('session_window');$launch=$Lease.ReadJson('launch');$ready=$Lease.ReadJson('ready');$mcp=$Lease.ReadJson('mcp_start')
 $service=New-Object -ComObject Schedule.Service;$service.Connect();$folder=$service.GetFolder('\')
 $new=$folder.GetTask($policy.taskPath.TrimStart('\'))
 $native=[HereIAmTaskInstanceProjection]::Observe($policy.taskPath.TrimStart('\'))
 $old=[HereIAmTaskInstanceProjection]::Observe($policy.oldTaskPath.TrimStart('\'))
 if(!$native.ObservationCompleted-or!$old.ObservationCompleted){throw 'identity_observation_incomplete'}
 if(!$record.ContainsKey('ActivationEvidence')){throw 'identity_enabled_state_missing'}
 $enabled=$record.ActivationEvidence.EnabledState
 $utf8=[Text.UTF8Encoding]::new($false,$true)
 foreach($pair in @(@([string]$new.Xml,'actualRawXmlSha256'),@([string]$new.Definition.XmlText,'actualDefinitionSha256'),@([string]$new.GetSecurityDescriptor(7),'taskSddlSha256'),@([string]$folder.GetSecurityDescriptor(7),'parentSddlSha256'))){
  if((Get-P4ByteHash ($utf8.GetBytes($pair[0])))-cne$enabled.($pair[1])){throw 'identity_task_four_anchor_changed'}
 }
 if([string](Export-ScheduledTask -TaskName ($policy.taskPath.TrimStart('\')) -TaskPath '\')-cne[string]$new.Xml){throw 'identity_actual_export_disagrees'}
 $raw=$new.GetInstances(0);$psCount=$raw.Count;$psExplicit=@($raw|ForEach-Object{$_}).Count
 if($native.RegisteredInstances.MatchingItems.Count-ne1-or$native.ServiceRunningIncludingHidden.MatchingItems.Count-ne1){throw 'identity_task_unique'}
 $registered=$native.RegisteredInstances.MatchingItems[0];$running=$native.ServiceRunningIncludingHidden.MatchingItems[0]
 if($null-ne$OriginalRunInstance-and!$PermitRecheck){
  $returned=[HereIAmTaskInstanceProjection]::ProjectReturnedInstance($OriginalRunInstance);$returnedSource='original-run'
 }else{
  if($null-eq$AttachedInstance){
   if($raw.Count-ne1){throw 'identity_attach_unique_required'}
   $AttachedInstance=$raw.Item(1)
  }
  $returned=[HereIAmTaskInstanceProjection]::ProjectReturnedInstance($AttachedInstance);$returnedSource='registered-item-attach'
 }
 if($returned.Path-cne$policy.taskPath){throw 'identity_returned_path'}
 $processes=[ordered]@{}
 foreach($entry in @(@('host',[int]$window.pid,'powershell'),@('supervisor',[int]$launch.parent_pid,'powershell'),@('core',[int]$ready.pid,'core_node'),@('mcp',[int]$mcp.pid,'node'))){
  $observed=[ICoreIdentityNative]::Process($entry[1]);$image=if($entry[0]-ceq'core'){$coreNode}else{$Lease.Path($entry[2])}
  if($observed.imagePath-ine$image){throw 'identity_image_path'}
  $processes[$entry[0]]=[ordered]@{pid=$observed.pid;parentPid=$observed.parentPid;startedTicks=$observed.startedTicks;imageSha256=$Lease.Hash($entry[2]);ownerSid=$observed.ownerSid;sessionId=$observed.sessionId}
 }
 $listeners=@([ICoreIdentityNative]::Listeners()|Sort-Object port|ForEach-Object{[ordered]@{address=$_.address;port=$_.port;pid=$_.pid;count=1}})
 $i=[ordered]@{
  format='i-core-observed-identity-v1';evidenceMode='reviewed-live';sessionId=[IO.Path]::GetFileName($record.Attachment.SessionPath);controlId=[IO.Path]::GetFileName($record.Attachment.ControlPath);newSessionCount=1;newControlCount=1
  approvalSha256=$Lease.ApprovalSha256;manifestSha256=$policy.manifestSha256;sourceInventorySha256=$policy.sourceInventorySha256;coreConfigSha256=$Lease.Hash('core_config');loginConfigSha256=$Lease.Hash('login_config');mcpConfigSha256=$Lease.Hash('mcp_config');automaticConfigSha256=$Lease.Hash('backup_config');nodeSha256=$Lease.Hash('node')
  sessionWindowSha256=$Lease.Hash('session_window');launchSha256=$Lease.Hash('launch');readySha256=$Lease.Hash('ready');mcpStartSha256=$Lease.Hash('mcp_start')
  tokenEqual=([string]$launch.token-cne''-and$launch.token-ceq$ready.token-and$launch.token-ceq$mcp.core_token)
  readyManifestEqual=($ready.manifest_sha256-ceq$policy.manifestSha256-and$window.manifest_sha256-ceq$policy.manifestSha256)
  mcpManifestEqual=($mcp.manifest_sha256-ceq$policy.manifestSha256);coreConfigEqual=($ready.configuration_sha256-ceq$policy.coreConfigSha256);coreReadyBound=($mcp.core_ready_bound-eq$true-and$window.hook_ready-eq$true)
  readyNodeEqual=($ready.node_sha256-ceq$policy.nodeSha256);authorityNodeEqual=($ready.health.node_id-ceq$policy.nodeId-and$ready.health.role-ceq'authority');nodeId=$ready.health.node_id;ownerSid=$policy.ownerSid;windowsSessionId=$policy.windowsSessionId
  task=[ordered]@{path=$policy.taskPath;oldPath=$policy.oldTaskPath;registeredFlags=0;registeredNativeCount=$native.RegisteredInstances.NativeCount;registeredItems=$native.RegisteredInstances.ExplicitItemsRead;registeredMatchingItems=$native.RegisteredInstances.MatchingItems.Count;psCount=$psCount;psExplicitCount=$psExplicit;serviceExactCount=$native.ServiceRunningIncludingHidden.MatchingItems.Count;newEnabled=$native.Enabled;registeredTaskState=$native.RegisteredState;oldDisabled=(!$old.Enabled);oldRegisteredCount=$old.RegisteredInstances.NativeCount;oldServiceCount=$old.ServiceRunningIncludingHidden.MatchingItems.Count;registeredGuid=$registered.InstanceGuid;serviceGuid=$running.InstanceGuid;returnedGuid=$returned.InstanceGuid;registeredState=$registered.State;serviceState=$running.State;returnedState=$returned.State;returnedSource=$returnedSource}
  processes=$processes;hostSystemPowerShell=($Lease.Path('powershell')-ceq'C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe');hiddenWindow=[HereIAmTaskCallerContext]::HiddenWindow([int]$window.pid,[long]$window.hwnd,[uint32]$window.thread_id);hwnd=[long]$window.hwnd;threadId=[uint32]$window.thread_id;enableStartedTicks=[string]$policy.activationUtcTicks
  launchParentPid=[int]$launch.parent_pid;launchParentStartedTicks=[string]$launch.parent_started_ticks;readyPid=[int]$ready.pid;mcpCorePid=[int]$mcp.core_pid;mcpStartedTicks=[string]$mcp.started_ticks;listeners=$listeners
 }
 # Re-read every lock-backed metadata hash and process identity after all observations.
 foreach($key in @(@('session_window','sessionWindowSha256'),@('launch','launchSha256'),@('ready','readySha256'),@('mcp_start','mcpStartSha256'))){if($Lease.Hash($key[0])-cne$i[$key[1]]){throw 'identity_metadata_changed'}}
 foreach($name in @('host','supervisor','core','mcp')){$again=[ICoreIdentityNative]::Process($processes[$name].pid);if($again.startedTicks-cne$processes[$name].startedTicks-or$again.parentPid-ne$processes[$name].parentPid){throw 'identity_pid_reused'}}
 if($watch.ElapsedMilliseconds-gt2500){throw 'identity_snapshot_timeout'}
 $null=Assert-StrictObservedIdentity $i $policy
 return [ordered]@{format='i-core-fresh-snapshot-v1';observedAt=[DateTime]::UtcNow.ToString('o');elapsedMs=$watch.ElapsedMilliseconds;identity=$i}
}
function Get-IdentityStableProjection($Identity){
 # Every identity field is part of the equality baseline; timing is outside it.
 return ($Identity|ConvertTo-Json -Depth 32 -Compress)
}

function ConvertTo-IdentityCanonicalJson {
 param($Value)
 if($null-eq$Value){return 'null'}
 if($Value-is[bool]){if($Value){return 'true'};return 'false'}
 if($Value-is[string]){return (ConvertTo-Json -InputObject $Value -Compress)}
 if($Value-is[byte]-or$Value-is[int16]-or$Value-is[int32]-or$Value-is[int64]-or$Value-is[uint16]-or$Value-is[uint32]-or$Value-is[uint64]){
  return $Value.ToString([Globalization.CultureInfo]::InvariantCulture)
 }
 if($Value-is[Collections.IDictionary]){
  $items=@();[string[]]$orderedKeys=@($Value.Keys);[Array]::Sort($orderedKeys,[StringComparer]::Ordinal);foreach($key in $orderedKeys){$items+=,((ConvertTo-IdentityCanonicalJson ([string]$key))+':'+(ConvertTo-IdentityCanonicalJson $Value[$key]))}
  return '{'+($items-join',')+'}'
 }
 if($Value-is[Collections.IEnumerable]){
  $items=@();foreach($item in $Value){$items+=,(ConvertTo-IdentityCanonicalJson $item)}
  return '['+($items-join',')+']'
 }
 if($Value-is[pscustomobject]){
  $map=@{};foreach($property in $Value.PSObject.Properties){$map[$property.Name]=$property.Value}
  return ConvertTo-IdentityCanonicalJson $map
 }
 throw 'identity_canonical_type'
}
function Get-IdentityCanonicalBytes($Value){
 return ,([Text.UTF8Encoding]::new($false,$true).GetBytes((ConvertTo-IdentityCanonicalJson $Value)+[char]10))
}
function Get-IdentityCompactBinding($Identity){
 $session=[Guid]::ParseExact($Identity.sessionId.Substring(8),'N').ToString('D')
 $control=[Guid]::ParseExact($Identity.controlId.Substring(8),'N').ToString('D')
 $value=[ordered]@{sessionId=$session;controlId=$control;runGuid=[Guid]::Parse($Identity.task.registeredGuid).ToString('D');host=$null;core=$null;mcp=$null}
 foreach($name in @('host','core','mcp')){$q=$Identity.processes.$name;$value[$name]=[ordered]@{pid=[int]$q.pid;startedTicks=[string]$q.startedTicks}}
 return $value
}
function Assert-IdentityObservationWindow {
 param([Parameter(Mandatory=$true)]$Frames,[Parameter(Mandatory=$true)]$Policy)
 $all=@($Frames)
 if($all.Count-lt7-or$all.Count-gt128){throw 'p3_frame_count'}
 $baseline=$null;$last=-1L
 foreach($frame in $all){
  foreach($v in @($frame.elapsedMs,$frame.snapshotElapsedMs)){if($v-isnot[int]-and$v-isnot[long]){throw 'p3_frame_integer_type'}}
  if($frame.elapsedMs-lt0-or$frame.elapsedMs-le$last-or$frame.snapshotElapsedMs-lt0-or$frame.snapshotElapsedMs-gt2500){throw 'p3_frame_time'}
  if($last-ge0-and$frame.elapsedMs-$last-gt7500){throw 'p3_frame_gap'}
  $null=Assert-StrictObservedIdentity $frame.identity $Policy
  $current=ConvertTo-IdentityCanonicalJson $frame.identity
  if($null-eq$baseline){$baseline=$current}elseif($current-cne$baseline){throw 'p3_identity_changed'}
  $last=[long]$frame.elapsedMs
 }
 if($all[0].elapsedMs-gt2500-or($last-[long]$all[0].elapsedMs)-lt30000-or$last-gt35000){throw 'p3_window_not_complete'}
 return $true
}

function Get-ReviewedIdentityRuntimePolicy {
 param([Parameter(Mandatory=$true)]$Lease)
 $record=Get-P4LeaseRecord $Lease
 $policy=$Lease.ReadJson('identity_policy')
 if($policy.format-cne'i-core-identity-policy-v1'-or$policy.evidenceMode-cne'reviewed-live'){throw 'identity_static_policy'}
 foreach($entry in @(@('manifestSha256','manifest'),@('sourceInventorySha256','source_inventory'),@('coreConfigSha256','core_config'),@('loginConfigSha256','login_config'),@('mcpConfigSha256','mcp_config'),@('automaticConfigSha256','backup_config'),@('nodeSha256','node'),@('powerShellSha256','powershell'))){
  $actual=$Lease.Hash($entry[1])
  if($policy.PSObject.Properties[$entry[0]]-and$null-ne$policy.($entry[0])-and$policy.($entry[0])-cne$actual){throw 'identity_static_hash_binding'}
  $policy|Add-Member NoteProperty $entry[0] $actual -Force
 }
 foreach($entry in @(@('approvalSha256',$Lease.ApprovalSha256),@('planSha256',$record.Policy.planSha256),@('attemptId',$record.Policy.attemptId),@('ownerSid',$record.Owner))){
  if($policy.PSObject.Properties[$entry[0]]-and$null-ne$policy.($entry[0])-and$policy.($entry[0])-cne$entry[1]){throw 'identity_static_authority_binding'}
  $policy|Add-Member NoteProperty $entry[0] $entry[1] -Force
 }
 if($record.ContainsKey('RuntimePhase')){
  if($record.RuntimePhase-cnotin@('initial-activation','login-recovery','host-control-recovery')-or@($policy.allowedPhases)-cnotcontains$record.RuntimePhase){throw 'identity_runtime_phase'}
  $policy.phase=$record.RuntimePhase
 }
 if($record.ContainsKey('ActivationEvidence')){
  $policy|Add-Member NoteProperty expectedSource $record.ActivationEvidence.Source -Force
  $policy|Add-Member NoteProperty instanceGuid $record.ActivationEvidence.InstanceGuid -Force
 }
 if($record.ContainsKey('ActivationStartedTicks')){$policy.activationUtcTicks=[string]$record.ActivationStartedTicks}
 return $policy
}
