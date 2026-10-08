param([Parameter(Mandatory=$true)][string]$SourcePath,[Parameter(Mandatory=$true)][string]$FixtureParent)
$ErrorActionPreference='Stop';Set-StrictMode -Version 2
$helperHash=(Get-FileHash -LiteralPath (Join-Path (Split-Path -Parent $SourcePath) 'owned_artifacts.ps1')).Hash.ToLowerInvariant()
$tokens=$null;$errors=$null;$ast=[Management.Automation.Language.Parser]::ParseFile($SourcePath,[ref]$tokens,[ref]$errors)
if($errors.Count){throw ($errors|Out-String)}
# Import functions for synthetic fault injection; never add a production bypass.
foreach($fn in $ast.FindAll({param($n)$n -is [Management.Automation.Language.FunctionDefinitionAst]},$false)){
 if($fn.Name -ceq 'Invoke-BackupConfigProtection'){Set-Item -LiteralPath ('Function:\'+$fn.Name) -Value $fn.Body.GetScriptBlock()}
 else{Invoke-Expression $fn.Extent.Text}
}
Initialize-BackupConfigAclNative
$owner=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value
$private=[Security.AccessControl.DirectorySecurity]::new()
$private.SetSecurityDescriptorSddlForm(('O:'+$owner+'D:P(A;OICI;FA;;;'+$owner+')(A;OICI;FA;;;SY)(A;OICI;FA;;;BA)'),[Security.AccessControl.AccessControlSections]::Access)
[IO.Directory]::SetAccessControl($FixtureParent,$private)
$checks=[Collections.Generic.List[string]]::new()
function Check([bool]$Condition,[string]$Name){if(!$Condition){throw ('check_failed_'+$Name)};$checks.Add($Name)}
function New-Case([string]$Name) {
 $base=Join-Path $FixtureParent $Name;[IO.Directory]::CreateDirectory($base)|Out-Null
 $caseAcl=[Security.AccessControl.DirectorySecurity]::new();$caseAcl.SetSecurityDescriptorSddlForm($private.GetSecurityDescriptorSddlForm([Security.AccessControl.AccessControlSections]::Access),[Security.AccessControl.AccessControlSections]::Access)
 [IO.Directory]::SetAccessControl($base,$caseAcl)
 $target=Join-Path $base 'synthetic-config.json';[IO.File]::WriteAllText($target,'{"synthetic":true}',[Text.UTF8Encoding]::new($false))
 $sibling=Join-Path $base 'sibling.json';[IO.File]::WriteAllText($sibling,'{"sibling":true}',[Text.UTF8Encoding]::new($false))
 $sddl=(Get-Acl -LiteralPath $target).Sddl
 $h=[BackupConfigAclNative]::Open($target,$false,$false);try{$identity=[BackupConfigAclNative]::Check($h,$target,$false)}finally{$h.Dispose()}
 $params=@{Path=$target;ExpectedOwnerSid=$owner;ExpectedContentSha256=(Get-FileHash -LiteralPath $target).Hash.ToLowerInvariant();ExpectedOriginalDaclSha256=Get-BackupConfigHash ([Text.Encoding]::UTF8.GetBytes((Get-BackupConfigDacl $sddl)));ExpectedProposedDaclSha256=Get-BackupConfigHash ([Text.Encoding]::UTF8.GetBytes((Get-BackupConfigProposedDacl $owner)));ReceiptDirectory=Join-Path $base 'receipt';ExpectedOwnedArtifactsSha256=$helperHash;Execute=$true}
 return [pscustomobject]@{base=$base;target=$target;sibling=$sibling;siblingSddl=(Get-Acl -LiteralPath $sibling).Sddl;parentSddl=(Get-Acl -LiteralPath $base).Sddl;sddl=$sddl;hash=$params.ExpectedContentSha256;identity=$identity;params=$params}
}
function Run-Case($c){$p=$c.params;return Invoke-BackupConfigProtection @p}
function Original-Intact($c){return ((Get-Acl -LiteralPath $c.target).Sddl -ceq $c.sddl -and (Get-FileHash -LiteralPath $c.target).Hash.ToLowerInvariant() -ceq $c.hash)}
function Unchanged-Other($c){return ((Get-Acl -LiteralPath $c.base).Sddl -ceq $c.parentSddl -and (Get-Acl -LiteralPath $c.sibling).Sddl -ceq $c.siblingSddl -and [IO.File]::ReadAllText($c.sibling) -ceq '{"sibling":true}')}
$c=New-Case 'success'
$before=Get-Acl -LiteralPath $c.target
Check (!$before.AreAccessRulesProtected -and @($before.GetAccessRules($true,$true,[Security.Principal.SecurityIdentifier])).Count -eq 3) 'synthetic_original_three_inherited'
$h=[BackupConfigAclNative]::Open($c.target,$false,$false);$rejected=$false
try{try{Assert-BackupConfigFixedAcl $h $owner}catch{$rejected=$_.Exception.Message -ceq 'custody_acl_invalid'}}finally{$h.Dispose()}
Check $rejected 'fixed_rule_rejects_original_inherited_three'
$r=Run-Case $c
if(!$r.passed){throw ('success_failed_'+($r|ConvertTo-Json -Compress)+'; synthetic diagnostic: '+$Error[0].Exception.Message+'; '+$Error[0].ScriptStackTrace)}
$after=Get-Acl -LiteralPath $c.target
Check ($r.passed -and !$r.rollbackAttempted -and $after.AreAccessRulesProtected -and @($after.GetAccessRules($true,$true,[Security.Principal.SecurityIdentifier])).Count -eq 2) 'inherited_three_to_protected_two'
$custodyPath=Join-Path (Split-Path -Parent (Split-Path -Parent $SourcePath)) 'release_schema6\key_custody.ps1'
. $custodyPath -Action Library
Assert-BackupPrivateAcl $c.target
Check $true 'fixed_production_assertion_accepts'
$h=[BackupConfigAclNative]::Open($c.target,$false,$false);try{$same=[BackupConfigAclNative]::Check($h,$c.target,$false) -ceq $c.identity}finally{$h.Dispose()}
Check ($same -and $after.GetOwner([Security.Principal.SecurityIdentifier]).Value -ceq $owner -and (Get-FileHash -LiteralPath $c.target).Hash.ToLowerInvariant() -ceq $c.hash -and (Unchanged-Other $c)) 'unchanged_identity_bytes_owner_parent_sibling'
foreach($p in @($c.params.ReceiptDirectory,(Join-Path $c.params.ReceiptDirectory 'original.json'),(Join-Path $c.params.ReceiptDirectory 'result.json'))){Check ((Get-Acl -LiteralPath $p).GetOwner([Security.Principal.SecurityIdentifier]).Value -ceq $owner) ('receipt_owner_'+[IO.Path]::GetFileName($p))}
$snapshot=Get-Content -LiteralPath (Join-Path $c.params.ReceiptDirectory 'original.json') -Raw|ConvertFrom-Json
$result=Get-Content -LiteralPath (Join-Path $c.params.ReceiptDirectory 'result.json') -Raw|ConvertFrom-Json
Check ($snapshot.originalDacl -ceq (Get-BackupConfigDacl $c.sddl) -and $snapshot.contentSha256 -ceq $c.hash) 'receipt_owner_readback'
Check ($null -eq $result.passed -and !$result.terminal -and $result.phase -ceq 'validated_requires_successful_exit' -and $r.passed -and $r.terminal -and $r.phase -ceq 'completed') 'success_checkpoint_is_nonterminal'
Check (!(Get-Content -LiteralPath (Join-Path $c.params.ReceiptDirectory 'original.json') -Raw).Contains('{"synthetic":true}')) 'receipt_excludes_content'
foreach($case in @('wrong_content','wrong_owner','wrong_original_dacl','wrong_proposed_dacl','wrong_helper','hardlink','reparse','existing_receipt','unprotected_output','foreign_output_ace','overlap','noncanonical','directory_target')){
 $c=New-Case $case
 switch($case){
  wrong_content {$c.params.ExpectedContentSha256='0'*64}
  wrong_owner {$c.params.ExpectedOwnerSid='S-1-0-0'}
  wrong_original_dacl {$c.params.ExpectedOriginalDaclSha256='0'*64}
  wrong_proposed_dacl {$c.params.ExpectedProposedDaclSha256='0'*64}
  wrong_helper {$c.params.ExpectedOwnedArtifactsSha256='0'*64}
  hardlink {New-Item -ItemType HardLink -Path (Join-Path $c.base 'link.json') -Target $c.target|Out-Null}
  reparse {$actual=$c.base+'-actual';[IO.Directory]::Move($c.base,$actual);New-Item -ItemType Junction -Path $c.base -Target $actual|Out-Null}
  existing_receipt {[IO.Directory]::CreateDirectory($c.params.ReceiptDirectory)|Out-Null}
  unprotected_output {$p=Join-Path $c.base 'inherited-output';[IO.Directory]::CreateDirectory($p)|Out-Null;$c.params.ReceiptDirectory=Join-Path $p 'receipt'}
  foreign_output_ace {$a=Get-Acl -LiteralPath $c.base;$a.AddAccessRule([Security.AccessControl.FileSystemAccessRule]::new([Security.Principal.SecurityIdentifier]::new('S-1-1-0'),'Read','Allow'));[IO.Directory]::SetAccessControl($c.base,$a)}
  overlap {$c.params.ReceiptDirectory=$c.target}
  noncanonical {$c.params.Path=$c.base+'\..\'+[IO.Path]::GetFileName($c.base)+'\synthetic-config.json'}
  directory_target {$c.params.Path=$c.base}
 }
 $r=Run-Case $c
 Check (!$r.passed -and !$r.rollbackAttempted -and (Original-Intact $c)) ('reject_'+$case)
 if($case -eq 'reparse'){[IO.Directory]::Delete($c.base)}
}
$c=New-Case 'no_execute';$c.params.Remove('Execute');$rejected=$false
try{Run-Case $c|Out-Null}catch{$rejected=$_.Exception.Message -ceq 'explicit_execute_required'}
Check ($rejected -and (Original-Intact $c)) 'reject_missing_execute'
$realSet=${function:Set-BackupConfigDacl};$realReceipt=${function:Write-BackupConfigReceipt}
function Set-BackupConfigDacl($Handle,[string]$Sddl,[bool]$Protected){[BackupConfigAclNative]::DaclOnly($Handle,$Sddl,$Protected);if($Protected){throw 'synthetic_after_write_failure'}}
$c=New-Case 'rollback';$r=Run-Case $c
Check (!$r.passed -and $r.rollbackAttempted -and $r.rollbackVerified -and (Original-Intact $c) -and (Unchanged-Other $c)) 'failure_restores_exact_dacl'
Check ((Get-Content -LiteralPath (Join-Path $c.params.ReceiptDirectory 'failure.json') -Raw|ConvertFrom-Json).rollbackVerified) 'durable_rollback_receipt'
function Set-BackupConfigDacl($Handle,[string]$Sddl,[bool]$Protected){if($Protected){[BackupConfigAclNative]::DaclOnly($Handle,$Sddl,$Protected);throw 'synthetic_after_write_failure'};throw 'synthetic_rollback_failure'}
$c=New-Case 'rollback_fails';$r=Run-Case $c
Check (!$r.passed -and $r.rollbackAttempted -and !$r.rollbackVerified -and $r.requiresReviewedRecovery -and $null -eq $r.ownerChanged -and $null -eq $r.fileBytesChanged) 'rollback_failure_remains_unknown'
Set-Item Function:Set-BackupConfigDacl $realSet
function Write-BackupConfigReceipt([string]$Name,$Value){if($Name -ceq 'original.json'){throw 'synthetic_snapshot_failure'};& $realReceipt $Name $Value}
$c=New-Case 'snapshot_failure';$r=Run-Case $c
Check (!$r.passed -and !$r.rollbackAttempted -and (Original-Intact $c)) 'snapshot_failure_before_mutation'
function Write-BackupConfigReceipt([string]$Name,$Value){if($Name -ceq 'result.json'){throw 'synthetic_result_failure'};& $realReceipt $Name $Value}
$c=New-Case 'result_failure';$r=Run-Case $c
Check (!$r.passed -and $r.rollbackAttempted -and $r.rollbackVerified -and (Original-Intact $c)) 'result_failure_rolls_back'
Set-Item Function:Write-BackupConfigReceipt $realReceipt
function Check-FailedCheckpoint($c,$r,[string]$Name) {
 $checkpoint=Get-Content -LiteralPath (Join-Path $c.params.ReceiptDirectory 'result.json') -Raw|ConvertFrom-Json
 $failure=Get-Content -LiteralPath (Join-Path $c.params.ReceiptDirectory 'failure.json') -Raw|ConvertFrom-Json
 Check (!$r.passed -and $r.terminal -and $r.phase -ceq 'failed' -and $r.rollbackVerified -and (Original-Intact $c) -and $null -eq $checkpoint.passed -and !$checkpoint.terminal -and $checkpoint.phase -ceq 'validated_requires_successful_exit' -and !$failure.passed -and $failure.terminal -and $failure.rollbackVerified) $Name
}
# Real file creation/readback succeeds, then the writer reports failure.
function Write-BackupConfigReceipt([string]$Name,$Value){$hash=& $realReceipt $Name $Value;if($Name -ceq 'result.json'){throw 'synthetic_after_result_write_failure'};return $hash}
$c=New-Case 'after_result_write_failure';$r=Run-Case $c
Check-FailedCheckpoint $c $r 'written_result_failure_has_no_terminal_success'
Set-Item Function:Write-BackupConfigReceipt $realReceipt
# The last applied-state assertion fails after result.json has been durably written.
$realAssert=${function:Assert-BackupConfigState};$script:appliedAssertions=0
function Assert-BackupConfigState([bool]$Applied){& $realAssert $Applied;if($Applied){$script:appliedAssertions++;if($script:appliedAssertions -eq 2){throw 'synthetic_final_assertion_failure'}}}
$c=New-Case 'final_assertion_failure';$r=Run-Case $c
Check-FailedCheckpoint $c $r 'final_assertion_failure_has_no_terminal_success'
Set-Item Function:Assert-BackupConfigState $realAssert
function Set-BackupConfigDacl($Handle,[string]$Sddl,[bool]$Protected){
 if($Protected){
  foreach($p in @($Path,(Join-Path $ReceiptDirectory 'original.json'))){
   $blocked=$false;try{$w=[IO.File]::OpenWrite($p);$w.Dispose()}catch{$blocked=$true};if(!$blocked){throw 'write_not_blocked'}
   $blocked=$false;try{[IO.File]::Move($p,($p+'.moved'))}catch{$blocked=$true};if(!$blocked){throw 'rename_not_blocked'}
   $blocked=$false;try{[IO.File]::Delete($p)}catch{$blocked=$true};if(!$blocked){throw 'delete_not_blocked'}
  }
  $script:locked=$true
 }
 [BackupConfigAclNative]::DaclOnly($Handle,$Sddl,$Protected)
}
$c=New-Case 'locks';$script:locked=$false;$r=Run-Case $c
Check ($r.passed -and $script:locked) 'snapshot_and_target_locked'
Set-Item Function:Set-BackupConfigDacl $realSet
$c=New-Case 'hardlink_race';$h=[BackupConfigAclNative]::Open($c.target,$false,$true);$rejected=$false
try{
 try{New-Item -ItemType HardLink -Path (Join-Path $c.base 'late-link.json') -Target $c.target|Out-Null}catch{$rejected=$true}
 if(!$rejected){try{[BackupConfigAclNative]::Check($h,$c.target,$false)|Out-Null}catch{$rejected=$true}}
}finally{$h.Dispose()}
Check $rejected 'hardlink_race_rejected_or_detected'
# Actual top-level dispatch in a fresh PS5 process.
$c=New-Case 'dispatch';$p=$c.params
$output=& (Join-Path $PSHOME 'powershell.exe') -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $SourcePath -Path $p.Path -ExpectedContentSha256 $p.ExpectedContentSha256 -ExpectedOwnerSid $p.ExpectedOwnerSid -ExpectedOriginalDaclSha256 $p.ExpectedOriginalDaclSha256 -ExpectedProposedDaclSha256 $p.ExpectedProposedDaclSha256 -ReceiptDirectory $p.ReceiptDirectory -ExpectedOwnedArtifactsSha256 $helperHash -Execute
$completion=$output|ConvertFrom-Json
Check ($LASTEXITCODE -eq 0 -and $completion.passed -and $completion.terminal -and $completion.phase -ceq 'completed' -and (Unchanged-Other $c)) 'dispatch_success'
[pscustomobject]@{passed=$true;checks=$checks.ToArray();psMajor=$PSVersionTable.PSVersion.Major;productionPathsTouched=$false;privilegeEnabled=$false;sourceSha256=(Get-FileHash -LiteralPath $SourcePath).Hash.ToLowerInvariant()}|ConvertTo-Json -Depth 5
