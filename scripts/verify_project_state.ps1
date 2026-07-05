param(
  [switch]$Quiet
)

$ErrorActionPreference = "Stop"

$projectStatePath = "docs/development/I_PROJECT_STATE.md"

if ($env:SKIP_PROJECT_STATE -eq "1" -or $env:SKIP_PROJECT_STATE -eq "true") {
  if (-not $Quiet) {
    Write-Host "Project state check skipped by SKIP_PROJECT_STATE=$env:SKIP_PROJECT_STATE"
  }
  exit 0
}

$staged = & git diff --cached --name-only --diff-filter=ACMRTD
if ($LASTEXITCODE -ne 0) {
  exit $LASTEXITCODE
}

$staged = @($staged | Where-Object { $_ -and $_.Trim().Length -gt 0 })
if ($staged.Count -eq 0) {
  if (-not $Quiet) {
    Write-Host "Project state check: no staged files."
  }
  exit 0
}

$stateChanged = $staged -contains $projectStatePath

function Test-ImpactfulProjectPath {
  param([string]$Path)

  if ($Path -eq $projectStatePath) { return $false }
  if ($Path -eq "DEVLOG.md") { return $false }

  if ($Path -eq "AGENTS.md") { return $true }
  if ($Path -eq "pubspec.yaml" -or $Path -eq "pubspec.lock") { return $true }

  $prefixes = @(
    "lib/",
    "test/",
    "scripts/",
    "tools/",
    "android/",
    "ios/",
    "assets/",
    "docs/companion-first/",
    "docs/development/",
    "UI design-here I am/"
  )

  foreach ($prefix in $prefixes) {
    if ($Path.StartsWith($prefix, [System.StringComparison]::OrdinalIgnoreCase)) {
      return $true
    }
  }

  return $false
}

$impactful = @($staged | Where-Object { Test-ImpactfulProjectPath $_ })

if ($impactful.Count -eq 0) {
  if (-not $Quiet) {
    Write-Host "Project state check: no project-state-impacting files staged."
  }
  exit 0
}

if ($stateChanged) {
  if (-not $Quiet) {
    Write-Host "Project state check: OK ($projectStatePath is staged)."
  }
  exit 0
}

Write-Host ""
Write-Host "Project state check failed."
Write-Host "You staged changes that may affect Lin Ai's project awareness, but did not update:"
Write-Host "  $projectStatePath"
Write-Host ""
Write-Host "Impactful staged files:"
$impactful | Select-Object -First 20 | ForEach-Object { Write-Host "  - $_" }
if ($impactful.Count -gt 20) {
  Write-Host "  ... and $($impactful.Count - 20) more"
}
Write-Host ""
Write-Host "Update and stage $projectStatePath, or bypass intentionally with:"
Write-Host "  `$env:SKIP_PROJECT_STATE='1'; git commit ..."
Write-Host ""

exit 1
