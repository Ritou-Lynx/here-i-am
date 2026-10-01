param([Parameter(Mandatory = $true)][string]$FlutterSdk, [switch]$NoResolve)
$ErrorActionPreference = 'Stop'
$repo = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../../../..'))
$harness = Join-Path $PSScriptRoot '.verification_a3'
$dartExe = Join-Path $FlutterSdk 'bin/cache/dart-sdk/bin/dart.exe'
$flutterTool = Join-Path $FlutterSdk 'bin/cache/flutter_tools.snapshot'
if (!(Test-Path -LiteralPath $dartExe) -or !(Test-Path -LiteralPath $flutterTool)) {
    throw 'An already initialized Flutter SDK is required; this script does not download an SDK.'
}
New-Item -ItemType Directory -Path $harness -Force | Out-Null
@'
name: mda2_android_a3_verification
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
Copy-Item -LiteralPath (Join-Path $repo 'analysis_options.yaml') -Destination $harness
$relativeFiles = @(
    'lib/data/services/activity/mda2_android/android_activity_normalizer.dart',
    'lib/data/services/activity/mda2_android/file_activity_outbox_store.dart',
    'lib/data/services/activity/mda2_android/activity_outbox_process_lease.dart',
    'lib/data/services/activity/mda2_android/activity_integrity_key_repository.dart',
    'lib/data/services/activity/mda2_android/android_activity_signal_platform.dart',
    'lib/data/services/activity/mda2_android/android_activity_collector.dart',
    'test/data/services/activity/mda2_android/android_activity_collector_test.dart'
)
foreach ($relative in $relativeFiles) {
    $destination = Join-Path $harness $relative
    New-Item -ItemType Directory -Path (Split-Path -Parent $destination) -Force | Out-Null
    Copy-Item -LiteralPath (Join-Path $repo $relative) -Destination $destination
}
$priorFlutterRoot = $env:FLUTTER_ROOT
$priorCI = $env:CI
$priorLocalAppData = $env:LOCALAPPDATA
try {
    $env:FLUTTER_ROOT = $FlutterSdk
    $env:CI = 'true'
    Push-Location $harness
    try {
        if (!$NoResolve) {
            & $dartExe $flutterTool pub get --offline
            if ($LASTEXITCODE -ne 0) { throw 'Offline A3 dependency resolution failed.' }
        }
        if (!(Test-Path -LiteralPath '.dart_tool/package_config.json')) {
            throw 'An offline-resolved A3 package_config is required.'
        }
        & $dartExe $flutterTool test --no-pub test/data/services/activity/mda2_android/android_activity_collector_test.dart --reporter expanded
        if ($LASTEXITCODE -ne 0) { throw 'A3 Flutter tests failed.' }
        $env:LOCALAPPDATA = Join-Path $harness 'local-app-data'
        New-Item -ItemType Directory -Path $env:LOCALAPPDATA -Force | Out-Null
        & $dartExe analyze --fatal-infos lib/data/services/activity/mda2_android
        if ($LASTEXITCODE -ne 0) { throw 'A3 source analysis failed.' }
        & $dartExe analyze --fatal-infos test/data/services/activity/mda2_android/android_activity_collector_test.dart
        if ($LASTEXITCODE -ne 0) { throw 'A3 test analysis failed.' }
    } finally { Pop-Location }
    foreach ($relative in $relativeFiles) {
        $original = (Get-FileHash -LiteralPath (Join-Path $repo $relative) -Algorithm SHA256).Hash
        $mirror = (Get-FileHash -LiteralPath (Join-Path $harness $relative) -Algorithm SHA256).Hash
        if ($original -ne $mirror) { throw "Test mirror drift: $relative" }
    }
    Write-Output 'Verified A3 mirror matches all tested Dart files byte for byte.'
} finally {
    $env:FLUTTER_ROOT = $priorFlutterRoot
    $env:CI = $priorCI
    $env:LOCALAPPDATA = $priorLocalAppData
}
