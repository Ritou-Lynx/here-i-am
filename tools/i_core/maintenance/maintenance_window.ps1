# Import-safe, filesystem-only window primitives. No tasks, processes or callbacks.
function Assert-MaintenancePlainDirectory([string]$Path) {
 if($Path -notmatch '^[A-Za-z]:\\' -or $Path.Substring(2).Contains(':') -or [IO.Path]::GetFullPath($Path) -cne $Path){throw 'window_path_not_canonical'}
 for($p=$Path;$p;$p=[IO.Path]::GetDirectoryName($p)){
  $item=Get-Item -LiteralPath $p -Force -ErrorAction Stop
  if(-not $item.PSIsContainer -or ($item.Attributes-band [IO.FileAttributes]::ReparsePoint)){throw 'window_path_not_plain'}
 }
}
function Acquire-MaintenanceGuard([string]$MaintenanceRoot) {
 Assert-MaintenancePlainDirectory $MaintenanceRoot
 $guardPath=Join-Path $MaintenanceRoot 'active-window.guard'
 if(Test-Path -LiteralPath $guardPath){$g=Get-Item -LiteralPath $guardPath -Force;if($g.PSIsContainer-or ($g.Attributes-band [IO.FileAttributes]::ReparsePoint)){throw 'window_guard_not_plain'}}
 # Resolve link count from the actual exclusive handle, never pathname metadata.
 if(-not ('MaintenanceGuardIdentity' -as [type])){
 Add-Type -TypeDefinition @"
using System;
using System.IO;
using System.Runtime.InteropServices;
using Microsoft.Win32.SafeHandles;
public static class MaintenanceGuardIdentity {
 [StructLayout(LayoutKind.Sequential)] struct Info {public uint attr,c1,c2,a1,a2,w1,w2,volume,sizeHigh,sizeLow,links,indexHigh,indexLow;}
 [DllImport("kernel32.dll",SetLastError=true)]static extern bool GetFileInformationByHandle(SafeFileHandle h,out Info i);
 public static void Check(SafeFileHandle h){Info i;if(!GetFileInformationByHandle(h,out i)||i.links!=1||(i.attr&0x400)!=0||(i.attr&0x10)!=0)throw new IOException("guard_link_or_identity_rejected");}
}
"@
 }
 # OpenOrCreate neither truncates nor appends. FileShare.None serializes stages/windows.
 $handle=[IO.File]::Open($guardPath,[IO.FileMode]::OpenOrCreate,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
 try{[MaintenanceGuardIdentity]::Check($handle.SafeFileHandle);return $handle}catch{$handle.Dispose();throw}
}
function Open-MaintenanceWindow {
 [CmdletBinding()]
 param([Parameter(Mandatory=$true)][string]$MaintenanceRoot,[Parameter(Mandatory=$true)][ValidatePattern('^[A-Za-z0-9][A-Za-z0-9_-]{7,79}$')][string]$WindowId)
 Assert-MaintenancePlainDirectory $MaintenanceRoot
 $guard=$null;$entry=$null
 try {
  $guard=Acquire-MaintenanceGuard $MaintenanceRoot
  $windows=Join-Path $MaintenanceRoot 'windows'
  if(-not (Test-Path -LiteralPath $windows)){$null=[IO.Directory]::CreateDirectory($windows)}
  Assert-MaintenancePlainDirectory $windows
  $directory=Join-Path $windows $WindowId
  if(Test-Path -LiteralPath $directory){throw 'window_id_already_used'}
  $null=[IO.Directory]::CreateDirectory($directory);Assert-MaintenancePlainDirectory $directory
  $entry=[IO.File]::Open((Join-Path $directory 'entry.lock'),[IO.FileMode]::CreateNew,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
  $bytes=[Text.UTF8Encoding]::new($false).GetBytes($WindowId+"`n")
  $entry.Write($bytes,0,$bytes.Length);$entry.Flush($true)
  $receipts=Join-Path $directory 'phase-receipts';$null=[IO.Directory]::CreateDirectory($receipts)
  return [pscustomobject]@{WindowId=$WindowId;Directory=$directory;PhaseReceiptsDirectory=$receipts;Guard=$guard;Entry=$entry}
 } catch {if($entry){$entry.Dispose()};if($guard){$guard.Dispose()};throw}
}
function Close-MaintenanceWindow($Window) {
 if($Window){try {if($Window.Entry){$Window.Entry.Dispose()}}finally{if($Window.Guard){$Window.Guard.Dispose()}}}
 # Never delete or truncate either lock, even on a failed window.
}
