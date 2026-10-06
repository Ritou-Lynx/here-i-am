[CmdletBinding()]
param(
  [Parameter(Mandatory=$true)][ValidatePattern('^[a-f0-9]{64}$')][string]$ManifestSha256,
  [string]$StateDirectory = '',
  [string]$ControlDirectory = '',
  [ValidateRange(0,65535)][int]$CorePort = 0,
  [string]$ConfigurationFile = '',
  [switch]$Start,
  [switch]$InitializeEmpty,
  [ValidateSet('verify','migrate','rollback')][string]$OfflineOperation
)
$ErrorActionPreference = 'Stop'
# Reject injected Node/Core settings before the first Node. Explicit config is authoritative.
$env:PSModulePath = "$PSHOME\Modules"
Get-ChildItem Env: | Where-Object { $_.Name -like 'I_CORE_*' -or $_.Name -like 'NODE_*' -or $_.Name -in @(
  'NODE_OPTIONS','NODE_PATH','NODE_EXTRA_CA_CERTS','OPENSSL_CONF','SSL_CERT_FILE','SSL_CERT_DIR'
) } | ForEach-Object { throw 'inherited_runtime_environment_rejected' }
$env:PATHEXT = '.EXE'
$env:PATH = "$PSHOME;$env:SystemRoot\System32;$env:SystemRoot"
$lifecycle = [IO.Path]::GetFullPath($PSScriptRoot)
$release = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..\..\..'))
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
$custodyLock = $null
$configHandle = $null
$externalHandles = @()
try {
  if ((-not $Start) -and ($InitializeEmpty -or $OfflineOperation -or $StateDirectory -or $ControlDirectory -or $PSBoundParameters.ContainsKey('CorePort') -or $ConfigurationFile)) { throw 'start_required_for_runtime_arguments' }
  Assert-Tree $release
  $manifestPath = Join-Path $release 'manifest.json'
  if ((Get-FileHash -LiteralPath $manifestPath -Algorithm SHA256).Hash -ne $ManifestSha256) { throw 'manifest_fingerprint_mismatch' }
  $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
  $expected = @($manifest.files.path)
  if($manifest.core_schema_version -ne 6 -or $manifest.node_version -ne 'v24.14.1' -or
     $manifest.pinned_node_sha256 -ne '58e74bf02fc5bbacc41dcb8bef089961cd5bddd37830b87784e4fc624d145d1f') { throw 'manifest_contract_mismatch' }
  foreach($entry in $expected) {
    if($entry -notmatch '^[A-Za-z0-9_/-]+\.[A-Za-z0-9]+$' -or $entry.Contains('..') -or $entry.StartsWith('/')) { throw 'manifest_path_rejected' }
  }
  if($manifest.policy.companion_upload_mode -ne 'legacy_b3' -or $manifest.policy.companion_reply_jobs -ne $false -or
     $manifest.policy.activity_enabled -ne $false -or $manifest.policy.domain_policy -ne 'owner_managed') { throw 'manifest_policy_rejected' }
  $actual = @(Get-ChildItem -LiteralPath $release -Force -Recurse -File | ForEach-Object { $_.FullName.Substring($release.Length + 1).Replace('\','/') })
  if (@(Compare-Object (($expected + @('manifest.json')) | Sort-Object) ($actual | Sort-Object)).Count -ne 0) { throw 'release_inventory_mismatch' }
  foreach ($entry in $manifest.files) {
    $target = Join-Path $release $entry.path
    if ((Get-Item -LiteralPath $target).Length -ne $entry.bytes -or (Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash -ne $entry.sha256) { throw 'release_content_mismatch' }
  }
  $node = Join-Path $release 'runtime/node.exe'
  if ((Get-FileHash -LiteralPath $node -Algorithm SHA256).Hash -ne '58e74bf02fc5bbacc41dcb8bef089961cd5bddd37830b87784e4fc624d145d1f') { throw 'node_fingerprint_mismatch' }
  # package.mjs verifies the fixed full inventory, source/manifest bindings and canonical paths.
  $LASTEXITCODE = $null
  & $node (Join-Path $release 'tools/i_core/release_schema6/cli.mjs') verify $release $ManifestSha256
  if ($null -eq $LASTEXITCODE -or $LASTEXITCODE -ne 0) { throw ('package_verification_failed:' + $LASTEXITCODE) }
  . (Join-Path $lifecycle 'protected_paths.ps1')
  Assert-ProtectedPath $release -Root
  foreach($item in Get-ChildItem -LiteralPath $release -Recurse -Force) { Assert-ProtectedPath $item.FullName }
  if (-not $Start) { exit 0 }
  foreach ($directory in @($StateDirectory,$ControlDirectory)) {
    Assert-PlainPath $directory
    Assert-ProtectedPath $directory -Root
    if (-not (Test-Path -LiteralPath $directory -PathType Container) -or $directory -eq [IO.Path]::GetPathRoot($directory)) { throw 'existing_nonroot_directory_required' }
  }
  Assert-Separate @($release,$StateDirectory,$ControlDirectory)
  if (-not $ConfigurationFile) { throw 'explicit_configuration_required' }
  if ($ConfigurationFile) {
    Assert-ProtectedPath ([IO.Path]::GetDirectoryName($ConfigurationFile)) -Root
    Assert-ProtectedPath $ConfigurationFile
    Assert-Separate @($release,$StateDirectory,$ControlDirectory,[IO.Path]::GetDirectoryName($ConfigurationFile))
    $configHandle=[IO.File]::Open($ConfigurationFile,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read)
  }
  if($InitializeEmpty -and $OfflineOperation) { throw 'operation_conflict' }
  try { $configuration = Get-Content -LiteralPath $ConfigurationFile -Raw | ConvertFrom-Json }
  catch { throw 'config_json_rejected' }
  foreach($name in @('grants_path','approvals_path','recovery_key_path')) {
    $external = $configuration.$name
    if(-not $external) { throw 'external_configuration_path_required' }
    Assert-ProtectedPath ([IO.Path]::GetDirectoryName($external)) -Root
    Assert-ProtectedPath $external
    Assert-Separate @($release,$StateDirectory,$ControlDirectory,$external)
    $externalHandles += [IO.File]::Open($external,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read)
  }
  if($configuration.backup_key_path) {
    Assert-ProtectedPath ([IO.Path]::GetDirectoryName($configuration.backup_key_path)) -Root
    Assert-ProtectedPath $configuration.backup_key_path
    Assert-Separate @($release,$StateDirectory,$ControlDirectory,$configuration.backup_key_path)
    $externalHandles += [IO.File]::Open($configuration.backup_key_path,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read)
  }
  if($configuration.backup_directory) {
    Assert-ProtectedPath $configuration.backup_directory -Root
    Assert-Separate @($release,$StateDirectory,$ControlDirectory,$configuration.backup_directory,$configuration.recovery_custody_directory)
  }
  Assert-ProtectedPath $configuration.recovery_custody_directory -Root
  Assert-Separate @($release,$StateDirectory,$ControlDirectory,$configuration.recovery_custody_directory)
  foreach($item in Get-ChildItem -LiteralPath $StateDirectory -Force -Recurse) { Assert-ProtectedPath $item.FullName }
  if($InitializeEmpty -and @(Get-ChildItem -LiteralPath $StateDirectory -Force).Count -ne 0) { throw 'initialize_requires_empty_state' }
  if (@(Get-ChildItem -LiteralPath $ControlDirectory -Force).Count -ne 0) { throw 'empty_control_directory_required' }
  foreach ($name in @('i-core.sqlite','i-core.sqlite-wal','i-core.sqlite-shm','i-core.sqlite-journal',
    'shortcut-mail-relay.runtime.lock','s6-lifecycle.json')) { Assert-PlainPath (Join-Path $StateDirectory $name) }
  try { $lock = [IO.File]::Open((Join-Path $StateDirectory 'shortcut-mail-relay.runtime.lock'),[IO.FileMode]::OpenOrCreate,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None) }
  catch { throw 'runtime_lock_busy' }
  $custodyLockPath=Join-Path $configuration.recovery_custody_directory 'custody.lock'
  Assert-PlainPath $custodyLockPath
  if(Test-Path -LiteralPath $custodyLockPath) { Assert-ProtectedPath $custodyLockPath }
  try { $custodyLock=[IO.File]::Open($custodyLockPath,[IO.FileMode]::OpenOrCreate,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None) }
  catch { throw 'custody_lock_busy' }
  if ($CorePort -ne 0) {
    $probe = [Net.Sockets.TcpListener]::new([Net.IPAddress]::Loopback,$CorePort)
    $probe.Server.ExclusiveAddressUse = $true
    try { $probe.Start() } finally { $probe.Stop() }
  }
  $tokenBytes = New-Object byte[] 32
  $rng = [Security.Cryptography.RandomNumberGenerator]::Create()
  try { $rng.GetBytes($tokenBytes) } finally { $rng.Dispose() }
  $token = ([BitConverter]::ToString($tokenBytes)).Replace('-','').ToLowerInvariant()
  $mode = if ($InitializeEmpty) { 'initialize-empty' } elseif($OfflineOperation) { 'offline-'+$OfflineOperation } else { 'start' }
  $rng=[Security.Cryptography.RandomNumberGenerator]::Create()
  try { $rng.GetBytes($tokenBytes) } finally { $rng.Dispose() }
  $stopKey=([BitConverter]::ToString($tokenBytes)).Replace('-','').ToLowerInvariant()
  [IO.File]::WriteAllText((Join-Path $ControlDirectory 'stop.key'),$stopKey,[Text.UTF8Encoding]::new($false))
  $sid=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value
  $config = @{ owner_sid=$sid; configuration_file=$ConfigurationFile; parent_pid=$PID; parent_started_ticks=(Get-Process -Id $PID).StartTime.ToUniversalTime().Ticks.ToString(); token=$token; mode=$mode; state=$StateDirectory; release=$release; lifecycle=$lifecycle; manifest_sha256=$ManifestSha256; port=$CorePort }
  [IO.File]::WriteAllText((Join-Path $ControlDirectory 'launch.pending'),($config | ConvertTo-Json),[Text.UTF8Encoding]::new($false))
  [IO.File]::Move((Join-Path $ControlDirectory 'launch.pending'),(Join-Path $ControlDirectory 'launch.json'))
  [IO.File]::WriteAllText((Join-Path $ControlDirectory 'manifest.id'),$ManifestSha256,[Text.UTF8Encoding]::new($false))
  . (Join-Path $lifecycle 'owned_job.ps1')
  $receipt = [Schema6OwnedJob]::Run($node,(Join-Path $lifecycle 'runtime_child.mjs'),$ControlDirectory,$token,$mode,0,(Join-Path $lifecycle 'job_guardian.ps1'),$lock.SafeFileHandle.DangerousGetHandle())
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
  $cleanExit=$receipt.child_exit_code -eq 0 -and $receipt.child_exit_confirmed -and $receipt.child_exit_code_confirmed -and $receipt.job_empty_confirmed -and $childReceiptConfirmed -and $guardianConfirmed -and -not $receipt.termination_requested
  if ($cleanExit) {
    $markerPath=Join-Path $StateDirectory 's6-lifecycle.json'
    Assert-ProtectedPath $markerPath
    $marker=Get-Content -LiteralPath $markerPath -Raw | ConvertFrom-Json
    if($marker.token -ne $token -or $marker.phase -ne 'close_prepared' -or $marker.manifest_sha256 -ne $ManifestSha256) { throw 'close_marker_mismatch' }
    $marker.phase='clean_closed'
    $marker | Add-Member -NotePropertyName supervisor -NotePropertyValue @{job_empty_confirmed=$true;child_exit_code=0;guardian_exit_code=0;termination_requested=$false} -Force
    $temporary=Join-Path $StateDirectory ('s6-final-'+$token+'.tmp')
    [IO.File]::WriteAllText($temporary,($marker | ConvertTo-Json -Depth 5),[Text.UTF8Encoding]::new($false))
    [IO.File]::Replace($temporary,$markerPath,[NullString]::Value)
  }
  if(-not $cleanExit) {
    $markerPath=Join-Path $StateDirectory 's6-lifecycle.json'
    if(Test-Path -LiteralPath $markerPath) {
      Assert-ProtectedPath $markerPath
      $failedMarker=Get-Content -LiteralPath $markerPath -Raw | ConvertFrom-Json
      if($failedMarker.token -eq $token) {
        $failedMarker.phase='recovery_required'
        $temporary=Join-Path $StateDirectory ('s6-failed-'+$token+'.tmp')
        [IO.File]::WriteAllText($temporary,($failedMarker | ConvertTo-Json -Depth 6),[Text.UTF8Encoding]::new($false))
        [IO.File]::Replace($temporary,$markerPath,[NullString]::Value)
      }
    }
  }
  $custodyLock.Dispose(); $custodyLock=$null
  $lock.Dispose(); $lock=$null
  $lockReleased=$false
  try { $probeLock=[IO.File]::Open((Join-Path $StateDirectory 'shortcut-mail-relay.runtime.lock'),[IO.FileMode]::Open,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None); $probeLock.Dispose(); $lockReleased=$true } catch { }
  $data = @{ guardian_receipt_confirmed=$guardianConfirmed; lock_released_confirmed=$lockReleased; token=$token; mode=$mode; manifest_sha256=$ManifestSha256; node_sha256=$manifest.pinned_node_sha256; result=$receipt; child_receipt_confirmed=$childReceiptConfirmed }
  [IO.File]::WriteAllText((Join-Path $ControlDirectory 'supervisor.json'),($data | ConvertTo-Json -Depth 6),[Text.UTF8Encoding]::new($false))
  $data | ConvertTo-Json -Depth 6 -Compress
  if (-not $guardianConfirmed -or -not $lockReleased -or -not $receipt.child_started -or -not $receipt.child_exit_confirmed -or -not $receipt.child_exit_code_confirmed -or
      -not $receipt.job_empty_confirmed -or -not $childReceiptConfirmed -or $receipt.child_exit_code -ne 0 -or $receipt.termination_requested -or ($receipt.reason -notin @('completed','cancelled'))) { exit 1 }
  exit 0
} catch {
  [Console]::Error.WriteLine((@{status='rejected';code=$_.Exception.Message} | ConvertTo-Json -Compress))
  exit 2
} finally { if ($null -ne $custodyLock) { $custodyLock.Dispose() }; if ($null -ne $lock) { $lock.Dispose() }; if ($null -ne $configHandle) { $configHandle.Dispose() }; foreach($handle in $externalHandles) { $handle.Dispose() } }
