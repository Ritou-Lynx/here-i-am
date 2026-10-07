#requires -Version 5.1
# Import-safe. The window launcher must explicitly call this function in a fresh,
# same-owner elevated PowerShell process with reviewed source/config SHA256 anchors.
function Invoke-OwnerAclMaintenance {
 [CmdletBinding()]
 param(
  [Parameter(Mandatory=$true)][string]$ScriptPath,
  [Parameter(Mandatory=$true)][string]$ExpectedScriptSha256,
  [Parameter(Mandatory=$true)][string]$ConfigPath,
  [Parameter(Mandatory=$true)][string]$ExpectedConfigSha256,
  [Parameter(Mandatory=$true)][ValidateSet('Apply','Rollback')][string]$Mode,
  [switch]$ConfirmFrozen
 )
 Set-StrictMode -Version 2
 $ErrorActionPreference='Stop'
 if(!$ConfirmFrozen){throw 'explicit_frozen_confirmation_required'}
 if($ExpectedScriptSha256 -cnotmatch '^[a-f0-9]{64}$'){throw 'sha256_anchor_required'}
 if($ScriptPath -notmatch '^[A-Za-z]:\\' -or [IO.Path]::GetFullPath($ScriptPath) -cne $ScriptPath -or $ScriptPath.Substring(2).Contains(':')){throw 'canonical_path_required'}
 for($q=$ScriptPath;$q;$q=[IO.Path]::GetDirectoryName($q)){if(((Get-Item -LiteralPath $q -Force).Attributes-band [IO.FileAttributes]::ReparsePoint)-ne 0){throw 'reparse_path_rejected'}}
 # Deny replacement/writes until the imported implementation has completed.
 $sourceLock=[IO.File]::Open($ScriptPath,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read)
 try {
  $sha=[Security.Cryptography.SHA256]::Create()
  try{$hash=([BitConverter]::ToString($sha.ComputeHash($sourceLock))).Replace('-','').ToLowerInvariant()}finally{$sha.Dispose()}
  if($hash -cne $ExpectedScriptSha256){throw 'maintenance_script_hash_changed'}
  . $ScriptPath
  $c=Read-AclConfiguration $ConfigPath $ExpectedConfigSha256
  if([Security.Principal.WindowsIdentity]::GetCurrent().User.Value -cne $c.ownerSid){throw 'owner_mismatch'}
  if(!(New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)){throw 'administrator_required'}
  if(Test-Path -LiteralPath $c.receiptPath){throw 'fresh_receipt_required'}
  $started=[DateTimeOffset]::UtcNow
  $answer=Invoke-AclMaintenance -ConfigPath $ConfigPath -ExpectedConfigSha256 $ExpectedConfigSha256 -Mode $Mode -ConfirmFrozen
  if(!$answer.passed -or $answer.exitCode -ne 0){throw 'acl_maintenance_failed'}
  $receipt=Get-Content -LiteralPath $c.receiptPath -Raw -Encoding UTF8|ConvertFrom-Json
  if($receipt.format -cne 'schema6-acl-maintenance-v2' -or $receipt.mode -cne $Mode -or $receipt.passed -ne $true -or [DateTimeOffset]::Parse($receipt.started_utc) -lt $started){throw 'apply_receipt_rejected'}
  foreach($key in @('windowId','candidateSourceCommit','candidateManifestSha256')){if($receipt.$key -cne $c.$key){throw 'apply_receipt_binding_mismatch'}}
  if($receipt.freezeSha256 -cne $c.frozenReceiptSha256){throw 'apply_receipt_binding_mismatch'}
  if($receipt.configSha256 -cne $ExpectedConfigSha256 -or $receipt.snapshot_sha256 -cne $c.snapshotSha256 -or $receipt.verified_count -ne $c.expectedCount -or $receipt.expected_count -ne $c.expectedCount -or $receipt.expected_foreign_owner_count -ne $c.expectedForeignOwnerCount){throw 'apply_receipt_anchor_mismatch'}
  $snapshot=@(Read-AclAnchoredJson $c.snapshotPath $c.snapshotSha256)
  $action=if($Mode -eq 'Apply'){'apply_readback'}else{'restore_readback'}
  $verified=@($receipt.items|Where-Object {$_.action -ceq $action})
  if($verified.Count -ne $c.expectedCount){throw 'apply_receipt_item_count'}
  $seen=@{}
  foreach($item in $verified){if($item.verified -ne $true -or $seen.ContainsKey($item.path)){throw 'apply_receipt_item_invalid'};$seen[$item.path]=$true}
  if($snapshot.Count -ne $c.expectedCount){throw 'apply_snapshot_count'}
  foreach($row in $snapshot){if(!$seen.ContainsKey($row.path)){throw 'apply_receipt_path_missing'}}
  # A structured receipt is evidence for this operation only, never a green UI Gate.
  return [pscustomobject]@{passed=$true;receipt=$c.receiptPath;verifiedCount=$verified.Count;windowId=$c.windowId;mode=$Mode;scope='owner_and_dacl_only';humanAcceptance=$false}
 }finally{$sourceLock.Dispose()}
}
