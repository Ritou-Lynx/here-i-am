# Current-user candidate boundary. Same-user/admin compromise is outside this contract.
function Assert-ProtectedPath([string]$Target, [switch]$Root) {
  if ($Target -notmatch '^[A-Za-z]:[\\/]' -or $Target.Substring(2).Contains(':') -or
      -not ([IO.Path]::GetFullPath($Target).Equals($Target.Replace('/','\'),[StringComparison]::OrdinalIgnoreCase))) { throw 'canonical_absolute_path_required' }
  $current = $Target
  while ($current) {
    if (([IO.File]::GetAttributes($current) -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw 'linked_path_rejected' }
    $parent = [IO.Directory]::GetParent($current)
    $current = if ($parent) { $parent.FullName } else { $null }
  }
  $sid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
  $acl = Get-Acl -LiteralPath $Target
  if ($acl.GetOwner([Security.Principal.SecurityIdentifier]).Value -ne $sid) { throw 'protected_owner_mismatch' }
  if ($Root -and -not $acl.AreAccessRulesProtected) { throw 'protected_root_required' }
  $own = $false
  foreach ($rule in $acl.GetAccessRules($true,$true,[Security.Principal.SecurityIdentifier])) {
    if ($rule.AccessControlType -eq 'Allow') {
      if ($rule.IdentityReference.Value -notin @($sid,'S-1-5-18','S-1-5-32-544')) { throw 'protected_acl_required' }
      if ($rule.IdentityReference.Value -eq $sid -and ($rule.FileSystemRights -band [Security.AccessControl.FileSystemRights]::FullControl) -eq [Security.AccessControl.FileSystemRights]::FullControl) { $own = $true }
    }
  }
  if (-not $own) { throw 'protected_user_control_required' }
}

function Protect-NewDirectory([string]$Target) {
  # Only a newly created empty owned directory may be initialized by this helper.
  if ($Target -notmatch '^[A-Za-z]:[\\/]' -or $Target.Substring(2).Contains(':') -or
      -not ([IO.Path]::GetFullPath($Target).Equals($Target.Replace('/','\'),[StringComparison]::OrdinalIgnoreCase))) { throw 'canonical_absolute_path_required' }
  $current=$Target
  while($current) {
    if(([IO.File]::GetAttributes($current) -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw 'linked_path_rejected' }
    $parent=[IO.Directory]::GetParent($current)
    $current=if($parent) { $parent.FullName } else { $null }
  }
  if (@(Get-ChildItem -LiteralPath $Target -Force).Count -ne 0) { throw 'new_empty_directory_required' }
  $sid = [Security.Principal.WindowsIdentity]::GetCurrent().User
  if((Get-Acl -LiteralPath $Target).GetOwner([Security.Principal.SecurityIdentifier]).Value -ne $sid.Value) { throw 'new_directory_owner_mismatch' }
  $acl = New-Object Security.AccessControl.DirectorySecurity
  $acl.SetOwner($sid)
  $acl.SetAccessRuleProtection($true,$false)
  foreach ($identity in @($sid,[Security.Principal.SecurityIdentifier]::new('S-1-5-18'),[Security.Principal.SecurityIdentifier]::new('S-1-5-32-544'))) {
    $acl.AddAccessRule([Security.AccessControl.FileSystemAccessRule]::new($identity,'FullControl','ContainerInherit,ObjectInherit','None','Allow'))
  }
  Set-Acl -LiteralPath $Target -AclObject $acl
  Assert-ProtectedPath $Target -Root
}
