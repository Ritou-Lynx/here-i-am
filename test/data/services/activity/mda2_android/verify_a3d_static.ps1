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
    $allowed = @(
        '^lib/a3d_device_gate_main\.dart$',
        '^lib/ui/a3d_device_gate/',
        '^lib/data/services/activity/mda2_android/',
        '^test/data/services/activity/mda2_android/',
        '^android/app/src/main/AndroidManifest\.xml$',
        '^android/app/src/main/kotlin/com/memexlab/memex/activity/',
        '^android/app/src/main/kotlin/com/memexlab/memex/channels/ActivitySignalChannelHandler\.kt$',
        '^android/app/src/test/kotlin/com/memexlab/memex/activity/',
        '^docs/development/activity/mda2/android/a3d/',
        '^docs/development/activity/mda2/android/a3f/',
        '^docs/development/activity/mda2/android/a3f_r1/HANDOFF\.md$'
    )
    $outside = @($changed | Where-Object {
        $path = $_
        -not ($allowed | Where-Object { $path -match $_ })
    })
    if ($changed.Count -eq 0 -or $outside.Count -gt 0) {
        throw "A3-D candidate path outside ownership: $($outside -join ', ')"
    }

    $protected = @(
        'lib/main.dart',
        'lib/config',
        'lib/routing',
        'lib/ui/settings',
        'android/app/build.gradle.kts',
        'pubspec.yaml',
        'tools/i_core',
        'lib/db',
        'DEVLOG.md',
        'docs/development/I_PROJECT_STATE.md',
        'docs/companion-first/PRODUCT_ROADMAP.md'
    )
    & git diff --quiet $base $candidate -- $protected
    if ($LASTEXITCODE -eq 1) { throw 'A protected product, A3-I, Android, Core, DB, or state path changed.' }
    if ($LASTEXITCODE -gt 1) { throw 'Unable to compare protected paths.' }

    $normalReferences = @(& git grep -n 'a3d_device_gate' $candidate -- 'lib/*.dart' 'lib/**/*.dart')
    if ($LASTEXITCODE -gt 1) { throw 'Unable to inspect normal Dart references.' }
    $outsideReferences = @($normalReferences | Where-Object {
        $_ -notmatch ':lib/a3d_device_gate_main\.dart:' -and
        $_ -notmatch ':lib/ui/a3d_device_gate/'
    })
    if ($outsideReferences.Count -gt 0) { throw 'Normal product Dart code references the A3-D entrypoint.' }

    $entry = (@(& git show "$candidate`:lib/a3d_device_gate_main.dart") -join "`n")
    if ($LASTEXITCODE -ne 0) { throw 'Unable to inspect the A3-D entrypoint.' }
    if ($entry -notmatch '!kDebugMode' -or
        $entry -notmatch "appFlavor != 'hereIAmV3'" -or
        $entry -match 'import\s+.+main\.dart') {
        throw 'A3-D entrypoint debug/flavor isolation is missing.'
    }

    $sources = @(
        'lib/a3d_device_gate_main.dart',
        'lib/ui/a3d_device_gate/a3d_device_gate_controller.dart',
        'lib/ui/a3d_device_gate/a3d_device_gate_screen.dart'
    )
    $content = @()
    foreach ($file in $sources) {
        $content += @(& git show "$candidate`:$file")
        if ($LASTEXITCODE -ne 0) { throw "Unable to inspect candidate path: $file" }
    }
    $joined = $content -join "`n"
    $forbidden = @(
        'package:(dio|http|web_socket_channel)',
        '\bTimer\s*\(',
        'WorkManager|AlarmManager|startForeground|BOOT_COMPLETED',
        'MemexRouter|AppDatabase|ChannelRegistrar|PhoneUsageChannelHandler',
        'BleHeartRate|checkin|CompanionForeground'
    )
    foreach ($pattern in $forbidden) {
        if ($joined -match $pattern) { throw "A3-D forbidden dependency: $pattern" }
    }
    if ($joined -notmatch "synthetic_local_diagnostic" -or
        $joined -notmatch "diagnostic_not_started") {
        throw 'A3-D local diagnostic authority or default state marker is missing.'
    }
    Write-Output "STATIC_A3D_OK base=$base candidate=$candidate changed_paths=$($changed.Count)"
} finally {
    Pop-Location
}
