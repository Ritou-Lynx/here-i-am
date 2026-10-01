param([string]$RunRoot,[string]$RunToken,[string]$NodePath,[string]$Mode,[int]$TimeoutMs)
$ErrorActionPreference = 'Stop'
foreach ($value in @($RunRoot,$NodePath,$PSScriptRoot)) { if ($value.Contains('"') -or $value.EndsWith('\')) { throw 'invalid_fixed_path' } }
$entry = Join-Path $PSScriptRoot 'supervise.ps1'
$arguments = @('-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-File',('"'+$entry+'"'),
  '-RunRoot',('"'+$RunRoot+'"'),'-RunToken',$RunToken,'-NodePath',('"'+$NodePath+'"'),'-Mode',$Mode,'-TimeoutMs',$TimeoutMs)
$supervisor = Start-Process -FilePath (Join-Path $PSHOME 'powershell.exe') -ArgumentList $arguments -WindowStyle Hidden -PassThru `
  -RedirectStandardOutput (Join-Path $RunRoot 'supervisor.stdout') -RedirectStandardError (Join-Path $RunRoot 'supervisor.stderr')
$handle = $supervisor.Handle
[IO.File]::WriteAllText((Join-Path $RunRoot 'supervisor-pid'), [string]$supervisor.Id)
if (-not $supervisor.WaitForExit($TimeoutMs + 20000)) { throw 'supervisor_exit_timeout' }
if ($supervisor.ExitCode -ne 0) { exit 2 }
$supervisor.Dispose()
