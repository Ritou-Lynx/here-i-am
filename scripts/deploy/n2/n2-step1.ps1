# N2 food rollout step 1 launcher. Windows PowerShell 5.1 only, start with -File.
# Finds the pinned node.exe inside the live release and runs n2-step1.mjs with it.
# Read-only here: no task, STATE, policy, credential or configuration changes.
$ErrorActionPreference = 'Stop'
if ($PSVersionTable.PSEdition -ne 'Desktop' -or $PSVersionTable.PSVersion.Major -ne 5) { throw 'host_not_51' }
$env:PSModulePath = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\Modules'
$task = Get-ScheduledTask -TaskName 'HereIAm-iCoreSchema6-d2b-mcp-20261025-129ec194'
$text = [string]$task.Actions[0].Arguments
$tokens = @()
foreach ($m in [regex]::Matches($text, '"([^"]*)"|(\S+)')) {
  if ($m.Groups[1].Success) { $tokens += $m.Groups[1].Value } else { $tokens += $m.Groups[2].Value }
}
$login = $null
for ($i = 0; $i -lt ($tokens.Count - 1); $i++) {
  if ($tokens[$i] -match '^-(Login)?ConfigurationPath$') { $login = $tokens[$i + 1] }
}
if (-not $login) { throw 'login_argument_missing' }
$config = [IO.File]::ReadAllText($login) | ConvertFrom-Json
$node = Join-Path $config.release_directory 'runtime\node.exe'
$script = Join-Path $PSScriptRoot 'n2-step1.mjs'
foreach ($name in @(Get-ChildItem Env: | Where-Object { $_.Name -like 'NODE_*' -or $_.Name -like 'I_CORE_*' } | ForEach-Object { $_.Name })) {
  Remove-Item -LiteralPath ('Env:' + $name)
}
& $node $script @args
exit $LASTEXITCODE
