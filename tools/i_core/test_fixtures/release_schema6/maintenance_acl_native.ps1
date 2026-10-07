#requires -Version 5.1
# Synthetic helper-only test. NEVER dot-sources or invokes the production maintenance script.
param([Parameter(Mandatory=$true)][string]$SourcePath,[Parameter(Mandatory=$true)][string]$FixtureParent)
$ErrorActionPreference='Stop';Set-StrictMode -Version 2
$source=$SourcePath
$sourceHash=(Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash.ToLowerInvariant()
$tokens=$null;$errors=$null;$ast=[Management.Automation.Language.Parser]::ParseFile($source,[ref]$tokens,[ref]$errors)
if($errors.Count){throw 'production_syntax_invalid'}
$command=@($ast.FindAll({param($n)$n -is [Management.Automation.Language.CommandAst] -and $n.GetCommandName() -eq 'Add-Type'},$true))[0]
Add-Type -TypeDefinition $command.CommandElements[2].Value
$allowed=@('Owner-Dacl','Read-OwnerDacl','New-PrivateSddl','Add-Receipt','Restore-Snapshot','Assert-Metadata','Inventory','Assert-Inventory','Assert-Plain','Test-InScope','Invoke-AclFailureRecovery')
foreach($name in $allowed){
 $fn=@($ast.FindAll({param($n)$n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -ceq $name},$true))
 if($fn.Count -ne 1){throw 'synthetic_helper_ambiguous'}
 Invoke-Expression $fn[0].Extent.Text
}
$owner=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value
$sections=[Security.AccessControl.AccessControlSections]::Owner -bor [Security.AccessControl.AccessControlSections]::Access
$fixture=Join-Path $FixtureParent ('acl-synthetic-'+[Guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($fixture)|Out-Null
$private=New-Object Security.AccessControl.DirectorySecurity
$private.SetSecurityDescriptorSddlForm((New-PrivateSddl $true),$sections)
[IO.Directory]::SetAccessControl($fixture,$private)
$roots=@((Join-Path $fixture 'core'),(Join-Path $fixture 'memory'))
foreach($r in $roots){
 [IO.Directory]::CreateDirectory((Join-Path $r 'nested'))|Out-Null
 [IO.File]::WriteAllText((Join-Path $r 'payload.txt'),'synthetic-payload',[Text.UTF8Encoding]::new($false))
 [IO.File]::WriteAllText((Join-Path $r 'nested\policy.json'),'{"synthetic":true}',[Text.UTF8Encoding]::new($false))
}
$rows=@(foreach($r in $roots){
 $all=@((Get-Item -LiteralPath $r -Force))+@(Get-ChildItem -LiteralPath $r -Force -Recurse)
 foreach($item in $all){$a=Get-Acl -LiteralPath $item.FullName;[pscustomobject]@{
 path=$item.FullName;directory=[bool]$item.PSIsContainer;owner=$a.GetOwner([Security.Principal.SecurityIdentifier]).Value
 sddl=$a.GetSecurityDescriptorSddlForm([Security.AccessControl.AccessControlSections]::All)
 }}
})
$rows=@($rows|Sort-Object @{Expression={$_.path.Split('\').Count}},@{Expression={$_.path}})
$targetHandles=@{};$before=@{};$fileHashes=@{};$groups=@{}
$receipt=[ordered]@{items=@()}
$result=[ordered]@{format='schema6-acl-native-synthetic-v1';source_sha256=$sourceHash;fixture=$fixture;owner=$owner;count=$rows.Count;production_script_executed=$false;production_roots_touched=$false;privilege_enabled=$false;legacy_foreign_owner_tested=$false;passed=$false;checks=@();started_utc=[DateTime]::UtcNow.ToString('o')}
$phase='capture'
function Check-All([string]$label,[bool]$privateExpected){
 Assert-Metadata
 foreach($r in $rows){
  $expected=if($privateExpected){New-PrivateSddl $r.directory}else{$r.sddl}
  if((Owner-Dacl (Read-OwnerDacl $r.path)) -cne (Owner-Dacl $expected)){throw 'synthetic_owner_dacl_mismatch'}
  $a=Get-Acl -LiteralPath $r.path
  if($a.GetSecurityDescriptorSddlForm([Security.AccessControl.AccessControlSections]::Group) -cne $groups[$r.path]){throw 'synthetic_group_changed'}
  if(!$r.directory -and (Get-FileHash -LiteralPath $r.path -Algorithm SHA256).Hash -cne $fileHashes[$r.path]){throw 'synthetic_file_bytes_changed'}
 }
 $result.checks+=@([ordered]@{label=$label;owner_dacl_verified=$true;metadata_unchanged=$true;file_hashes_unchanged=$true;group_unchanged=$true})
}
try{
 foreach($r in $rows){
  if(!$r.path.StartsWith($fixture+'\',[StringComparison]::OrdinalIgnoreCase)){throw 'synthetic_scope_violation'}
  $targetHandles[$r.path]=[CutoverAclNative]::Open($r.path,$true)
  $before[$r.path]=@{identity=[CutoverAclNative]::Identity($targetHandles[$r.path])}
  $groups[$r.path]=(Get-Acl -LiteralPath $r.path).GetSecurityDescriptorSddlForm([Security.AccessControl.AccessControlSections]::Group)
  if(!$r.directory){$fileHashes[$r.path]=(Get-FileHash -LiteralPath $r.path -Algorithm SHA256).Hash}
 }
 $inherited=@($rows|Where-Object{!((Get-Acl -LiteralPath $_.path).AreAccessRulesProtected)})
 if($inherited.Count -eq 0){throw 'synthetic_inheritance_not_exercised'}
 $result.initial_unprotected_count=$inherited.Count
 $phase='apply'
 foreach($r in $rows){[CutoverAclNative]::SetOwnerDacl($targetHandles[$r.path],(New-PrivateSddl $r.directory),$true)}
 Check-All 'apply_private' $true
 $phase='restore'
 if(!(Restore-Snapshot)){throw 'synthetic_restore_failed'}
 Check-All 'restore_inheritance' $false
 $phase='interruption_parent_propagation'
 # Alter one root only: Windows may propagate to unprotected descendants.
 $first=$rows[0]
 [CutoverAclNative]::SetOwnerDacl($targetHandles[$first.path],(New-PrivateSddl $true),$true)
 $result.simulated_interruption_after_root=$true
 if(!(Restore-Snapshot)){throw 'synthetic_interruption_restore_failed'}
 Check-All 'partial_apply_full_restore' $false
 $phase='pending_inventory_drift'
 # A new pending file remains intact. The exact inventory check must reject it.
 $pending=Join-Path $roots[0] 'new.pending'
 [IO.File]::WriteAllText($pending,'preserve synthetic pending',[Text.UTF8Encoding]::new($false))
 $driftRejected=$false
 try{Assert-Inventory}catch{if($_.Exception.Message -ceq 'inventory_drift'){$driftRejected=$true}else{throw}}
 if(!$driftRejected){throw 'synthetic_pending_not_rejected'}
 function Assert-Frozen { }
 function Restore-Snapshot { throw 'synthetic_restore_must_not_run_after_drift' }
 $receipt.rollback_attempted=$false
 Invoke-AclFailureRecovery
 if($receipt.rollback_attempted -or !$receipt.rollback_deferred -or !$receipt.requires_reviewed_recovery -or !(Test-Path -LiteralPath $pending)){throw 'synthetic_pending_recovery_not_deferred'}
 $result.checks+=@([ordered]@{label='pending_inventory_drift';rejected=$true;rollback_deferred=$true;pending_preserved=$true})
 $result.passed=$true
}catch{
 $result.failed_phase=$phase;$result.error_type=$_.Exception.GetType().FullName;$result.hresult=$_.Exception.HResult
 $result.error_code=if($_.Exception.Message -match '^[a-z_]+$'){$_.Exception.Message}else{'synthetic_test_failed'}
 try{$result.best_effort_restore_verified=Restore-Snapshot}catch{$result.best_effort_restore_verified=$false}
}finally{
 foreach($h in $targetHandles.Values){$h.Dispose()}
 $result.completed_utc=[DateTime]::UtcNow.ToString('o')
 $result.items=$receipt.items
 $out=Join-Path $fixture 'synthetic-receipt.json'
 [IO.File]::WriteAllText($out,($result|ConvertTo-Json -Depth 10),[Text.UTF8Encoding]::new($false))
}
[Console]::Out.WriteLine((@{passed=$result.passed;phase=$phase;receipt=$out;source_sha256=$sourceHash;production_script_executed=$false;privilege_enabled=$false;legacy_foreign_owner_tested=$false;checks=$result.checks}|ConvertTo-Json -Depth 5 -Compress))
if(!$result.passed){exit 2}
