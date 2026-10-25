[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$StudyDirectory,
    [Parameter(Mandatory = $true)][string]$ConfigPath,
    [string]$NodeExecutable = 'node',
    [string]$CodexExecutable = 'codex'
)

# Windows PowerShell 5.1. Invoke this multiline script via -EncodedCommand.
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false)
$OutputEncoding = [Console]::OutputEncoding
function Invoke-DailyStep {
    param([string]$Executable, [string[]]$CommandArguments)
    # npm puts both codex.cmd and an extensionless shell script on PATH, and
    # Get-Command returns both. Take the first Windows-runnable match only.
    $resolvedExecutable = @(Get-Command $Executable -CommandType Application -ErrorAction Stop |
        Where-Object { $_.Extension -in @('.exe', '.cmd', '.bat', '.com') }) | Select-Object -First 1
    if ($null -eq $resolvedExecutable) { throw 'daily_executable_not_found' }
    # PS 5.1 otherwise turns native stderr into a terminating NativeCommandError
    # before we can preserve the actual process exit code.
    $ErrorActionPreference = 'Continue'
    & $resolvedExecutable.Source @CommandArguments *> $null
    if ($null -eq $LASTEXITCODE) { return 1 }
    return $LASTEXITCODE
}
function Test-DirectoryContains {
    param([string]$Parent, [string]$Child)
    $prefix = $Parent.TrimEnd('\', '/') + [System.IO.Path]::DirectorySeparatorChar
    return $Parent.Equals($Child, [System.StringComparison]::OrdinalIgnoreCase) -or $Child.StartsWith($prefix, [System.StringComparison]::OrdinalIgnoreCase)
}
$dailyExit = 1
$dailyLock = $null
$dailyLog = $null
$previousLocation = Get-Location
try {
    $studyRoot = (Resolve-Path -LiteralPath $StudyDirectory).Path
    $resolvedConfig = (Resolve-Path -LiteralPath $ConfigPath).Path
    $toolRoot = (Resolve-Path -LiteralPath $PSScriptRoot).Path
    foreach ($protectedRoot in @($toolRoot, (Split-Path -Parent $resolvedConfig))) {
        if ((Test-DirectoryContains $studyRoot $protectedRoot) -or (Test-DirectoryContains $protectedRoot $studyRoot)) { throw 'daily_layout_invalid' }
    }
    $syncScript = Join-Path $toolRoot 'sync\feishu_sync.mjs'
    $stateDirectory = Join-Path $studyRoot 'state'
    $dailyConfig = Get-Content -LiteralPath $resolvedConfig -Raw -Encoding UTF8 | ConvertFrom-Json
    if ([string]::IsNullOrWhiteSpace($dailyConfig.model) -or $dailyConfig.model.StartsWith('-') -or $dailyConfig.model.Contains('<')) {
        throw 'daily_model_invalid'
    }
    $logsDirectory = Join-Path $studyRoot 'logs'
    New-Item -ItemType Directory -Path $logsDirectory -Force | Out-Null
    $dailyLog = Join-Path $logsDirectory ('daily-{0}-{1}.log' -f (Get-Date -Format 'yyyyMMdd-HHmmss'), $PID)
    # Hold an exclusive handle across pull -> Codex -> push. A crash releases it.
    $dailyLock = [System.IO.File]::Open((Join-Path $logsDirectory '.daily.lock'), [System.IO.FileMode]::OpenOrCreate, [System.IO.FileAccess]::ReadWrite, [System.IO.FileShare]::None)
    Set-Location -LiteralPath $studyRoot
    $pending = @(Get-ChildItem -LiteralPath (Join-Path $studyRoot 'state\outbox') -Filter '*.json' -File -ErrorAction SilentlyContinue)
    $uncertain = @(Get-ChildItem -LiteralPath (Join-Path $studyRoot 'state\outbox\inflight') -File -ErrorAction SilentlyContinue)
    if ($pending.Count -gt 0 -or $uncertain.Count -gt 0) { throw 'daily_pending_outbox' }

    # Logs contain step names and exit codes only, never raw model/CLI output.
    'pull_start' | Out-File -LiteralPath $dailyLog -Encoding utf8 -Append
    $stepExit = Invoke-DailyStep -Executable $NodeExecutable -CommandArguments @($syncScript, 'pull', '--config', $resolvedConfig, '--state', $stateDirectory)
    if ($stepExit -ne 0) { ('pull_failed:{0}' -f $stepExit) | Out-File -LiteralPath $dailyLog -Encoding utf8 -Append; exit $stepExit }

    'codex_start' | Out-File -LiteralPath $dailyLog -Encoding utf8 -Append
    # The prompt is encoded in the source so PS 5.1 also reads an UTF-8/no-BOM
    # checkout correctly. It decodes to the required Chinese daily instruction.
    $dailyPrompt = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String('5Ye65LuK5aSp55qE5a2m5Lmg5Y2V'))
    $stepExit = Invoke-DailyStep -Executable $CodexExecutable -CommandArguments @('exec', '-C', $studyRoot, '-s', 'workspace-write', '-m', $dailyConfig.model, '-c', 'sandbox_workspace_write.network_access=false', $dailyPrompt)
    if ($stepExit -ne 0) { ('codex_failed:{0}' -f $stepExit) | Out-File -LiteralPath $dailyLog -Encoding utf8 -Append; exit $stepExit }

    'push_start' | Out-File -LiteralPath $dailyLog -Encoding utf8 -Append
    $stepExit = Invoke-DailyStep -Executable $NodeExecutable -CommandArguments @($syncScript, 'push', '--config', $resolvedConfig, '--state', $stateDirectory)
    if ($stepExit -ne 0) { ('push_failed:{0}' -f $stepExit) | Out-File -LiteralPath $dailyLog -Encoding utf8 -Append; exit $stepExit }
    'daily_done' | Out-File -LiteralPath $dailyLog -Encoding utf8 -Append
    $dailyExit = 0
} catch {
    if ($dailyLog) { 'daily_failed' | Out-File -LiteralPath $dailyLog -Encoding utf8 -Append }
    $dailyError = if ($_.Exception.Message -eq 'daily_layout_invalid') { 'daily_layout_invalid' } else { 'daily_failed' }
    Write-Error $dailyError -ErrorAction Continue
} finally {
    if ($dailyLock) { $dailyLock.Dispose() }
    Set-Location -LiteralPath $previousLocation.Path
}
exit $dailyExit
