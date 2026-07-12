[CmdletBinding()]
param(
  [string]$IHome = (Join-Path $env:USERPROFILE '.i'),
  [Security.SecureString]$Passphrase
)

$ErrorActionPreference = 'Stop'
$KeyDirectory = Join-Path $IHome 'keys'
$SecretPath = Join-Path $KeyDirectory 'device-sync-passphrase.dpapi.txt'
if ($null -eq $Passphrase) {
  $Passphrase = Read-Host 'Enter the i device-sync passphrase (at least 16 characters)' -AsSecureString
}
$Pointer = [IntPtr]::Zero
try {
  $Pointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($Passphrase)
  $Length = [Runtime.InteropServices.Marshal]::ReadInt32($Pointer, -4) / 2
  if ($Length -lt 16) { throw 'The sync passphrase must contain at least 16 characters.' }
} finally {
  if ($Pointer -ne [IntPtr]::Zero) { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($Pointer) }
}
New-Item -ItemType Directory -Force -Path $KeyDirectory | Out-Null
$Protected = ConvertFrom-SecureString -SecureString $Passphrase
$Temp = "$SecretPath.$PID.tmp"
try {
  [System.IO.File]::WriteAllText($Temp, "$Protected`n", [Text.UTF8Encoding]::new($false))
  if (Test-Path -LiteralPath $SecretPath) {
    $Backup = "$SecretPath.$PID.bak"
    [System.IO.File]::Replace($Temp, $SecretPath, $Backup)
    Remove-Item -LiteralPath $Backup -Force -ErrorAction SilentlyContinue
  } else {
    [System.IO.File]::Move($Temp, $SecretPath)
  }
} finally {
  Remove-Item -LiteralPath $Temp -Force -ErrorAction SilentlyContinue
}
[pscustomobject]@{
  configured = $true
  provider = 'windows-dpapi-current-user'
  secret_path = $SecretPath
  note = 'Enter the same passphrase on the other device. Do not copy this DPAPI file.'
} | ConvertTo-Json
