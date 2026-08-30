param(
  [string]$Serial,
  [string]$Prompt,
  [string]$AdbPath,
  [string]$ConversationId,
  [string]$ProjectTitle,
  [switch]$Execute,
  [int]$ResponseTimeoutMs = 120000,
  [int]$AudioEndTimeoutMs = 180000
)

$ErrorActionPreference = "Stop"

$node = Get-Command node -ErrorAction SilentlyContinue
if (-not $node) {
  throw "Node.js is required to run the ChatGPT Android bridge PoC."
}

$scriptPath = Join-Path $PSScriptRoot "chatgpt_sleep_bridge.mjs"
$arguments = @($scriptPath)

if ($Execute) {
  if ([string]::IsNullOrWhiteSpace($Prompt)) {
    throw "-Prompt is required together with -Execute."
  }
  $arguments += "--execute"
  $arguments += "--prompt"
  $arguments += $Prompt
} else {
  $arguments += "--dry-run"
}

if (-not [string]::IsNullOrWhiteSpace($Serial)) {
  $arguments += "--serial"
  $arguments += $Serial
}

if (-not [string]::IsNullOrWhiteSpace($AdbPath)) {
  $arguments += "--adb"
  $arguments += $AdbPath
}

if (
  -not [string]::IsNullOrWhiteSpace($ConversationId) -or
  -not [string]::IsNullOrWhiteSpace($ProjectTitle)
) {
  if (
    [string]::IsNullOrWhiteSpace($ConversationId) -or
    [string]::IsNullOrWhiteSpace($ProjectTitle)
  ) {
    throw "-ConversationId and -ProjectTitle must be supplied together."
  }
  $arguments += "--conversation-id"
  $arguments += $ConversationId
  $arguments += "--project-title"
  $arguments += $ProjectTitle
}

$arguments += "--response-timeout-ms"
$arguments += [string]$ResponseTimeoutMs
$arguments += "--audio-end-timeout-ms"
$arguments += [string]$AudioEndTimeoutMs

& $node.Source @arguments
exit $LASTEXITCODE
