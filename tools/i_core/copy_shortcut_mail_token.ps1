[CmdletBinding()]
param(
  [string]$ConfigPath = '',
  [ValidateRange(15, 300)][int]$ClearAfterSeconds = 90
)

$ErrorActionPreference = 'Stop'
$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
if ([string]::IsNullOrWhiteSpace($ConfigPath)) {
  $ConfigPath = Join-Path $scriptRoot '.state\shortcut-mail-relay.json'
}
$config = Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json
if ($config.workflow -ne 'ios_shortcut_test_v0' -or -not $config.token_credential_path) {
  throw 'Shortcut mail relay token configuration is incomplete.'
}
$expiresAt = [DateTimeOffset]::FromUnixTimeMilliseconds([Int64]$config.token_expires_at_ms)
if ([DateTimeOffset]::UtcNow -ge $expiresAt) {
  throw 'The scoped test token has expired. Rotate the relay configuration before continuing.'
}
$credential = Import-Clixml -LiteralPath ([string]$config.token_credential_path)
if ($credential -isnot [System.Management.Automation.PSCredential]) {
  throw 'Invalid DPAPI token credential.'
}
$token = $credential.GetNetworkCredential().Password
if ([string]::IsNullOrWhiteSpace($token)) { throw 'The DPAPI token credential is empty.' }

if (-not ('HereIAmSensitiveClipboard' -as [type])) {
  Add-Type -TypeDefinition @'
using System;
using System.ComponentModel;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;

public static class HereIAmSensitiveClipboard
{
    private const uint CF_UNICODETEXT = 13;
    private const uint GMEM_MOVEABLE = 0x0002;

    [DllImport("user32.dll", SetLastError = true)]
    private static extern bool OpenClipboard(IntPtr owner);
    [DllImport("user32.dll", SetLastError = true)]
    private static extern bool CloseClipboard();
    [DllImport("user32.dll", SetLastError = true)]
    private static extern bool EmptyClipboard();
    [DllImport("user32.dll", SetLastError = true)]
    private static extern IntPtr SetClipboardData(uint format, IntPtr memory);
    [DllImport("user32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern uint RegisterClipboardFormat(string format);
    [DllImport("user32.dll")]
    private static extern uint GetClipboardSequenceNumber();
    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern IntPtr GlobalAlloc(uint flags, UIntPtr bytes);
    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern IntPtr GlobalLock(IntPtr memory);
    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool GlobalUnlock(IntPtr memory);
    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern IntPtr GlobalFree(IntPtr memory);

    private static void OpenWithRetry()
    {
        for (int attempt = 0; attempt < 20; attempt++)
        {
            if (OpenClipboard(IntPtr.Zero)) return;
            Thread.Sleep(50);
        }
        throw new Win32Exception(Marshal.GetLastWin32Error(), "Unable to open the Windows clipboard.");
    }

    private static IntPtr Allocate(byte[] bytes)
    {
        IntPtr memory = GlobalAlloc(GMEM_MOVEABLE, (UIntPtr)bytes.Length);
        if (memory == IntPtr.Zero) throw new Win32Exception(Marshal.GetLastWin32Error());
        IntPtr target = GlobalLock(memory);
        if (target == IntPtr.Zero)
        {
            GlobalFree(memory);
            throw new Win32Exception(Marshal.GetLastWin32Error());
        }
        try { Marshal.Copy(bytes, 0, target, bytes.Length); }
        finally { GlobalUnlock(memory); }
        return memory;
    }

    private static void Put(uint format, byte[] bytes)
    {
        IntPtr memory = Allocate(bytes);
        if (SetClipboardData(format, memory) == IntPtr.Zero)
        {
            GlobalFree(memory);
            throw new Win32Exception(Marshal.GetLastWin32Error());
        }
    }

    public static uint SetText(string text)
    {
        OpenWithRetry();
        try
        {
            if (!EmptyClipboard()) throw new Win32Exception(Marshal.GetLastWin32Error());
            uint noHistory = RegisterClipboardFormat("CanIncludeInClipboardHistory");
            uint noCloud = RegisterClipboardFormat("CanUploadToCloudClipboard");
            uint noMonitor = RegisterClipboardFormat("ExcludeClipboardContentFromMonitorProcessing");
            if (noHistory == 0 || noCloud == 0 || noMonitor == 0)
                throw new Win32Exception(Marshal.GetLastWin32Error());
            Put(noHistory, BitConverter.GetBytes(0));
            Put(noCloud, BitConverter.GetBytes(0));
            Put(noMonitor, new byte[] { 1 });
            Put(CF_UNICODETEXT, Encoding.Unicode.GetBytes(text + "\0"));
        }
        catch
        {
            EmptyClipboard();
            throw;
        }
        finally { CloseClipboard(); }
        return GetClipboardSequenceNumber();
    }

    public static uint SequenceNumber() { return GetClipboardSequenceNumber(); }

    public static bool ClearIfSequence(uint expected)
    {
        OpenWithRetry();
        try
        {
            if (GetClipboardSequenceNumber() != expected) return false;
            if (!EmptyClipboard()) throw new Win32Exception(Marshal.GetLastWin32Error());
            return true;
        }
        finally { CloseClipboard(); }
    }
}
'@
}

$sequence = [HereIAmSensitiveClipboard]::SetText($token)
$handoffDeleteFailed = $false
try {
  Remove-Item -LiteralPath ([string]$config.token_credential_path) -Force
} catch {
  $handoffDeleteFailed = $true
}
Write-Output "Scoped token copied without clipboard history/cloud upload. Paste it into the Android debug page within $ClearAfterSeconds seconds; this window will then clear it if unchanged."
try {
  Start-Sleep -Seconds $ClearAfterSeconds
  $unchanged = [HereIAmSensitiveClipboard]::SequenceNumber() -eq $sequence
  if ($unchanged) {
    try {
      $current = Get-Clipboard -Raw -ErrorAction Stop
      if ([string]::Equals([string]$current, $token, [StringComparison]::Ordinal)) {
        if ([HereIAmSensitiveClipboard]::ClearIfSequence($sequence)) {
          Write-Output 'Scoped token cleared from the current clipboard.'
        } else {
          Write-Output 'Clipboard changed during cleanup; newer clipboard content was left untouched.'
        }
      } else {
        Write-Output 'Clipboard text no longer matches the copied token; it was left untouched.'
      }
    } catch {
      try {
        if ([HereIAmSensitiveClipboard]::ClearIfSequence($sequence)) {
          Write-Output 'Clipboard readback failed, so the unchanged sensitive clipboard was cleared.'
        } else {
          Write-Output 'Clipboard changed during cleanup; newer clipboard content was left untouched.'
        }
      } catch {
        Write-Warning 'The sensitive clipboard could not be cleared. Copy another harmless value now; the server-side token still expires automatically.'
      }
    }
  } else {
    Write-Output 'Clipboard changed after the copy; newer clipboard content was left untouched.'
  }
} finally {
  try {
    if ([HereIAmSensitiveClipboard]::SequenceNumber() -eq $sequence) {
      [void][HereIAmSensitiveClipboard]::ClearIfSequence($sequence)
    }
  } catch {
    Write-Warning 'Final sensitive clipboard cleanup did not complete; copy another harmless value now.'
  }
  $token = $null
}
if ($handoffDeleteFailed) {
  throw 'The DPAPI token handoff file could not be removed. Rotate the relay configuration after this Gate.'
}
