#requires -Version 5.1
param([Parameter(Mandatory=$true)][string]$SourcePath,[Parameter(Mandatory=$true)][string]$FixtureParent)
$ErrorActionPreference='Stop';Set-StrictMode -Version 2
. $SourcePath
$helperHash=(Get-FileHash -LiteralPath (Join-Path (Split-Path -Parent $SourcePath) 'owned_artifacts.ps1')).Hash.ToLowerInvariant()
Initialize-CutoverAclNative
$owner=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value
$sections=[Security.AccessControl.AccessControlSections]::Owner -bor [Security.AccessControl.AccessControlSections]::Access
$maintenance=Join-Path $FixtureParent 'maintenance';$root=Join-Path $FixtureParent 'target';$windowId='synthetic-audit-window';$window=Join-Path (Join-Path $maintenance 'windows') $windowId
$null=[IO.Directory]::CreateDirectory($window);$null=[IO.Directory]::CreateDirectory($root)
foreach($p in @($maintenance,$window,$root)){$acl=New-Object Security.AccessControl.DirectorySecurity;$acl.SetSecurityDescriptorSddlForm((New-PrivateSddl $true),$sections);Set-Acl -LiteralPath $p -AclObject $acl}
$file=Join-Path $root 'synthetic.txt';[IO.File]::WriteAllText($file,'synthetic audit',[Text.UTF8Encoding]::new($false))
$rows=@(foreach($p in @($root,$file)){$item=Get-Item -LiteralPath $p;$acl=Get-Acl -LiteralPath $p;@{path=$p;directory=[bool]$item.PSIsContainer;owner=$acl.GetOwner([Security.Principal.SecurityIdentifier]).Value;sddl=$acl.GetSecurityDescriptorSddlForm($sections)}})
$snapshot=Join-Path $window 'snapshot.json';[IO.File]::WriteAllText($snapshot,($rows|ConvertTo-Json -Depth 5),[Text.UTF8Encoding]::new($false))
$configPath=Join-Path $window 'config.json';$receiptPath=Join-Path $window 'audit.json';$guardPath=Join-Path $maintenance 'active-window.guard'
[IO.File]::WriteAllText($guardPath,'existing durable lock bytes',[Text.UTF8Encoding]::new($false));$guardHash=(Get-FileHash -LiteralPath $guardPath -Algorithm SHA256).Hash
$c=[ordered]@{format='schema6-acl-config-v1';windowId=$windowId;candidateSourceCommit=('a'*40);candidateManifestSha256=('b'*64);maintenanceRoot=$maintenance;baseDirectory=$window;snapshotPath=$snapshot;snapshotSha256=(Get-FileHash -LiteralPath $snapshot -Algorithm SHA256).Hash.ToLowerInvariant();ownerSid=$owner;roots=@($root);expectedCount=2;expectedForeignOwnerCount=@($rows|Where-Object {$_.owner -cne $owner}).Count;taskNames=@('\SyntheticNeverRead');ports=@(12345);frozenReceiptPath=(Join-Path $window 'never-read-freeze.json');frozenReceiptSha256=('c'*64);receiptPath=$receiptPath}
function Save-Config {[IO.File]::WriteAllText($configPath,($c|ConvertTo-Json -Depth 5),[Text.UTF8Encoding]::new($false));return (Get-FileHash -LiteralPath $configPath -Algorithm SHA256).Hash.ToLowerInvariant()}
$configHash=Save-Config
# Prevent any live task/listener enumeration even if Audit accidentally calls it.
function Get-ScheduledTask { throw 'synthetic_live_task_access_forbidden' }
function Get-NetTCPConnection { throw 'synthetic_live_port_access_forbidden' }
$answer=Invoke-AclMaintenance -ConfigPath $configPath -ExpectedConfigSha256 $configHash -ExpectedOwnedArtifactsSha256 $helperHash -Mode Audit
if(!$answer.passed -or $answer.exitCode -ne 0 -or $answer.result.items.Count -ne 2){throw 'synthetic_audit_failed'}
if((Get-FileHash -LiteralPath $guardPath -Algorithm SHA256).Hash -cne $guardHash){throw 'guard_bytes_changed'}
$c.receiptPath=Join-Path $window 'locked-audit.json';$configHash=Save-Config
$lock=[IO.File]::Open($guardPath,[IO.FileMode]::Open,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
try{$answer=Invoke-AclMaintenance -ConfigPath $configPath -ExpectedConfigSha256 $configHash -ExpectedOwnedArtifactsSha256 $helperHash -Mode Audit;if($answer.passed -or (Test-Path -LiteralPath $c.receiptPath)){throw 'concurrent_guard_not_rejected'}}finally{$lock.Dispose()}
$guardLink=Join-Path $maintenance 'synthetic-guard-link'
$null=New-Item -ItemType HardLink -Path $guardLink -Target $guardPath
try{
 $answer=Invoke-AclMaintenance -ConfigPath $configPath -ExpectedConfigSha256 $configHash -ExpectedOwnedArtifactsSha256 $helperHash -Mode Audit
 if($answer.passed -or (Test-Path -LiteralPath $c.receiptPath)){throw 'hardlink_guard_not_rejected'}
}finally{Remove-Item -LiteralPath $guardLink -Force}
# New inventory is preserved, and exact old snapshot remains insufficient.
$pending=Join-Path $root 'synthetic.pending';[IO.File]::WriteAllText($pending,'preserve',[Text.UTF8Encoding]::new($false))
$c.receiptPath=Join-Path $window 'drift-audit.json';$configHash=Save-Config
$answer=Invoke-AclMaintenance -ConfigPath $configPath -ExpectedConfigSha256 $configHash -ExpectedOwnedArtifactsSha256 $helperHash -Mode Audit
if($answer.passed -or $answer.result.error_code -cne 'inventory_drift' -or !(Test-Path -LiteralPath $pending)){throw 'audit_inventory_drift_not_preserved'}
[Console]::WriteLine('{"passed":true,"fullAudit":true,"guardBytesPreserved":true,"concurrentGuardRejected":true,"hardlinkGuardRejected":true,"pendingPreserved":true,"liveTasksRead":false}')
