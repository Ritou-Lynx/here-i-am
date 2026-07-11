[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)]
  [string]$ProjectPath,
  [Parameter(Mandatory = $true)]
  [ValidatePattern('^[a-zA-Z0-9][a-zA-Z0-9._-]{1,79}$')]
  [string]$ProjectKey,
  [string]$DisplayName,
  [ValidateSet('personal_full', 'work_redacted', 'confidential_local', 'ephemeral')]
  [string]$Policy = 'confidential_local',
  [ValidateSet('hidden', 'name_only', 'summary')]
  [string]$CrossProjectVisibility = 'hidden',
  [ValidateSet('generic_git', 'markdown', 'here_i_am')]
  [string]$Provider = 'generic_git',
  [string[]]$ContextFiles = @(),
  [string[]]$AllowedClients = @('codex', 'claude-code', 'hermes'),
  [string]$IHome = (Join-Path $env:USERPROFILE '.i')
)

$ErrorActionPreference = 'Stop'
$Utf8NoBom = [System.Text.UTF8Encoding]::new($false)
$Node = (Get-Command node -ErrorAction Stop).Source
$ProjectItem = Get-Item -LiteralPath $ProjectPath -ErrorAction Stop
if (-not $ProjectItem.PSIsContainer) { throw "ProjectPath must be a directory: $ProjectPath" }
$Root = $ProjectItem.FullName
$RegistryPath = Join-Path $IHome 'projects.json'
New-Item -ItemType Directory -Force -Path $IHome | Out-Null

if (Test-Path -LiteralPath $RegistryPath) {
  try {
    $Registry = Get-Content -Raw -Encoding UTF8 $RegistryPath | ConvertFrom-Json
  } catch {
    throw "Existing i project registry is invalid; it was not changed: $RegistryPath"
  }
  if ($null -eq $Registry.projects) {
    throw "Existing i project registry has no projects array; it was not changed: $RegistryPath"
  }
} else {
  $Registry = [pscustomobject]@{ schema_version = 1; projects = @() }
}

$DuplicateRoot = @($Registry.projects | Where-Object {
  $_.project_key -ne $ProjectKey -and @($_.roots) -contains $Root
})
if ($DuplicateRoot.Count -gt 0) {
  throw "This root is already registered as project '$($DuplicateRoot[0].project_key)'."
}

$NormalizedFiles = foreach ($File in $ContextFiles) {
  $Relative = $File.Replace('\', '/').Trim()
  if (-not $Relative -or [System.IO.Path]::IsPathRooted($Relative) -or $Relative.Split('/') -contains '..') {
    throw "Context file must stay inside the project root: $File"
  }
  $Kind = if ($Relative -match '(?i)devlog|changelog') {
    'devlog'
  } elseif ($Relative -match '(?i)project[_-]?state|status|state\.md$') {
    'project_state'
  } else {
    'document'
  }
  [pscustomobject]@{ path = $Relative; kind = $Kind }
}

if ($Policy -in @('confidential_local', 'ephemeral')) {
  $CrossProjectVisibility = 'hidden'
  $MemoryV3 = 'none'
} elseif ($Policy -eq 'work_redacted') {
  $MemoryV3 = 'redacted_summary'
} else {
  $MemoryV3 = 'project_summary'
}
$Existing = @($Registry.projects | Where-Object { $_.project_key -eq $ProjectKey } | Select-Object -First 1)
$ProjectId = if ($Existing.Count -gt 0 -and $Existing[0].project_id) {
  [string]$Existing[0].project_id
} else {
  [guid]::NewGuid().ToString()
}
$Name = if ($DisplayName) { $DisplayName } else { Split-Path -Leaf $Root }
$Entry = [pscustomobject][ordered]@{
  project_id = $ProjectId
  project_key = $ProjectKey
  display_name = $Name
  roots = @($Root)
  provider = $Provider
  context_files = @($NormalizedFiles)
  policy = [pscustomobject][ordered]@{
    id = $Policy
    classification = if ($Policy -eq 'personal_full') { 'personal' } elseif ($Policy -eq 'work_redacted') { 'work' } else { 'confidential' }
    cross_project_visibility = $CrossProjectVisibility
    memory_v3 = $MemoryV3
    allowed_clients = @($AllowedClients)
  }
}
$Others = @($Registry.projects | Where-Object { $_.project_key -ne $ProjectKey })
$Registry.schema_version = 1
$Registry.projects = @($Others + $Entry)
$Json = $Registry | ConvertTo-Json -Depth 20
$RegistryTemp = "$RegistryPath.$PID.tmp"
try {
  [System.IO.File]::WriteAllText($RegistryTemp, "$Json`n", $Utf8NoBom)
  & $Node (Join-Path $PSScriptRoot 'validate_i_project_registry.mjs') $RegistryTemp | Out-Null
  if ($LASTEXITCODE -ne 0) { throw 'Proposed i Project Registry failed strict validation; the existing registry was not changed.' }
  if (Test-Path -LiteralPath $RegistryPath) {
    [System.IO.File]::Replace($RegistryTemp, $RegistryPath, $null)
  } else {
    [System.IO.File]::Move($RegistryTemp, $RegistryPath)
  }
} finally {
  Remove-Item -LiteralPath $RegistryTemp -Force -ErrorAction SilentlyContinue
}

$IndexRebuild = Join-Path $PSScriptRoot 'rebuild_i_activity_index.mjs'
$PreviousIHome = $env:I_HOME
try {
  $env:I_HOME = $IHome
  & $Node $IndexRebuild | Out-Null
  if ($LASTEXITCODE -ne 0) {
    throw "Project registry was updated, but the encrypted Activity Index could not be re-policy-filtered. Retry: node `"$IndexRebuild`""
  }
} finally {
  if ($null -eq $PreviousIHome) {
    Remove-Item Env:I_HOME -ErrorAction SilentlyContinue
  } else {
    $env:I_HOME = $PreviousIHome
  }
}

[pscustomobject]@{
  project_id = $ProjectId
  project_key = $ProjectKey
  display_name = $Name
  policy = $Policy
  cross_project_visibility = $CrossProjectVisibility
  status = 'registered'
} | ConvertTo-Json
