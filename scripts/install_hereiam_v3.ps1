param(
  [ValidatePattern('^[a-fA-F0-9]{40}$')][string]$CandidateCommit = '',
  [ValidatePattern('^[a-fA-F0-9]{64}$')][string]$ApkSha256 = '',
  [switch]$UseExistingBuild,
  [switch]$ValidateOnly,
  [string]$DeviceSerial = ''
)
$ErrorActionPreference = "Stop"

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
Set-Location $repoRoot

$expectedBranch = "v3-lab"
$expectedPackage = "com.memexlab.hereiam.v3"
$apkPath = "build\app\outputs\flutter-apk\app-hereiamv3-debug.apk"

$currentBranch = (& git rev-parse --abbrev-ref HEAD).Trim()
if ($CandidateCommit) {
  $candidateHead = (& git rev-parse HEAD).Trim()
  if ($currentBranch -notlike 'codex/*' -or $candidateHead -ne $CandidateCommit) {
    throw 'Candidate install requires the exact committed codex/ branch HEAD.'
  }
  & git diff --quiet HEAD -- lib android assets packages pubspec.yaml pubspec.lock
  if ($LASTEXITCODE -ne 0) { throw 'Candidate source changed after commit; refusing to install.' }
  $untrackedInputs = @(& git ls-files --others --exclude-standard -- lib android assets packages pubspec.yaml pubspec.lock)
  if ($LASTEXITCODE -ne 0 -or $untrackedInputs.Count -gt 0) {
    throw 'Candidate has untracked build inputs; refusing to install.'
  }
} elseif ($currentBranch -ne $expectedBranch) {
  throw "Refusing to install: current branch is '$currentBranch', expected '$expectedBranch'."
}
if ($UseExistingBuild -and (-not $CandidateCommit -or -not $ApkSha256)) {
  throw 'An existing candidate APK requires an exact commit and SHA256.'
}

Write-Host "== Here I Am V3 install =="
Write-Host "Branch: $currentBranch"
Write-Host "Package: $expectedPackage"

# Resolve local SDK tools before any device operation.
$candidateRoots = @()
if ($env:ANDROID_HOME) { $candidateRoots += $env:ANDROID_HOME }
if ($env:ANDROID_SDK_ROOT) { $candidateRoots += $env:ANDROID_SDK_ROOT }
if ($env:LOCALAPPDATA) { $candidateRoots += (Join-Path $env:LOCALAPPDATA 'Android\Sdk') }
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

if (-not $UseExistingBuild) {
  & flutter build apk --debug --flavor hereIAmV3
  if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
}
if (-not (Test-Path -LiteralPath $apkPath -PathType Leaf)) { throw 'Candidate APK is missing.' }
if ($ApkSha256 -and (Get-FileHash -LiteralPath $apkPath -Algorithm SHA256).Hash -ne $ApkSha256) {
  throw 'Candidate APK hash mismatch; refusing to touch the phone.'
}
# A valid hash alone does not establish which application the APK installs.
$apkInspector = Get-Command aapt2,aapt -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty Source
if (-not $apkInspector) {
  foreach ($sdkRoot in $candidateRoots) {
    $buildTools = Join-Path $sdkRoot 'build-tools'
    if (-not (Test-Path -LiteralPath $buildTools -PathType Container)) { continue }
    foreach ($version in (Get-ChildItem -LiteralPath $buildTools -Directory | Sort-Object Name -Descending)) {
      foreach ($toolName in @('aapt2.exe','aapt.exe')) {
        $toolPath = Join-Path $version.FullName $toolName
        if (Test-Path -LiteralPath $toolPath -PathType Leaf) { $apkInspector = $toolPath; break }
      }
      if ($apkInspector) { break }
    }
    if ($apkInspector) { break }
  }
}
if (-not $apkInspector) { throw 'APK manifest inspector unavailable; refusing to touch the phone.' }
$badging = @(& $apkInspector dump badging $apkPath 2>&1)
if ($LASTEXITCODE -ne 0) { throw 'Cannot inspect APK manifest; refusing to touch the phone.' }
$packageLines = @($badging | Where-Object { "$_" -match "^package: name='([^']+)'" })
if ($packageLines.Count -ne 1 -or "$($packageLines[0])" -notmatch "^package: name='([^']+)'" -or $Matches[1] -cne $expectedPackage) {
  throw 'APK package is not com.memexlab.hereiam.v3; refusing to touch the phone.'
}
if ($ValidateOnly) {
  Write-Host 'Candidate commit, source, APK hash and package verified; no phone operation.'
  exit 0
}
$adbTarget = if ($DeviceSerial) { @('-s', $DeviceSerial) } else { @() }

& adb @adbTarget shell am force-stop $expectedPackage
& adb @adbTarget install -r -d -t $apkPath
if ($LASTEXITCODE -ne 0) {
  exit $LASTEXITCODE
}

& adb @adbTarget shell monkey -p $expectedPackage -c android.intent.category.LAUNCHER 1
