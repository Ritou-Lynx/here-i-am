# Parameterized, source-reviewed freeze. Does not migrate, replace or start a candidate.
# Windows PowerShell 5.1. All deployment bindings come from the pinned private JSON.
[CmdletBinding()]
param(
 [Parameter(Mandatory=$true)][string]$ConfigPath,
 [Parameter(Mandatory=$true)][ValidatePattern('^[a-f0-9]{64}$')][string]$ExpectedConfigSha256,
 [Parameter(Mandatory=$true)][ValidatePattern('^[A-Za-z0-9][A-Za-z0-9_-]{7,79}$')][string]$WindowId,
 [Parameter(Mandatory=$true)][switch]$Execute
)
$ErrorActionPreference='Stop'
Set-StrictMode -Version 2
$env:PSModulePath=Join-Path $PSHOME 'Modules'
$stage='preflight';$started=[DateTime]::UtcNow;$clock=[Diagnostics.Stopwatch]::StartNew()
$script:drift=$false;$script:changed=$false;$script:stopped=@{};$script:originals=@{}
$script:bindings=@{};$script:proofFiles=@();$script:journal=$null;$script:receiptSeq=0
$script:rawFrozen=@();$script:initialDbIdentity=$null;$script:externalInitial=@()
$script:leases=@();$script:window=$null;$script:validatorMayRead=$false;$script:validatorTree=@()
function Fail([string]$Code,[switch]$Drift){if($Drift){$script:drift=$true};throw [InvalidOperationException]::new($Code)}
function Stage([string]$Name){$script:stage=$Name;[Console]::Out.WriteLine('stage='+$Name+' elapsed_ms='+$clock.ElapsedMilliseconds)}
function XmlHash([string]$Text){$sha=[Security.Cryptography.SHA256]::Create();try{return ([BitConverter]::ToString($sha.ComputeHash([Text.UTF8Encoding]::new($false).GetBytes($Text)))).Replace('-','').ToLowerInvariant()}finally{$sha.Dispose()}}
function Hash([string]$Path){return (Get-FileHash -LiteralPath $Path -Algorithm SHA256 -ErrorAction Stop).Hash.ToLowerInvariant()}
function Plain([string]$Path){
 if(-not [IO.Path]::IsPathRooted($Path)-or [IO.Path]::GetFullPath($Path)-cne $Path){Fail 'noncanonical_path'}
 $c=$Path;while($c){$item=Get-Item -LiteralPath $c -Force -ErrorAction Stop;if(($item.Attributes-band [IO.FileAttributes]::ReparsePoint)-ne 0){Fail 'reparse_path' -Drift};$p=[IO.Directory]::GetParent($c);if($p){$c=$p.FullName}else{$c=$null}}
}
function Private([string]$Path,[switch]$Root){
 Plain $Path;$a=Get-Acl -LiteralPath $Path
 if($a.GetOwner([Security.Principal.SecurityIdentifier]).Value-ne $owner){Fail 'private_owner'}
 if($Root-and -not $a.AreAccessRulesProtected){Fail 'private_root'}
 $own=$false;foreach($r in $a.GetAccessRules($true,$true,[Security.Principal.SecurityIdentifier])){
  if($r.AccessControlType-eq 'Allow'){
   if($r.IdentityReference.Value-notin @($owner,'S-1-5-18','S-1-5-32-544')){Fail 'private_acl'}
   if($r.IdentityReference.Value-eq $owner-and ($r.FileSystemRights-band [Security.AccessControl.FileSystemRights]::FullControl)-eq [Security.AccessControl.FileSystemRights]::FullControl){$own=$true}
  }
 };if(-not $own){Fail 'private_user_control'}
}
function WriteNew([string]$Path,$Value){
 Private ([IO.Path]::GetDirectoryName($Path))
 $bytes=[Text.UTF8Encoding]::new($false).GetBytes(($Value|ConvertTo-Json -Depth 16))
 $f=[IO.File]::Open($Path,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::Read)
 try{$f.Write($bytes,0,$bytes.Length);$f.Flush($true)}finally{$f.Dispose()}
 Private $Path
}
function Receipt([string]$Name,$Value){
 if(-not $script:journal){return}
 $script:receiptSeq++
 WriteNew (Join-Path $script:journal ('{0:D3}-{1}.json'-f $script:receiptSeq,$Name)) ([ordered]@{format='schema6-legacy-freeze-phase-v1';stage=$script:stage;windowId=$WindowId;configurationSha256=$ExpectedConfigSha256;atUtc=[DateTime]::UtcNow.ToString('o');elapsedMs=$clock.ElapsedMilliseconds;data=$Value})
}
function ReadJson([string]$Path){Private $Path;return Get-Content -LiteralPath $Path -Raw|ConvertFrom-Json}
function Pin([string]$Path,[string]$Expected){
 Plain $Path;if((Hash $Path)-cne $Expected){Fail 'pinned_file_changed' -Drift}
 $s=[IO.File]::Open($Path,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read)
 $script:leases+=$s
 if((Hash $Path)-cne $Expected){Fail 'pinned_file_open_race' -Drift}
 $systemPowerShell=Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
 if($Path-ine $systemPowerShell){$null=[FreezeIdentity]::FileId($Path)}
 $script:proofFiles+=@{path=$Path;sha256=$Expected}
}
function VerifyPins{foreach($p in $script:proofFiles){if((Hash $p.path)-cne $p.sha256){Fail 'pinned_file_drift' -Drift}}}
Add-Type -TypeDefinition @"
using System;
using System.IO;
using System.Runtime.InteropServices;
public static class FreezeIdentity {
 [StructLayout(LayoutKind.Sequential)] struct INFO {public uint attributes;public System.Runtime.InteropServices.ComTypes.FILETIME creation,access,write;public uint serial,high,low,links,indexHigh,indexLow;}
 [DllImport("kernel32.dll",SetLastError=true)]static extern bool GetFileInformationByHandle(Microsoft.Win32.SafeHandles.SafeFileHandle h,out INFO i);
 public static string FileId(string p){using(var f=new FileStream(p,FileMode.Open,FileAccess.Read,FileShare.ReadWrite|FileShare.Delete)){INFO i;if(!GetFileInformationByHandle(f.SafeFileHandle,out i)||i.links!=1)throw new IOException("file_identity_rejected");return i.serial.ToString("x8")+":"+i.indexHigh.ToString("x8")+i.indexLow.ToString("x8");}}
}
"@
function FileStamp([string]$Path){
 Plain $Path;$id=[FreezeIdentity]::FileId($Path);$a=Get-Item -LiteralPath $Path
 $hash=Hash $Path;$b=Get-Item -LiteralPath $Path
 if($id-cne [FreezeIdentity]::FileId($Path)-or $a.Length-ne $b.Length-or $a.LastWriteTimeUtc.Ticks-ne $b.LastWriteTimeUtc.Ticks){Fail 'file_changed_during_hash' -Drift}
 return [pscustomobject]@{path=$Path;exists=$true;size=[long]$b.Length;sha256=$hash;file_id=$id}
}
function ProcessRows{return @(Get-CimInstance Win32_Process -Property ProcessId,ParentProcessId,ExecutablePath,CreationDate)}
function PIdentity($Row){
 $p=Get-Process -Id ([int]$Row.ProcessId) -ErrorAction Stop
 try{$null=$p.Handle;$ticks=$p.StartTime.ToUniversalTime().Ticks.ToString();$exe=$p.MainModule.FileName
  # WMI DMTF CreationDate has microsecond precision; Process.StartTime is 100 ns.
  if($null-eq $Row.CreationDate-or [Math]::Abs([long]$ticks-[long]$Row.CreationDate.ToUniversalTime().Ticks)-gt 9){Fail 'cim_handle_creation_mismatch' -Drift}
  if(-not $exe-or -not $Row.ExecutablePath-or $exe-ine $Row.ExecutablePath){Fail 'process_path_unavailable' -Drift}
  if(-not $allowedImages.ContainsKey($exe.ToLowerInvariant())-or (Hash $exe)-cne $allowedImages[$exe.ToLowerInvariant()]){Fail 'unapproved_tree_image' -Drift}
  return [pscustomobject]@{pid=[int]$Row.ProcessId;parent_pid=[int]$Row.ParentProcessId;started_ticks=$ticks;path=$exe;sha256=(Hash $exe)}
 }finally{$p.Dispose()}
}
function SameAlive($Binding){
 $p=Get-Process -Id $Binding.pid -ErrorAction SilentlyContinue;if(-not $p){return $false}
 try{$null=$p.Handle;if($p.StartTime.ToUniversalTime().Ticks.ToString()-cne $Binding.started_ticks-or $p.MainModule.FileName-ine $Binding.path){Fail 'process_identity_reused' -Drift};if((Hash $Binding.path)-cne $Binding.sha256){Fail 'process_image_changed' -Drift};return $true}finally{$p.Dispose()}
}
function Listeners([int[]]$Ports){
 return @(Get-NetTCPConnection -State Listen -ErrorAction Stop|Where-Object {$_.LocalPort-in $Ports}|Select-Object LocalAddress,LocalPort,OwningProcess)
}
function Instances([string]$Name){return @((Task $Name).GetInstances(0))}
function Namespace($Doc){$n=[Xml.XmlNamespaceManager]::new($Doc.NameTable);$n.AddNamespace('t',$Doc.DocumentElement.NamespaceURI);return ,$n}
function NodeXml($Doc,[string]$XPath){$n=$Doc.SelectSingleNode($XPath,(Namespace $Doc));if($n){return $n.OuterXml};return ''}
function AssertNodes($A,$B,[string[]]$Names){foreach($n in $Names){if((NodeXml $A ('/t:Task/t:'+$n))-cne (NodeXml $B ('/t:Task/t:'+$n))){Fail ('task_'+$n+'_drift') -Drift}}}
function GetBound([string]$Name,[int[]]$Ports,[string]$NodePath,[string]$Server,[string]$ServerHash){
 $inst=@(Instances $Name);if($inst.Count-ne 1){Fail 'task_instance_not_single' -Drift}
 $listen=Listeners $Ports;foreach($port in $Ports){if(@($listen|Where-Object LocalPort -eq $port).Count-lt 1){Fail 'expected_listener_missing' -Drift}}
 $ids=@($listen|Select-Object -ExpandProperty OwningProcess -Unique);if($ids.Count-ne 1){Fail 'listener_owner_ambiguous' -Drift}
 $rows=ProcessRows;$child=@($rows|Where-Object ProcessId -eq $ids[0]);if($child.Count-ne 1){Fail 'listener_process_missing' -Drift}
 $root=@($rows|Where-Object ProcessId -eq $child[0].ParentProcessId);if($root.Count-ne 1-or [int]$root[0].ProcessId-ne [int]$inst[0].EnginePID){Fail 'task_engine_parent_mismatch' -Drift}
 $ni=PIdentity $child[0];$ri=PIdentity $root[0]
 if($ni.path-ine $NodePath-or $ni.sha256-cne $taskConfigs[$Name].nodeSha256-or $ri.path-ine $powershell-or $ri.sha256-cne $config.powershellSha256-or [long]$ri.started_ticks-gt [long]$ni.started_ticks){Fail 'bound_executable_mismatch' -Drift}
 if((Hash $Server)-cne $ServerHash){Fail 'bound_server_changed' -Drift}
 $known=@{([int]$ri.pid)=$ri};$tree=@($ri);$progress=$true
 while($progress){$progress=$false;foreach($row in $rows){if($known.ContainsKey([int]$row.ParentProcessId)-and -not $known.ContainsKey([int]$row.ProcessId)){$x=PIdentity $row;$parentBinding=$known[[int]$row.ParentProcessId];if([long]$x.started_ticks-lt [long]$parentBinding.started_ticks){Fail 'descendant_parent_time_mismatch' -Drift};$known[[int]$x.pid]=$x;$tree+=$x;$progress=$true}}}
 return [pscustomobject]@{task=$Name;instance_guid=[string]$inst[0].InstanceGuid;ports=$Ports;root=$ri;node=$ni;tree=$tree;server_path=$Server;server_sha256=$ServerHash}
}
function CheckFrozenTask([string]$Name){
 $t=(Task $Name);[xml]$x=$t.Xml;AssertNodes $x $script:originals[$Name].doc @('Actions','Principals')
 $n=Namespace $x
 if($t.Enabled-or $x.SelectNodes('/t:Task/t:Triggers/*',$n).Count-ne 0-or $x.SelectNodes('/t:Task/t:Settings/t:RestartOnFailure',$n).Count-ne 0){Fail 'old_task_not_frozen' -Drift}
 if($t.GetSecurityDescriptor(7)-cne $script:originals[$Name].sddl){Fail 'task_security_descriptor_drift' -Drift}
}
function FreezeDefinition([string]$Name){
 $o=$script:originals[$Name];[xml]$x=$o.xml;$n=Namespace $x
 foreach($xpath in @('/t:Task/t:Triggers','/t:Task/t:Settings/t:RestartOnFailure')){$node=$x.SelectSingleNode($xpath,$n);if($node){$null=$node.ParentNode.RemoveChild($node)}}
 $settings=$x.SelectSingleNode('/t:Task/t:Settings',$n);$enabled=$settings.SelectSingleNode('t:Enabled',$n)
 if(-not $enabled){$enabled=$x.CreateElement('Enabled',$x.DocumentElement.NamespaceURI);$null=$settings.AppendChild($enabled)}
 $enabled.InnerText='false';AssertNodes $x $o.doc @('Actions','Principals')
 $null=(TaskFolder $Name).RegisterTask($Name,$x.OuterXml,60,$owner,$null,3,$null);CheckFrozenTask $Name
}
function AssertNoOriginalTree($Bound){
 foreach($b in $Bound.tree){if(SameAlive $b){Fail 'original_tree_still_alive'}}
 $ids=@($Bound.tree|ForEach-Object {$_.pid});$unexpected=@(ProcessRows|Where-Object {$_.ParentProcessId-in $ids})
 if($unexpected.Count){Fail 'unbound_descendant_after_stop' -Drift}
 if(@(Listeners $Bound.ports).Count){Fail 'listener_after_stop' -Drift}
 if(@(Instances $Bound.task).Count){Fail 'task_instance_after_stop' -Drift}
}
function KillBound($b){
 $p=Get-Process -Id $b.pid -ErrorAction SilentlyContinue;if(-not $p){return}
 try{
  # Cache the OS handle BEFORE checking identity. Kill acts on this opened process.
  $null=$p.Handle
  if($p.StartTime.ToUniversalTime().Ticks.ToString()-cne $b.started_ticks-or $p.MainModule.FileName-ine $b.path-or (Hash $b.path)-cne $b.sha256){Fail 'kill_binding_drift' -Drift}
  $p.Kill();if(-not $p.WaitForExit(3000)){Fail 'bound_process_stop_timeout'}
 }finally{$p.Dispose()}
}
function StopBound([string]$Name){
 CheckFrozenTask $Name;$old=$script:bindings[$Name]
 # Rebind immediately before stopping, including any newly spawned descendants.
 $fresh=GetBound $Name $old.ports $old.node.path $old.server_path $old.server_sha256
 if($fresh.root.started_ticks-cne $old.root.started_ticks-or $fresh.node.started_ticks-cne $old.node.started_ticks-or $fresh.instance_guid-cne $old.instance_guid){Fail 'runtime_restarted_before_stop' -Drift}
 $script:bindings[$Name]=$fresh;Receipt 'stop-intent' $fresh
 $script:stopped[$Name]=$true
 Stop-ScheduledTask -TaskName $Name -TaskPath $taskConfigs[$Name].taskPath -ErrorAction Stop
 $deadline=[DateTime]::UtcNow.AddSeconds(3)
 do{$alive=@($fresh.tree|Where-Object {SameAlive $_});if(-not $alive.Count){break};Start-Sleep -Milliseconds 150}while([DateTime]::UtcNow-lt $deadline)
 $forced=@();for($i=$fresh.tree.Count-1;$i-ge 0;$i--){$b=$fresh.tree[$i];if(SameAlive $b){KillBound $b;$forced+=$b.pid}}
 Start-Sleep -Milliseconds 150;AssertNoOriginalTree $fresh
 Receipt 'stop-complete' @{task=$Name;forced_pids=$forced;legacy_clean_close_proven=$false;native_lease_proven=$false}
}
function ExternalCheck($Validation){
 $pairs=@(@{key='approvals';source=$config.approvalsPath;copy=(Join-Path $copyDirectory 'approvals.json')},@{key='grants';source=$config.grantsPath;copy=(Join-Path $copyDirectory 'grants.json')})
 foreach($p in $pairs){
  $expected=$Validation.external.($p.key)
  foreach($path in @($p.source,$p.copy)){$actual=FileStamp $path;if($actual.sha256-cne $expected.sha256-or $actual.size-ne $expected.size){Fail 'external_hash_mismatch' -Drift}}
 }
}
function FrozenFiles($Validation,[switch]$Record){
 $expectedPaths=@('','-wal','-shm','-journal')|ForEach-Object{$config.databasePath+$_}
 if(@($Validation.rawAfter).Count-ne 4-or @(Compare-Object ($expectedPaths|Sort-Object) (@($Validation.rawAfter|ForEach-Object{$_.path})|Sort-Object)).Count){Fail 'raw_inventory_invalid' -Drift}
 $now=@()
 $reference=if($Record){$Validation.rawAfter}else{$script:rawFrozen}
 foreach($entry in $reference){
  $exists=Test-Path -LiteralPath $entry.path -PathType Leaf
  if($exists-ne [bool]$entry.exists){if($Record){Fail 'frozen_sidecar_set_changed'}else{Fail 'frozen_sidecar_set_changed' -Drift}}
  if($exists){$actual=FileStamp $entry.path;if($actual.sha256-cne $entry.sha256-or $actual.size-ne $entry.size){if($Record){Fail 'frozen_raw_hash_changed'}else{Fail 'frozen_raw_hash_changed' -Drift}};$now+=$actual}else{$now+=[pscustomobject]@{path=$entry.path;exists=$false}}
 }
 if(-not $Record){
  foreach($a in $now|Where-Object exists){$before=@($script:rawFrozen|Where-Object path -eq $a.path);if($before.Count-ne 1-or $before[0].file_id-cne $a.file_id){Fail 'frozen_file_identity_drift' -Drift}}
 }else{$script:rawFrozen=$now}
 ExternalCheck $Validation;return $now
}
function CoreHealth{
 $request=[Net.HttpWebRequest]::Create($config.coreHealthUrl);$request.Timeout=1500;$request.ReadWriteTimeout=1500;$request.Proxy=$null
 $response=$null;$reader=$null
 try{$response=$request.GetResponse();if([int]$response.StatusCode-ne 200){return $false};$reader=[IO.StreamReader]::new($response.GetResponseStream());$h=$reader.ReadToEnd()|ConvertFrom-Json;return ($h.schema_version-eq 4)}
 catch{return $false}finally{if($reader){$reader.Dispose()};if($response){$response.Dispose()}}
}
function Rollback{
 Stage 'rollback'
 Receipt 'rollback-intent' @{original_task_names=@($script:originals.Keys);drift=$script:drift}
 # Restore original definitions in DISABLED mode first. Never enable on drift.
 foreach($name in $taskOrder){
  if(-not $script:originals.ContainsKey($name)){continue}
  $o=$script:originals[$name];[xml]$live=(Task $name).Xml
  AssertNodes $live $o.doc @('Actions','Principals')
  if((Task $name).GetSecurityDescriptor(7)-cne $o.sddl){Fail 'rollback_task_acl_drift' -Drift}
  $null=(TaskFolder $name).RegisterTask($name,$o.xml,60,$owner,$null,3,$null)
  $restoredTask=Task $name;[xml]$restored=$restoredTask.Definition.XmlText
  $disabledDefinition=$svc.NewTask(0);$disabledDefinition.XmlText=$o.xml;$disabledDefinition.Settings.Enabled=$false
  [xml]$disabledOriginal=$disabledDefinition.XmlText
  AssertNodes $restored $disabledOriginal @('Actions','Principals','Triggers','Settings')
  if($restoredTask.Enabled-or $restoredTask.GetSecurityDescriptor(7)-cne $o.sddl){Fail 'rollback_definition_readback_failed' -Drift}
 }
 if($script:drift){return @{restored_definitions_disabled=$true;runtime_restored=$false;manual_recovery_required=$true;reason='identity_or_file_drift'}}
 VerifyPins
 if($script:initialDbIdentity-cne [FreezeIdentity]::FileId($config.databasePath)){Fail 'rollback_database_replaced' -Drift}
 foreach($b in $script:externalInitial){$now=FileStamp $b.path;if($now.file_id-cne $b.file_id-or $now.sha256-cne $b.sha256){Fail 'rollback_external_drift' -Drift}}
 foreach($name in $taskOrder){
  $bound=$script:bindings[$name]
  $rootAlive=SameAlive $bound.root;$nodeAlive=SameAlive $bound.node
  if($rootAlive-and $nodeAlive){
   # A rejected Stop call may leave the exact original runtime intact.
   $still=GetBound $name $bound.ports $bound.node.path $bound.server_path $bound.server_sha256
   if($still.root.started_ticks-cne $bound.root.started_ticks-or $still.node.started_ticks-cne $bound.node.started_ticks){Fail 'rollback_existing_runtime_changed' -Drift}
   if($name-eq $coreName-and -not (CoreHealth)){Fail 'rollback_existing_core_unhealthy'}
   (Task $name).Enabled=$true
  }elseif($script:stopped.ContainsKey($name)-and -not $rootAlive-and -not $nodeAlive){
   # No blind retry when any surviving/foreign instance or port owner remains.
   AssertNoOriginalTree $bound
   (Task $name).Enabled=$true
   $null=(Task $name).Run($null)
   $deadline=[DateTime]::UtcNow.AddSeconds(30);$healthy=$false
   do{
    $portsNow=Listeners $bound.ports
    $missing=@($bound.ports|Where-Object {$wanted=$_;@($portsNow|Where-Object LocalPort -eq $wanted).Count-eq 0})
    if($missing.Count-eq 0-and @(Instances $name).Count-eq 1){
     $liveBound=GetBound $name $bound.ports $bound.node.path $bound.server_path $bound.server_sha256
     $healthy=($name-ne $coreName-or (CoreHealth))
     if($healthy){break}
    }
    Start-Sleep -Milliseconds 500
   }while([DateTime]::UtcNow-lt $deadline)
   if(-not $healthy){Fail 'rollback_runtime_health_timeout'}
  }else{Fail 'rollback_partial_or_unexpected_runtime_exit' -Drift}
  [xml]$after=(Task $name).Xml;AssertNodes $after $script:originals[$name].doc @('Actions','Principals','Triggers')
  if(-not (Task $name).Enabled){Fail 'rollback_task_settings_mismatch'};AssertNodes $after $script:originals[$name].doc @('Settings')
 }
 return @{restored_definitions_disabled=$false;runtime_restored=$true;manual_recovery_required=$false;core_health_schema4=$true}
}

function TaskFolder([string]$Name){return $svc.GetFolder($taskConfigs[$Name].taskPath)}
function Task([string]$Name){return (TaskFolder $Name).GetTask($Name)}
function RequireHash([string]$Value){if($Value-cnotmatch '^[a-f0-9]{64}$'){Fail 'invalid_sha256'}}
function RequiredPin([string]$Path,[string]$Expected){RequireHash $Expected;Pin $Path $Expected}
function RefreshValidatorTree($Process){
 $rows=ProcessRows
 if(-not $script:validatorTree.Count){
  $row=@($rows|Where-Object ProcessId -eq $Process.Id)
  if($row.Count-ne 1){Fail 'validator_identity_unavailable' -Drift}
  $root=PIdentity $row[0]
  if($root.path-ine $config.nodePath-or $root.started_ticks-cne $Process.StartTime.ToUniversalTime().Ticks.ToString()){Fail 'validator_identity_mismatch' -Drift}
  $script:validatorTree=@($root)
 }
 $known=@{};foreach($binding in $script:validatorTree){$known[[int]$binding.pid]=$binding}
 $progress=$true
 while($progress){$progress=$false;foreach($row in $rows){
  if($known.ContainsKey([int]$row.ParentProcessId)-and -not $known.ContainsKey([int]$row.ProcessId)){
   $binding=PIdentity $row
   if([long]$binding.started_ticks-lt [long]$known[[int]$binding.parent_pid].started_ticks){Fail 'validator_descendant_identity_rejected' -Drift}
   $known[[int]$binding.pid]=$binding;$script:validatorTree+=$binding;$progress=$true
  }
 }}
}
function AssertValidatorTreeExited {
 foreach($binding in $script:validatorTree){if(SameAlive $binding){Fail 'validator_tree_still_alive' -Drift}}
 $ids=@($script:validatorTree|ForEach-Object{$_.pid})
 if(@(ProcessRows|Where-Object{$_.ParentProcessId-in $ids}).Count){Fail 'validator_unbound_descendant' -Drift}
 $script:validatorMayRead=$false
}
function StopValidatorTree($Process){
 RefreshValidatorTree $Process
 # Stop the pinned parent first so it cannot launch new children during cleanup.
 KillBound $script:validatorTree[0]
 for($i=$script:validatorTree.Count-1;$i-ge 1;$i--){KillBound $script:validatorTree[$i]}
 AssertValidatorTreeExited
}
function AssertValidation($Validation){
 if($Validation.format-cne 'schema6-cutover-copy-validation-v1'-or $Validation.sourceCommit-cne $config.candidateSourceCommit-or $Validation.comparison_policy-cne 'online-db-wal-bytes-identity-journal-existence-shm-existence-size-v1'-or $Validation.originalSqliteReadOnly-ne $true-or $Validation.deployed-ne $false){Fail 'copy_receipt_binding_rejected'}
 foreach($f in @('passed','rawStable','sourceCopyUnchanged','externalSourcesUnchanged','legacyDigestVerified')){if($Validation.$f-isnot [bool]-or $Validation.$f-ne $true){Fail 'precutover_validation_gate_failed'}}
 if($Validation.preflight.preflight_passed-ne $true-or $Validation.preflight.exact_bindings-ne $config.expectedExactBindings-or $Validation.preflight.grants-ne $config.expectedGrants-or $Validation.preflight.database_schema_version-ne 5){Fail 'precutover_preflight_gate_failed'}
 if($Validation.startedAt-lt $validatorStartedMs-or $Validation.completedAt-lt $Validation.startedAt-or $Validation.completedAt-gt [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()){Fail 'copy_receipt_time_rejected'}
 if((Hash $copyConfigPath)-cne $copyConfigurationSha256){Fail 'copy_configuration_changed' -Drift}
 VerifyPins
}

try{
 if(-not $Execute){Fail 'execute_switch_required'}
 if($PSVersionTable.PSVersion.Major-ne 5-or $PSVersionTable.PSEdition-ne 'Desktop'){Fail 'windows_powershell_51_required'}
 Plain $ConfigPath;RequireHash $ExpectedConfigSha256
 # Lock the exact bytes before parsing, and keep this lease through rollback.
 Pin $ConfigPath $ExpectedConfigSha256
 $config=Get-Content -LiteralPath $ConfigPath -Raw|ConvertFrom-Json
 if($config.windowId-cne $WindowId-or $config.format-cne 'schema6-maintenance-freeze-config-v2'-or $config.candidateSourceCommit-cnotmatch '^[a-f0-9]{40}$'){Fail 'configuration_format_rejected'}
 $owner=[string]$config.ownerSid
 if([Security.Principal.WindowsIdentity]::GetCurrent().User.Value-cne $owner){Fail 'owner_sid_mismatch'}
 Private $ConfigPath;Private $config.maintenanceRoot -Root
 RequiredPin $PSCommandPath $config.freezeScriptSha256
 $windowModule=Join-Path $PSScriptRoot 'maintenance_window.ps1'
 RequiredPin $windowModule $config.windowModuleSha256
 . $windowModule
 $script:window=Open-MaintenanceWindow -MaintenanceRoot $config.maintenanceRoot -WindowId $WindowId
 Private (Join-Path $config.maintenanceRoot 'active-window.guard')
 $prep=$script:window.Directory;$script:journal=$script:window.PhaseReceiptsDirectory
 Private $prep;Private $script:journal
 $release=$config.candidateDirectory;$manifestHash=$config.candidateManifestSha256;$xmlHash=$config.approvedXmlSha256
 $powershell=Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
 RequiredPin $powershell $config.powershellSha256
 RequiredPin (Join-Path $release 'manifest.json') $manifestHash
 RequiredPin $config.approvedXmlPath $xmlHash
 $manifest=ReadJson (Join-Path $release 'manifest.json')
 if($manifest.source_commit-cne $config.candidateSourceCommit){Fail 'candidate_source_commit_mismatch'}
 if($manifest.pinned_node_sha256-cne '58e74bf02fc5bbacc41dcb8bef089961cd5bddd37830b87784e4fc624d145d1f'-or $manifest.node_version-cne 'v24.14.1'-or $config.nodeSha256-cne $manifest.pinned_node_sha256){Fail 'fixed_node_binding_rejected'}
 if($config.validatorTimeoutMs-isnot [int]-or $config.validatorTimeoutMs-lt 30000-or $config.validatorTimeoutMs-gt 300000){Fail 'validator_timeout_rejected'}
 # Use THIS reviewed branch adapter and guard, with caller-pinned module hashes.
 $validatorPath=Join-Path $PSScriptRoot 'precutover_validate_copy.mjs';$validatorHash=$config.validatorSha256
 RequiredPin $validatorPath $validatorHash
 RequiredPin (Join-Path $PSScriptRoot 'online_preflight_input_guard.mjs') $config.onlineGuardSha256
 RequiredPin $config.nodePath $config.nodeSha256
 if(@($config.modulePins).Count-lt 5){Fail 'module_pins_required'}
 foreach($module in $config.modulePins){RequiredPin $module.path $module.sha256}
 $repoRoot=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..\..'))
 foreach($relative in @('tools\i_core\release_schema6\package.mjs','tools\i_core\release_schema6\backup_bundle.mjs','tools\i_core\activity_control_plane.mjs','tools\i_core\inspection_read_only.mjs','tools\i_core\maintenance\freeze_verify_candidate.mjs')){
  $needed=Join-Path $repoRoot $relative
  if(@($config.modulePins|Where-Object {$_.path-ceq $needed}).Count-ne 1){Fail 'adapter_dependency_pin_missing'}
 }
 foreach($file in $manifest.files){
  if($file.path-notmatch '^[a-zA-Z0-9_./-]+$'-or $file.path.Contains('..')-or [IO.Path]::IsPathRooted($file.path)){Fail 'candidate_inventory_path_rejected'}
  RequiredPin (Join-Path $release $file.path) $file.sha256
 }
 # Validate the entire fixed inventory before importing its protected-path helper.
 $verifyInfo=[Diagnostics.ProcessStartInfo]::new();$verifyInfo.FileName=$config.nodePath
 $verifyInfo.Arguments='"'+(Join-Path $PSScriptRoot 'freeze_verify_candidate.mjs')+'" "'+$release+'" "'+$manifestHash+'" "'+$config.candidateSourceCommit+'"'
 $verifyInfo.UseShellExecute=$false;$verifyInfo.CreateNoWindow=$true;$verifyInfo.RedirectStandardOutput=$true;$verifyInfo.RedirectStandardError=$true
 $verifyInfo.EnvironmentVariables.Clear()
 foreach($key in @('SystemRoot','WINDIR','TEMP','TMP','COMSPEC')){$value=[Environment]::GetEnvironmentVariable($key);if($null-ne $value){$verifyInfo.EnvironmentVariables[$key]=$value}}
 $verifyProcess=[Diagnostics.Process]::new();$verifyProcess.StartInfo=$verifyInfo
 try{$null=$verifyProcess.Start();$null=$verifyProcess.Handle;$vo=$verifyProcess.StandardOutput.ReadToEndAsync();$ve=$verifyProcess.StandardError.ReadToEndAsync()
  if(-not $verifyProcess.WaitForExit(30000)){$verifyProcess.Kill();if(-not $verifyProcess.WaitForExit(3000)){Fail 'candidate_verifier_stop_failed' -Drift};Fail 'candidate_verifier_timeout'}
  if($verifyProcess.ExitCode-ne 0){Fail 'candidate_inventory_rejected'}
 }finally{$verifyProcess.Dispose()}
 $taskConfigs=@{};$coreName=[string]$config.tasks.core.name;$mcpName=[string]$config.tasks.mcp.name
 if(-not $coreName-or -not $mcpName-or $coreName-ieq $mcpName){Fail 'task_names_rejected'}
 $taskOrder=@($coreName,$mcpName)
 $taskConfigs[$coreName]=$config.tasks.core;$taskConfigs[$mcpName]=$config.tasks.mcp
 $ports=@($taskOrder|ForEach-Object{$taskConfigs[$_].ports})
 if(-not $ports.Count-or @($ports|Sort-Object -Unique).Count-ne $ports.Count-or @($ports|Where-Object{$_-lt 1-or $_-gt 65535}).Count){Fail 'ports_rejected'}
 $health=[Uri]$config.coreHealthUrl
 if($health.Scheme-cne 'http'-or $health.Host-cne '127.0.0.1'-or $health.Port-notin $config.tasks.core.ports-or $health.AbsolutePath-cne '/v1/core/health'-or $health.Query-or $health.UserInfo){Fail 'core_health_url_rejected'}
 $allowedImages=@{}
 foreach($pin in @($config.processImagePins)){
  RequiredPin $pin.path $pin.sha256;$allowedImages[$pin.path.ToLowerInvariant()]=$pin.sha256
 }
 foreach($image in @($powershell,$config.nodePath,$config.tasks.core.nodePath,$config.tasks.mcp.nodePath)){if(-not $allowedImages.ContainsKey($image.ToLowerInvariant())){Fail 'process_image_pin_missing'}}
 $svc=New-Object -ComObject Schedule.Service;$svc.Connect()
 foreach($name in $taskOrder){
  $tc=$taskConfigs[$name]
  if($tc.taskPath-notmatch '^\\.*\\$'-and $tc.taskPath-cne '\'){Fail 'task_path_rejected'}
  RequiredPin $tc.originalXmlPath $tc.originalXmlSha256
  RequiredPin $tc.nodePath $tc.nodeSha256;RequiredPin $tc.serverPath $tc.serverSha256
  RequiredPin $tc.launcherPath $tc.launcherSha256;RequiredPin $tc.manifestPath $tc.manifestSha256
  $text=Get-Content -LiteralPath $tc.originalXmlPath -Raw;[xml]$doc=$text
  $t=Task $name;[xml]$live=$t.Xml;AssertNodes $live $doc @('Actions','Principals','Triggers','Settings')
  if(-not $t.Enabled-or $t.GetSecurityDescriptor(7)-cne $tc.originalSddl){Fail 'original_task_baseline_mismatch' -Drift}
  $script:originals[$name]=@{xml=$text;doc=$doc;path=$tc.originalXmlPath;sha256=$tc.originalXmlSha256;sddl=$tc.originalSddl;enabled=$true}
  $script:bindings[$name]=GetBound $name $tc.ports $tc.nodePath $tc.serverPath $tc.serverSha256
 }
 $script:initialDbIdentity=[FreezeIdentity]::FileId($config.databasePath)
 foreach($p in @($config.approvalsPath,$config.grantsPath)){$script:externalInitial+=FileStamp $p}
 if(-not (CoreHealth)){Fail 'original_core_health_not_schema4'}
 $copyDirectory=Join-Path $prep 'copy-validation'
 if(Test-Path -LiteralPath $copyDirectory){Fail 'fresh_copy_directory_required'}
 $null=[IO.Directory]::CreateDirectory($copyDirectory)
 # This fixed, manifest-pinned helper protects ONLY the fresh empty artifact.
 # It does not Apply the cutover ACL plan to any existing runtime/data target.
 . (Join-Path $release 'tools\i_core\release_schema6\lifecycle\protected_paths.ps1')
 Protect-NewDirectory $copyDirectory;Private $copyDirectory -Root
 $copyConfigPath=Join-Path $prep 'copy-validation-config.json'
 WriteNew $copyConfigPath ([ordered]@{releaseDirectory=$release;manifestSha256=$manifestHash;databasePath=$config.databasePath;approvalsPath=$config.approvalsPath;grantsPath=$config.grantsPath;outputDirectory=$copyDirectory})
 $copyConfigurationSha256=Hash $copyConfigPath;Pin $copyConfigPath $copyConfigurationSha256
 $validationPath=Join-Path $copyDirectory 'precutover-validation-receipt.json'
 Receipt 'baseline' @{candidateSourceCommit=$config.candidateSourceCommit;candidateManifestSha256=$manifestHash;configurationSha256=$ExpectedConfigSha256;tasks=@($taskOrder|ForEach-Object{@{name=$_;xmlSha256=$script:originals[$_].sha256;sddl=$script:originals[$_].sddl}});bindings=$script:bindings;databaseFileId=$script:initialDbIdentity;processCommandlinesRead=$false}
 Stage 'disable-old-tasks'
 Receipt 'disable-intent' @{tasks=$taskOrder};$script:changed=$true
 foreach($name in $taskOrder){Disable-ScheduledTask -TaskPath $taskConfigs[$name].taskPath -TaskName $name|Out-Null;if((Task $name).Enabled){Fail 'disable_failed'}}
 foreach($name in $taskOrder){FreezeDefinition $name}
 Receipt 'definitions-frozen' @{bothDisabled=$true;triggersRemoved=$true;retryRemoved=$true}
 Stage 'stop-mcp';StopBound $mcpName
 Stage 'validate-copy'
 Receipt 'validator-intent' @{validatorSha256=$validatorHash;receiptPath=$validationPath;copyConfigurationSha256=$copyConfigurationSha256}
 $out=Join-Path $script:journal 'validator.stdout.txt';$err=Join-Path $script:journal 'validator.stderr.txt'
 $pi=[Diagnostics.ProcessStartInfo]::new();$pi.FileName=$config.nodePath
 $pi.Arguments='"'+$validatorPath+'" --config "'+$copyConfigPath+'"';$pi.WorkingDirectory=$prep;$pi.UseShellExecute=$false;$pi.CreateNoWindow=$true;$pi.RedirectStandardOutput=$true;$pi.RedirectStandardError=$true
 $pi.EnvironmentVariables.Clear()
 foreach($environmentName in @('SystemRoot','WINDIR','TEMP','TMP','COMSPEC')){$environmentValue=[Environment]::GetEnvironmentVariable($environmentName);if($null-ne $environmentValue){$pi.EnvironmentVariables[$environmentName]=$environmentValue}}
 $validatorStartedMs=[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
 $vp=[Diagnostics.Process]::new();$vp.StartInfo=$pi
 try{$null=$vp.Start();$null=$vp.Handle;$script:validatorMayRead=$true
  RefreshValidatorTree $vp
  $os=$vp.StandardOutput.ReadToEndAsync();$es=$vp.StandardError.ReadToEndAsync();$validatorClock=[Diagnostics.Stopwatch]::StartNew()
  while(-not $vp.WaitForExit(250)){
   RefreshValidatorTree $vp
   if($validatorClock.ElapsedMilliseconds-ge $config.validatorTimeoutMs){StopValidatorTree $vp;Fail 'precutover_validator_timeout'}
  }
  RefreshValidatorTree $vp;AssertValidatorTreeExited
  foreach($pair in @(@{path=$out;text=$os.GetAwaiter().GetResult()},@{path=$err;text=$es.GetAwaiter().GetResult()})){$b=[Text.UTF8Encoding]::new($false).GetBytes($pair.text);$f=[IO.File]::Open($pair.path,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::Read);try{$f.Write($b,0,$b.Length);$f.Flush($true)}finally{$f.Dispose()}}
  if($vp.ExitCode-ne 0){Fail 'precutover_validator_failed'}
 }catch{if($script:validatorMayRead){try{StopValidatorTree $vp}catch{$script:drift=$true}};throw}finally{$vp.Dispose()}
 $validation=ReadJson $validationPath;AssertValidation $validation;ExternalCheck $validation
 $validationReceiptSha256=Hash $validationPath;Pin $validationPath $validationReceiptSha256
 Receipt 'validator-passed' @{validationReceiptPath=$validationPath;validationReceiptSha256=$validationReceiptSha256;copyConfigurationSha256=$copyConfigurationSha256;comparisonPolicy=$validation.comparison_policy;originalSchemaMigrationPerformed=$false}
 Stage 'stop-core';StopBound $coreName
 Stage 'frozen-file-check';$null=FrozenFiles $validation -Record
 if($script:initialDbIdentity-cne [FreezeIdentity]::FileId($config.databasePath)){Fail 'database_identity_drift' -Drift}
 Receipt 'raw-frozen' @{raw=$script:rawFrozen;sqliteOpenedAfterCoreStop=$false}
 Stage 'observe-65s';$observe=[Diagnostics.Stopwatch]::StartNew()
 do{
  foreach($name in $taskOrder){CheckFrozenTask $name;AssertNoOriginalTree $script:bindings[$name]}
  if(@(Listeners $ports).Count){Fail 'port_reoccupied' -Drift}
  $null=FrozenFiles $validation
  Start-Sleep -Seconds 2
 }while($observe.ElapsedMilliseconds-lt 65000)
 VerifyPins;$finalRaw=FrozenFiles $validation
 $now=[DateTime]::UtcNow
 $ready=[ordered]@{format='schema6-frozen-legacy-runtime-ready-v2';passed=$true;windowId=$WindowId;windowDirectory=$prep;candidateSourceCommit=$config.candidateSourceCommit;candidateManifestSha256=$manifestHash;configurationSha256=$ExpectedConfigSha256;createdUtc=$now.ToString('o');expiresUtc=$now.AddMinutes(30).ToString('o');observationMs=$observe.ElapsedMilliseconds;approvedXmlSha256=$xmlHash;validatorSha256=$validatorHash;validationReceiptPath=$validationPath;validationReceiptSha256=$validationReceiptSha256;copyConfigurationPath=$copyConfigPath;copyConfigurationSha256=$copyConfigurationSha256;rawAfter=$finalRaw;external=$validation.external;tasks=@($taskOrder|ForEach-Object{@{name=$_;taskPath=$taskConfigs[$_].taskPath;originalXmlSha256=$script:originals[$_].sha256;originalSddl=$script:originals[$_].sddl;frozenXmlSha256=(XmlHash (Task $_).Xml);disabled=$true;triggers=0;retries=0;instances=0}});bindings=$script:bindings;portsFree=$ports;aclApplied=$false;databaseReplaced=$false;schemaMigrationPerformed=$false;legacyCleanCloseProven=$false;nativeLeaseProven=$false;phaseReceiptsDirectory=$script:journal}
 WriteNew (Join-Path $prep 'frozen-legacy-runtime-ready.json') $ready
 Receipt 'finished' @{passed=$true};Stage 'frozen-ready'
}catch{
 if($script:validatorMayRead){$script:drift=$true}
 $failedStage=$stage;$code=$_.Exception.Message;if($code-notmatch '^[a-z0-9_]+$'){$code='unexpected_failure'}
 $rollback=@{attempted=$false;runtime_restored=$false;manual_recovery_required=$false}
 if($script:changed){
  try{$rollback=Rollback;$rollback.attempted=$true}
  catch{$rollback=@{attempted=$true;runtime_restored=$false;manual_recovery_required=$true;reason='rollback_incomplete'};try{foreach($n in $taskOrder){Disable-ScheduledTask -TaskName $n -TaskPath $taskConfigs[$n].taskPath|Out-Null}}catch{}}
 }
 try{Receipt 'failed' @{failedStage=$failedStage;code=$code;drift=$script:drift;rollback=$rollback;noMigrationOrReplacementPerformed=$true}}catch{}
 throw ('freeze_failed_'+$code)
}finally{
 foreach($h in $script:leases){$h.Dispose()}
 if($script:window){Close-MaintenanceWindow $script:window}
 # Append-only receipts and all lock files deliberately remain for review.
}
