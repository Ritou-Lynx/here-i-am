# Pure Windows file-ACE inheritance policy. Import never reads a task or connects COM.
Set-StrictMode -Version 2
function Get-TaskSecuritySha256([string]$Text) {
 $sha=[Security.Cryptography.SHA256]::Create()
 try{return ([BitConverter]::ToString($sha.ComputeHash([Text.UTF8Encoding]::new($false).GetBytes($Text)))).Replace('-','').ToLowerInvariant()}finally{$sha.Dispose()}
}
function Read-TaskPolicySecurity([string]$Sddl) {
 try{$sd=[Security.AccessControl.RawSecurityDescriptor]::new($Sddl)}catch{throw 'task_policy_sddl_rejected'}
 if($null-eq $sd.Owner -or $null-eq $sd.Group -or $null-eq $sd.DiscretionaryAcl -or $null-ne $sd.SystemAcl){throw 'task_policy_shape_rejected'}
 foreach($ace in $sd.DiscretionaryAcl){
  if($ace -isnot [Security.AccessControl.CommonAce] -or $ace.AceQualifier-ne [Security.AccessControl.AceQualifier]::AccessAllowed -or $ace.IsCallback -or ([int]$ace.AceFlags-band (-bnot 31))){throw 'task_policy_ace_rejected'}
 }
 return $sd
}
function Convert-TaskFileMask([int]$Mask) {
 $bits=[long]$Mask-band 0xffffffffL
 # Only FILE_ALL_ACCESS bits plus the four explicitly mapped generic bits exist.
 if($bits-band (-bnot 0xf01f01ffL)){throw 'task_policy_unknown_rights'}
 $result=$bits-band 0x001f01ffL
 if($bits-band 0x80000000L){$result=$result-bor 0x00120089L}
 if($bits-band 0x40000000L){$result=$result-bor 0x00120116L}
 if($bits-band 0x20000000L){$result=$result-bor 0x001200a0L}
 if($bits-band 0x10000000L){$result=$result-bor 0x001f01ffL}
 return [int]$result
}
function Assert-TaskAllowedRights([string]$Sddl,[string]$OwnerSid) {
 $sd=Read-TaskPolicySecurity $Sddl
 if($sd.Owner.Value-cne $OwnerSid -or ($sd.ControlFlags-band [Security.AccessControl.ControlFlags]::DiscretionaryAclProtected)){throw 'task_policy_owner_or_protection_rejected'}
 $allowed=@($OwnerSid,'S-1-5-18','S-1-5-32-544')
 foreach($ace in $sd.DiscretionaryAcl){
  $mask=[long]$ace.AccessMask-band 0xffffffffL
  if($mask-band (-bnot 0x001f01ffL)){throw 'task_policy_final_rights_rejected'}
  if([int]$ace.AceFlags-notin @(0,16)){throw 'task_policy_final_flags_rejected'}
  if($ace.SecurityIdentifier.Value-notin $allowed){
   # FILE_EXECUTE permits running a task and is not read-only access.
   if([int]$ace.AceFlags-ne 16 -or ($mask-band (-bnot 0x00120089L))){throw 'task_policy_foreign_rights_rejected'}
  }
 }
}
function Get-TaskInheritedReadOnlyPrincipals([string]$Sddl,[string]$OwnerSid) {
 Assert-TaskAllowedRights $Sddl $OwnerSid
 $sd=Read-TaskPolicySecurity $Sddl;$rights=@{}
 foreach($ace in $sd.DiscretionaryAcl){
  if($ace.SecurityIdentifier.Value-in @($OwnerSid,'S-1-5-18','S-1-5-32-544')){continue}
  $key=$ace.SecurityIdentifier.Value+'|'+[int]$ace.AceFlags
  if(!$rights.ContainsKey($key)){$rights[$key]=0};$rights[$key]=$rights[$key]-bor $ace.AccessMask
 }
 $keys=[string[]]@($rights.Keys);[Array]::Sort($keys,[StringComparer]::Ordinal)
 $items=@($keys|ForEach-Object{$parts=$_.Split('|');[pscustomobject][ordered]@{sid=$parts[0];flags=[int]$parts[1];mask=('{0:X8}' -f $rights[$_])}})
 return ,$items
}
function Get-TaskPolicyExpectedSecurity([string]$RegistrationSddl,[string]$ParentSddl,[string]$OwnerSid) {
 $child=Read-TaskPolicySecurity $RegistrationSddl;$parent=Read-TaskPolicySecurity $ParentSddl
 if($child.Owner.Value-cne $OwnerSid -or ($child.ControlFlags-band [Security.AccessControl.ControlFlags]::DiscretionaryAclProtected)){throw 'task_policy_input_owner_or_protection_rejected'}
 $acl=[Security.AccessControl.RawAcl]::new(2,($child.DiscretionaryAcl.Count+$parent.DiscretionaryAcl.Count))
 foreach($ace in $child.DiscretionaryAcl){
  if([int]$ace.AceFlags-ne 0 -or $ace.SecurityIdentifier.Value-notin @($OwnerSid,'S-1-5-18','S-1-5-32-544')){throw 'task_policy_explicit_principal_rejected'}
  $copy=[Security.AccessControl.CommonAce]::new([Security.AccessControl.AceFlags]::None,[Security.AccessControl.AceQualifier]::AccessAllowed,(Convert-TaskFileMask $ace.AccessMask),$ace.SecurityIdentifier,$false,$null)
  $acl.InsertAce($acl.Count,$copy)
 }
 foreach($ace in $parent.DiscretionaryAcl){
  # Validate every parent ACE, even when it does not propagate to a file.
  $mask=Convert-TaskFileMask $ace.AccessMask
  if(([int]$ace.AceFlags-band 1)-eq 0){continue}
  $who=$ace.SecurityIdentifier
  if($who.Value-ceq 'S-1-3-0'){$who=$child.Owner}
  elseif($who.Value-ceq 'S-1-3-1'){$who=$child.Group}
  # A noncontainer inherits OI, including OI|IO and OI|NP. Propagation flags
  # are removed; only INHERITED_ACE remains. CI alone never reaches a file.
  $copy=[Security.AccessControl.CommonAce]::new([Security.AccessControl.AceFlags]::Inherited,[Security.AccessControl.AceQualifier]::AccessAllowed,$mask,$who,$false,$null)
  $acl.InsertAce($acl.Count,$copy)
 }
 $child.DiscretionaryAcl=$acl
 $result=$child.GetSddlForm([Security.AccessControl.AccessControlSections]::All)
 Assert-TaskAllowedRights $result $OwnerSid
 return $result
}
function Assert-TaskSecurityPolicy($Config,[string]$ParentSddl) {
 if($Config.PSObject.Properties.Name-contains 'approvedSddl'){throw 'task_policy_legacy_field_rejected'}
 foreach($name in @('ownerSid','registrationSddl','expectedRegisteredSddl','parentSddlSha256','taskSecurityPolicyVersion','inheritedReadOnlyPrincipals')){
  if($Config.PSObject.Properties.Name-notcontains $name){throw 'task_policy_field_required'}
 }
 if($Config.taskSecurityPolicyVersion-cne 'windows-file-oi-v1'){throw 'task_policy_version_rejected'}
 if($Config.parentSddlSha256-cnotmatch '^[a-f0-9]{64}$' -or (Get-TaskSecuritySha256 $ParentSddl)-cne $Config.parentSddlSha256){throw 'task_policy_parent_changed'}
 $derived=Get-TaskPolicyExpectedSecurity $Config.registrationSddl $ParentSddl $Config.ownerSid
 Assert-TaskAllowedRights $Config.expectedRegisteredSddl $Config.ownerSid
 if((Convert-TaskSecurity $derived)-cne (Convert-TaskSecurity $Config.expectedRegisteredSddl)){throw 'task_policy_expected_changed'}
 $disclosure=Get-TaskInheritedReadOnlyPrincipals $derived $Config.ownerSid
 if($Config.inheritedReadOnlyPrincipals -isnot [array] -or $Config.inheritedReadOnlyPrincipals.Count-ne $disclosure.Count){throw 'task_policy_disclosure_changed'}
 for($i=0;$i-lt $disclosure.Count;$i++){
  $approved=$Config.inheritedReadOnlyPrincipals[$i];$expected=$disclosure[$i]
  if(@($approved.PSObject.Properties.Name).Count-ne 3 -or $approved.sid-isnot [string] -or $approved.flags-isnot [int] -or $approved.mask-isnot [string] -or $approved.sid-cne $expected.sid -or $approved.flags-ne $expected.flags -or $approved.mask-cne $expected.mask){throw 'task_policy_disclosure_changed'}
 }
 return [pscustomobject][ordered]@{taskSecurityPolicyVersion='windows-file-oi-v1';parentSddlSha256=$Config.parentSddlSha256;registrationSddlSha256=(Get-TaskSecuritySha256 $Config.registrationSddl);expectedRegisteredSddlSha256=(Get-TaskSecuritySha256 $Config.expectedRegisteredSddl);inheritedReadOnlyPrincipals=$disclosure}
}
