$ErrorActionPreference = 'Stop'
$stage = 'compile'
# Private inherited pipes only. No key, raw event, or configuration in argv/logs.
try {
  Add-Type -AssemblyName System.Security
  Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
using Microsoft.Win32.SafeHandles;
using System.Text;
public static class W2Handles {
  [DllImport("kernel32.dll", CharSet=CharSet.Unicode, SetLastError=true)]
  static extern SafeFileHandle CreateFile(string n, uint a, uint s, IntPtr p, uint c, uint f, IntPtr t);
  [DllImport("kernel32.dll", CharSet=CharSet.Unicode, SetLastError=true)]
  static extern uint GetFinalPathNameByHandle(SafeFileHandle h, StringBuilder b, uint n, uint f);
  public static SafeFileHandle Hold(string p, bool stable) {
    var h = CreateFile(p, 0, stable ? 3u : 7u, IntPtr.Zero, 3, 0x02200000, IntPtr.Zero);
    if (h.IsInvalid) throw new Exception("path_lock_failed_" + Marshal.GetLastWin32Error().ToString());
    var b = new StringBuilder(32768);
    if (GetFinalPathNameByHandle(h,b,32768,0)==0 ||
        !String.Equals(b.ToString().Replace("\\\\?\\", ""),p,StringComparison.OrdinalIgnoreCase)) {
      h.Dispose(); throw new Exception("canonical_path_required");
    }
    return h;
  }
}
'@
  $stage = 'request'
  $request = [Console]::ReadLine() | ConvertFrom-Json
  $root = [IO.Path]::GetFullPath([string]$request.root).TrimEnd('\')
  if ($root -notmatch '^[A-Za-z]:\\' -or $root -match '(^|\\)\.\.?($|\\)' -or $root.Substring(2).Contains(':')) { throw 'invalid_path' }
  $sid = [Security.Principal.WindowsIdentity]::GetCurrent().User
  $systemSid = New-Object Security.Principal.SecurityIdentifier 'S-1-5-18'
  function Assert-NoReparse([string]$p) {
    if (([IO.File]::GetAttributes($p) -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw 'reparse_rejected' }
  }
  $ancestors = @(); $cursor = $root
  while ($cursor) {
    if (Test-Path -LiteralPath $cursor) { Assert-NoReparse $cursor; $ancestors += $cursor }
    $parent = [IO.Directory]::GetParent($cursor); if ($null -eq $parent) { break }; $cursor = $parent.FullName
  }
  $stage = 'ancestor_handles'
  $holds = @(); foreach ($p in $ancestors) { $holds += [W2Handles]::Hold($p,$false) }
  function Protect-Directory([string]$p) {
    $acl = New-Object Security.AccessControl.DirectorySecurity
    $acl.SetOwner($sid); $acl.SetAccessRuleProtection($true,$false)
    foreach ($id in @($sid,$systemSid)) {
      $rule = New-Object Security.AccessControl.FileSystemAccessRule($id,'FullControl','ContainerInherit,ObjectInherit','None','Allow')
      $acl.AddAccessRule($rule)
    }
    Set-Acl -LiteralPath $p -AclObject $acl
  }
  $stage = 'provision'
  if ($request.fresh) {
    if (Test-Path -LiteralPath $root) { throw 'fresh_path_exists' }
    [IO.Directory]::CreateDirectory($root) | Out-Null; Protect-Directory $root
    foreach ($name in @('queue','keys')) {
      $p = Join-Path $root $name; [IO.Directory]::CreateDirectory($p) | Out-Null; Protect-Directory $p
    }
  }
  function Validate-Tree {
    $pendingPaths = New-Object 'System.Collections.Generic.Queue[string]'
    $pendingPaths.Enqueue($root)
    while ($pendingPaths.Count -gt 0) {
      $currentPath = $pendingPaths.Dequeue()
      $item = Get-Item -LiteralPath $currentPath -Force
      Assert-NoReparse $item.FullName
      $acl = Get-Acl -LiteralPath $item.FullName
      if ($acl.GetOwner([Security.Principal.SecurityIdentifier]).Value -ne $sid.Value) { throw 'owner_mismatch' }
      foreach ($ace in $acl.GetAccessRules($true,$true,[Security.Principal.SecurityIdentifier])) {
        if ($ace.AccessControlType -eq 'Allow' -and $ace.IdentityReference.Value -notin @($sid.Value,$systemSid.Value)) { throw 'acl_too_broad' }
      }
      if ($item.PSIsContainer) {
        foreach ($child in @(Get-ChildItem -LiteralPath $item.FullName -Force)) { $pendingPaths.Enqueue($child.FullName) }
      }
    }
  }
  $stage = 'acl'
  Validate-Tree
  foreach ($p in @($root,(Join-Path $root 'queue'),(Join-Path $root 'keys'))) { $holds += [W2Handles]::Hold($p,$true) }
  $stage = 'owner_lock'
  $lockPath = Join-Path $root 'owner.lock'
  $lock = [IO.File]::Open($lockPath,[IO.FileMode]::OpenOrCreate,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
  $entropy = [Convert]::FromBase64String($request.entropy)
  $keyPath = Join-Path $root 'keys\queue.dpapi'
  $stage = 'dpapi'
  if ($request.fresh) {
    $key = New-Object byte[] 32
    $rng = [Security.Cryptography.RandomNumberGenerator]::Create(); $rng.GetBytes($key); $rng.Dispose()
    $sealed = [Security.Cryptography.ProtectedData]::Protect($key,$entropy,[Security.Cryptography.DataProtectionScope]::CurrentUser)
    $file = [IO.File]::Open($keyPath,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
    $file.Write($sealed,0,$sealed.Length); $file.Flush($true); $file.Dispose()
  } else {
    $key = [Security.Cryptography.ProtectedData]::Unprotect([IO.File]::ReadAllBytes($keyPath),$entropy,[Security.Cryptography.DataProtectionScope]::CurrentUser)
  }
  if ($key.Length -ne 32) { throw 'key_invalid' }
  Validate-Tree
  [Console]::WriteLine((@{ok=$true;key=[Convert]::ToBase64String($key);root=$root} | ConvertTo-Json -Compress))
  [Array]::Clear($key,0,$key.Length)
  while ($null -ne ($line = [Console]::ReadLine())) {
    if ($line -eq 'close') { break }
    if ($line -ne 'validate') { throw 'invalid_guard_command' }
    Validate-Tree
    [Console]::WriteLine('{"ok":true}')
  }
  $lock.Dispose(); foreach ($h in $holds) { $h.Dispose() }
  exit 0
} catch {
  # Fixed code avoids leaking paths, key bytes, or native exception text.
  $detail = $_.Exception.InnerException.Message
  if (!$detail) { $detail = $_.Exception.Message }
  if ($detail -match '^(path_lock_failed_[0-9]+|canonical_path_required|owner_mismatch|acl_too_broad|reparse_rejected)$') { $stage += '_' + $detail }
  else { $stage += '_' + $_.Exception.GetType().Name.ToLowerInvariant() }
  [Console]::WriteLine((@{ok=$false;code=('windows_protection_rejected_' + $stage)} | ConvertTo-Json -Compress))
  exit 20
}
