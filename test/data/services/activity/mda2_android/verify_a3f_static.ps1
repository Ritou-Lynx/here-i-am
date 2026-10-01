param(
    [Parameter(Mandatory = $true)][string]$BaseCommit,
    [string]$CandidateCommit = 'HEAD'
)
$ErrorActionPreference = 'Stop'
$repo = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../../../..'))
Push-Location $repo
try {
    $base = (& git rev-parse "$BaseCommit`^{commit}").Trim()
    if ($LASTEXITCODE -ne 0 -or !$base) { throw 'BaseCommit does not resolve to a commit.' }
    $candidate = (& git rev-parse "$CandidateCommit`^{commit}").Trim()
    if ($LASTEXITCODE -ne 0 -or !$candidate) { throw 'CandidateCommit does not resolve to a commit.' }
    & git merge-base --is-ancestor $base $candidate
    if ($LASTEXITCODE -ne 0) { throw 'BaseCommit must be an ancestor of CandidateCommit.' }

    $changed = @(& git diff --name-only $base $candidate | Where-Object { $_ } | Sort-Object -Unique)
    $allowed = @(
        '^android/app/src/main/AndroidManifest\.xml$',
        '^android/app/src/main/kotlin/com/memexlab/memex/activity/(ActivityDeliveryLedger|ActivityObservationForegroundService|ActivityPermissionEpochStore|ActivityUsageEventSource|ActivitySignalPolicy|AndroidActivitySignalCollector)\.kt$',
        '^android/app/src/main/kotlin/com/memexlab/memex/channels/ActivitySignalChannelHandler\.kt$',
        '^android/app/src/test/kotlin/com/memexlab/memex/activity/',
        '^lib/data/services/activity/mda2_android/',
        '^lib/ui/a3d_device_gate/',
        '^lib/a3d_device_gate_main\.dart$',
        '^test/data/services/activity/mda2_android/',
        '^docs/development/activity/mda2/android/a3f/',
        '^docs/development/activity/mda2/android/a3f_r1/HANDOFF\.md$'
    )
    $outside = @($changed | Where-Object {
        $path = $_
        -not ($allowed | Where-Object { $path -match $_ })
    })
    if ($changed.Count -eq 0 -or $outside.Count -gt 0) {
        throw "A3-F candidate path outside ownership: $($outside -join ', ')"
    }

    $forbiddenShared = @(
        'lib/main.dart', 'lib/config', 'lib/routing', 'lib/ui/settings',
        'tools/i_core', 'lib/db', 'DEVLOG.md',
        'docs/development/I_PROJECT_STATE.md',
        'docs/companion-first/PRODUCT_ROADMAP.md'
    )
    & git diff --quiet $base $candidate -- $forbiddenShared
    if ($LASTEXITCODE -eq 1) { throw 'A normal app, Core, DB, or global state path changed.' }
    if ($LASTEXITCODE -gt 1) { throw 'Unable to compare protected paths.' }

    $manifest = (@(& git show "$candidate`:android/app/src/main/AndroidManifest.xml") -join "`n")
    if ($manifest -notmatch 'android\.permission\.FOREGROUND_SERVICE_SPECIAL_USE' -or
        $manifest -notmatch '\.activity\.ActivityObservationForegroundService' -or
        $manifest -notmatch 'android:foregroundServiceType="specialUse"' -or
        $manifest -notmatch 'android\.app\.PROPERTY_SPECIAL_USE_FGS_SUBTYPE') {
        throw 'Activity FGS specialUse manifest contract is incomplete.'
    }

    $service = (@(& git show "$candidate`:android/app/src/main/kotlin/com/memexlab/memex/activity/ActivityObservationForegroundService.kt") -join "`n")
    foreach ($pattern in @(
        'BleHeartRateService',
        'CompanionForegroundTask',
        'CheckinService',
        'BOOT_COMPLETED',
        'START_STICKY',
        'WorkManager',
        'AlarmManager'
    )) {
        if ($service -match $pattern) { throw "Activity FGS isolation violation: $pattern" }
    }
    if ($service -notmatch 'START_NOT_STICKY' -or
        $service -notmatch 'notification_not_visible' -or
        $service -notmatch 'foreground_start_not_allowed' -or
        $service -notmatch 'ActivityPermissionEpochAuthority') {
        throw 'Activity FGS fail-closed lifecycle markers are incomplete.'
    }

    $receiver = (@(& git show "$candidate`:android/app/src/main/kotlin/com/memexlab/memex/activity/AndroidActivitySignalCollector.kt") -join "`n")
    if ($receiver -match 'clockMs\(\)' -or $receiver -match 'reduceScreenAction\(' -or
        $receiver -notmatch 'onQueryHint') {
        throw 'Dynamic broadcast receiver still creates occurrence-time signals.'
    }

    $normalReferences = @(& git grep -n 'ActivityObservationForegroundService\|mda2_activity_authority' $candidate -- 'lib/main.dart' 'lib/config/**' 'lib/routing/**' 'lib/ui/settings/**')
    if ($LASTEXITCODE -gt 1) { throw 'Unable to inspect normal app references.' }
    if ($normalReferences.Count -gt 0) { throw 'Normal app entry references the A3-F diagnostic source.' }

    $outbound = @(
        'android/app/src/main/kotlin/com/memexlab/memex/activity/ActivitySignalPolicy.kt',
        'android/app/src/main/kotlin/com/memexlab/memex/activity/ActivityObservationForegroundService.kt',
        'android/app/src/main/kotlin/com/memexlab/memex/channels/ActivitySignalChannelHandler.kt',
        'lib/data/services/activity/mda2_android/android_activity_signal_platform.dart'
    )
    $joined = @($outbound | ForEach-Object { @(& git show "$candidate`:$_") }) -join "`n"
    foreach ($pattern in @(
        '"packageName"\s+to',
        '"packageId"\s+to',
        '"appName"\s+to',
        '"rawUsageEvents"\s+to',
        'AccessibilityNodeInfo'
    )) {
        if ($joined -match $pattern) { throw "Private/raw outbound field found: $pattern" }
    }
    Write-Output "STATIC_A3F_OK base=$base candidate=$candidate changed_paths=$($changed.Count)"
} finally {
    Pop-Location
}
