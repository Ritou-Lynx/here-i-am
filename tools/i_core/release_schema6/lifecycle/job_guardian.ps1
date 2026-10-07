# Internal fixed guardian. It never opens a database or creates a clean receipt.
param([Parameter(Mandatory=$true)][string]$ControlDirectory,[Parameter(Mandatory=$true)][ValidatePattern('^[a-f0-9]{64}$')][string]$RunId)
$ErrorActionPreference='Stop'
$env:PSModulePath="$PSHOME\Modules"
. (Join-Path $PSScriptRoot 'protected_paths.ps1')
Assert-ProtectedPath $ControlDirectory -Root
Assert-ProtectedPath (Join-Path $ControlDirectory 'launch.json')
$launch=Get-Content -LiteralPath (Join-Path $ControlDirectory 'launch.json') -Raw | ConvertFrom-Json
if($launch.token -ne $RunId -or $launch.lifecycle -ne $PSScriptRoot) { throw 'guardian_binding_mismatch' }
. (Join-Path $PSScriptRoot 'owned_job.ps1')
# Guard owns the bounded bootstrap, original parent handle, Job and transferred
# lock handle. It reaps on incomplete transfer as well as on later parent loss.
$result=[Schema6OwnedJob]::Guard($ControlDirectory,$RunId,[uint32]$launch.parent_pid,$launch.parent_started_ticks)
# Parent loss never creates a clean receipt. Persist only fail-closed status,
# while this guardian still has established the original named Job is empty.
if($result.parent_exit_observed -and $result.job_empty_confirmed) {
  $markerPath=Join-Path $launch.state 's6-lifecycle.json'
  if(Test-Path -LiteralPath $markerPath) {
    Assert-ProtectedPath $markerPath
    $marker=Get-Content -LiteralPath $markerPath -Raw | ConvertFrom-Json
    if($marker.token -eq $RunId) {
      $marker.phase='recovery_required'
      $temporary=Join-Path $launch.state ('s6-guardian-'+$RunId+'.tmp')
      [IO.File]::WriteAllText($temporary,($marker | ConvertTo-Json -Depth 6),[Text.UTF8Encoding]::new($false))
      [IO.File]::Replace($temporary,$markerPath,[NullString]::Value)
    }
  }
}
$data=@{run_id=$RunId;result=$result}
[IO.File]::WriteAllText((Join-Path $ControlDirectory 'guardian.json'),($data | ConvertTo-Json -Depth 5),[Text.UTF8Encoding]::new($false))
if(-not $result.job_empty_confirmed) { exit 1 }
