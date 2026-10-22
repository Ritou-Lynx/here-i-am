[CmdletBinding(SupportsShouldProcess)]
param(
    [switch]$Remove,
    [string]$TaskName = 'HereIAm-AgentRelay',
    [string]$ConfigPath = '',
    [string]$NodePath = '',
    [string]$GhPath = '',
    [switch]$ShowAction,
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$LegacyArguments
)
$ErrorActionPreference = 'Stop'
if ($LegacyArguments.Count) {
    if ($LegacyArguments -match '^-CodexPath(?:$|:)') { throw '-CodexPath 已移除；请改用配置里的 codexPath/codexSearch。' }
    throw ('未知参数：' + ($LegacyArguments -join ' '))
}
if ($ShowAction -and $Remove) { throw '-ShowAction 不能与 -Remove 一起使用。' }
if ($Remove) {
    if (Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue) {
        if ($PSCmdlet.ShouldProcess($TaskName, '删除 Agent Relay 计划任务')) {
            Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
        }
    }
    return
}
if (!$ConfigPath) { $ConfigPath = Join-Path $PSScriptRoot '.state\config.json' }
if (!$NodePath) { $NodePath = (Get-Command node -ErrorAction Stop).Source }
if (!$GhPath) { $GhPath = (Get-Command gh -ErrorAction Stop).Source }
$NodePath = (Resolve-Path -LiteralPath $NodePath).Path
$GhPath = (Resolve-Path -LiteralPath $GhPath).Path
# Preview also works before the local configuration has been created.
if ($ShowAction) { $ConfigPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($ConfigPath) }
else { $ConfigPath = (Resolve-Path -LiteralPath $ConfigPath).Path }
$watcher = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot 'relay_watcher.mjs')).Path
# Capture only executable directories. No token, auth file or user configuration is copied.
$commandDirs = @((Split-Path $NodePath), (Split-Path $GhPath), (Split-Path (Get-Command git -ErrorAction Stop).Source))
# Do not freeze a Codex version inherited from an older launcher either.
$inheritedDirs = @($env:PATH -split ';' | Where-Object {
    $_ -and (Test-Path -LiteralPath $_.Trim('"') -PathType Container) -and
        !(Test-Path -LiteralPath (Join-Path $_.Trim('"') 'codex.exe') -PathType Leaf)
})
$taskPath = (($commandDirs + $inheritedDirs) -join ';')
function Quote-PsLiteral([string]$Value) { return "'" + $Value.Replace("'", "''") + "'" }
$logDir = Join-Path (Split-Path $ConfigPath) 'logs'
$logFile = Join-Path $logDir 'task-last.log'
$command = '$ErrorActionPreference=''Stop''; [Console]::OutputEncoding=[Text.UTF8Encoding]::new($false); $OutputEncoding=[Console]::OutputEncoding; $relayExit=1; try { $env:PATH=' + (Quote-PsLiteral $taskPath) + '; New-Item -ItemType Directory -Path ' + (Quote-PsLiteral $logDir) + ' -Force | Out-Null; & ' + (Quote-PsLiteral $NodePath) + ' ' + (Quote-PsLiteral $watcher) + ' --once --config ' + (Quote-PsLiteral $ConfigPath) + ' *> ' + (Quote-PsLiteral $logFile) + '; if ($null -eq $LASTEXITCODE) { throw ''Node exit code unavailable'' }; $relayExit=$LASTEXITCODE } catch { $_ | Out-File -LiteralPath ' + (Quote-PsLiteral $logFile) + ' -Append -Encoding utf8; $relayExit=1 }; exit $relayExit'
$encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($command))
$conhost = Join-Path $env:SystemRoot 'System32\conhost.exe'
if (!(Test-Path -LiteralPath $conhost -PathType Leaf)) { throw 'conhost.exe 不存在；无法注册 headless 任务。' }
$powershell = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
$arguments = '--headless "' + $powershell + '" -NoProfile -NonInteractive -EncodedCommand ' + $encoded
if ($ShowAction) {
    Write-Output ('Execute: ' + $conhost)
    Write-Output ('Command: --headless "' + $powershell + '" -NoProfile -NonInteractive -Command ' + $command)
    return
}
$config = Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json
if (Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue) {
    throw '同名任务已存在；请先用 -Remove 删除，避免覆盖现有任务。'
}
$action = New-ScheduledTaskAction -Execute $conhost -Argument $arguments -WorkingDirectory (Split-Path $watcher)
$trigger = New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(1) -RepetitionInterval (New-TimeSpan -Minutes 3)
$identity = [Security.Principal.WindowsIdentity]::GetCurrent().Name
$principal = New-ScheduledTaskPrincipal -UserId $identity -LogonType Interactive -RunLevel Limited
$settings = New-ScheduledTaskSettingsSet -MultipleInstances IgnoreNew -StartWhenAvailable -ExecutionTimeLimit (New-TimeSpan -Minutes ([double]$config.codexTimeoutMinutes + 15))
if ($PSCmdlet.ShouldProcess($TaskName, "注册当前普通用户 $identity 的 3 分钟任务")) {
    Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Description 'GitHub Agent Relay; current user; synthetic/source tasks only.'
}
