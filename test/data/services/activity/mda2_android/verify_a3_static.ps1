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
    if ($base -eq $candidate) { throw 'BaseCommit and CandidateCommit must differ.' }
    & git merge-base --is-ancestor $base $candidate
    if ($LASTEXITCODE -ne 0) { throw 'BaseCommit must be an ancestor of CandidateCommit.' }

    $changed = @(& git diff --name-only $base $candidate)
    if ($LASTEXITCODE -ne 0) { throw 'Unable to enumerate Base..Candidate paths.' }
    $changed = @($changed | Where-Object { $_ } | Sort-Object -Unique)
    if ($changed.Count -eq 0) { throw 'Base..Candidate contains no changed paths.' }
    $allowed = @(
        '^android/app/src/main/kotlin/com/memexlab/memex/activity/',
        '^android/app/src/main/kotlin/com/memexlab/memex/channels/ActivitySignalChannelHandler\.kt$',
        '^android/app/src/main/kotlin/com/memexlab/memex/channels/ChannelRegistrar\.kt$',
        '^android/app/src/test/kotlin/com/memexlab/memex/activity/',
        '^android/app/src/main/AndroidManifest\.xml$',
        '^lib/data/services/activity/mda2_android/',
        '^lib/a3d_device_gate_main\.dart$',
        '^lib/ui/a3d_device_gate/',
        '^test/data/services/activity/mda2_android/',
        '^docs/development/activity/mda2/android/a3/',
        '^docs/development/activity/mda2/android/a3f/',
        '^docs/development/activity/mda2/android/a3f_r1/HANDOFF\.md$'
    )
    $outside = @($changed | Where-Object {
        $path = $_
        -not ($allowed | Where-Object { $path -match $_ })
    })
    if ($outside.Count -gt 0) { throw "Candidate path outside ownership: $($outside -join ', ')" }

    $protected = @(
        'android/app/src/main/kotlin/com/memexlab/memex/channels/PhoneUsageChannelHandler.kt',
        'android/app/src/main/kotlin/com/weshop/memex/MainActivity.kt',
        'android/app/build.gradle.kts',
        'pubspec.yaml',
        'tools/i_core',
        'lib/db'
    )
    & git diff --quiet $base $candidate -- $protected
    if ($LASTEXITCODE -eq 1) { throw 'A protected manifest, channel, dependency, Core, or DB path changed.' }
    if ($LASTEXITCODE -gt 1) { throw 'Unable to compare protected paths.' }

    $manifest = 'android/app/src/main/AndroidManifest.xml'
    $candidateManifest = (& git rev-parse "$candidate`:$manifest").Trim()
    if ($LASTEXITCODE -ne 0) { throw 'Unable to resolve the candidate manifest.' }

    $dartSources = @(
        'lib/data/services/activity/mda2_android/activity_integrity_key_repository.dart',
        'lib/data/services/activity/mda2_android/android_activity_signal_platform.dart',
        'lib/data/services/activity/mda2_android/android_activity_collector.dart'
    )
    $kotlinSources = @(
        'android/app/src/main/kotlin/com/memexlab/memex/activity/ActivitySignalPolicy.kt',
        'android/app/src/main/kotlin/com/memexlab/memex/activity/AndroidActivitySignalCollector.kt',
        'android/app/src/main/kotlin/com/memexlab/memex/channels/ActivitySignalChannelHandler.kt'
    )
    $forbidden = @(
        @{ Pattern = 'package:(dio|http|web_socket_channel)'; Files = $dartSources; Code = 'network_client_added' },
        @{ Pattern = 'WorkManager|AlarmManager|BOOT_COMPLETED'; Files = $kotlinSources; Code = 'scheduler_or_boot_receiver_added' },
        @{ Pattern = 'packageName|appName|rawUsageEvents'; Files = $dartSources; Code = 'private_native_field_entered_dart' },
        @{ Pattern = 'PhoneUsageChannelHandler\.'; Files = @('android/app/src/main/kotlin/com/memexlab/memex/channels/ActivitySignalChannelHandler.kt'); Code = 'phone_usage_channel_reused' }
    )
    foreach ($rule in $forbidden) {
        foreach ($file in $rule.Files) {
            $content = @(& git show "$candidate`:$file")
            if ($LASTEXITCODE -ne 0) { throw "Unable to inspect candidate path: $file" }
            if ([regex]::IsMatch(($content -join "`n"), $rule.Pattern)) {
                throw $rule.Code
            }
        }
    }
    $collectorSource = (@(& git show "$candidate`:android/app/src/main/kotlin/com/memexlab/memex/activity/AndroidActivitySignalCollector.kt") -join "`n")
    if ($LASTEXITCODE -ne 0) { throw 'Unable to inspect AndroidActivitySignalCollector.kt.' }
    if ($collectorSource -notmatch 'Context\.RECEIVER_EXPORTED' -or
        $collectorSource -match 'Context\.RECEIVER_NOT_EXPORTED' -or
        $collectorSource -notmatch 'Intent\.ACTION_SCREEN_ON' -or
        $collectorSource -notmatch 'Intent\.ACTION_SCREEN_OFF' -or
        $collectorSource -notmatch 'Intent\.ACTION_USER_PRESENT') {
        throw 'Protected system screen receiver export contract is missing.'
    }
    Write-Output "STATIC_A3_OK base=$base candidate=$candidate changed_paths=$($changed.Count) manifest_blob=$candidateManifest"
} finally {
    Pop-Location
}
