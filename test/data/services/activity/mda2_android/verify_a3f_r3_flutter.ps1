param([Parameter(Mandatory = $true)][string]$FlutterSdk, [switch]$NoResolve, [string]$HarnessRoot)
$ErrorActionPreference = 'Stop'
$repo = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../../../..'))
$harness = if ($HarnessRoot) { [IO.Path]::GetFullPath($HarnessRoot) } else { Join-Path $PSScriptRoot '.verification_a3/r3' }
$dartExe = Join-Path $FlutterSdk 'bin/cache/dart-sdk/bin/dart.exe'
$flutterTool = Join-Path $FlutterSdk 'bin/cache/flutter_tools.snapshot'
if (!(Test-Path -LiteralPath $dartExe) -or !(Test-Path -LiteralPath $flutterTool)) { throw 'An initialized Flutter SDK is required.' }
New-Item -ItemType Directory -Path $harness -Force | Out-Null
@'
name: memex
publish_to: none
environment:
  sdk: '>=3.6.0 <4.0.0'
dependencies:
  crypto: ^3.0.7
  flutter:
    sdk: flutter
  flutter_secure_storage: 10.3.1
dev_dependencies:
  flutter_test:
    sdk: flutter
  flutter_lints: ^3.0.0
'@ | Set-Content -LiteralPath (Join-Path $harness 'pubspec.yaml') -Encoding utf8
$relativeFiles = @(
    'analysis_options.yaml',
    'lib/data/services/activity/mda2_android/android_activity_normalizer.dart',
    'lib/data/services/activity/mda2_android/file_activity_outbox_store.dart',
    'lib/data/services/activity/mda2_android/activity_integrity_key_repository.dart',
    'lib/data/services/activity/mda2_android/activity_outbox_process_lease.dart',
    'lib/data/services/activity/mda2_android/android_activity_signal_platform.dart',
    'lib/data/services/activity/mda2_android/android_activity_collector.dart',
    'lib/ui/a3d_device_gate/a3d_device_gate_controller.dart',
    'lib/ui/a3d_device_gate/a3d_device_gate_screen.dart',
    'lib/a3d_device_gate_main.dart'
)
# Tests are enumerated before execution and bound byte for byte afterwards.
$testDir = 'test/data/services/activity/mda2_android'
$testFiles = @(Get-ChildItem -LiteralPath (Join-Path $repo $testDir) -File -Filter '*_test.dart' | Sort-Object Name | ForEach-Object { $testDir + '/' + $_.Name })
if (!$testFiles.Count) { throw 'No R3 tests found.' }
$relativeFiles += $testFiles
# Refuse a stale mirror rather than silently execute tests removed from this candidate.
$mirrorTestDir = Join-Path $harness $testDir
if (Test-Path -LiteralPath $mirrorTestDir) {
    foreach ($file in Get-ChildItem -LiteralPath $mirrorTestDir -File -Filter '*_test.dart') {
        if (($testDir + '/' + $file.Name) -notin $testFiles) { throw 'Stale test mirror; use a new owned harness.' }
    }
}
foreach ($relative in $relativeFiles) {
    $destination = Join-Path $harness $relative
    New-Item -ItemType Directory -Path (Split-Path -Parent $destination) -Force | Out-Null
    Copy-Item -LiteralPath (Join-Path $repo $relative) -Destination $destination -Force
}
$priorFlutterRoot = $env:FLUTTER_ROOT
$priorCI = $env:CI
$priorLocalAppData = $env:LOCALAPPDATA
$priorTemp = $env:TEMP
$priorTmp = $env:TMP
try {
    $env:FLUTTER_ROOT = $FlutterSdk
    $env:CI = 'true'
    $env:TEMP = Join-Path $harness 'temp'
    $env:TMP = $env:TEMP
    New-Item -ItemType Directory -Path $env:TEMP -Force | Out-Null
    Push-Location $harness
    try {
        if (!$NoResolve) {
            & $dartExe $flutterTool pub get --offline
            if ($LASTEXITCODE -ne 0) { throw 'Offline resolution failed; verify any generated package_config before a separate -NoResolve run.' }
        }
        if (!(Test-Path -LiteralPath '.dart_tool/package_config.json')) { throw 'An offline-resolved package_config is required.' }
        & $dartExe $flutterTool test --no-pub @testFiles --reporter expanded
        if ($LASTEXITCODE -ne 0) { throw 'R3 combined Flutter tests failed.' }
        $env:LOCALAPPDATA = Join-Path $harness 'local-app-data'
        New-Item -ItemType Directory -Path $env:LOCALAPPDATA -Force | Out-Null
        & $dartExe analyze --fatal-infos lib test
        if ($LASTEXITCODE -ne 0) { throw 'R3 combined source/test analysis failed.' }
    } finally { Pop-Location }
    foreach ($relative in $relativeFiles) {
        $original = (Get-FileHash -LiteralPath (Join-Path $repo $relative) -Algorithm SHA256).Hash
        $mirror = (Get-FileHash -LiteralPath (Join-Path $harness $relative) -Algorithm SHA256).Hash
        if ($original -ne $mirror) { throw "R3 mirror drift: $relative" }
    }
    Write-Output "R3 combined mirror verified byte-for-byte: files=$($relativeFiles.Count) test_files=$($testFiles.Count). No Android/device claim."
} finally {
    $env:FLUTTER_ROOT = $priorFlutterRoot
    $env:CI = $priorCI
    $env:LOCALAPPDATA = $priorLocalAppData
    $env:TEMP = $priorTemp
    $env:TMP = $priorTmp
}
