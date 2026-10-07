#requires -Version 5.1
param([Parameter(Mandatory=$true)][string]$SourcePath,[Parameter(Mandatory=$true)][string]$FixtureParent)
$ErrorActionPreference='Stop';Set-StrictMode -Version 2
if(!(New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)){
 [Console]::WriteLine('{"skipped":true,"reason":"same_owner_administrator_token_unavailable","foreignOwnerRoundtripVerified":false}');exit 0
}
. (Join-Path ([IO.Path]::GetDirectoryName($SourcePath)) 'owner_elevation_probe.ps1')
$owner=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value
$hash=(Get-FileHash -LiteralPath $SourcePath -Algorithm SHA256).Hash.ToLowerInvariant()
# Built-in Users is an intentionally different synthetic owner, never a deployed SID.
$result=Invoke-AclOwnerRoundtripProbe -FixtureParent $FixtureParent -OwnerSid $owner -ForeignOwnerSid 'S-1-5-32-545' -NativeSourcePath $SourcePath -ExpectedNativeSourceSha256 $hash
if(!$result.passed -or !$result.foreign_owner_roundtrip_verified){throw 'synthetic_foreign_owner_probe_failed'}
[Console]::WriteLine(($result|ConvertTo-Json -Compress))
