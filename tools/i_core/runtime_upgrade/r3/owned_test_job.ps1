# Internal fixed-fixture supervisor. No arbitrary command or database entry point.
[CmdletBinding()]
param(
  [Parameter(Mandatory=$true)][string]$RunRoot,
  [Parameter(Mandatory=$true)][ValidatePattern('^[a-f0-9]{64}$')][string]$RunToken,
  [Parameter(Mandatory=$true)][string]$NodePath,
  [ValidateSet('suite','normal','hang','descendant-hang','residual','startup-failure','missing-receipt','forged-receipt')][string]$FixtureMode = 'suite',
  [ValidateRange(50,360000)][int]$TimeoutMs = 360000
)
$ErrorActionPreference = 'Stop'
$env:PSModulePath = "$PSHOME\Modules"
function Assert-PlainPath([string]$Target) {
  $current = [IO.Path]::GetFullPath($Target)
  while ($current) {
    if ((Test-Path -LiteralPath $current) -and (([IO.File]::GetAttributes($current) -band [IO.FileAttributes]::ReparsePoint) -ne 0)) {
      throw 'linked_path_rejected'
    }
    $parent = [IO.Directory]::GetParent($current)
    $current = if ($null -eq $parent) { $null } else { $parent.FullName }
  }
}
$RunRoot = [IO.Path]::GetFullPath($RunRoot)
Assert-PlainPath $RunRoot
Assert-PlainPath $NodePath
if ((Split-Path $RunRoot -Leaf) -notmatch '^mda2-r3-supervised-[A-Za-z0-9]+$' -or
    -not ([IO.Directory]::GetParent($RunRoot).FullName.TrimEnd('\').Equals([IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\'), [StringComparison]::OrdinalIgnoreCase))) {
  throw 'unowned_run_root'
}
foreach ($name in @('owner.json','scratch','stop','receipt.json','ready','grandchild-ready','output.log')) {
  Assert-PlainPath (Join-Path $RunRoot $name)
}
$owner = Get-Content -LiteralPath (Join-Path $RunRoot 'owner.json') -Raw | ConvertFrom-Json
if ($owner.token -ne $RunToken -or $owner.mode -ne $FixtureMode) { throw 'run_identity_mismatch' }
if ((Get-FileHash -LiteralPath $NodePath -Algorithm SHA256).Hash -ne '58e74bf02fc5bbacc41dcb8bef089961cd5bddd37830b87784e4fc624d145d1f') {
  throw 'node_fingerprint_mismatch'
}
Get-ChildItem Env: | Where-Object { $_.Name -like 'I_CORE_*' -or $_.Name -in @('NODE_OPTIONS','NODE_PATH') } | ForEach-Object {
  Remove-Item -LiteralPath ('Env:' + $_.Name)
}
$entry = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../test_fixtures/runtime_upgrade/r3/supervised_child.mjs'))
Assert-PlainPath $entry

. (Join-Path $PSScriptRoot 'owned_job.ps1')
$receipt = [Mda2R3OwnedJob]::Run($NodePath, $entry, $RunRoot, $RunToken, $FixtureMode, $TimeoutMs)
$data = @{ token=$RunToken; mode=$FixtureMode; result=$receipt }
if ($FixtureMode -in @('missing-receipt','forged-receipt')) {
  # Independent actual Job result retained by the fault fixture. The parent must
  # still fail closed when its normal receipt is omitted or has the wrong identity.
  [IO.File]::WriteAllText((Join-Path $RunRoot 'witness.json'), ($data | ConvertTo-Json -Depth 5), [Text.UTF8Encoding]::new($false))
  if ($FixtureMode -eq 'missing-receipt') { exit 0 }
  $data.token = 'wrong-identity'
}
[IO.File]::WriteAllText((Join-Path $RunRoot 'receipt.json'), ($data | ConvertTo-Json -Depth 5), [Text.UTF8Encoding]::new($false))
