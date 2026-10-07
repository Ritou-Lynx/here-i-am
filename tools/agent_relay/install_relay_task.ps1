[CmdletBinding(SupportsShouldProcess)]
param(
    [switch]$Remove,
    [string]$TaskName = 'HereIAm-AgentRelay',
    [string]$ConfigPath = (Join-Path $PSScriptRoot '.state\config.json'),
    [string]$NodePath = '',
    [string]$GhPath = '',
    [string]$CodexPath = ''
)
$ErrorActionPreference = 'Stop'
if ($Remove) {
    if (Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue) {
        if ($PSCmdlet.ShouldProcess($TaskName, '删除 Agent Relay 计划任务')) {
            Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
        }
    }
    return
}
if (!$NodePath) { $NodePath = (Get-Command node -ErrorAction Stop).Source }
if (!$GhPath) { $GhPath = (Get-Command gh -ErrorAction Stop).Source }
if (!$CodexPath) { $CodexPath = (Get-Command codex -ErrorAction Stop).Source }
$NodePath = (Resolve-Path -LiteralPath $NodePath).Path
$GhPath = (Resolve-Path -LiteralPath $GhPath).Path
$CodexPath = (Resolve-Path -LiteralPath $CodexPath).Path
$ConfigPath = (Resolve-Path -LiteralPath $ConfigPath).Path
$watcher = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot 'relay_watcher.mjs')).Path
$config = Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json
if (Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue) {
    throw '同名任务已存在；请先用 -Remove 删除，避免覆盖现有任务。'
}
# Capture only executable directories. No token, auth file or user configuration is copied.
$commandDirs = @((Split-Path $NodePath), (Split-Path $GhPath), (Split-Path $CodexPath), (Split-Path (Get-Command git -ErrorAction Stop).Source))
$taskPath = (($commandDirs + @($env:PATH)) -join ';')
function Quote-PsLiteral([string]$Value) { return "'" + $Value.Replace("'", "''") + "'" }
$logDir = Join-Path (Split-Path $ConfigPath) 'logs'
$logFile = Join-Path $logDir 'task-last.log'
$command = '$ErrorActionPreference=''Stop''; [Console]::OutputEncoding=[Text.UTF8Encoding]::new($false); $OutputEncoding=[Console]::OutputEncoding; $relayExit=1; try { $env:PATH=' + (Quote-PsLiteral $taskPath) + '; New-Item -ItemType Directory -Path ' + (Quote-PsLiteral $logDir) + ' -Force | Out-Null; & ' + (Quote-PsLiteral $NodePath) + ' ' + (Quote-PsLiteral $watcher) + ' --once --config ' + (Quote-PsLiteral $ConfigPath) + ' *> ' + (Quote-PsLiteral $logFile) + '; if ($null -eq $LASTEXITCODE) { throw ''Node exit code unavailable'' }; $relayExit=$LASTEXITCODE } catch { $_ | Out-File -LiteralPath ' + (Quote-PsLiteral $logFile) + ' -Append -Encoding utf8; $relayExit=1 }; exit $relayExit'
$encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($command))
$action = New-ScheduledTaskAction -Execute (Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe') -Argument "-NoProfile -NonInteractive -WindowStyle Hidden -EncodedCommand $encoded" -WorkingDirectory (Split-Path $watcher)
$trigger = New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(1) -RepetitionInterval (New-TimeSpan -Minutes 3)
$identity = [Security.Principal.WindowsIdentity]::GetCurrent().Name
$principal = New-ScheduledTaskPrincipal -UserId $identity -LogonType Interactive -RunLevel Limited
$settings = New-ScheduledTaskSettingsSet -MultipleInstances IgnoreNew -StartWhenAvailable -ExecutionTimeLimit (New-TimeSpan -Minutes ([double]$config.codexTimeoutMinutes + 15))
if ($PSCmdlet.ShouldProcess($TaskName, "注册当前普通用户 $identity 的 3 分钟任务")) {
    Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Description 'GitHub Agent Relay; current user; synthetic/source tasks only.'
}
