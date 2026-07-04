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
