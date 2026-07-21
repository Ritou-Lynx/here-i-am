param(
  [string]$HostName = "127.0.0.1",
  [int]$Port = 47831,
  [string]$CertPath = "",
  [string]$KeyPath = ""
)

$ErrorActionPreference = "Stop"

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

node "$PSScriptRoot\dev_agent_bridge.mjs"
