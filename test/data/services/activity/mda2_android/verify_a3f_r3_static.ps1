param([Parameter(Mandatory = $true)][string]$BaseCommit)
$ErrorActionPreference = 'Stop'
$repo = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../../../..'))
Push-Location $repo
try {
    $base = (& git rev-parse ($BaseCommit + '^{commit}')).Trim()
    if ($LASTEXITCODE -ne 0) { throw 'Invalid base.' }
    $head = (& git rev-parse HEAD).Trim()
    if ($head -ne $base) { throw 'This uncommitted R3 candidate must have the exact approved base.' }
    $changed = @(& git diff --name-only $base)
    if ($LASTEXITCODE -ne 0) { throw 'Unable to enumerate tracked diff.' }
    $changed += @(& git ls-files --others --exclude-standard)
    if ($LASTEXITCODE -ne 0) { throw 'Unable to enumerate untracked candidate.' }
    $changed = @($changed | Where-Object { $_ } | Sort-Object -Unique)
    $allowed = @(
        '^android/app/src/main/kotlin/com/memexlab/memex/activity/(ActivityObservationForegroundService|ActivityStartupConfirmation|ActivityObservationControlState|AndroidActivitySignalCollector)\.kt$',
        '^android/app/src/main/kotlin/com/memexlab/memex/channels/ActivitySignalChannelHandler\.kt$',
        '^android/app/src/test/kotlin/com/memexlab/memex/activity/(ActivityObservationControlStateTest|ActivityStartupConfirmationTest|ActivityStartupServiceIntegrationTest)\.kt$',
        '^lib/data/services/activity/mda2_android/(android_activity_collector|android_activity_signal_platform|activity_outbox_process_lease|file_activity_outbox_store)\.dart$',
        '^lib/ui/a3d_device_gate/a3d_device_gate_(controller|screen)\.dart$',
        '^test/data/services/activity/mda2_android/(android_activity_collector|android_activity_observation_platform|android_activity_observation_collector|file_activity_outbox_store|a3d_device_gate|a3f_r3_owner_release|a3f_r3_ui)_test\.dart$',
        '^test/data/services/activity/mda2_android/verify_(a3_android|a3_flutter|a3d_flutter|flutter_synthetic|a3f_r3_flutter|a3f_r3_static)\.ps1$',
        '^docs/development/activity/mda2/android/a3f_r3/(N_HANDOFF|D_HANDOFF|U_HANDOFF|V_REVIEW|W0_CONTROL_CONTRACT|W0_ACCEPTANCE_AND_DEVICE_GATE|CANDIDATE_MANIFEST|CANDIDATE_MANIFEST_PATHFIX|CANDIDATE_MANIFEST_UI_ACTION|DEVICE_GATE|PATH_CANONICALIZATION_FIX)\.(md|json)$',
        '^docs/development/goals/GOAL-20260927-a3f-r3-activity-stop-recovery\.md$'
    )
    $outside = @($changed | Where-Object { $path = $_; -not ($allowed | Where-Object { $path -match $_ }) })
    if (!$changed.Count -or $outside.Count) { throw "R3 scope violation: $($outside -join ', ')" }
    $protected = @('android/app/src/main/AndroidManifest.xml','android/app/build.gradle.kts','android/settings.gradle.kts','pubspec.yaml','pubspec.lock','lib/main.dart','lib/a3d_device_gate_main.dart','lib/config','lib/routing','lib/ui/settings','lib/db','tools/i_core','DEVLOG.md','docs/development/I_PROJECT_STATE.md','docs/companion-first/PRODUCT_ROADMAP.md','test/data/services/activity/mda2_android/fixtures')
    & git diff --quiet $base -- $protected
    if ($LASTEXITCODE -ne 0) { throw 'Protected source/dependency/wire/global-state diff.' }
    $native = 'android/app/src/main/kotlin/com/memexlab/memex/activity/'
    $service = Get-Content -Raw -LiteralPath ($native + 'ActivityObservationForegroundService.kt')
    $startup = Get-Content -Raw -LiteralPath ($native + 'ActivityStartupConfirmation.kt')
    $channel = Get-Content -Raw -LiteralPath 'android/app/src/main/kotlin/com/memexlab/memex/channels/ActivitySignalChannelHandler.kt'
    if ($service -notmatch 'SystemClock.elapsedRealtime' -or $service -notmatch 'FOREGROUND_SERVICE_IMMEDIATE' -or $service -notmatch 'scheduleStartupConfirmation' -or $service -notmatch 'startup.isActive\(requestToken, service.serviceInstanceId\)') { throw 'R2 startup/dispatch markers missing.' }
    if ($startup -notmatch 'attempt.owner != owner' -or $startup -notmatch 'attempt.answered' -or $channel -notmatch 'startupReplies.invalidate\(detach = true\)') { throw 'R2 instance/callback markers missing.' }
    if ($service -match 'Thread.sleep|context.stopService|BleHeartRateService|CompanionForegroundTask|CheckinService|BOOT_COMPLETED|START_STICKY|WorkManager|AlarmManager') { throw 'Forbidden lifecycle coupling.' }
    if ($channel -match '"packageName"|"appName"|"rawUsageEvents"|java.net|okhttp') { throw 'Forbidden private/transport bridge field.' }
    $entry = Get-Content -Raw -LiteralPath 'lib/a3d_device_gate_main.dart'
    if ($entry -notmatch '!kDebugMode' -or $entry -notmatch "appFlavor != 'hereIAmV3'") { throw 'Diagnostic entry isolation missing.' }
    $receiver = Get-Content -Raw -LiteralPath ($native + 'AndroidActivitySignalCollector.kt')
    if ($receiver -match 'clockMs\(\)|reduceScreenAction\(' -or $receiver -notmatch 'onQueryHint') { throw 'Occurrence timestamp contract changed.' }
    & git diff --check
    if ($LASTEXITCODE -ne 0) { throw 'Candidate diff whitespace check failed.' }
    Write-Output "STATIC_A3F_R3_OK base=$base changed_paths=$($changed.Count) protected_diff=0. Scope/source markers only; not behavioral or device evidence."
} finally { Pop-Location }
