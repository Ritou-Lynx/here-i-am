[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'

# Hosted Windows runners have an elevated token whose default file owner can
# be Administrators. Give this synthetic test process tree a user-owned default
# instead. This does not change machine policy or relax production ACL checks.
Add-Type -TypeDefinition @'
using System;
using System.ComponentModel;
using System.Runtime.InteropServices;
using System.Security.Principal;
public static class Schema6SyntheticTokenOwner {
  [DllImport("kernel32.dll")] static extern IntPtr GetCurrentProcess();
  [DllImport("kernel32.dll")] static extern bool CloseHandle(IntPtr h);
  [DllImport("advapi32.dll", SetLastError=true)] static extern bool OpenProcessToken(IntPtr p, uint access, out IntPtr token);
  [DllImport("advapi32.dll", SetLastError=true)] static extern bool GetTokenInformation(IntPtr token, int info, IntPtr data, int size, out int needed);
  [DllImport("advapi32.dll", SetLastError=true)] static extern bool SetTokenInformation(IntPtr token, int info, IntPtr data, int size);
  public static string Set(string owner) {
    IntPtr token;
    if (!OpenProcessToken(GetCurrentProcess(), 0x0088, out token)) throw new Win32Exception();
    IntPtr previous = IntPtr.Zero, sidBuffer = IntPtr.Zero, ownerBuffer = IntPtr.Zero;
    try {
      int length;
      GetTokenInformation(token, 4, IntPtr.Zero, 0, out length);
      previous = Marshal.AllocHGlobal(length);
      if (!GetTokenInformation(token, 4, previous, length, out length)) throw new Win32Exception();
      string old = new SecurityIdentifier(Marshal.ReadIntPtr(previous)).Value;
      if (old == owner) return old;
      var sid = new SecurityIdentifier(owner);
      byte[] bytes = new byte[sid.BinaryLength]; sid.GetBinaryForm(bytes, 0);
      sidBuffer = Marshal.AllocHGlobal(bytes.Length); Marshal.Copy(bytes, 0, sidBuffer, bytes.Length);
      ownerBuffer = Marshal.AllocHGlobal(IntPtr.Size); Marshal.WriteIntPtr(ownerBuffer, sidBuffer);
      if (!SetTokenInformation(token, 4, ownerBuffer, IntPtr.Size)) throw new Win32Exception();
      return old;
    } finally {
      if (previous != IntPtr.Zero) Marshal.FreeHGlobal(previous);
      if (sidBuffer != IntPtr.Zero) Marshal.FreeHGlobal(sidBuffer);
      if (ownerBuffer != IntPtr.Zero) Marshal.FreeHGlobal(ownerBuffer);
      CloseHandle(token);
    }
  }
}
'@
$owner = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
$previousOwner = [Schema6SyntheticTokenOwner]::Set($owner)
try {
  New-Item -ItemType Directory -Force build/ci | Out-Null
  # The small hosted runner cannot service concurrent suites' native ACL/DPAPI
  # subprocess trees within production deadlines. Serialize suites, not checks.
  # Every original test still runs once. Both reporters observe the same run.
  & node --test --test-concurrency=1 --test-reporter=spec --test-reporter=tap --test-reporter-destination=stdout --test-reporter-destination=build/ci/schema6-windows.tap tools/i_core/release_schema6/*.test.mjs tools/i_core/release_schema6/lifecycle/*.test.mjs
  $testExitCode = $LASTEXITCODE
} finally {
  [void][Schema6SyntheticTokenOwner]::Set($previousOwner)
}
exit $testExitCode
