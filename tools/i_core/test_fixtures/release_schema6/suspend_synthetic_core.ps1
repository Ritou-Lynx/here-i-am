param([Parameter(Mandatory=$true)][int]$ProcessId,[Parameter(Mandatory=$true)][string]$Executable,[Parameter(Mandatory=$true)][ValidatePattern('^[a-f0-9]{64}$')][string]$RunId,[ValidateSet('Suspend','Kill')][string]$Action='Suspend')
$ErrorActionPreference='Stop'
Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
using System.Text;
public static class SuspendSyntheticCore {
 [DllImport("kernel32.dll",SetLastError=true)] static extern IntPtr OpenProcess(uint access,bool inherit,uint pid);
 [DllImport("kernel32.dll",CharSet=CharSet.Unicode)] static extern IntPtr OpenJobObject(uint access,bool inherit,string name);
 [DllImport("kernel32.dll")] static extern bool IsProcessInJob(IntPtr process,IntPtr job,out bool member);
 [DllImport("kernel32.dll",CharSet=CharSet.Unicode)] static extern bool QueryFullProcessImageName(IntPtr process,uint flags,StringBuilder image,ref uint size);
 [DllImport("kernel32.dll")] static extern bool CloseHandle(IntPtr handle);
 [DllImport("ntdll.dll")] static extern int NtSuspendProcess(IntPtr process);
 [DllImport("kernel32.dll")] static extern bool TerminateProcess(IntPtr process,uint code);
 public static void Inject(uint pid,string executable,string run,bool kill) {
  IntPtr process=OpenProcess(0x1801,false,pid),job=OpenJobObject(4,false,"Local\\ICoreSchema6-"+run);
  try{bool member;uint size=32768;StringBuilder image=new StringBuilder(32768);if(process==IntPtr.Zero||job==IntPtr.Zero||!IsProcessInJob(process,job,out member)||!member||!QueryFullProcessImageName(process,0,image,ref size)||!image.ToString().Equals(executable,StringComparison.OrdinalIgnoreCase))throw new InvalidOperationException("synthetic_process_identity_mismatch");if(kill){if(!TerminateProcess(process,137))throw new InvalidOperationException("synthetic_kill_failed");}else if(NtSuspendProcess(process)!=0)throw new InvalidOperationException("synthetic_suspend_failed");}
  finally{if(process!=IntPtr.Zero)CloseHandle(process);if(job!=IntPtr.Zero)CloseHandle(job);}
 }
}
'@
[SuspendSyntheticCore]::Inject($ProcessId,$Executable,$RunId,($Action -eq 'Kill'))
@{synthetic_core_suspended=($Action -eq 'Suspend');synthetic_core_killed=($Action -eq 'Kill')}|ConvertTo-Json -Compress
