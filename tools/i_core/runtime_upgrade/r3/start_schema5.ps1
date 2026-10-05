[CmdletBinding()]
param(
  [Parameter(Mandatory=$true)][ValidatePattern('^[a-f0-9]{64}$')][string]$ManifestSha256,
  [string]$StateDirectory = '',
  [string]$ControlDirectory = '',
  [ValidateRange(0,65535)][int]$CorePort = 0,
  [string]$ConfigurationFile = '',
  [switch]$Start,
  [switch]$MigrateV4
)
$ErrorActionPreference = 'Stop'
# This outer PowerShell entry clears inherited enablement before the first Node.
$env:PSModulePath = "$PSHOME\Modules"
Get-ChildItem Env: | Where-Object { $_.Name -like 'I_CORE_*' -or $_.Name -in @(
  'NODE_OPTIONS','NODE_PATH','NODE_EXTRA_CA_CERTS','OPENSSL_CONF','SSL_CERT_FILE','SSL_CERT_DIR'
) } | ForEach-Object { Remove-Item -LiteralPath ('Env:' + $_.Name) }
$env:PATH = "$PSHOME;$env:SystemRoot\System32;$env:SystemRoot"
$release = [IO.Path]::GetFullPath($PSScriptRoot)
function Assert-PlainPath([string]$Target) {
  if ($Target -notmatch '^[A-Za-z]:[\\/]' -or $Target.Substring(2).Contains(':') -or
      -not ([IO.Path]::GetFullPath($Target).Equals($Target.Replace('/','\'), [StringComparison]::OrdinalIgnoreCase))) {
    throw 'canonical_absolute_path_required'
  }
  $current = [IO.Path]::GetFullPath($Target)
  while ($current) {
    try {
      if (([IO.File]::GetAttributes($current) -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw 'linked_path_rejected' }
    } catch [IO.FileNotFoundException] { } catch [IO.DirectoryNotFoundException] { }
    $parent = [IO.Directory]::GetParent($current)
    $current = if ($null -eq $parent) { $null } else { $parent.FullName }
  }
}
function Assert-Separate([string[]]$Paths) {
  foreach ($a in $Paths) { foreach ($b in $Paths) {
    if ($a -cne $b -and ($a.Equals($b,[StringComparison]::OrdinalIgnoreCase) -or $a.StartsWith($b + '\',[StringComparison]::OrdinalIgnoreCase))) { throw 'paths_must_be_separate' }
  } }
  if (@($Paths | Sort-Object -Unique).Count -ne $Paths.Count) { throw 'paths_must_be_separate' }
}
function Assert-Tree([string]$Root) {
  Assert-PlainPath $Root
  foreach ($item in Get-ChildItem -LiteralPath $Root -Force) {
    Assert-PlainPath $item.FullName
    if ($item.PSIsContainer) { Assert-Tree $item.FullName }
  }
}
$lock = $null
$configHandle = $null
try {
  if ((-not $Start) -and ($MigrateV4 -or $StateDirectory -or $ControlDirectory -or $PSBoundParameters.ContainsKey('CorePort') -or $ConfigurationFile)) { throw 'start_required_for_runtime_arguments' }
  Assert-Tree $release
  $manifestPath = Join-Path $release 'manifest.json'
  if ((Get-FileHash -LiteralPath $manifestPath -Algorithm SHA256).Hash -ne $ManifestSha256) { throw 'manifest_fingerprint_mismatch' }
  $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
  $expected = @('tools/i_core/i_core_server.mjs','tools/i_core/i_core_store.mjs','tools/i_core/shortcut_mail_relay.mjs',
    'tools/i_core/send_shortcut_mail.ps1','tools/i_core/strict_smtp_tls_validation.ps1','tools/i_core/activity_control_plane.mjs',
    'package.mjs','start_schema5.ps1','owned_job.ps1','runtime_child.mjs','configuration.mjs','protected_paths.ps1','request_stop.ps1','job_guardian.ps1','verify_v4_state.mjs','runtime/node.exe')
  if ($manifest.format -ne 'i-core-schema5-candidate-r3' -or $manifest.source_commit -ne 'f605d5017cbc0a8eb69983e00c25cd1bba08a0eb' -or
      $manifest.core_schema_version -ne 5 -or $manifest.node_version -ne 'v24.14.1' -or
      $manifest.node_sha256 -ne '58e74bf02fc5bbacc41dcb8bef089961cd5bddd37830b87784e4fc624d145d1f' -or
      @($manifest.files).Count -ne $expected.Count -or
      @(Compare-Object ($expected | Sort-Object) (@($manifest.files.path) | Sort-Object)).Count -ne 0) { throw 'manifest_contract_mismatch' }
  $actual = @(Get-ChildItem -LiteralPath $release -Force -Recurse -File | ForEach-Object { $_.FullName.Substring($release.Length + 1).Replace('\','/') })
  if (@(Compare-Object (($expected + @('manifest.json')) | Sort-Object) ($actual | Sort-Object)).Count -ne 0) { throw 'release_inventory_mismatch' }
  foreach ($entry in $manifest.files) {
    $target = Join-Path $release $entry.path
    if ((Get-Item -LiteralPath $target).Length -ne $entry.bytes -or (Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash -ne $entry.sha256) { throw 'release_content_mismatch' }
  }
  $node = Join-Path $release 'runtime/node.exe'
  if ((Get-FileHash -LiteralPath $node -Algorithm SHA256).Hash -ne '58e74bf02fc5bbacc41dcb8bef089961cd5bddd37830b87784e4fc624d145d1f') { throw 'node_fingerprint_mismatch' }
  # package.mjs also checks the hard-coded accepted Core source hashes and canonical paths.
  & $node (Join-Path $release 'package.mjs') --verify $release $ManifestSha256
  if ($LASTEXITCODE -ne 0) { throw 'package_verification_failed' }
  . (Join-Path $release 'protected_paths.ps1')
  Assert-ProtectedPath $release -Root
  foreach($item in Get-ChildItem -LiteralPath $release -Recurse -Force) { Assert-ProtectedPath $item.FullName }
  if (-not $Start) { exit 0 }
  foreach ($directory in @($StateDirectory,$ControlDirectory)) {
    Assert-PlainPath $directory
    Assert-ProtectedPath $directory -Root
    if (-not (Test-Path -LiteralPath $directory -PathType Container) -or $directory -eq [IO.Path]::GetPathRoot($directory)) { throw 'existing_nonroot_directory_required' }
  }
  Assert-Separate @($release,$StateDirectory,$ControlDirectory)
  if ($ConfigurationFile) {
    Assert-ProtectedPath ([IO.Path]::GetDirectoryName($ConfigurationFile)) -Root
    Assert-ProtectedPath $ConfigurationFile
    Assert-Separate @($release,$StateDirectory,$ControlDirectory,[IO.Path]::GetDirectoryName($ConfigurationFile))
    $configHandle=[IO.File]::Open($ConfigurationFile,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read)
  }
  foreach($item in Get-ChildItem -LiteralPath $StateDirectory -Force) { Assert-ProtectedPath $item.FullName }
  if (@(Get-ChildItem -LiteralPath $ControlDirectory -Force).Count -ne 0) { throw 'empty_control_directory_required' }
  foreach ($name in @('i-core.sqlite','i-core.sqlite-wal','i-core.sqlite-shm','i-core.sqlite-journal',
    'shortcut-mail-relay.runtime.lock','r3-lifecycle.json')) { Assert-PlainPath (Join-Path $StateDirectory $name) }
  try { $lock = [IO.File]::Open((Join-Path $StateDirectory 'shortcut-mail-relay.runtime.lock'),[IO.FileMode]::OpenOrCreate,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None) }
  catch { throw 'runtime_lock_busy' }
  if ($CorePort -ne 0) {
    $probe = [Net.Sockets.TcpListener]::new([Net.IPAddress]::Loopback,$CorePort)
    $probe.Server.ExclusiveAddressUse = $true
    try { $probe.Start() } finally { $probe.Stop() }
  }
  $tokenBytes = New-Object byte[] 32
  $rng = [Security.Cryptography.RandomNumberGenerator]::Create()
  try { $rng.GetBytes($tokenBytes) } finally { $rng.Dispose() }
  $token = ([BitConverter]::ToString($tokenBytes)).Replace('-','').ToLowerInvariant()
  $mode = if ($MigrateV4) { 'migrate-v4' } else { 'start' }
  $rng=[Security.Cryptography.RandomNumberGenerator]::Create()
  try { $rng.GetBytes($tokenBytes) } finally { $rng.Dispose() }
  $stopKey=([BitConverter]::ToString($tokenBytes)).Replace('-','').ToLowerInvariant()
  [IO.File]::WriteAllText((Join-Path $ControlDirectory 'stop.key'),$stopKey,[Text.UTF8Encoding]::new($false))
  $sid=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value
  $config = @{ owner_sid=$sid; configuration_file=$ConfigurationFile; parent_pid=$PID; parent_started_ticks=(Get-Process -Id $PID).StartTime.ToUniversalTime().Ticks.ToString(); token=$token; mode=$mode; state=$StateDirectory; release=$release; manifest_sha256=$ManifestSha256; port=$CorePort }
  [IO.File]::WriteAllText((Join-Path $ControlDirectory 'launch.pending'),($config | ConvertTo-Json),[Text.UTF8Encoding]::new($false))
  [IO.File]::Move((Join-Path $ControlDirectory 'launch.pending'),(Join-Path $ControlDirectory 'launch.json'))
  [IO.File]::WriteAllText((Join-Path $ControlDirectory 'manifest.id'),$ManifestSha256,[Text.UTF8Encoding]::new($false))
  . (Join-Path $release 'owned_job.ps1')
  $receipt = [Mda2R3OwnedJob]::Run($node,(Join-Path $release 'runtime_child.mjs'),$ControlDirectory,$token,$mode,0,(Join-Path $release 'job_guardian.ps1'),$lock.SafeFileHandle.DangerousGetHandle())
  $childReceiptConfirmed = $false
  try {
    $childReceiptPath = Join-Path $ControlDirectory 'child.json'
    Assert-PlainPath $childReceiptPath
    $childReceipt = Get-Content -LiteralPath $childReceiptPath -Raw | ConvertFrom-Json
    $childReceiptConfirmed = $childReceipt.token -eq $token -and $childReceipt.mode -eq $mode -and
      $childReceipt.manifest_sha256 -eq $ManifestSha256 -and $childReceipt.phase -eq 'clean_closed' -and
      $childReceipt.store_close_confirmed -eq $true -and $childReceipt.listener_closed_confirmed -eq $true
  } catch { $childReceiptConfirmed = $false }
  # The child prepares a close receipt; only real exit + Job emptiness finalizes restart authority.
  $guardianConfirmed=$false
  try {
    Assert-ProtectedPath (Join-Path $ControlDirectory 'guardian.json')
    $guardian=Get-Content -LiteralPath (Join-Path $ControlDirectory 'guardian.json') -Raw | ConvertFrom-Json
    $guardianConfirmed=$guardian.run_id -eq $token -and $guardian.result.job_empty_confirmed -eq $true -and $guardian.result.parent_exit_observed -eq $false -and $receipt.guardian_started -and $receipt.guardian_exit_confirmed -and $receipt.guardian_exit_code_confirmed -and $receipt.guardian_exit_code -eq 0
  } catch { }
  $cleanExit=$receipt.child_exit_confirmed -and $receipt.child_exit_code_confirmed -and $receipt.job_empty_confirmed -and $childReceiptConfirmed -and $guardianConfirmed -and -not $receipt.termination_requested
  if ($cleanExit) {
    $markerPath=Join-Path $StateDirectory 'r3-lifecycle.json'
    Assert-ProtectedPath $markerPath
    $marker=Get-Content -LiteralPath $markerPath -Raw | ConvertFrom-Json
    if($marker.token -ne $token -or $marker.phase -ne 'close_prepared' -or $marker.manifest_sha256 -ne $ManifestSha256) { throw 'close_marker_mismatch' }
    $marker.phase='clean_closed'
    $temporary=Join-Path $StateDirectory ('r3-final-'+$token+'.tmp')
    [IO.File]::WriteAllText($temporary,($marker | ConvertTo-Json -Depth 5),[Text.UTF8Encoding]::new($false))
    [IO.File]::Replace($temporary,$markerPath,[NullString]::Value)
  }
  $lock.Dispose(); $lock=$null
  $lockReleased=$false
  try { $probeLock=[IO.File]::Open((Join-Path $StateDirectory 'shortcut-mail-relay.runtime.lock'),[IO.FileMode]::Open,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None); $probeLock.Dispose(); $lockReleased=$true } catch { }
  $data = @{ guardian_receipt_confirmed=$guardianConfirmed; lock_released_confirmed=$lockReleased; token=$token; mode=$mode; manifest_sha256=$ManifestSha256; node_sha256=$manifest.node_sha256; result=$receipt; child_receipt_confirmed=$childReceiptConfirmed }
  [IO.File]::WriteAllText((Join-Path $ControlDirectory 'supervisor.json'),($data | ConvertTo-Json -Depth 6),[Text.UTF8Encoding]::new($false))
  $data | ConvertTo-Json -Depth 6 -Compress
  if (-not $guardianConfirmed -or -not $lockReleased -or -not $receipt.child_started -or -not $receipt.child_exit_confirmed -or -not $receipt.child_exit_code_confirmed -or
      -not $receipt.job_empty_confirmed -or -not $childReceiptConfirmed -or $receipt.child_exit_code -ne 0 -or $receipt.termination_requested -or ($receipt.reason -notin @('completed','cancelled'))) { exit 1 }
  exit 0
} catch {
  [Console]::Error.WriteLine((@{status='rejected';code=$_.Exception.Message} | ConvertTo-Json -Compress))
  exit 2
} finally { if ($null -ne $lock) { $lock.Dispose() }; if ($null -ne $configHandle) { $configHandle.Dispose() } }
