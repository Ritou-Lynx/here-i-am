$ErrorActionPreference = "Stop"

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
Set-Location $repoRoot

& git config core.hooksPath .githooks
if ($LASTEXITCODE -ne 0) {
  exit $LASTEXITCODE
}

Write-Host "Git hooks installed for this clone: core.hooksPath=.githooks"
Write-Host "Project state commits will be checked by scripts/verify_project_state.ps1"
