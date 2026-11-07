[Console]::OutputEncoding = [Text.UTF8Encoding]::new($false)
# 给 FeishuNotes-Mirror 加一个每天 19:20 的触发器（日摘要白天版 19:30 生成，先同步一次日记）。
# 脚本轮 mode=write：用户在评论上点 👍 后由 watcher 运行。原来每 30 分钟的触发器保持不变，不立即触发任务。
# 输出每行一个 JSON，不含本机路径或 SID。
$ErrorActionPreference = 'Stop'
if ($PSVersionTable.PSEdition -ne 'Desktop' -or $PSVersionTable.PSVersion.Major -ne 5) { throw 'host_not_51' }
$env:PSModulePath = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\Modules'
function Out-Row($step, $ok, $detail) { Write-Output (ConvertTo-Json -Compress -InputObject ([ordered]@{ step = $step; ok = $ok; detail = $detail })) }
function Get-TriggerSummary($task) {
  @($task.Triggers | ForEach-Object {
    $kind = $_.CimClass.CimClassName -replace '^MSFT_Task|Trigger$', ''
    $at = if ($_.StartBoundary) { ([datetime]$_.StartBoundary).ToString('HH:mm') } else { '-' }
    $every = if ($_.Repetition -and $_.Repetition.Interval) { '/' + [string]$_.Repetition.Interval } else { '' }
    $kind + '@' + $at + $every
  }) -join ','
}
try {
  $taskName = 'FeishuNotes-Mirror'
  $vbs = Join-Path (Join-Path $env:USERPROFILE 'feishu-tutor-tool') 'notes-mirror.vbs'
  $wscript = Join-Path $env:SystemRoot 'System32\wscript.exe'
  $task = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
  if (-not $task) { throw 'task_missing' }
  $a = $task.Actions[0]
  if ($a.Execute -ne $wscript -or -not ([string]$a.Arguments).Contains($vbs)) { throw 'task_not_ours' }
  $before = Get-TriggerSummary $task
  $has = @($task.Triggers | Where-Object { $_.CimClass.CimClassName -eq 'MSFT_TaskDailyTrigger' -and $_.StartBoundary -and ([datetime]$_.StartBoundary).ToString('HH:mm') -eq '19:20' }).Count -gt 0
  Out-Row 'preflight' $true ('triggers=' + $before + ' has_1920=' + $has)
  if (-not $has) {
    $daily = New-ScheduledTaskTrigger -Daily -At ([datetime]::Today.AddHours(19).AddMinutes(20))
    Set-ScheduledTask -TaskName $taskName -Trigger (@($task.Triggers) + $daily) | Out-Null
  }
  $after = Get-ScheduledTask -TaskName $taskName
  $rep = @($after.Triggers | Where-Object { $_.Repetition -and $_.Repetition.Interval })
  if ($rep.Count -lt 1 -or [string]$rep[0].Repetition.Interval -ne 'PT30M' -or $rep[0].Repetition.Duration) { throw 'repeat_trigger_changed' }
  $info = Get-ScheduledTaskInfo -TaskName $taskName
  Out-Row 'schedule' $true ('state=' + [string]$after.State + ' triggers=' + (Get-TriggerSummary $after) + ' last_result=' + [string]$info.LastTaskResult + ' last_run=' + $(if ($info.LastRunTime) { $info.LastRunTime.ToString('yyyy-MM-ddTHH:mm') } else { 'none' }))
  exit 0
} catch {
  $msg = [string]$_.Exception.Message
  if ($msg -notmatch '^[a-z_0-9]{1,60}$') { $msg = 'failed:' + $_.Exception.GetType().Name }
  Out-Row 'error' $false $msg
  exit 1
}
