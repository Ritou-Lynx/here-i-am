param([Parameter(Mandatory=$true)][string]$PolicyPath,[Parameter(Mandatory=$true)][string]$PrimitivesPath)
$ErrorActionPreference='Stop';Set-StrictMode -Version 2
. $PrimitivesPath
. $PolicyPath
# Synthetic SID literals and in-memory descriptors only. No Scheduler COM.
$owner='S-1-5-21-100-200-300-1001';$foreign='S-1-5-21-100-200-300-1002'
$prefix='O:'+$owner+'G:'+$owner+'D:'
$inputSddl=$prefix+'(A;;FA;;;'+$owner+')(A;;FA;;;SY)(A;;FA;;;BA)'
$baseParent='O:SYG:SYD:'
$script:checks=0
function Check([bool]$Value,[string]$Message){if(!$Value){throw $Message};$script:checks++}
function Reject([scriptblock]$Action,[string]$Code){
 try{& $Action;throw 'fixture_expected_rejection'}catch{if($_.Exception.Message-cne $Code){throw ('fixture_wrong_rejection_'+$Code+': '+$_.Exception.Message)}}
 $script:checks++
}
function New-FixtureConfig([string]$Parent,[string]$Expected,[array]$Disclosure=@()){
 return [pscustomobject]@{ownerSid=$owner;registrationSddl=$inputSddl;expectedRegisteredSddl=$Expected;parentSddlSha256=(Get-TaskSecuritySha256 $Parent);taskSecurityPolicyVersion='windows-file-oi-v1';inheritedReadOnlyPrincipals=$Disclosure}
}
$parent=$baseParent+'(A;OICI;GA;;;SY)(A;OIIO;GR;;;CO)(A;OINP;GX;;;CG)(A;CI;FA;;;'+$foreign+')(A;OI;GR;;;'+$foreign+')'
$expected=$inputSddl+'(A;ID;FA;;;SY)(A;ID;FR;;;'+$owner+')(A;ID;FX;;;'+$owner+')(A;ID;FR;;;'+$foreign+')'
$disclosure=@([pscustomobject]@{sid=$foreign;flags=16;mask='00120089'})
$config=New-FixtureConfig $parent $expected $disclosure
$policy=Assert-TaskSecurityPolicy $config $parent
Check ($policy.inheritedReadOnlyPrincipals.Count-eq 1) 'fixture_disclosure_count'
Check ($policy.registrationSddlSha256-ceq (Get-TaskSecuritySha256 $inputSddl)) 'fixture_input_hash'
Check ($policy.expectedRegisteredSddlSha256-ceq (Get-TaskSecuritySha256 $expected)) 'fixture_expected_hash'
Check ((Convert-TaskSecurity (Get-TaskPolicyExpectedSecurity $inputSddl $parent $owner))-ceq (Convert-TaskSecurity $expected)) 'fixture_inheritance_oracle'
# Exact UTF-8 parent bytes are pinned, even for semantically identical descriptors.
Reject {Assert-TaskSecurityPolicy $config ($parent.Replace('GR','0x00120089'))} 'task_policy_parent_changed'
$bad=New-FixtureConfig $parent ($expected+'(A;ID;FA;;;BA)') $disclosure
Reject {Assert-TaskSecurityPolicy $bad $parent} 'task_policy_expected_changed'
$bad=New-FixtureConfig $parent $expected @()
Reject {Assert-TaskSecurityPolicy $bad $parent} 'task_policy_disclosure_changed'
foreach($entry in @(
 [pscustomobject]@{sid=$foreign;flags=0;mask='00120089'},
 [pscustomobject]@{sid=$owner;flags=16;mask='00120089'},
 [pscustomobject]@{sid=$foreign;flags=16;mask='001200A9'},
 [pscustomobject]@{sid=$foreign;flags=16;mask='00120089';extra=$true}
)){$bad=New-FixtureConfig $parent $expected @($entry);Reject {Assert-TaskSecurityPolicy $bad $parent} 'task_policy_disclosure_changed'}
$bad=New-FixtureConfig $parent $expected @($disclosure[0],$disclosure[0])
Reject {Assert-TaskSecurityPolicy $bad $parent} 'task_policy_disclosure_changed'
$bad=New-FixtureConfig $parent $expected $disclosure;$bad.taskSecurityPolicyVersion='another-version'
Reject {Assert-TaskSecurityPolicy $bad $parent} 'task_policy_version_rejected'
$bad=New-FixtureConfig $parent $expected $disclosure;$bad|Add-Member approvedSddl $inputSddl
Reject {Assert-TaskSecurityPolicy $bad $parent} 'task_policy_legacy_field_rejected'
$bad=New-FixtureConfig $parent $expected $disclosure;$bad.PSObject.Properties.Remove('registrationSddl')
Reject {Assert-TaskSecurityPolicy $bad $parent} 'task_policy_field_required'
# Same SID+flags redundant read remains strictly semantically equivalent.
$redundant=$expected+'(A;;FR;;;'+$owner+')(A;ID;FR;;;'+$foreign+')'
$same=New-FixtureConfig $parent $redundant $disclosure;$null=Assert-TaskSecurityPolicy $same $parent;$script:checks++
foreach($rights in @('FW','FA','GW','GA','GX','FX','GRGX','0x00000020','0x001200A9','SD','WD','WO','0x00000002','0x00000004','0x00000010','0x00000040','0x00000100','0x000d0116')){
 $p=$baseParent+'(A;OI;'+$rights+';;;'+$foreign+')'
 Reject {Get-TaskPolicyExpectedSecurity $inputSddl $p $owner} 'task_policy_foreign_rights_rejected'
}
foreach($rights in @('FX','0x00000020','0x001200A9')){
 Reject {Assert-TaskAllowedRights ($inputSddl+'(A;ID;'+$rights+';;;'+$foreign+')') $owner} 'task_policy_foreign_rights_rejected'
}
foreach($rights in @('GR','GX','GW','GA','0x01000000','0x02000000','0x00000200','0x00200000')){
 Reject {Assert-TaskAllowedRights ($inputSddl+'(A;ID;'+$rights+';;;'+$foreign+')') $owner} 'task_policy_final_rights_rejected'
}
foreach($rights in @('0x01000000','0x02000000','0x00000200','0x00200000')){
 Reject {Get-TaskPolicyExpectedSecurity $inputSddl ($baseParent+'(A;OI;'+$rights+';;;SY)') $owner} 'task_policy_unknown_rights'
}
Reject {Get-TaskPolicyExpectedSecurity ($inputSddl.Replace('D:','D:P')) $parent $owner} 'task_policy_input_owner_or_protection_rejected'
Reject {Assert-TaskAllowedRights ($expected.Replace('D:','D:P')) $owner} 'task_policy_owner_or_protection_rejected'
Reject {Get-TaskPolicyExpectedSecurity ($inputSddl+'(A;;FR;;;'+$foreign+')') $parent $owner} 'task_policy_explicit_principal_rejected'
Reject {Get-TaskPolicyExpectedSecurity ($inputSddl+'(A;ID;FR;;;SY)') $parent $owner} 'task_policy_explicit_principal_rejected'
Reject {Assert-TaskAllowedRights ($inputSddl+'(A;;FR;;;'+$foreign+')') $owner} 'task_policy_foreign_rights_rejected'
Reject {Assert-TaskAllowedRights ($inputSddl+'(A;OI;FR;;;SY)') $owner} 'task_policy_final_flags_rejected'
foreach($ace in @('(D;OI;FR;;;SY)','(OA;OI;FR;00000000-0000-0000-0000-000000000001;;SY)')){
 Reject {Get-TaskPolicyExpectedSecurity $inputSddl ($baseParent+$ace) $owner} 'task_policy_ace_rejected'
}
Reject {Get-TaskPolicyExpectedSecurity $inputSddl ($baseParent+'(A;OISA;FR;;;SY)') $owner} 'task_policy_sddl_rejected'
# Construct a valid callback ACE without asking the SDDL parser to parse conditions.
$callbackSd=[Security.AccessControl.RawSecurityDescriptor]::new($baseParent)
$callback=[Security.AccessControl.CommonAce]::new([Security.AccessControl.AceFlags]::ObjectInherit,[Security.AccessControl.AceQualifier]::AccessAllowed,0x120089,[Security.Principal.SecurityIdentifier]::new('S-1-5-18'),$true,$null)
$callbackSd.DiscretionaryAcl.InsertAce(0,$callback)
$callbackText=$callbackSd.GetSddlForm([Security.AccessControl.AccessControlSections]::All)
Reject {Get-TaskPolicyExpectedSecurity $inputSddl $callbackText $owner} 'task_policy_sddl_rejected'
# Creator group substitution must use the approved child's group, never parent's.
$groupInput=$inputSddl.Replace('G:'+$owner,'G:'+$foreign)
$groupParent=$baseParent+'(A;OI;GR;;;CG)'
$groupExpected=$groupInput+'(A;ID;FR;;;'+$foreign+')'
Check ((Convert-TaskSecurity (Get-TaskPolicyExpectedSecurity $groupInput $groupParent $owner))-ceq (Convert-TaskSecurity $groupExpected)) 'fixture_creator_group'
Reject {Get-TaskPolicyExpectedSecurity $groupInput ($baseParent+'(A;OI;GA;;;CG)') $owner} 'task_policy_foreign_rights_rejected'
# Read-only subsets merge and disclose once per SID/flags; no execute bit.
$reads=$baseParent+'(A;OI;0x00020089;;;'+$foreign+')(A;OICIIOID;0x00100000;;;'+$foreign+')'
$readExpected=$inputSddl+'(A;ID;0x00120089;;;'+$foreign+')'
$merged=New-FixtureConfig $reads $readExpected @([pscustomobject]@{sid=$foreign;flags=16;mask='00120089'})
$null=Assert-TaskSecurityPolicy $merged $reads;$script:checks++
$other='S-1-5-21-100-200-300-1003'
$twoParent=$reads+'(A;OI;FR;;;'+$other+')'
$twoExpected=$readExpected+'(A;ID;FR;;;'+$other+')'
$twoDisclosure=@([pscustomobject]@{sid=$foreign;flags=16;mask='00120089'},[pscustomobject]@{sid=$other;flags=16;mask='00120089'})
$two=New-FixtureConfig $twoParent $twoExpected $twoDisclosure
$null=Assert-TaskSecurityPolicy $two $twoParent;$script:checks++
$two.inheritedReadOnlyPrincipals=@($twoDisclosure[1],$twoDisclosure[0])
Reject {Assert-TaskSecurityPolicy $two $twoParent} 'task_policy_disclosure_changed'
# Final flags and masks stay part of strict comparison even for trusted SIDs.
$bad=New-FixtureConfig $parent ($expected.Replace('(A;ID;FA;;;SY)','(A;;FA;;;SY)')) $disclosure
Reject {Assert-TaskSecurityPolicy $bad $parent} 'task_policy_expected_changed'
$genericInput=$prefix+'(A;;GA;;;'+$owner+')(A;;GW;;;SY)(A;;GX;;;BA)'
$genericExpected=$prefix+'(A;;FA;;;'+$owner+')(A;;FW;;;SY)(A;;FX;;;BA)'
Check ((Convert-TaskSecurity (Get-TaskPolicyExpectedSecurity $genericInput $baseParent $owner))-ceq (Convert-TaskSecurity $genericExpected)) 'fixture_explicit_generic_mapping'
Reject {Get-TaskPolicyExpectedSecurity ('O:SYG:SYD:(A;;FA;;;SY)') $baseParent $owner} 'task_policy_input_owner_or_protection_rejected'
Reject {Get-TaskPolicyExpectedSecurity ('O:'+$owner+'G:'+$owner+'D:NO_ACCESS_CONTROL') $baseParent $owner} 'task_policy_shape_rejected'
$empty=New-FixtureConfig $baseParent $inputSddl @();$emptyResult=Assert-TaskSecurityPolicy $empty $baseParent
Check ($emptyResult.inheritedReadOnlyPrincipals.Count-eq 0) 'fixture_empty_disclosure'
[Console]::Out.WriteLine(([ordered]@{passed=$true;checks=$script:checks;syntheticOnly=$true;comConnected=$false;registered=$false;started=$false}|ConvertTo-Json -Compress))
