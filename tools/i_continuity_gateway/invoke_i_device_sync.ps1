[CmdletBinding()]
param(
  [ValidateSet('export', 'import', 'sync')]
  [string]$Operation = 'sync',
  [Parameter(Mandatory = $true)]
  [string]$SyncRoot,
  [string]$IHome = (Join-Path $env:USERPROFILE '.i')
)

$ErrorActionPreference = 'Stop'
$SecretPath = Join-Path $IHome 'keys\device-sync-passphrase.dpapi.txt'
$RuntimeScript = Join-Path $IHome 'runtime\sync_i_devices.mjs'
if (-not (Test-Path -LiteralPath $SecretPath)) {
  throw "The sync passphrase is not configured. Run configure_i_device_sync.ps1 first: $SecretPath"
}
if (-not (Test-Path -LiteralPath $RuntimeScript)) {
  throw "The i device-sync runtime is missing. Install the latest Gateway first: $RuntimeScript"
}
$Root = (Get-Item -LiteralPath $SyncRoot -ErrorAction Stop).FullName
if (-not (Test-Path -LiteralPath (Join-Path $Root '.git'))) {
  throw "SyncRoot must be a separate Git repository: $Root"
}
$Secure = ConvertTo-SecureString (Get-Content -Raw -Encoding UTF8 $SecretPath).Trim()
$Pointer = [IntPtr]::Zero
$Plaintext = $null
$Previous = $env:I_SYNC_PASSPHRASE
try {
  $Pointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($Secure)
  $Plaintext = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($Pointer)
  if ([string]::IsNullOrEmpty($Plaintext) -or $Plaintext.Length -lt 16) { throw 'The local DPAPI sync passphrase is invalid.' }
  $env:I_SYNC_PASSPHRASE = $Plaintext
  & node $RuntimeScript $Operation $Root
  if ($LASTEXITCODE -ne 0) { throw "i device sync failed with exit code $LASTEXITCODE" }
} finally {
  $Plaintext = $null
  if ($Pointer -ne [IntPtr]::Zero) { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($Pointer) }
  if ($null -eq $Previous) { Remove-Item Env:I_SYNC_PASSPHRASE -ErrorAction SilentlyContinue }
  else { $env:I_SYNC_PASSPHRASE = $Previous }
}
