#requires -Version 5.1
param([Parameter(Mandatory=$true)][string]$SourcePath,[Parameter(Mandatory=$true)][string]$FixtureParent)
$ErrorActionPreference='Stop';Set-StrictMode -Version 2
$before=@(Get-ChildItem -LiteralPath $FixtureParent -Force).Count
. $SourcePath
. (Join-Path ([IO.Path]::GetDirectoryName($SourcePath)) 'owner-apply-runtime-permissions.ps1')
. (Join-Path ([IO.Path]::GetDirectoryName($SourcePath)) 'owner_elevation_probe.ps1')
if(('CutoverAclNative' -as [type]) -or @(Get-ChildItem -LiteralPath $FixtureParent -Force).Count -ne $before){throw 'import_has_side_effect'}
$tokens=$null;$parseErrors=$null
foreach($file in @($SourcePath,(Join-Path ([IO.Path]::GetDirectoryName($SourcePath)) 'owner-apply-runtime-permissions.ps1'),(Join-Path ([IO.Path]::GetDirectoryName($SourcePath)) 'owner_elevation_probe.ps1'))){
 $null=[Management.Automation.Language.Parser]::ParseFile($file,[ref]$tokens,[ref]$parseErrors)
 if($parseErrors.Count){throw 'source_parse_failed'}
}
$file=Join-Path $FixtureParent 'anchored.json';[IO.File]::WriteAllText($file,'{"passed":true}',[Text.UTF8Encoding]::new($false))
$hash=(Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash.ToLowerInvariant()
if(!(Read-AclAnchoredJson $file $hash).passed){throw 'anchored_read_failed'}
$rejected=$false;try{$null=Read-AclAnchoredJson $file ('0'*64)}catch{if($_.Exception.Message -ceq 'anchored_json_hash_mismatch'){$rejected=$true}else{throw}}
if(!$rejected){throw 'hash_mismatch_accepted'}
$rejected=$false;try{$null=Read-AclConfiguration $file $hash}catch{if($_.Exception.Message -ceq 'acl_config_fields_invalid'){$rejected=$true}else{throw}}
if(!$rejected){throw 'passed_only_config_accepted'}
$c=[pscustomobject]@{frozenReceiptPath=$file;frozenReceiptSha256=$hash;baseDirectory=$FixtureParent;windowId='synthetic-window';candidateSourceCommit=('a'*40);candidateManifestSha256=('b'*64);taskNames=@('\SyntheticCore');ports=@(12345)}
$rejected=$false;try{Assert-FreezeReceipt $c}catch{$rejected=$true}
if(!$rejected){throw 'passed_only_freeze_accepted'}
$f=[ordered]@{format='schema6-frozen-legacy-runtime-ready-v2';passed=$true;databaseReplaced=$false;aclApplied=$false;observationMs=65000;windowDirectory=$FixtureParent;windowId=$c.windowId;candidateSourceCommit=$c.candidateSourceCommit;candidateManifestSha256=$c.candidateManifestSha256;createdUtc=[DateTimeOffset]::UtcNow.AddMinutes(-1).ToString('o');expiresUtc=[DateTimeOffset]::UtcNow.AddMinutes(20).ToString('o');tasks=@(@{name='SyntheticCore';taskPath='\';disabled=$true;instances=0;triggers=0;retries=0;frozenXmlSha256=('d'*64);originalSddl='synthetic-sddl'});portsFree=@(12345)}
function Save-Freeze {$json=$f|ConvertTo-Json -Depth 8;[IO.File]::WriteAllText($file,$json,[Text.UTF8Encoding]::new($false));$c.frozenReceiptSha256=(Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash.ToLowerInvariant()}
Save-Freeze;Assert-FreezeReceipt $c
$expectedTask=[pscustomobject]$f.tasks[0]
$actualTask=$expectedTask|ConvertTo-Json|ConvertFrom-Json
Assert-AclFrozenTaskState $expectedTask $actualTask
foreach($field in @('frozenXmlSha256','originalSddl','disabled','triggers','retries','instances')){
 $changed=$expectedTask|ConvertTo-Json|ConvertFrom-Json
 if($field -eq 'disabled'){$changed.$field=$false}elseif($field -in @('triggers','retries','instances')){$changed.$field=1}else{$changed.$field='changed'}
 $rejected=$false;try{Assert-AclFrozenTaskState $expectedTask $changed}catch{$rejected=$true}
 if(!$rejected){throw 'changed_frozen_task_accepted'}
}
$f.tasks+=@($f.tasks[0]);Save-Freeze
$rejected=$false;try{Assert-FreezeReceipt $c}catch{if($_.Exception.Message -ceq 'freeze_task_duplicate'){$rejected=$true}else{throw}}
if(!$rejected){throw 'duplicate_frozen_task_accepted'}
$f.tasks=@($f.tasks[0]);Save-Freeze
$f.windowId='old-synthetic-window';Save-Freeze
$rejected=$false;try{Assert-FreezeReceipt $c}catch{if($_.Exception.Message -ceq 'freeze_binding_mismatch'){$rejected=$true}else{throw}}
if(!$rejected){throw 'stale_window_accepted'}
$f.windowId=$c.windowId;$f.expiresUtc=[DateTimeOffset]::UtcNow.AddMinutes(-1).ToString('o');Save-Freeze
$rejected=$false;try{Assert-FreezeReceipt $c}catch{if($_.Exception.Message -ceq 'freeze_receipt_expired'){$rejected=$true}else{throw}}
if(!$rejected){throw 'expired_freeze_accepted'}
[Console]::WriteLine('{"passed":true,"importSafe":true,"hashMismatchRejected":true,"passedOnlyRejected":true,"staleWindowRejected":true,"expiredFreezeRejected":true}')
