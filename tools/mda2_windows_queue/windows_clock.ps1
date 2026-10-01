$ErrorActionPreference = 'Stop'
try {
  Add-Type -TypeDefinition @'
using System.Runtime.InteropServices;
public static class W2Clock {
  [DllImport("kernel32.dll")] public static extern ulong GetTickCount64();
}
'@
  while ($null -ne ($line = [Console]::ReadLine())) {
    if ($line -eq 'close') { break }
    if ($line -ne 'sample') { exit 21 }
    [Console]::WriteLine([W2Clock]::GetTickCount64().ToString())
  }
} catch { exit 22 }
