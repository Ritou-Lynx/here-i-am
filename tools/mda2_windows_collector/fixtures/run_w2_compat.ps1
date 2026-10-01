param()

$ErrorActionPreference = 'Stop'
$workspace = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..\..'))
$scratchBase = [IO.Path]::GetFullPath((Join-Path $workspace 'tools\mda2_windows_collector\.scratch\w2-compat'))
$run = [IO.Path]::GetFullPath((Join-Path $scratchBase ('run-' + [guid]::NewGuid().ToString('N'))))
$evidenceRoot = Join-Path $workspace 'docs\development\activity\mda2\windows\w3'
$summaryPath = Join-Path $evidenceRoot 'W2_COMPAT_SUMMARY.json'
$resultPath = Join-Path $evidenceRoot 'W2_COMPAT_RESULT.json'
$logPath = Join-Path $evidenceRoot 'W2_COMPAT_RUN.log'

function Write-Utf8LfJson([string]$Path, [object]$Value) {
  $json = $Value | ConvertTo-Json -Depth 5
  $json = $json.Replace("`r`n", "`n").TrimEnd("`r", "`n") + "`n"
  [IO.File]::WriteAllText($Path, $json, [Text.UTF8Encoding]::new($false))
}

New-Item -ItemType Directory -Path (Join-Path $run 'tools') -Force | Out-Null
New-Item -ItemType Directory -Path (Join-Path $run 'docs\development\activity\mda2\windows\w2') -Force | Out-Null
Copy-Item -LiteralPath (Join-Path $workspace 'tools\mda2_windows_queue') -Destination (Join-Path $run 'tools\mda2_windows_queue') -Recurse
Copy-Item -LiteralPath (Join-Path $workspace 'tools\i_core') -Destination (Join-Path $run 'tools\i_core') -Recurse
New-Item -ItemType Directory -Path $evidenceRoot -Force | Out-Null

$previousPreference = $ErrorActionPreference
$ErrorActionPreference = 'Continue'
$output = & node (Join-Path $run 'tools\mda2_windows_queue\fixtures\run_tests.mjs') 2>&1
$exitCode = $LASTEXITCODE
$ErrorActionPreference = $previousPreference
[IO.File]::WriteAllLines($logPath, [string[]]$output, [Text.UTF8Encoding]::new($false))
$generated = Join-Path $run 'docs\development\activity\mda2\windows\w2\RESULT.json'
$passed = 0
$scratchRemoved = $false
if ($exitCode -eq 0 -and (Test-Path -LiteralPath $generated -PathType Leaf)) {
  Copy-Item -LiteralPath $generated -Destination $resultPath -Force
  $result = Get-Content -LiteralPath $generated -Raw | ConvertFrom-Json
  $passed = [int]$result.passed
  $scratchRemoved = [bool]$result.scratchRemoved
}

$preliminary = [ordered]@{
  suite = 'w2-protected-disk-v1-on-w3-candidate'
  node_exit_code = $exitCode
  passed = $passed
  w2_inner_scratch_removed = $scratchRemoved
  mirror_removed = $false
  historical_w2_result_overwritten = $false
  real_os_collection = $false
  real_transport = $false
}
Write-Utf8LfJson $summaryPath $preliminary

$baseResolved = [IO.Path]::GetFullPath((Resolve-Path -LiteralPath $scratchBase).Path)
$runResolved = [IO.Path]::GetFullPath((Resolve-Path -LiteralPath $run).Path)
if ([IO.Path]::GetDirectoryName($runResolved) -ne $baseResolved -or $runResolved -eq $baseResolved) { throw 'w2_compat_cleanup_scope_rejected' }
$item = Get-Item -LiteralPath $runResolved -Force
if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'w2_compat_cleanup_reparse_rejected' }
Remove-Item -LiteralPath $runResolved -Recurse -Force -ErrorAction Stop
$preliminary.mirror_removed = -not (Test-Path -LiteralPath $runResolved)
Write-Utf8LfJson $summaryPath $preliminary

if ($exitCode -ne 0 -or $passed -ne 35 -or -not $scratchRemoved -or -not $preliminary.mirror_removed) { throw 'w2_compatibility_failed' }
$preliminary | ConvertTo-Json -Compress
