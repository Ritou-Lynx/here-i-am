param([Parameter(Mandatory=$true)][int]$ProcessId)
$ErrorActionPreference = 'Stop'
$target = [Diagnostics.Process]::GetProcessById($ProcessId)
$handle = $target.Handle
@{pid=$target.Id; created_ticks=$target.StartTime.ToUniversalTime().Ticks.ToString([Globalization.CultureInfo]::InvariantCulture); image=$target.MainModule.FileName} | ConvertTo-Json -Compress
$target.Dispose()
