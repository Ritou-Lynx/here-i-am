#requires -Version 5.1
param([Parameter(Mandatory=$true)][string]$SourcePath,[Parameter(Mandatory=$true)][string]$FixtureParent)
$ErrorActionPreference='Stop';Set-StrictMode -Version 2
$sourceRoot=Split-Path -Parent $SourcePath
. $SourcePath
. (Join-Path $sourceRoot 'maintenance_window.ps1')
. (Join-Path $sourceRoot 'prepare_live_guard.ps1')
. (Join-Path $sourceRoot 'acl-cutover-maintenance.ps1')
Initialize-OwnedArtifactNative;Initialize-CutoverAclNative
$identity=[Security.Principal.WindowsIdentity]::GetCurrent();$ownerSid=$identity.User.Value
$checks=[Collections.Generic.List[string]]::new()
function Check([string]$Name,[bool]$Condition){if(!$Condition){throw ('synthetic_assertion_failed_'+$Name)};$checks.Add($Name)}
function Rejected([scriptblock]$Action,[string]$Code=''){
 try{& $Action;return $false}catch{if($Code -and $_.Exception.ToString()-notmatch [regex]::Escape($Code)){throw};return $true}
}
$root=Join-Path $FixtureParent 'fresh-artifacts'
New-OwnedArtifactDirectory $root $ownerSid
$acl=Get-Acl -LiteralPath $root
Check 'directory_private_owner' ($acl.AreAccessRulesProtected-and $acl.GetOwner([Security.Principal.SecurityIdentifier]).Value-ceq $ownerSid)
$first=[CutoverAclNative]::OpenSourceDirectory($root);$second=$null
try{
 $firstId=[OwnedArtifactNative]::Check($first,$root,$true);$second=[CutoverAclNative]::OpenSourceDirectory($root)
 Check 'directory_handle_identity_stable' ([OwnedArtifactNative]::Check($second,$root,$true)-ceq $firstId)
 Check 'directory_rename_denied' (Rejected {[IO.Directory]::Move($root,($root+'-moved'))})
}finally{if($second){$second.Dispose()};$first.Dispose()}
$moved=$root+'-moved'
[IO.Directory]::Move($root,$moved)
try{Check 'directory_rename_after_lease_release' ((Test-Path -LiteralPath $moved)-and !(Test-Path -LiteralPath $root))}finally{[IO.Directory]::Move($moved,$root)}
$file=Join-Path $root 'receipt.json';$bytes=[Text.Encoding]::UTF8.GetBytes('{"passed":true,"synthetic":true}')
Write-OwnedArtifactBytes $file $bytes $ownerSid
$acl=Get-Acl -LiteralPath $file
Check 'file_private_owner' ($acl.AreAccessRulesProtected-and $acl.GetOwner([Security.Principal.SecurityIdentifier]).Value-ceq $ownerSid)
Check 'file_bytes_readback' ([Convert]::ToBase64String([IO.File]::ReadAllBytes($file))-ceq [Convert]::ToBase64String($bytes))
$hash=(Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash.ToLowerInvariant();$pin=Open-PreparePin $file $hash
try{Check 'real_prepare_consumer' ($pin.Length-eq $bytes.Length)}finally{$pin.Dispose()}
Check 'duplicate_file_rejected' (Rejected {Write-OwnedArtifactBytes $file ([Text.Encoding]::UTF8.GetBytes('replacement')) $ownerSid})
Check 'duplicate_file_bytes_preserved' ([Convert]::ToBase64String([IO.File]::ReadAllBytes($file))-ceq [Convert]::ToBase64String($bytes))
$wrong=Join-Path $root 'wrong-owner.json'
Check 'wrong_owner_zero_artifact' ((Rejected {Write-OwnedArtifactBytes $wrong $bytes 'S-1-5-32-544'} 'artifact_same_owner_required')-and !(Test-Path -LiteralPath $wrong))
$null=New-Item -ItemType HardLink -Path (Join-Path $root 'receipt-link.json') -Target $file
Check 'hardlink_rejected' (Rejected {Assert-OwnedArtifact $file $ownerSid} 'artifact_identity_rejected')
$window=Open-MaintenanceWindow $root 'synthetic-window-01'
try{
 Check 'window_private_owner' ((Get-Acl -LiteralPath $window.Directory).GetOwner([Security.Principal.SecurityIdentifier]).Value-ceq $ownerSid)
 Check 'guard_exclusive' (Rejected {$other=Acquire-MaintenanceGuard $root;$other.Dispose()})
}finally{Close-MaintenanceWindow $window}
$guard=Acquire-MaintenanceGuard $root
try{Check 'guard_reacquired' (!$guard.SafeFileHandle.IsInvalid)}finally{$guard.Dispose()}
Check 'old_window_id_rejected' (Rejected {$other=Open-MaintenanceWindow $root 'synthetic-window-01';Close-MaintenanceWindow $other} 'window_id_already_used')
$before=(Get-Acl -LiteralPath $root).Sddl
Check 'directory_collision_preserves_sddl' ((Rejected {New-OwnedArtifactDirectory $root $ownerSid})-and (Get-Acl -LiteralPath $root).Sddl-ceq $before)
# Hosted tests may have a user TokenOwner but remain elevated. Classify actual
# token; never skip native tests or pretend this is ordinary-user evidence.
Add-Type -TypeDefinition @"
using System;using System.ComponentModel;using System.Runtime.InteropServices;
public static class OwnedFixtureToken {
 [DllImport("advapi32.dll",SetLastError=true)] static extern bool GetTokenInformation(IntPtr token,int kind,out int value,int size,out int returned);
 public static bool Elevated(IntPtr token){int value,size;if(!GetTokenInformation(token,20,out value,4,out size)||size!=4)throw new Win32Exception(Marshal.GetLastWin32Error());return value!=0;}
}
"@
$elevated=[OwnedFixtureToken]::Elevated($identity.Token)
$administrator=([Security.Principal.WindowsPrincipal]::new($identity)).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
$ordinary=(!$elevated-and !$administrator-and $identity.Owner.Value-ceq $ownerSid)
$rejected=Rejected {Assert-OwnedArtifactUnelevatedProcess $ownerSid}
Check 'ordinary_token_gate_matches_actual_token' ($rejected-eq (!$ordinary))
Check 'ordinary_token_wrong_sid_rejected' (Rejected {Assert-OwnedArtifactUnelevatedProcess 'S-1-5-32-544'} 'maintenance_unelevated_owner_required')
# Hardlink only fresh fixture copies, never production source. Both source gate
# failures must precede even reading the deliberately nonexistent ACL config.
$sourceCopy=Join-Path $root 'source-copy';New-OwnedArtifactDirectory $sourceCopy $ownerSid
$helperCopy=Join-Path $sourceCopy 'owned_artifacts.ps1';$aclCopy=Join-Path $sourceCopy 'acl-cutover-maintenance.ps1'
Write-OwnedArtifactBytes $helperCopy ([IO.File]::ReadAllBytes($SourcePath)) $ownerSid
Write-OwnedArtifactBytes $aclCopy ([IO.File]::ReadAllBytes((Join-Path $sourceRoot 'acl-cutover-maintenance.ps1'))) $ownerSid
. $aclCopy
$neverConfig=Join-Path $sourceCopy 'never-created-config.json'
Check 'acl_helper_wrong_hash_rejected_before_config' (Rejected {Invoke-AclMaintenance -ConfigPath $neverConfig -ExpectedConfigSha256 ('b'*64) -ExpectedOwnedArtifactsSha256 ('0'*64) -Mode Audit|Out-Null} 'owned_artifact_source_hash_rejected')
$helperHash=(Get-FileHash -LiteralPath $helperCopy -Algorithm SHA256).Hash.ToLowerInvariant()
$null=New-Item -ItemType HardLink -Path (Join-Path $sourceCopy 'linked-helper.ps1') -Target $helperCopy
Check 'acl_helper_linked_source_rejected_before_config' (Rejected {Invoke-AclMaintenance -ConfigPath $neverConfig -ExpectedConfigSha256 ('b'*64) -ExpectedOwnedArtifactsSha256 $helperHash -Mode Audit|Out-Null} 'linked_target_rejected')
[pscustomobject]@{passed=$true;checks=@($checks.ToArray());productionPathsTouched=$false;privilegeEnabled=$false;skipped=$false;tokenClassification=$(if($ordinary){'ordinary_owner'}else{'elevated_or_nonowner_default'})}|ConvertTo-Json -Depth 4 -Compress
