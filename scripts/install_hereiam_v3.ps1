$ErrorActionPreference = "Stop"

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
Set-Location $repoRoot

$expectedBranch = "v3-lab"
$expectedPackage = "com.memexlab.hereiam.v3"
$apkPath = "build\app\outputs\flutter-apk\app-hereiamv3-debug.apk"

$currentBranch = (& git rev-parse --abbrev-ref HEAD).Trim()
if ($currentBranch -ne $expectedBranch) {
  Write-Error "Refusing to install: current branch is '$currentBranch', expected '$expectedBranch'."
  exit 1
}

Write-Host "== Here I Am V3 install =="
Write-Host "Branch: $currentBranch"
Write-Host "Package: $expectedPackage"

# Ensure adb is reachable. Some shells don't have platform-tools on PATH.
if (-not (Get-Command adb -ErrorAction SilentlyContinue)) {
  $candidateRoots = @()
  if ($env:ANDROID_HOME) { $candidateRoots += $env:ANDROID_HOME }
  if ($env:ANDROID_SDK_ROOT) { $candidateRoots += $env:ANDROID_SDK_ROOT }
  if ($env:LOCALAPPDATA) { $candidateRoots += (Join-Path $env:LOCALAPPDATA "Android\Sdk") }
  $adbDir = $null
  foreach ($root in $candidateRoots) {
    $dir = Join-Path $root "platform-tools"
    if (Test-Path -LiteralPath (Join-Path $dir "adb.exe")) {
      $adbDir = $dir
      break
    }
  }
  if (-not $adbDir) {
    Write-Error "adb not found on PATH or in common Android SDK locations. Set ANDROID_HOME or add platform-tools to PATH."
    exit 1
  }
  $env:PATH = "$adbDir;$env:PATH"
  Write-Host "adb resolved to: $adbDir"
}

& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $repoRoot "scripts\verify_critical_fixes.ps1")
if ($LASTEXITCODE -ne 0) {
  exit $LASTEXITCODE
}

& flutter build apk --debug --flavor hereIAmV3
if ($LASTEXITCODE -ne 0) {
  exit $LASTEXITCODE
}

& adb shell am force-stop $expectedPackage
& adb install -r -d -t $apkPath
if ($LASTEXITCODE -ne 0) {
  exit $LASTEXITCODE
}

& adb shell monkey -p $expectedPackage -c android.intent.category.LAUNCHER 1
