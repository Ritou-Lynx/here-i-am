[CmdletBinding()]
param(
  [Parameter(Mandatory=$true)][string]$RunRoot,
  [Parameter(Mandatory=$true)][ValidatePattern('^[a-f0-9]{64}$')][string]$RunToken,
  [Parameter(Mandatory=$true)][string]$NodePath,
  [ValidateSet('pin','migration','core','supervision','normal','descendants')][string]$Mode,
  [ValidateRange(100,240000)][int]$TimeoutMs = 120000
)
$ErrorActionPreference = 'Stop'
$env:PSModulePath = "$PSHOME\Modules"
function Assert-PlainPath([string]$Target) {
  $current = [IO.Path]::GetFullPath($Target)
  while ($current) {
    if ((Test-Path -LiteralPath $current) -and (([IO.File]::GetAttributes($current) -band [IO.FileAttributes]::ReparsePoint) -ne 0)) { throw 'linked_path_rejected' }
    $parent = [IO.Directory]::GetParent($current)
    $current = if ($null -eq $parent) { $null } else { $parent.FullName }
  }
}
$RunRoot = [IO.Path]::GetFullPath($RunRoot)
Assert-PlainPath $RunRoot
Assert-PlainPath $NodePath
if ((Split-Path $RunRoot -Leaf) -notmatch '^mda2-m3-supervised-[A-Za-z0-9]+$' -or
    -not ([IO.Directory]::GetParent($RunRoot).FullName.TrimEnd('\').Equals([IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\'), [StringComparison]::OrdinalIgnoreCase))) { throw 'unowned_root' }
foreach ($name in @('owner.json','scratch','stop','receipt.json','ready','descendant-ready','output.log','suite.json')) { Assert-PlainPath (Join-Path $RunRoot $name) }
$owner = Get-Content -LiteralPath (Join-Path $RunRoot 'owner.json') -Raw | ConvertFrom-Json
if ($owner.token -ne $RunToken -or $owner.mode -ne $Mode -or $owner.parent_pid -le 0 -or
    $owner.parent_created_ticks -notmatch '^\d+$' -or -not [IO.Path]::IsPathRooted($owner.parent_image)) { throw 'run_identity_mismatch' }
if ((Get-FileHash -LiteralPath $NodePath -Algorithm SHA256).Hash -ne '58e74bf02fc5bbacc41dcb8bef089961cd5bddd37830b87784e4fc624d145d1f') { throw 'node_hash_mismatch' }
Get-ChildItem Env: | Where-Object { $_.Name -like 'I_CORE_*' -or $_.Name -in @('NODE_OPTIONS','NODE_PATH') } | ForEach-Object { Remove-Item -LiteralPath ('Env:' + $_.Name) }
$entry = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../test_fixtures/migration_m3/supervised_child.mjs'))
Assert-PlainPath $entry
. (Join-Path $PSScriptRoot 'owned_job.ps1')
$receipt = [Mda2M3OwnedJob]::Run($NodePath, $entry, $RunRoot, $RunToken, $Mode, $TimeoutMs, $owner.parent_pid, $owner.parent_created_ticks, $owner.parent_image)
[IO.File]::WriteAllText((Join-Path $RunRoot 'receipt.json'), (@{ token=$RunToken; mode=$Mode; result=$receipt } | ConvertTo-Json -Depth 5), [Text.UTF8Encoding]::new($false))
if (-not $receipt.child_exit_confirmed -or -not $receipt.child_exit_code_confirmed -or -not $receipt.job_empty_confirmed) { exit 2 }
