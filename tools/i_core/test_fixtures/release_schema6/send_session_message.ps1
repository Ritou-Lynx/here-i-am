param([Parameter(Mandatory=$true)][long]$Window,[Parameter(Mandatory=$true)][int]$ExpectedPid,[Parameter(Mandatory=$true)][ValidateSet(16,17,22)][int]$Message,[int]$WParam=0)
$ErrorActionPreference='Stop'
Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class SyntheticSessionMessage {
 [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr window,out uint pid);
 [DllImport("user32.dll",SetLastError=true)] static extern IntPtr SendMessageTimeout(IntPtr window,uint message,IntPtr wp,IntPtr lp,uint flags,uint timeout,out IntPtr result);
 public static long Send(long window,uint expected,uint message,int wp){uint actual;if(GetWindowThreadProcessId(new IntPtr(window),out actual)==0||actual!=expected)throw new InvalidOperationException("synthetic_window_identity_mismatch");IntPtr result;if(SendMessageTimeout(new IntPtr(window),message,new IntPtr(wp),IntPtr.Zero,2,45000,out result)==IntPtr.Zero)throw new InvalidOperationException("synthetic_message_timeout");return result.ToInt64();}
}
'@
$watch=[Diagnostics.Stopwatch]::StartNew()
$result=[SyntheticSessionMessage]::Send($Window,$ExpectedPid,$Message,$WParam)
@{result=$result;elapsed_ms=$watch.ElapsedMilliseconds}|ConvertTo-Json -Compress
