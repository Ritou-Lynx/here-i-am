# Real logoff fixture (hosted Windows only)

Do not execute these scripts locally. Local validation is limited to the Windows
PowerShell 5.1 parser and `node --check probe_child.mjs`. The orchestrator rejects
non-hosted environments before changing the system. Logon tasks also require a
short-lived permit bound to the disposable user's SID and runner machine.

The optional `logoff-repro.yml` workflow uses the hosted image's installed Node
and Windows `mstsc`/`cmdkey`; it downloads no RDP client. It records Node's version
and executable SHA256. If mstsc cannot establish a test-user session within five
minutes, the job fails with its infrastructure stage. There is no unpinned binary
fallback. RDP firewall permission and saved-credential delegation target loopback
only. Credentials are masked, kept in memory/temporary credential storage, and
removed in cleanup; no password is stored in an artifact or `.rdp` file.

Two interactive-token LogonTrigger tasks launch the same hidden PowerShell host
shape. A keeps its console and creates the Node child with `CREATE_NO_WINDOW`.
B first calls `FreeConsole`, uses `DETACHED_PROCESS`, and records the result of
`ShutdownBlockReasonCreate` in QUERYENDSESSION. Both return TRUE. The candidate
is measured, without assuming that registering a reason prevents termination.
See Microsoft's [creation flags](https://learn.microsoft.com/en-us/windows/win32/procthread/process-creation-flags)
and [QUERYENDSESSION contract](https://learn.microsoft.com/en-us/windows/win32/shutdown/wm-queryendsession).

The experiment uses `logoff.exe <test-session-id>` once both probes are ready.
The runner retains host/child process handles outside that session, so it can
record their real exit codes and kernel exit FILETIMEs even when the processes
cannot write final receipts. Observations are frozen before cleanup starts.
LastTaskResult is also recorded, and is a fallback for the host's exit code.

`conclusion.json` is printed to the job log and step summary and uploaded with
raw timelines. Each variant's `reproduced` requires readiness, real logoff,
confirmed session disappearance, host exit `3221225786` (`0xC000013A`), and no
QUERYENDSESSION/ENDSESSION receipts. The top-level value describes A; B remains
a separate result. A complete negative result is `evidence_collected` with
`reproduced: false`. Probe/collection failures after session establishment are
reported as `inconclusive`, never as evidence that the bug is absent. Only
failure to establish the interactive session makes the job fail.

Child heartbeat times do not prove a termination time. Ordering compares the
kernel exit FILETIME with the first host window receipt's precise FILETIME;
both use the same machine wall clock, without controlling clock adjustments.
When no window receipt or child exit is available, the ordering is null with a
reason. Node's hrtime has its own epoch and is never compared to host QPC ticks.

This fixture changes no runtime file. Manual service stop before logoff remains
the mitigation pending review of actual hosted evidence and a separate fix
contract. No local execution or successful hosted reproduction is implied by
parser validation.
