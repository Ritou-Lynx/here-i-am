param([Parameter(Mandatory = $true)][string]$EvidenceDirectory)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2
# NEVER run this fixture locally. This guard precedes every system mutation.
if ($env:GITHUB_ACTIONS -ne 'true' -or $env:RUNNER_ENVIRONMENT -ne 'github-hosted' -or $env:RUNNER_OS -ne 'Windows') {
    throw 'This fixture may only execute in a GitHub-hosted Windows job.'
}

$EvidenceDirectory = [IO.Path]::GetFullPath($EvidenceDirectory)
if (Test-Path -LiteralPath $EvidenceDirectory) { throw 'A fresh evidence directory is required.' }
$null = New-Item -ItemType Directory -Path $EvidenceDirectory
$utf8 = New-Object -TypeName Text.UTF8Encoding -ArgumentList $false
function Write-Json([string]$Path, $Value) {
    [IO.File]::WriteAllText($Path, ($Value | ConvertTo-Json -Depth 30), $utf8)
}
function Record([string]$Event, $Detail) {
    $line = [ordered]@{ event = $Event; ticks = [Diagnostics.Stopwatch]::GetTimestamp().ToString();
        utc = [DateTime]::UtcNow.ToString('o'); detail = $Detail }
    [IO.File]::AppendAllText((Join-Path $EvidenceDirectory 'collector-events.jsonl'),
        (($line | ConvertTo-Json -Depth 12 -Compress) + "`n"), $utf8)
}
$parseIssues = New-Object 'System.Collections.Generic.List[string]'
function Read-Lines([string]$Path) {
    if (Test-Path -LiteralPath $Path) {
        foreach ($line in [IO.File]::ReadAllLines($Path)) {
            if (-not [string]::IsNullOrWhiteSpace($line)) {
                try { $line | ConvertFrom-Json } catch { $parseIssues.Add([IO.Path]::GetFileName($Path)) }
            }
        }
    }
}

function Initialize-NativeInterop {
Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.Runtime.InteropServices;
public static class LogoffNative {
    [StructLayout(LayoutKind.Sequential)] struct Session { public int id; public IntPtr name; public int state; }
    [DllImport("wtsapi32.dll", EntryPoint="WTSEnumerateSessionsW", SetLastError=true)] static extern bool Enumerate(IntPtr server,int reserved,int version,out IntPtr data,out int count);
    [DllImport("wtsapi32.dll", EntryPoint="WTSQuerySessionInformationW", SetLastError=true)] static extern bool Query(IntPtr server,int id,int kind,out IntPtr data,out int size);
    [DllImport("wtsapi32.dll")] static extern void WTSFreeMemory(IntPtr data);
    public static int[] UserSessions(string username) {
        IntPtr data; int count;
        if(!Enumerate(IntPtr.Zero,0,1,out data,out count)) throw new Win32Exception(Marshal.GetLastWin32Error());
        var ids=new List<int>();
        try {
            int size=Marshal.SizeOf(typeof(Session));
            for(int n=0;n<count;n++) {
                var session=(Session)Marshal.PtrToStructure(IntPtr.Add(data,n*size),typeof(Session));
                IntPtr text; int length;
                if(Query(IntPtr.Zero,session.id,5,out text,out length)) {
                    try { if(String.Equals(Marshal.PtrToStringUni(text),username,StringComparison.OrdinalIgnoreCase)) ids.Add(session.id); }
                    finally { WTSFreeMemory(text); }
                }
            }
        } finally { WTSFreeMemory(data); }
        return ids.ToArray();
    }
    [DllImport("kernel32.dll", SetLastError=true)] static extern IntPtr OpenProcess(uint rights,bool inherit,int pid);
    [DllImport("kernel32.dll", SetLastError=true)] static extern bool ProcessIdToSessionId(uint pid,out uint session);
    [DllImport("kernel32.dll")] static extern uint WaitForSingleObject(IntPtr handle,uint milliseconds);
    [DllImport("kernel32.dll", SetLastError=true)] static extern bool GetExitCodeProcess(IntPtr handle,out uint code);
    [DllImport("kernel32.dll", SetLastError=true)] static extern bool GetProcessTimes(IntPtr handle,out long created,out long exited,out long kernel,out long user);
    [DllImport("kernel32.dll")] static extern bool CloseHandle(IntPtr handle);
    public sealed class Watch : IDisposable {
        IntPtr handle;
        public readonly int Pid;
        public Watch(int pid,int sessionId) {
            uint session;
            if(!ProcessIdToSessionId((uint)pid,out session) || session!=(uint)sessionId) throw new InvalidOperationException("probe_process_session_mismatch");
            handle=OpenProcess(0x00101000,false,pid); // SYNCHRONIZE | QUERY_LIMITED_INFORMATION
            if(handle==IntPtr.Zero) throw new Win32Exception(Marshal.GetLastWin32Error());
            Pid=pid;
        }
        public bool Exited { get { return WaitForSingleObject(handle,0)==0; } }
        public uint ExitCode { get { uint code; if(!Exited || !GetExitCodeProcess(handle,out code)) throw new InvalidOperationException("exit_code_unavailable"); return code; } }
        public long ExitFileTime { get { long c,e,k,u; if(!Exited || !GetProcessTimes(handle,out c,out e,out k,out u)) throw new InvalidOperationException("exit_time_unavailable"); return e; } }
        public void Dispose() { if(handle!=IntPtr.Zero) { CloseHandle(handle); handle=IntPtr.Zero; } }
    }
}
'@
}

$runnerSessionId = [Diagnostics.Process]::GetCurrentProcess().SessionId
$stage = 'native_interop'
$established = $false
$logoffAttempted = $false
$sessionGone = $false
$sessionId = $null
$failure = $null
$testUser = 'hiaL' + [Guid]::NewGuid().ToString('N').Substring(0,12)
$account = "$env:COMPUTERNAME\$testUser"
$taskNames = @{}
$ready = @{}
$watches = @{}
$taskResults = @{}
$registryChanges = New-Object 'System.Collections.Generic.List[object]'
$firewallName = 'HIA-logoff-' + [Guid]::NewGuid().ToString('N')
$controlDirectory = Join-Path $env:RUNNER_TEMP ('hia-logoff-control-' + [Guid]::NewGuid().ToString('N'))
$client = $null
$logoffClient = $null
$userCreated = $false
$credentialCreated = $false
$firewallCreated = $false
function Set-JobRegistry([string]$Path, [string]$Name, $Value, [string]$Kind) {
    $key = Get-Item -LiteralPath $Path -ErrorAction SilentlyContinue
    $existed = $null -ne $key -and $key.GetValueNames() -contains $Name
    $oldValue = $null; $oldKind = $null
    if ($existed) { $oldValue = $key.GetValue($Name); $oldKind = $key.GetValueKind($Name).ToString() }
    $registryChanges.Add(@{ path = $Path; name = $Name; existed = $existed; oldValue = $oldValue; oldKind = $oldKind })
    $null = New-Item -Path $Path -Force
    $null = New-ItemProperty -Path $Path -Name $Name -Value $Value -PropertyType $Kind -Force
}
function Test-Session([int]$Id) {
    if ($Id -eq $runnerSessionId -or $Id -le 0) { throw 'runner_or_system_session_rejected' }
    $ids = @([LogoffNative]::UserSessions($testUser))
    return $ids -contains $Id
}
function Snapshot($Watch) {
    if ($null -eq $Watch) { return $null }
    $result = [ordered]@{ pid = $Watch.Pid; exited = $Watch.Exited; exitCode = $null; exitFiletime = $null; exitUtc = $null }
    if ($result.exited) {
        $result.exitCode = [long]$Watch.ExitCode
        $result.exitFiletime = $Watch.ExitFileTime.ToString()
        $result.exitUtc = [DateTime]::FromFileTimeUtc($Watch.ExitFileTime).ToString('o')
    }
    return $result
}

try {
    Initialize-NativeInterop
    $stage = 'diagnostics'
    Write-Output ('runner session id: ' + $runnerSessionId)
    $diagnostics = [ordered]@{
        whoami = @(& whoami.exe 2>&1 | ForEach-Object { "$_" })
        runnerSessionId = $runnerSessionId
        querySession = @(& query.exe session 2>&1 | ForEach-Object { "$_" })
        rdpService = (Get-Service TermService).Status.ToString()
    }
    Write-Json (Join-Path $EvidenceDirectory 'diagnostics.json') $diagnostics
    Write-Output ($diagnostics | ConvertTo-Json -Depth 5)
    Record 'diagnostics' $diagnostics

    $stage = 'create_test_user'
    $random = New-Object byte[] 32
    $rng = [Security.Cryptography.RandomNumberGenerator]::Create()
    try { $rng.GetBytes($random) } finally { $rng.Dispose() }
    $testPassword = 'aA9!' + [Convert]::ToBase64String($random)
    Write-Output "::add-mask::$testPassword"
    $env:HIA_LOGOFF_PASSWORD = $testPassword
    $secure = ConvertTo-SecureString $testPassword -AsPlainText -Force
    $user = New-LocalUser -Name $testUser -Password $secure -AccountNeverExpires -PasswordNeverExpires -Description 'Disposable hosted logoff fixture'
    $userCreated = $true
    # SID avoids localized Remote Desktop Users group names. This is a standard user.
    foreach ($groupSid in @('S-1-5-32-545', 'S-1-5-32-555')) {
        $membership = @(Get-LocalGroupMember -SID $groupSid | Where-Object { $_.SID.Value -eq $user.SID.Value })
        if ($membership.Count -eq 0) { Add-LocalGroupMember -SID $groupSid -Member $user }
    }
    Record 'test_user_created' @{ username = $testUser; sid = $user.SID.Value; administrator = $false }

    $stage = 'enable_loopback_rdp'
    Set-JobRegistry 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server' 'fDenyTSConnections' 0 'DWord'
    Set-JobRegistry 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp' 'UserAuthentication' 0 'DWord'
    # Allow cached credentials only for this loopback target, including NTLM fallback.
    $delegation = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\CredentialsDelegation'
    Set-JobRegistry $delegation 'AllowSavedCredentialsWhenNTLMOnly' 1 'DWord'
    Set-JobRegistry ($delegation + '\AllowSavedCredentialsWhenNTLMOnly') '9999' 'TERMSRV/127.0.0.2' 'String'
    $null = New-NetFirewallRule -Name $firewallName -DisplayName $firewallName -Direction Inbound -Action Allow -Protocol TCP -LocalPort 3389 -RemoteAddress '127.0.0.0/8'
    $firewallCreated = $true
    Start-Service TermService
    $listening = $false
    $deadline = [DateTime]::UtcNow.AddSeconds(30)
    do {
        $socket = New-Object Net.Sockets.TcpClient
        try { $socket.Connect('127.0.0.2', 3389); $listening = $true } catch { Start-Sleep -Milliseconds 500 }
        finally { $socket.Dispose() }
    } while (-not $listening -and [DateTime]::UtcNow -lt $deadline)
    if (-not $listening) { throw 'loopback_rdp_listener_unavailable' }
    Record 'loopback_rdp_listening' @{ target = '127.0.0.2:3389'; service = (Get-Service TermService).Status.ToString() }

    $stage = 'register_logon_tasks'
    $fixture = Join-Path $EvidenceDirectory 'fixture'
    $null = New-Item -ItemType Directory -Path $fixture
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'probe_host.ps1'), (Join-Path $PSScriptRoot 'probe_child.mjs') -Destination $fixture
    $grant = '*' + $user.SID.Value + ':(OI)(CI)M'
    $aclOutput = @(& icacls.exe $EvidenceDirectory /grant $grant 2>&1)
    if ($LASTEXITCODE -ne 0) { throw 'evidence_acl_failed' }
    $node = (Get-Command node.exe -CommandType Application).Source
    Record 'node_identity' @{ version = (& $node --version); sha256 = (Get-FileHash -LiteralPath $node -Algorithm SHA256).Hash }
    $powerShell = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    foreach ($variant in @('A', 'B')) {
        $directory = Join-Path $EvidenceDirectory $variant
        $null = New-Item -ItemType Directory -Path $directory
        Write-Json (Join-Path $directory 'hosted-job.json') @{
            githubHosted = $true; machine = $env:COMPUTERNAME; userSid = $user.SID.Value;
            runnerSessionId = $runnerSessionId; expiresUtc = [DateTime]::UtcNow.AddMinutes(20).ToString('o')
        }
        $arguments = '-NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File "{0}" -Variant {1} -EvidenceDirectory "{2}" -NodePath "{3}"' -f (Join-Path $fixture 'probe_host.ps1'), $variant, $directory, $node
        $action = New-ScheduledTaskAction -Execute $powerShell -Argument $arguments -WorkingDirectory $fixture
        $trigger = New-ScheduledTaskTrigger -AtLogOn -User $account
        $principal = New-ScheduledTaskPrincipal -UserId $account -LogonType Interactive -RunLevel Limited
        $settings = New-ScheduledTaskSettingsSet -ExecutionTimeLimit (New-TimeSpan -Minutes 12) -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
        $taskNames[$variant] = 'HIA-logoff-' + $testUser + '-' + $variant
        $null = Register-ScheduledTask -TaskName $taskNames[$variant] -Action $action -Trigger $trigger -Principal $principal -Settings $settings
        Record 'task_registered' @{ variant = $variant; task = $taskNames[$variant]; executable = $powerShell; arguments = $arguments; logonType = 'InteractiveToken' }
    }

    $stage = 'mstsc_connect'
    $null = New-Item -ItemType Directory -Path $controlDirectory
    & cmdkey.exe '/generic:TERMSRV/127.0.0.2' "/user:$account" "/pass:$env:HIA_LOGOFF_PASSWORD" *> $null
    if ($LASTEXITCODE -ne 0) { throw 'cmdkey_failed' }
    $credentialCreated = $true
    # No password is in the .rdp file, child environment, logs, or artifact.
    Remove-Item Env:\HIA_LOGOFF_PASSWORD
    $testPassword = $null; $secure = $null
    $rdpPath = Join-Path $controlDirectory 'loopback.rdp'
    [IO.File]::WriteAllText($rdpPath, (@(
        'full address:s:127.0.0.2:3389', "username:s:$account", 'prompt for credentials:i:0',
        'promptcredentialonce:i:0', 'authentication level:i:0', 'enablecredsspsupport:i:1',
        'screen mode id:i:1', 'desktopwidth:i:800', 'desktopheight:i:600',
        'redirectclipboard:i:0', 'drivestoredirect:s:', 'audiomode:i:2'
    ) -join "`r`n"), $utf8)
    $client = Start-Process -FilePath (Join-Path $env:SystemRoot 'System32\mstsc.exe') -ArgumentList ('"' + $rdpPath + '"') -WindowStyle Hidden -PassThru
    Record 'mstsc_started' @{ pid = $client.Id; target = '127.0.0.2'; thirdPartyClient = $false }
    $stage = 'wait_interactive_session_and_ready'
    $deadline = [DateTime]::UtcNow.AddMinutes(5)
    do {
        $sessions = @([LogoffNative]::UserSessions($testUser))
        if ($sessions.Count -gt 1) { throw 'multiple_test_sessions_rejected' }
        if ($sessions.Count -eq 1) {
            $sessionId = [int]$sessions[0]
            if (-not (Test-Session $sessionId)) { throw 'test_session_identity_failed' }
            if (-not $established) { Record 'interactive_session_established' @{ sessionId = $sessionId }; $established = $true }
            foreach ($variant in @('A', 'B')) {
                $readyPath = Join-Path (Join-Path $EvidenceDirectory $variant) 'ready.json'
                if (-not $ready.ContainsKey($variant) -and (Test-Path -LiteralPath $readyPath)) {
                    try { $value = Get-Content -LiteralPath $readyPath -Raw | ConvertFrom-Json } catch { continue }
                    if ($value.session_id -ne $sessionId -or $value.variant -ne $variant) { throw 'ready_session_mismatch' }
                    $watches[$variant + 'Host'] = New-Object 'LogoffNative+Watch' -ArgumentList ([int]$value.pid), $sessionId
                    $watches[$variant + 'Child'] = New-Object 'LogoffNative+Watch' -ArgumentList ([int]$value.child_pid), $sessionId
                    $ready[$variant] = $value
                    Record 'probe_ready' $value
                }
            }
        }
        if ($ready.Count -eq 2) { break }
        Start-Sleep -Milliseconds 500
    } while ([DateTime]::UtcNow -lt $deadline)
    if (-not $established) {
        Record 'mstsc_unavailable' @{ reason = 'No test-user interactive session within five minutes; no third-party binary downloaded.' }
        throw 'interactive_session_timeout'
    }
    if ($ready.Count -ne 2) { throw 'probe_ready_timeout' }

    $stage = 'real_logoff'
    if (-not (Test-Session $sessionId)) { throw 'test_session_disappeared_before_logoff' }
    $logoffAttempted = $true
    Record 'logoff_requested' @{ sessionId = $sessionId; method = 'logoff.exe'; runnerSessionId = $runnerSessionId }
    $logoffClient = Start-Process -FilePath (Join-Path $env:SystemRoot 'System32\logoff.exe') -ArgumentList "$sessionId" -WindowStyle Hidden -PassThru
    $deadline = [DateTime]::UtcNow.AddMinutes(2)
    do {
        $sessionGone = -not (Test-Session $sessionId)
        if ($sessionGone) { break }
        Start-Sleep -Milliseconds 100
    } while ([DateTime]::UtcNow -lt $deadline)
    Record 'logoff_wait_finished' @{ disappeared = $sessionGone; sessionId = $sessionId }
    if ($logoffClient.HasExited) { Record 'logoff_command_returned' @{ exitCode = $logoffClient.ExitCode } }
    else { Record 'logoff_command_still_running' @{ pid = $logoffClient.Id } }
    $stage = 'collect_evidence'
    # Task Scheduler can publish LastTaskResult slightly after the process exits.
    $deadline = [DateTime]::UtcNow.AddSeconds(15)
    do {
        $running = @($taskNames.Values | ForEach-Object { Get-ScheduledTask -TaskName $_ } | Where-Object { $_.State -eq 'Running' })
        if ($running.Count -eq 0) { break }
        Start-Sleep -Milliseconds 250
    } while ([DateTime]::UtcNow -lt $deadline)
} catch {
    # Do not serialize exception messages or invocation details: native arguments may contain credentials.
    $failure = @{ stage = $stage; errorType = $_.Exception.GetType().FullName; errorId = $_.FullyQualifiedErrorId.Split(',')[0] }
    Record 'experiment_incomplete' $failure
} finally {
    # Snapshot BEFORE cleanup so stopping tasks cannot masquerade as a logoff result.
    try {
        $queryOutput = @(& query.exe session 2>&1 | ForEach-Object { "$_" })
        Write-Json (Join-Path $EvidenceDirectory 'sessions-before-cleanup.json') $queryOutput
        Write-Output ($queryOutput -join "`n")
    } catch { Record 'snapshot_incomplete' @{ operation = 'query_session' } }
    foreach ($variant in @('A', 'B')) {
        try {
            if ($taskNames.ContainsKey($variant)) {
                $info = Get-ScheduledTaskInfo -TaskName $taskNames[$variant]
                $task = Get-ScheduledTask -TaskName $taskNames[$variant]
                $taskResults[$variant] = @{ lastTaskResult = ([long]$info.LastTaskResult -band 4294967295L); state = $task.State.ToString(); lastRunUtc = $info.LastRunTime.ToUniversalTime().ToString('o') }
            }
            foreach ($kind in @('Host', 'Child')) {
                $key = $variant + $kind
                if ($watches.ContainsKey($key)) { Write-Json (Join-Path (Join-Path $EvidenceDirectory $variant) ($kind.ToLowerInvariant() + '-process.json')) (Snapshot $watches[$key]) }
            }
        } catch { Record 'snapshot_incomplete' @{ variant = $variant; errorType = $_.Exception.GetType().FullName } }
    }
    Record 'cleanup_started' @{ experimentLogoffAttempted = $logoffAttempted }
    # Cleanup uses the same exact test identity check; never logs off the runner.
    try {
        foreach ($testSession in @([LogoffNative]::UserSessions($testUser))) {
            if (Test-Session $testSession) {
                $cleanupLogoff = Start-Process -FilePath (Join-Path $env:SystemRoot 'System32\logoff.exe') -ArgumentList "$testSession" -WindowStyle Hidden -PassThru
                if (-not $cleanupLogoff.WaitForExit(10000)) { Stop-Process -Id $cleanupLogoff.Id -ErrorAction SilentlyContinue }
                $cleanupLogoff.Dispose()
            }
        }
    } catch { Record 'cleanup_warning' @{ operation = 'test_session_logoff' } }
    foreach ($taskName in $taskNames.Values) {
        try { Stop-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue; Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction Stop }
        catch { Record 'cleanup_warning' @{ operation = 'test_task_remove' } }
    }
    foreach ($watch in $watches.Values) { $watch.Dispose() }
    if ($null -ne $logoffClient) {
        try { if (-not $logoffClient.HasExited) { Stop-Process -Id $logoffClient.Id -ErrorAction Stop }; $logoffClient.Dispose() }
        catch { Record 'cleanup_warning' @{ operation = 'logoff_client_stop' } }
    }
    if ($null -ne $client) { try { if (-not $client.HasExited) { Stop-Process -Id $client.Id -ErrorAction Stop } } catch { Record 'cleanup_warning' @{ operation = 'mstsc_stop' } } }
    if ($credentialCreated) { & cmdkey.exe '/delete:TERMSRV/127.0.0.2' *> $null }
    if ($firewallCreated) { Remove-NetFirewallRule -Name $firewallName -ErrorAction SilentlyContinue }
    for ($n = $registryChanges.Count - 1; $n -ge 0; $n--) {
        $change = $registryChanges[$n]
        try {
            if ($change.existed) { $null = New-ItemProperty -Path $change.path -Name $change.name -Value $change.oldValue -PropertyType $change.oldKind -Force }
            else { Remove-ItemProperty -Path $change.path -Name $change.name -ErrorAction SilentlyContinue }
        } catch { Record 'cleanup_warning' @{ operation = 'restore_job_registry' } }
    }
    if ($userCreated) { try { Remove-LocalUser -Name $testUser } catch { Record 'cleanup_warning' @{ operation = 'test_user_remove' } } }
    Remove-Item Env:\HIA_LOGOFF_PASSWORD -ErrorAction SilentlyContinue
    $testPassword = $null; $secure = $null
    # Only delete the single freshly generated control folder after checking its absolute parent.
    if ([IO.Path]::GetDirectoryName([IO.Path]::GetFullPath($controlDirectory)) -eq [IO.Path]::GetFullPath($env:RUNNER_TEMP).TrimEnd('\') -and
        [IO.Path]::GetFileName($controlDirectory).StartsWith('hia-logoff-control-')) {
        Remove-Item -LiteralPath $controlDirectory -Recurse -Force -ErrorAction SilentlyContinue
    }
}

$variants = [ordered]@{}
foreach ($variant in @('A', 'B')) {
    $directory = Join-Path $EvidenceDirectory $variant
    $variantParseStart = $parseIssues.Count
    $hostEvents = @(Read-Lines (Join-Path $directory 'host-events.jsonl'))
    $childEvents = @(Read-Lines (Join-Path $directory 'child-events.jsonl'))
    $hostProcess = $null; $childProcess = $null
    foreach ($kind in @('host', 'child')) {
        $path = Join-Path $directory ($kind + '-process.json')
        if (Test-Path -LiteralPath $path) {
            try {
                $value = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json
                if ($kind -eq 'host') { $hostProcess = $value } else { $childProcess = $value }
            } catch { $parseIssues.Add($variant + '/' + $kind + '-process.json') }
        }
    }
    $window = @($hostEvents | Where-Object { $_.event -eq 'WM_QUERYENDSESSION' -or $_.event -eq 'WM_ENDSESSION' } | Sort-Object { [long]$_.ticks })
    $heartbeat = @($childEvents | Where-Object { $_.event -eq 'heartbeat' } | Select-Object -Last 1)
    $taskResult = $null
    if ($taskResults.ContainsKey($variant)) { $taskResult = $taskResults[$variant] }
    $exitCode = $null; $exitSource = 'unavailable'
    if ($null -ne $hostProcess -and $hostProcess.exited) { $exitCode = $hostProcess.exitCode; $exitSource = 'retained_process_handle' }
    elseif ($ready.ContainsKey($variant) -and $null -ne $taskResult -and $taskResult.state -ne 'Running' -and $taskResult.lastTaskResult -ne 267009) {
        $exitCode = $taskResult.lastTaskResult; $exitSource = 'LastTaskResult'
    }
    $childBeforeWindow = $null; $orderReason = 'child_exit_or_window_message_unavailable'
    if ($null -ne $childProcess -and $childProcess.exited -and $window.Count -gt 0) {
        # Kernel process exit FILETIME and precise wall clock receipt share an epoch.
        # Node hrtime and last heartbeat are not evidence of the termination time.
        $childBeforeWindow = [long]$childProcess.exitFiletime -lt [long]$window[0].utc_filetime
        $orderReason = 'kernel_exit_time_compared_to_first_window_receipt_entry; shared_FILETIME_epoch'
    } elseif ($window.Count -eq 0) { $orderReason = 'no_window_message_observed; termination_order_unknown' }
    $queryReceived = @($hostEvents | Where-Object { $_.event -eq 'WM_QUERYENDSESSION' }).Count -gt 0
    $endReceived = @($hostEvents | Where-Object { $_.event -eq 'WM_ENDSESSION' }).Count -gt 0
    $isControlCExit = $null -ne $exitCode -and $exitCode -eq 3221225786L
    $shapeValid = $false
    if ($ready.ContainsKey($variant)) {
        $shapeValid = ($variant -eq 'A' -and $ready[$variant].console_attached -and $ready[$variant].creation_flags -eq 134217728) -or
            ($variant -eq 'B' -and -not $ready[$variant].console_attached -and $ready[$variant].creation_flags -eq 8)
    }
    $complete = $shapeValid -and $ready.ContainsKey($variant) -and $logoffAttempted -and $sessionGone -and $null -ne $exitCode -and
        $null -ne $childProcess -and $childProcess.exited -and $parseIssues.Count -eq $variantParseStart
    $lastHeartbeat = $null
    if ($heartbeat.Count -gt 0) { $lastHeartbeat = $heartbeat[0] }
    $variants[$variant] = [ordered]@{
        ready = $ready.ContainsKey($variant); launchShapeValid = [bool]$shapeValid; evidenceComplete = [bool]$complete
        queryEndSession = $queryReceived; endSession = $endReceived
        ctrlLogoff = @($hostEvents | Where-Object { $_.event -eq 'CTRL_LOGOFF_EVENT' }).Count -gt 0
        ctrlEvents = @($hostEvents | Where-Object { $_.event -like 'CTRL_*' })
        hostExitCode = $exitCode; hostExitCodeSource = $exitSource; is0xC000013A = $isControlCExit
        task = $taskResult; hostProcess = $hostProcess; childProcess = $childProcess
        childLastHeartbeat = $lastHeartbeat; childTerminatedBeforeWindowMessage = $childBeforeWindow; childOrderReason = $orderReason
        reproduced = [bool]($complete -and $isControlCExit -and -not $queryReceived -and -not $endReceived)
        hostTimeline = $hostEvents; childTimeline = $childEvents
    }
}
$complete = $variants.A.evidenceComplete -and $variants.B.evidenceComplete -and $parseIssues.Count -eq 0
$outcome = 'inconclusive'
if (-not $established) { $outcome = 'infrastructure_failure' }
elseif ($complete) { $outcome = 'evidence_collected' }
$summary = [ordered]@{
    schema = 1; outcome = $outcome; stage = $stage; failure = $failure
    runnerSessionId = $runnerSessionId; testSessionId = $sessionId; interactiveSessionEstablished = $established
    logoffMethod = 'logoff.exe'; logoffAttempted = $logoffAttempted; sessionDisappeared = $sessionGone
    reproduced = [bool]$variants.A.reproduced; evidenceComplete = [bool]$complete
    interpretation = 'reproduced requires ready + real logoff + session disappearance + host 0xC000013A + no window receipts; false with incomplete evidence is inconclusive.'
    variants = $variants; parseIssues = @($parseIssues.ToArray())
    collectorTimeline = @(Read-Lines (Join-Path $EvidenceDirectory 'collector-events.jsonl'))
    retainedMitigation = 'Manual service stop before logoff remains in place; no runtime changes.'
}
Write-Json (Join-Path $EvidenceDirectory 'conclusion.json') $summary
$json = $summary | ConvertTo-Json -Depth 30
Write-Output $json
if ($env:GITHUB_STEP_SUMMARY) {
    [IO.File]::AppendAllText($env:GITHUB_STEP_SUMMARY, ("## Real logoff reproduction`n" + '```json' + "`n" + $json + "`n" + '```' + "`n"), $utf8)
}
# A genuine interactive session with incomplete probe evidence is inconclusive, not an infrastructure failure.
if (-not $established) { exit 1 }
exit 0
