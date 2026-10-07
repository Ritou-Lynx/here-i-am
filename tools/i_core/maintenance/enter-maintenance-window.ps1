# The production entry has one fixed action and no callback or test bypass.
[CmdletBinding()]
param(
 [Parameter(Mandatory=$true)][string]$ConfigPath,
 [Parameter(Mandatory=$true)][ValidatePattern('^[a-f0-9]{64}$')][string]$ExpectedConfigSha256,
 [Parameter(Mandatory=$true)][ValidatePattern('^[A-Za-z0-9][A-Za-z0-9_-]{7,79}$')][string]$WindowId,
 [Parameter(Mandatory=$true)][switch]$Execute
)
$ErrorActionPreference='Stop'
$env:PSModulePath=Join-Path $PSHOME 'Modules'
function Assert-EntryPlain([string]$Path){
 if($Path-notmatch '^[A-Za-z]:\\'-or $Path.Substring(2).Contains(':')-or [IO.Path]::GetFullPath($Path)-cne $Path){throw 'entry_path_not_canonical'}
 for($p=$Path;$p;$p=[IO.Path]::GetDirectoryName($p)){$item=Get-Item -LiteralPath $p -Force;if($item.Attributes-band [IO.FileAttributes]::ReparsePoint){throw 'entry_reparse_rejected'}}
}
function Get-EntryHandleHash($Handle){
 $hash=[Security.Cryptography.SHA256]::Create()
 try{$Handle.Position=0;return ([BitConverter]::ToString($hash.ComputeHash($Handle))).Replace('-','').ToLowerInvariant()}finally{$Handle.Position=0;$hash.Dispose()}
}
function Assert-EntryPrivate($Handle,[string]$Owner){
 $acl=$Handle.GetAccessControl()
 if($acl.GetOwner([Security.Principal.SecurityIdentifier]).Value-cne $Owner){throw 'entry_config_owner_rejected'}
 $own=$false
 foreach($r in $acl.GetAccessRules($true,$true,[Security.Principal.SecurityIdentifier])){if($r.AccessControlType-eq 'Allow'){
  if($r.IdentityReference.Value-notin @($Owner,'S-1-5-18','S-1-5-32-544')){throw 'entry_config_acl_rejected'}
  if($r.IdentityReference.Value-eq $Owner-and ($r.FileSystemRights-band [Security.AccessControl.FileSystemRights]::FullControl)-eq [Security.AccessControl.FileSystemRights]::FullControl){$own=$true}
 }}
 if(-not $own){throw 'entry_config_control_rejected'}
}
$configLease=$null;$freezeLease=$null
try {
 Assert-EntryPlain $ConfigPath
 $configLease=[IO.File]::Open($ConfigPath,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read)
 if((Get-EntryHandleHash $configLease)-cne $ExpectedConfigSha256){throw 'configuration_hash_rejected'}
 $reader=[IO.StreamReader]::new($configLease,[Text.UTF8Encoding]::new($false),$true,1024,$true)
 try{$config=$reader.ReadToEnd()|ConvertFrom-Json}finally{$reader.Dispose()}
 $owner=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value
 if($config.ownerSid-cne $owner){throw 'entry_owner_mismatch'}
 Assert-EntryPrivate $configLease $owner
 $freeze=Join-Path $PSScriptRoot 'freeze-legacy-runtime.ps1';Assert-EntryPlain $freeze
 $freezeLease=[IO.File]::Open($freeze,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read)
 if($config.freezeScriptSha256-cnotmatch '^[a-f0-9]{64}$'-or (Get-EntryHandleHash $freezeLease)-cne $config.freezeScriptSha256){throw 'freeze_source_hash_rejected'}
 & $freeze -ConfigPath $ConfigPath -ExpectedConfigSha256 $ExpectedConfigSha256 -WindowId $WindowId -Execute:$Execute
} finally {
 if($freezeLease){$freezeLease.Dispose()};if($configLease){$configLease.Dispose()}
}
