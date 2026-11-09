[Console]::OutputEncoding = [Text.UTF8Encoding]::new($false)
$ErrorActionPreference = 'Stop'
try {
  if ($PSVersionTable.PSEdition -ne 'Desktop' -or $PSVersionTable.PSVersion.Major -ne 5) { throw 'host_not_51' }
  $env:PSModulePath = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\Modules'
  $task = Get-ScheduledTask -TaskName 'HereIAm-LifeDigest'
  if ($task.State -eq 'Running') { throw 'generator_busy' }
  $vbs = Join-Path $env:USERPROFILE 'life-digest\life-digest.vbs'
  if (-not ([string]$task.Actions[0].Arguments).Contains($vbs)) { throw 'task_launcher_mismatch' }
  $text = [IO.File]::ReadAllText($vbs, [Text.Encoding]::Unicode).Replace('""','"')
  $match = [regex]::Match($text, '"([A-Za-z]:\\[^"\r\n]*?node\.exe)"', 'IgnoreCase')
  if (-not $match.Success) { throw 'node_not_found' }
  $node = $match.Groups[1].Value
  $helper = Join-Path $PSScriptRoot 'update.mjs'
  $content = [IO.File]::ReadAllText($helper).Replace("`r`n", "`n")
  $sha = [Security.Cryptography.SHA256]::Create()
  try { $actual = ([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($content)))).Replace('-','').ToLowerInvariant() } finally { $sha.Dispose() }
  if ($actual -ne '4317805bd541d27e6a7fd55d75b7ba6edda8e60082c568495721456d4a47079b') { throw 'helper_hash_mismatch' }
  foreach ($name in @(Get-ChildItem Env: | Where-Object { $_.Name -like 'NODE_*' } | ForEach-Object { $_.Name })) { Remove-Item -LiteralPath ('Env:' + $name) }
  & $node $helper write
  exit $LASTEXITCODE
} catch {
  Write-Output '{"ok":false,"detail":"launcher_check_failed"}'
  exit 1
}
