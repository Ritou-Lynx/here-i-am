[CmdletBinding()]
param(
  [ValidateSet('i')]
  [string]$ServerName = 'i',
  [switch]$SkipCodex,
  [switch]$SkipClaude,
  [switch]$SkipHermes,
  [switch]$SkipGuidance
)

$ErrorActionPreference = 'Stop'
$Utf8NoBom = [System.Text.UTF8Encoding]::new($false)
$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$Branch = (& git -C $RepoRoot branch --show-current).Trim()
if ($LASTEXITCODE -ne 0 -or $Branch -ne 'v3-lab') {
  throw "Global i Gateway must be installed from v3-lab; current branch: $Branch"
}

$IHome = Join-Path $env:USERPROFILE '.i'
$Runtime = Join-Path $IHome 'runtime'
$IdentityPath = Join-Path $IHome 'identity.json'
$RegistryPath = Join-Path $IHome 'projects.json'
$RuntimeServer = Join-Path $Runtime 'i_mcp_server.mjs'
$Node = (Get-Command node -ErrorAction Stop).Source
New-Item -ItemType Directory -Force -Path $Runtime | Out-Null

foreach ($File in @(
  'i_project_registry.mjs',
  'i_activity_crypto.mjs',
  'i_activity_key_provider.mjs',
  'i_activity_store.mjs',
  'i_context.mjs',
  'i_mcp_server.mjs',
  'rebuild_i_activity_index.mjs',
  'validate_i_project_registry.mjs'
)) {
  Copy-Item -Force (Join-Path $PSScriptRoot $File) (Join-Path $Runtime $File)
}
if (-not (Test-Path -LiteralPath $IdentityPath)) {
  Copy-Item (Join-Path $PSScriptRoot 'identity.default.json') $IdentityPath
}

if (Test-Path -LiteralPath $RegistryPath) {
  try {
    $Registry = Get-Content -Raw -Encoding UTF8 $RegistryPath | ConvertFrom-Json
  } catch {
    throw "Existing i project registry is invalid; it was not overwritten: $RegistryPath"
  }
  if ($null -eq $Registry.projects) {
    throw "Existing i project registry has no projects array; it was not overwritten: $RegistryPath"
  }
} else {
  $Registry = [pscustomobject]@{ schema_version = 1; projects = @() }
}

$Existing = @($Registry.projects | Where-Object { $_.project_key -eq 'here-i-am' } | Select-Object -First 1)
$ProjectId = if ($Existing.Count -gt 0 -and $Existing[0].project_id) {
  [string]$Existing[0].project_id
} else {
  [guid]::NewGuid().ToString()
}
$DefaultPolicy = [pscustomobject][ordered]@{
  id = 'personal_full'
  classification = 'personal'
  cross_project_visibility = 'summary'
  memory_v3 = 'project_summary'
  allowed_clients = @('codex', 'claude-code', 'hermes', 'i-probe')
}
$ExistingPolicy = if ($Existing.Count -gt 0 -and $null -ne $Existing[0].policy) {
  $Existing[0].policy
} elseif ($Existing.Count -gt 0) {
  [pscustomobject][ordered]@{
    id = 'confidential_local'
    classification = 'confidential'
    cross_project_visibility = 'hidden'
    memory_v3 = 'none'
    allowed_clients = @('codex', 'claude-code', 'hermes')
  }
} else {
  $DefaultPolicy
}
$HereIAm = [pscustomobject][ordered]@{
  project_id = $ProjectId
  project_key = 'here-i-am'
  display_name = 'Here I am'
  roots = @($RepoRoot)
  provider = 'here_i_am'
  context_files = @(
    [pscustomobject]@{ path = 'docs/development/I_PROJECT_STATE.md'; kind = 'project_state' },
    [pscustomobject]@{ path = 'DEVLOG.md'; kind = 'devlog' }
  )
  policy = $ExistingPolicy
}
$OtherProjects = @($Registry.projects | Where-Object { $_.project_key -ne 'here-i-am' })
$Registry.schema_version = 1
$Registry.projects = @($OtherProjects + $HereIAm)
$RegistryJson = $Registry | ConvertTo-Json -Depth 20
$RegistryTemp = "$RegistryPath.$PID.tmp"
try {
  [System.IO.File]::WriteAllText($RegistryTemp, "$RegistryJson`n", $Utf8NoBom)
  & $Node (Join-Path $Runtime 'validate_i_project_registry.mjs') $RegistryTemp | Out-Null
  if ($LASTEXITCODE -ne 0) { throw 'Proposed i Project Registry failed strict validation.' }
  if (Test-Path -LiteralPath $RegistryPath) {
    [System.IO.File]::Replace($RegistryTemp, $RegistryPath, $null)
  } else {
    [System.IO.File]::Move($RegistryTemp, $RegistryPath)
  }
} finally {
  Remove-Item -LiteralPath $RegistryTemp -Force -ErrorAction SilentlyContinue
}

function Update-ManagedBlock([string]$Path, [string]$Body) {
  $Directory = Split-Path -Parent $Path
  New-Item -ItemType Directory -Force -Path $Directory | Out-Null
  $Start = '<!-- i-continuity:start -->'
  $End = '<!-- i-continuity:end -->'
  $Block = "$Start`n$($Body.Trim())`n$End"
  $Current = if (Test-Path -LiteralPath $Path) {
    [string](Get-Content -Raw -Encoding UTF8 $Path)
  } else {
    ''
  }
  $Pattern = '(?s)' + [regex]::Escape($Start) + '.*?' + [regex]::Escape($End)
  if ([regex]::IsMatch($Current, $Pattern)) {
    $Updated = [regex]::Replace($Current, $Pattern, $Block)
  } else {
    $Prefix = if ([string]::IsNullOrWhiteSpace($Current)) { '' } else { $Current.TrimEnd() + "`n`n" }
    $Updated = $Prefix + $Block + "`n"
  }
  [System.IO.File]::WriteAllText($Path, $Updated, $Utf8NoBom)
}

function Invoke-QuietRemove([scriptblock]$Command) {
  $PreviousPreference = $ErrorActionPreference
  try {
    $ErrorActionPreference = 'Continue'
    & $Command 2>$null | Out-Null
  } finally {
    $ErrorActionPreference = $PreviousPreference
  }
}

$PreviousIHome = $env:I_HOME
try {
  $env:I_HOME = $IHome
  & $Node (Join-Path $Runtime 'rebuild_i_activity_index.mjs') | Out-Null
  if ($LASTEXITCODE -ne 0) {
    throw 'Failed to rebuild the encrypted i Activity Index with the current Project Registry.'
  }
} finally {
  if ($null -eq $PreviousIHome) {
    Remove-Item Env:I_HOME -ErrorAction SilentlyContinue
  } else {
    $env:I_HOME = $PreviousIHome
  }
}
if (-not $SkipCodex) {
  Invoke-QuietRemove { codex mcp remove $ServerName }
  & codex mcp add $ServerName --env "I_HOME=$IHome" --env 'I_CLIENT_ID=codex' -- $Node $RuntimeServer
  if ($LASTEXITCODE -ne 0) { throw 'Failed to install the Codex user-level i MCP server.' }
}
if (-not $SkipClaude) {
  Invoke-QuietRemove { claude mcp remove $ServerName --scope user }
  & claude mcp add -e "I_HOME=$IHome" -e 'I_CLIENT_ID=claude-code' --transport stdio --scope user $ServerName -- $Node $RuntimeServer
  if ($LASTEXITCODE -ne 0) { throw 'Failed to install the Claude user-level i MCP server.' }
}
if (-not $SkipHermes) {
  Invoke-QuietRemove { hermes mcp remove $ServerName }
  'y' | & hermes mcp add $ServerName --command $Node --env "I_HOME=$IHome" 'I_CLIENT_ID=hermes' --args $RuntimeServer
  if ($LASTEXITCODE -ne 0) { throw 'Failed to install the Hermes i MCP server.' }
}

if (-not $SkipGuidance) {
  $Guidance = Get-Content -Raw -Encoding UTF8 (Join-Path $PSScriptRoot 'i_global_guidance.md')
  if (-not $SkipCodex) {
    Update-ManagedBlock (Join-Path $env:USERPROFILE '.codex\AGENTS.md') $Guidance
  }
  if (-not $SkipClaude) {
    Update-ManagedBlock (Join-Path $env:USERPROFILE '.claude\CLAUDE.md') $Guidance
  }
  if (-not $SkipHermes) {
    $HermesConfig = (& hermes config path).Trim()
    if ($LASTEXITCODE -eq 0 -and $HermesConfig) {
      Update-ManagedBlock (Join-Path (Split-Path -Parent $HermesConfig) 'SOUL.md') $Guidance
    }
  }
}

[pscustomobject]@{
  server_name = $ServerName
  i_home = $IHome
  runtime_server = $RuntimeServer
  project_key = 'here-i-am'
  branch = $Branch
  mode = 'project_closeout_ingress'
  phase = '2'
} | ConvertTo-Json
