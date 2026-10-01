param(
  [string]$HostName = "127.0.0.1",
  [int]$Port = 47831,
  [string]$CertPath = "",
  [string]$KeyPath = "",
  [switch]$EnableExperimentalRuntime,
  [switch]$UseEnvProxy,
  [string]$CodexExecutable = ""
)

$ErrorActionPreference = "Stop"

function Get-CurrentWindowsIdentityName {
  return [Security.Principal.WindowsIdentity]::GetCurrent().Name
}

function Assert-PortIsAvailable {
  param([int]$RequestedPort)

  try {
    $listener = [Net.NetworkInformation.IPGlobalProperties]::GetIPGlobalProperties().GetActiveTcpListeners() |
      Where-Object { $_.Port -eq $RequestedPort } |
      Select-Object -First 1
  } catch {
    throw "Dev Agent Bridge was not started because listening TCP ports could not be inspected: $($_.Exception.Message)"
  }
  if (-not $listener) {
    return
  }

  $owningProcessId = "unknown"
  $processName = "unknown"
  try {
    $connection = Get-NetTCPConnection -LocalPort $RequestedPort -ErrorAction Stop |
      Where-Object { $_.State -eq "Listen" } |
      Select-Object -First 1
    if ($connection) {
      $owningProcessId = $connection.OwningProcess
      $processName = (Get-Process -Id $owningProcessId -ErrorAction Stop).ProcessName
    }
  } catch {
    # The listener remains a conflict even when Windows declines PID diagnostics.
  }
  throw "Dev Agent Bridge was not started and did not replace the existing listener on port $RequestedPort (PID $owningProcessId, process $processName). Stop or choose that listener explicitly, then retry."
}

$runtimeEnabled = $EnableExperimentalRuntime -or
  ($env:DEV_AGENT_EXPERIMENTAL_RUNTIME_ADAPTER -eq "1")

if ($CodexExecutable) {
  if (-not $runtimeEnabled) {
    throw "-CodexExecutable requires -EnableExperimentalRuntime (or DEV_AGENT_EXPERIMENTAL_RUNTIME_ADAPTER=1)."
  }
  if (-not (Test-Path -LiteralPath $CodexExecutable -PathType Leaf)) {
    throw "Codex executable was not found: $CodexExecutable"
  }
  if ([IO.Path]::GetExtension($CodexExecutable) -ne ".exe") {
    throw "Codex executable must be a .exe file: $CodexExecutable"
  }
  $env:DEV_AGENT_EXPERIMENTAL_APP_SERVER_COMMAND =
    (Resolve-Path -LiteralPath $CodexExecutable -ErrorAction Stop).Path
  $env:DEV_AGENT_EXPERIMENTAL_APP_SERVER_ARGS_JSON =
    '["app-server","--stdio"]'
}

if ($runtimeEnabled) {
  $identityName = Get-CurrentWindowsIdentityName
  if ($identityName -match '(?i)(?:^|\\)CodexSandbox(?:Offline|Online)$') {
    throw "Experimental Runtime was not started because the current Windows identity is $identityName. Run this command from the ordinary user session or an approved host; do not try to bypass the Codex sandbox."
  }
  $env:DEV_AGENT_EXPERIMENTAL_RUNTIME_ADAPTER = "1"
}

Assert-PortIsAvailable -RequestedPort $Port

$env:DEV_AGENT_BRIDGE_HOST = $HostName
$env:DEV_AGENT_BRIDGE_PORT = "$Port"

if ($CertPath -and $KeyPath) {
  $env:DEV_AGENT_BRIDGE_CERT = $CertPath
  $env:DEV_AGENT_BRIDGE_KEY = $KeyPath
} else {
  Remove-Item Env:\DEV_AGENT_BRIDGE_CERT -ErrorAction SilentlyContinue
  Remove-Item Env:\DEV_AGENT_BRIDGE_KEY -ErrorAction SilentlyContinue
}

# Default model for OpenCode runs when no per-call / per-session / per-project
# override is supplied. Use the user's MiniMax 套餐 by default so Bridge
# runs don't burn the opencode-go quota. Setting this here lets Bridge pick
# up a sane default without requiring a project-level setting.
if (-not (Test-Path Env:\DEV_AGENT_OPENCODE_MODEL)) {
  $env:DEV_AGENT_OPENCODE_MODEL = "minimax-cn-coding-plan/MiniMax-M3"
}

# Start-Process launches node without the user-level PATH expansion that
# interactive shells do (npm-global tools like `opencode` are installed
# under %APPDATA%\npm, which only shows up via HKCU\Environment). Merge
# the user PATH into the process-level PATH so spawn() inside the bridge
# can resolve `opencode` and friends.
$userPath = [Environment]::GetEnvironmentVariable('PATH', 'User')
if ($userPath) {
  $env:PATH = $env:PATH + ';' + $userPath
}

if ($UseEnvProxy) {
  # Node fetch uses the existing HTTP(S)_PROXY environment only with this flag.
  # Keep the default launch unchanged for hosts with direct network access.
  node --use-env-proxy "$PSScriptRoot\dev_agent_bridge.mjs"
} else {
  node "$PSScriptRoot\dev_agent_bridge.mjs"
}
$nodeExitCode = $LASTEXITCODE
exit $nodeExitCode
