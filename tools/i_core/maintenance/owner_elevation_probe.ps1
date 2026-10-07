#requires -Version 5.1
# Synthetic only. Importing does not create files, enable privileges or run probes.
function Invoke-AclOwnerRoundtripProbe {
 [CmdletBinding()]
 param([Parameter(Mandatory=$true)][string]$FixtureParent,
  [Parameter(Mandatory=$true)][string]$OwnerSid,
  [Parameter(Mandatory=$true)][string]$ForeignOwnerSid,
  [Parameter(Mandatory=$true)][string]$NativeSourcePath,
  [Parameter(Mandatory=$true)][string]$ExpectedNativeSourceSha256)
 Set-StrictMode -Version 2;$ErrorActionPreference='Stop'
 if([Security.Principal.WindowsIdentity]::GetCurrent().User.Value -cne $OwnerSid){throw 'same_owner_required'}
 if(!(New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)){throw 'elevated_same_owner_required'}
 if($ForeignOwnerSid -ceq $OwnerSid){throw 'different_synthetic_owner_required'}
 $null=[Security.Principal.SecurityIdentifier]::new($ForeignOwnerSid)
 $sourceLock=[IO.File]::Open($NativeSourcePath,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read)
 $privilege=$null;$handle=$null;$saved=$null;$testFile=$null
 $result=[ordered]@{format='schema6-owner-elevation-probe-v2';passed=$false;production_paths_touched=$false;services_changed=$false;tasks_changed=$false;foreign_owner_roundtrip_verified=$false}
 try {
  if($ExpectedNativeSourceSha256 -cnotmatch '^[a-f0-9]{64}$' -or (Get-FileHash -LiteralPath $NativeSourcePath -Algorithm SHA256).Hash.ToLowerInvariant() -cne $ExpectedNativeSourceSha256){throw 'reviewed_native_source_changed'}
  . $NativeSourcePath
  Assert-Plain $NativeSourcePath;Assert-Plain $FixtureParent
  Initialize-CutoverAclNative
  $privilege=New-Object CutoverAclNative+Privilege
  $owner=$OwnerSid;$sections=[Security.AccessControl.AccessControlSections]::Owner -bor [Security.AccessControl.AccessControlSections]::Access
  $fixture=Join-Path $FixtureParent ('acl-owner-synthetic-'+[Guid]::NewGuid().ToString('N'))
  $null=[IO.Directory]::CreateDirectory($fixture)
  $acl=New-Object Security.AccessControl.DirectorySecurity;$acl.SetSecurityDescriptorSddlForm((New-PrivateSddl $true),$sections);Set-Acl -LiteralPath $fixture -AclObject $acl
  $testFile=Join-Path $fixture 'synthetic.txt';[IO.File]::WriteAllText($testFile,'synthetic owner roundtrip',[Text.UTF8Encoding]::new($false))
  $acl=Get-Acl -LiteralPath $testFile;$acl.SetOwner([Security.Principal.SecurityIdentifier]::new($owner));Set-Acl -LiteralPath $testFile -AclObject $acl
  $saved=Read-OwnerDacl $testFile;$beforeHash=(Get-FileHash -LiteralPath $testFile -Algorithm SHA256).Hash
  $handle=[CutoverAclNative]::Open($testFile,$true);$identity=[CutoverAclNative]::Identity($handle)
  $foreign=New-Object Security.AccessControl.FileSecurity;$foreign.SetSecurityDescriptorSddlForm($saved,$sections);$foreign.SetOwner([Security.Principal.SecurityIdentifier]::new($ForeignOwnerSid))
  [CutoverAclNative]::SetOwnerDacl($handle,$foreign.GetSecurityDescriptorSddlForm($sections),$foreign.AreAccessRulesProtected)
  if((Get-Acl -LiteralPath $testFile).GetOwner([Security.Principal.SecurityIdentifier]).Value -cne $ForeignOwnerSid){throw 'synthetic_foreign_owner_not_set'}
  $sd=New-Object Security.AccessControl.RawSecurityDescriptor($saved)
  [CutoverAclNative]::SetOwnerDacl($handle,$saved,(($sd.ControlFlags-band [Security.AccessControl.ControlFlags]::DiscretionaryAclProtected)-ne 0))
  if((Owner-Dacl (Read-OwnerDacl $testFile)) -cne (Owner-Dacl $saved) -or (Get-FileHash -LiteralPath $testFile -Algorithm SHA256).Hash -cne $beforeHash -or [CutoverAclNative]::Identity($handle) -cne $identity){throw 'synthetic_roundtrip_mismatch'}
  $result.foreign_owner_roundtrip_verified=$true;$result.passed=$true;$result.fixture=$fixture
 }finally{
  if($handle -and $saved){try{$sd=New-Object Security.AccessControl.RawSecurityDescriptor($saved);[CutoverAclNative]::SetOwnerDacl($handle,$saved,(($sd.ControlFlags-band [Security.AccessControl.ControlFlags]::DiscretionaryAclProtected)-ne 0));if((Owner-Dacl (Read-OwnerDacl $testFile)) -cne (Owner-Dacl $saved)){throw 'synthetic_final_restore_mismatch'}}catch{$result.passed=$false}}
  if($handle){$handle.Dispose()};if($privilege){$privilege.Dispose()};$sourceLock.Dispose()
 }
 return [pscustomobject]$result
}
