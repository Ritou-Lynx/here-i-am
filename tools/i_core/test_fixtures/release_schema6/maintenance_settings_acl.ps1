param([Parameter(Mandatory=$true)][string]$SourcePath,[Parameter(Mandatory=$true)][string]$FixtureParent)
$ErrorActionPreference='Stop';Set-StrictMode -Version 2
$tokens=$null;$errors=$null;$ast=[Management.Automation.Language.Parser]::ParseFile($SourcePath,[ref]$tokens,[ref]$errors)
if($errors.Count){throw ($errors|Out-String)}
# Import only reviewed function definitions, never top-level production dispatch.
foreach($fn in $ast.FindAll({param($n)$n -is [Management.Automation.Language.FunctionDefinitionAst]},$false)){Invoke-Expression $fn.Extent.Text}
Initialize-SettingsAclNative
$owner=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value
$private=[Security.AccessControl.DirectorySecurity]::new()
$private.SetSecurityDescriptorSddlForm(('O:'+$owner+'D:P(A;OICI;FA;;;'+$owner+')(A;OICI;FA;;;SY)(A;OICI;FA;;;BA)'),[Security.AccessControl.AccessControlSections]::Access)
[IO.Directory]::SetAccessControl($FixtureParent,$private)
$checks=[Collections.Generic.List[string]]::new()
function New-Case([string]$Name) {
 $base=Join-Path $FixtureParent $Name;[IO.Directory]::CreateDirectory($base)|Out-Null
 $caseAcl=[Security.AccessControl.DirectorySecurity]::new();$caseAcl.SetSecurityDescriptorSddlForm($private.GetSecurityDescriptorSddlForm([Security.AccessControl.AccessControlSections]::Access),[Security.AccessControl.AccessControlSections]::Access);[IO.Directory]::SetAccessControl($base,$caseAcl)
 $root=Join-Path $base 'settings';[IO.Directory]::CreateDirectory($root)|Out-Null
 foreach($n in @('one.json','two.json','three.json')){[IO.File]::WriteAllText((Join-Path $root $n),'{"synthetic":true}',[Text.UTF8Encoding]::new($false))}
 $rows=@(foreach($item in @((Get-Item -LiteralPath $root))+@(Get-ChildItem -LiteralPath $root)){
  $r=[ordered]@{path=$item.FullName;directory=[bool]$item.PSIsContainer;originalSddl=(Get-Acl -LiteralPath $item.FullName).Sddl}
  if(!$item.PSIsContainer){$r.sha256=(Get-FileHash -LiteralPath $item.FullName).Hash.ToLowerInvariant()};[pscustomobject]$r
 })
 $acl=Get-Acl -LiteralPath $root;$before=$acl.Sddl;$acl.SetAccessRuleProtection($true,$true);$expected=$acl.Sddl
 $proposal=[pscustomobject]@{format='schema6-production-settings-acl-proposal-v1';requiresNewAuthorization=$true;executed=$false;preserveOwnerAndRights=$true;operation='directory-only SetAccessRuleProtection(true,true), preserve all ACEs';rollback='restore original directory DACL';path=$root;beforeSddlSha256=Get-SettingsHash ([Text.Encoding]::UTF8.GetBytes($before));expectedSddlSha256=Get-SettingsHash ([Text.Encoding]::UTF8.GetBytes($expected));expectedSddl=$expected;objects=$rows}
 return [pscustomobject]@{base=$base;root=$root;originalRows=($rows|ConvertTo-Json -Depth 8|ConvertFrom-Json);proposal=$proposal;proposalPath=Join-Path $base 'proposal.json';receipt=Join-Path $base 'receipt'}
}
function Save-Case($c){[IO.File]::WriteAllText($c.proposalPath,($c.proposal|ConvertTo-Json -Depth 8),[Text.UTF8Encoding]::new($false));return (Get-FileHash -LiteralPath $c.proposalPath).Hash.ToLowerInvariant()}
function Run-Case($c,[string]$Hash='') {if(!$Hash){$Hash=Save-Case $c};return Invoke-SettingsProtection -ProposalPath $c.proposalPath -ExpectedProposalSha256 $Hash -ReceiptDirectory $c.receipt -Execute}
function Check([bool]$Condition,[string]$Name){if(!$Condition){throw ('check_failed_'+$Name)};$checks.Add($Name)}
function Original-Intact($c){foreach($r in $c.originalRows){if((Get-Acl -LiteralPath $r.path).Sddl -cne $r.originalSddl){return $false};if(!$r.directory -and (Get-FileHash -LiteralPath $r.path).Hash.ToLowerInvariant() -cne $r.sha256){return $false}};return $true}
$c=New-Case 'success';$r=Run-Case $c
if(!$r.passed){throw ('success_failed_'+$r.errorCode)}
Check ($r.passed -and !$r.rollbackAttempted -and (Get-Acl -LiteralPath $c.root).Sddl -ceq $c.proposal.expectedSddl) 'protection_success'
foreach($f in $c.proposal.objects|Where-Object {!$_.directory}){Check ((Get-Acl -LiteralPath $f.path).Sddl -ceq $f.originalSddl -and (Get-FileHash -LiteralPath $f.path).Hash.ToLowerInvariant() -ceq $f.sha256) ('unchanged_'+[IO.Path]::GetFileName($f.path))}
Check ((Test-Path (Join-Path $c.receipt 'original.json')) -and (Test-Path (Join-Path $c.receipt 'result.json')) -and (Get-Acl -LiteralPath $c.receipt).AreAccessRulesProtected) 'durable_private_receipt'
foreach($case in @('wrong_proposal','wrong_hash','extra_file','sddl_drift','changed_rights','hardlink','reparse','existing_receipt','unprotected_output','overlap','foreign_output_ace')){
 $c=New-Case $case;$hash=Save-Case $c
 switch($case){
  wrong_proposal {$hash='0'*64}
  wrong_hash {$c.proposal.objects[1].sha256='0'*64;$hash=Save-Case $c}
  extra_file {[IO.File]::WriteAllText((Join-Path $c.root 'extra.json'),'extra')}
  sddl_drift {$a=Get-Acl -LiteralPath $c.root;$a.SetAccessRuleProtection($true,$true);[IO.Directory]::SetAccessControl($c.root,$a)}
  changed_rights {$c.proposal.expectedSddl=$c.proposal.expectedSddl.Replace('FA','FR');$c.proposal.expectedSddlSha256=Get-SettingsHash ([Text.Encoding]::UTF8.GetBytes($c.proposal.expectedSddl));$hash=Save-Case $c}
  hardlink {New-Item -ItemType HardLink -Path (Join-Path $c.base 'link.json') -Target $c.proposal.objects[1].path|Out-Null}
  reparse {Rename-Item -LiteralPath $c.root -NewName 'actual-settings';New-Item -ItemType Junction -Path $c.root -Target (Join-Path $c.base 'actual-settings')|Out-Null}
  existing_receipt {[IO.Directory]::CreateDirectory($c.receipt)|Out-Null}
  unprotected_output {$p=Join-Path $c.base 'unprotected';[IO.Directory]::CreateDirectory($p)|Out-Null;$c.receipt=Join-Path $p 'receipt'}
  overlap {$c.receipt=Join-Path $c.root 'receipt'}
  foreign_output_ace {$p=Join-Path $c.base 'foreign';[IO.Directory]::CreateDirectory($p)|Out-Null;$a=Get-Acl -LiteralPath $p;$a.SetAccessRuleProtection($true,$true);$a.AddAccessRule([Security.AccessControl.FileSystemAccessRule]::new([Security.Principal.SecurityIdentifier]::new('S-1-1-0'),'Read','Allow'));[IO.Directory]::SetAccessControl($p,$a);$c.receipt=Join-Path $p 'receipt'}
 }
 $r=Run-Case $c $hash
 Check (!$r.passed -and !$r.rollbackAttempted) ('reject_'+$case)
 if($case -notin @('sddl_drift','reparse')){Check (Original-Intact $c) ('no_mutation_'+$case)}
 if($case -eq 'reparse'){[IO.Directory]::Delete($c.root)}
}
$c=New-Case 'owner';$h=[SettingsAclNative]::Open($c.root,$true,$false);$savedOwner=$owner;$owner='S-1-0-0';$rejected=$false
try{Assert-SettingsPrivate $h $false}catch{$rejected=$_.Exception.Message -ceq 'owner_mismatch'}finally{$h.Dispose();$owner=$savedOwner}
Check $rejected 'reject_owner_mismatch'
$c=New-Case 'no_execute';$hash=Save-Case $c;$rejected=$false
try{Invoke-SettingsProtection -ProposalPath $c.proposalPath -ExpectedProposalSha256 $hash -ReceiptDirectory $c.receipt|Out-Null}catch{$rejected=$_.Exception.Message -ceq 'explicit_execute_required'}
Check ($rejected -and (Original-Intact $c)) 'reject_missing_execute'
$realSet=${function:Set-SettingsDacl};$realReceipt=${function:Write-SettingsReceipt}
function Set-SettingsDacl($Handle,[string]$Sddl,[bool]$Protected){[SettingsAclNative]::DaclOnly($Handle,$Sddl,$Protected);if($Protected){throw 'synthetic_after_write_failure'}}
$c=New-Case 'rollback';$r=Run-Case $c
Check (!$r.passed -and $r.rollbackAttempted -and $r.rollbackVerified -and (Original-Intact $c)) 'failure_restores_exact_dacl_and_files'
Check ((Get-Content -LiteralPath (Join-Path $c.receipt 'failure.json') -Raw|ConvertFrom-Json).rollbackVerified) 'durable_rollback_receipt'
function Set-SettingsDacl($Handle,[string]$Sddl,[bool]$Protected){if($Protected){[SettingsAclNative]::DaclOnly($Handle,$Sddl,$Protected);throw 'synthetic_after_write_failure'};throw 'synthetic_rollback_failure'}
$c=New-Case 'rollback_fails';$r=Run-Case $c
Check (!$r.passed -and $r.rollbackAttempted -and !$r.rollbackVerified -and $r.requiresReviewedRecovery -and $null -eq $r.ownerChanged -and $null -eq $r.childAclsChanged -and $null -eq $r.fileBytesChanged) 'rollback_failure_remains_unknown'
Set-Item Function:Set-SettingsDacl $realSet
# Fail original receipt before the mutator can run.
function Write-SettingsReceipt([string]$Name,$Value){if($Name -eq 'original.json'){throw 'synthetic_snapshot_write_failure'};& $realReceipt $Name $Value}
$c=New-Case 'snapshot_failure';$r=Run-Case $c
Check (!$r.passed -and !$r.rollbackAttempted -and (Original-Intact $c)) 'snapshot_failure_before_mutation'
function Write-SettingsReceipt([string]$Name,$Value){if($Name -eq 'result.json'){throw 'synthetic_result_write_failure'};& $realReceipt $Name $Value}
$c=New-Case 'result_failure';$r=Run-Case $c
Check (!$r.passed -and $r.rollbackAttempted -and $r.rollbackVerified -and (Original-Intact $c)) 'result_receipt_failure_rolls_back'
Set-Item Function:Write-SettingsReceipt $realReceipt
# ACL races remain possible for the same owner. Detect, restore root, and never claim child recovery.
function Set-SettingsDacl($Handle,[string]$Sddl,[bool]$Protected){[SettingsAclNative]::DaclOnly($Handle,$Sddl,$Protected);if($Protected){$f=$proposal.objects|Where-Object {!$_.directory}|Select-Object -First 1;$a=Get-Acl -LiteralPath $f.path;$a.SetAccessRuleProtection($true,$true);[IO.File]::SetAccessControl($f.path,$a)}}
$c=New-Case 'child_acl_drift';$r=Run-Case $c
Check (!$r.passed -and $r.rollbackAttempted -and !$r.rollbackVerified -and $r.requiresReviewedRecovery -and $null -eq $r.childAclsChanged -and (Get-Acl -LiteralPath $c.root).Sddl -ceq $c.originalRows[0].originalSddl) 'child_acl_drift_requires_reviewed_recovery'
Set-Item Function:Set-SettingsDacl $realSet
$c=New-Case 'file_lock';$h=[SettingsAclNative]::Open($c.proposal.objects[1].path,$false,$false);$denied=$false
try{try{$writer=[IO.File]::OpenWrite($c.proposal.objects[1].path);$writer.Dispose()}catch{$denied=$true}}finally{$h.Dispose()}
Check $denied 'write_denied_while_pinned'
$c=New-Case 'root_lock';$h=[SettingsAclNative]::Open($c.root,$true,$true);$denied=$false
try{try{[IO.Directory]::Move($c.root,($c.root+'-moved'))}catch{$denied=$true}}finally{$h.Dispose()}
Check $denied 'rename_denied_while_pinned'
$c=New-Case 'hardlink_race';$h=[SettingsAclNative]::Open($c.proposal.objects[1].path,$false,$false);$rejected=$false
try{
 try{New-Item -ItemType HardLink -Path (Join-Path $c.base 'late-link.json') -Target $c.proposal.objects[1].path|Out-Null}catch{$rejected=$true}
 if(!$rejected){try{[SettingsAclNative]::Check($h,$c.proposal.objects[1].path,$false)|Out-Null}catch{$rejected=$true}}
}finally{$h.Dispose()}
Check $rejected 'hardlink_race_rejected_or_detected'
# The snapshot's immutable bytes remain readable while data writes and deletion are blocked.
function Set-SettingsDacl($Handle,[string]$Sddl,[bool]$Protected){
 if($Protected){
  $p=Join-Path $ReceiptDirectory 'original.json';$blocked=$false
  try{$w=[IO.File]::OpenWrite($p);$w.Dispose()}catch{$blocked=$true}
  if(!$blocked){throw 'snapshot_not_pinned'}
  $script:snapshotPinned=$true
 }
 [SettingsAclNative]::DaclOnly($Handle,$Sddl,$Protected)
}
$c=New-Case 'snapshot_pin';$script:snapshotPinned=$false;$r=Run-Case $c
Check ($r.passed -and $script:snapshotPinned) 'snapshot_write_denied_while_pinned'
Set-Item Function:Set-SettingsDacl $realSet
[pscustomobject]@{passed=$true;checks=$checks.ToArray();productionPathsTouched=$false;servicesChanged=$false;tasksChanged=$false;privilegeEnabled=$false;sourceSha256=(Get-FileHash -LiteralPath $SourcePath).Hash.ToLowerInvariant()}|ConvertTo-Json -Depth 5
