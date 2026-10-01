# Test-only: open one known child handle and verify its unique fixture executable.
param([int]$ChildId, [string]$ExpectedExecutable)
$ErrorActionPreference = 'Stop'
$env:PSModulePath = "$PSHOME\Modules"
$canonical = [IO.Path]::GetFullPath($ExpectedExecutable)
if ($canonical -notmatch '\\mda2-r3-[A-Za-z0-9]+\\release\\runtime\\node.exe$' -or
    -not $canonical.StartsWith([IO.Path]::GetFullPath([IO.Path]::GetTempPath()),[StringComparison]::OrdinalIgnoreCase)) { throw 'owned_fixture_required' }
Add-Type @'
using System;
using System.Text;
using System.Runtime.InteropServices;
public static class R3CrashFixture {
  [DllImport("kernel32.dll",SetLastError=true)] static extern IntPtr OpenProcess(uint rights,bool inherit,uint id);
  [DllImport("kernel32.dll",CharSet=CharSet.Unicode,SetLastError=true)] static extern bool QueryFullProcessImageName(IntPtr p,uint flags,StringBuilder text,ref uint size);
  [DllImport("kernel32.dll",SetLastError=true)] static extern bool TerminateProcess(IntPtr p,uint code);
  [DllImport("kernel32.dll",SetLastError=true)] static extern uint WaitForSingleObject(IntPtr p,uint ms);
  [DllImport("kernel32.dll")] static extern bool CloseHandle(IntPtr p);
  public static bool Crash(uint id,string expected) {
    var handle=OpenProcess(0x101001,false,id);
    if(handle==IntPtr.Zero) throw new Exception("child_handle_unavailable");
    try {
      uint size=32768; var text=new StringBuilder((int)size);
      if(!QueryFullProcessImageName(handle,0,text,ref size) || !text.ToString().Equals(expected,StringComparison.OrdinalIgnoreCase)) throw new Exception("child_identity_mismatch");
      if(!TerminateProcess(handle,137)) throw new Exception("termination_failed");
      return WaitForSingleObject(handle,5000)==0;
    } finally { CloseHandle(handle); }
  }
}
'@
if (-not [R3CrashFixture]::Crash($ChildId,$canonical)) { throw 'child_exit_unconfirmed' }
'{"fixture_child_exit_confirmed":true}'
